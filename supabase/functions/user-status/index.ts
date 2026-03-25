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

    // Use service role to read subscription (RLS allows user reads, but this is more explicit)
    const serviceClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const { data: profile } = await serviceClient
      .from("profiles")
      .select("email, display_name, avatar_url")
      .eq("id", user.id)
      .single();

    const { data: subscription } = await serviceClient
      .from("subscriptions")
      .select("plan, words_used, word_limit, status, current_period_end")
      .eq("user_id", user.id)
      .single();

    return new Response(JSON.stringify({
      user_id: user.id,
      email: profile?.email ?? user.email,
      display_name: profile?.display_name,
      avatar_url: profile?.avatar_url,
      plan: subscription?.plan ?? "free",
      words_used: subscription?.words_used ?? 0,
      word_limit: subscription?.word_limit ?? 2000,
      subscription_status: subscription?.status ?? "active",
      current_period_end: subscription?.current_period_end,
    }), {
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 500 });
  }
});
