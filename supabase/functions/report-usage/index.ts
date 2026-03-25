import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type" },
    });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), { status: 401 });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } }
    );

    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid token" }), { status: 401 });
    }

    const { words } = await req.json();
    if (!words || typeof words !== "number") {
      return new Response(JSON.stringify({ error: "Invalid words count" }), { status: 400 });
    }

    const serviceClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Update usage
    const { data: sub } = await serviceClient
      .from("subscriptions")
      .select("words_used, word_limit, plan")
      .eq("user_id", user.id)
      .single();

    const newWordsUsed = (sub?.words_used ?? 0) + words;

    await serviceClient
      .from("subscriptions")
      .update({ words_used: newWordsUsed })
      .eq("user_id", user.id);

    // Log usage
    await serviceClient.from("usage_log").insert({
      user_id: user.id,
      words,
      action: "dictation",
    });

    return new Response(JSON.stringify({
      words_used: newWordsUsed,
      word_limit: sub?.word_limit ?? 2000,
      plan: sub?.plan ?? "free",
    }), {
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 500 });
  }
});
