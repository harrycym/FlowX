import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type" },
    });
  }

  try {
    // Authenticate
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

    const serviceClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Pre-check usage limit
    const { data: sub } = await serviceClient
      .from("subscriptions")
      .select("words_used, word_limit, plan")
      .eq("user_id", user.id)
      .single();

    if (sub && sub.word_limit !== null && sub.words_used >= sub.word_limit) {
      return new Response(JSON.stringify({
        error: "usage_limit_reached",
        words_used: sub.words_used,
        word_limit: sub.word_limit,
      }), { status: 403 });
    }

    // Parse request body
    const body = await req.json();
    const { model, messages, temperature, max_tokens } = body;

    if (!messages || !Array.isArray(messages)) {
      return new Response(JSON.stringify({ error: "Invalid request: messages required" }), { status: 400 });
    }

    // Forward to Groq LLM
    const groqKey = Deno.env.get("GROQ_API_KEY");
    if (!groqKey) {
      return new Response(JSON.stringify({ error: "Server misconfigured" }), { status: 500 });
    }

    const groqResp = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${groqKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: model || "llama-3.3-70b-versatile",
        messages,
        temperature: temperature ?? 0.0,
        max_tokens: max_tokens ?? 2048,
      }),
    });

    if (!groqResp.ok) {
      const errBody = await groqResp.text();
      return new Response(JSON.stringify({ error: `Groq error: ${errBody}` }), { status: 502 });
    }

    const groqJson = await groqResp.json();
    const resultText = groqJson.choices?.[0]?.message?.content?.trim() ?? "";

    // Count words in result
    const wordCount = resultText.split(/\s+/).filter((w: string) => w.length > 0).length;

    // Atomic usage update — only succeeds if within limit
    const { data: updated, error: updateErr } = await serviceClient.rpc("increment_usage", {
      p_user_id: user.id,
      p_words: wordCount,
    });

    // If the RPC doesn't exist yet, fall back to direct update
    if (updateErr) {
      await serviceClient
        .from("subscriptions")
        .update({ words_used: (sub?.words_used ?? 0) + wordCount })
        .eq("user_id", user.id);
    }

    // Log usage
    await serviceClient.from("usage_log").insert({
      user_id: user.id,
      words: wordCount,
      action: "dictation",
    });

    const newWordsUsed = (sub?.words_used ?? 0) + wordCount;

    return new Response(JSON.stringify({
      result: resultText,
      words_used: newWordsUsed,
      word_limit: sub?.word_limit ?? null,
      words_remaining: sub?.word_limit ? Math.max(0, sub.word_limit - newWordsUsed) : null,
    }), {
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 500 });
  }
});
