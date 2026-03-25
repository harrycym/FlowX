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

    // Check usage limit before transcribing
    const serviceClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

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

    // Forward audio to Groq Whisper
    const groqKey = Deno.env.get("GROQ_API_KEY");
    if (!groqKey) {
      return new Response(JSON.stringify({ error: "Server misconfigured" }), { status: 500 });
    }

    // Pass through the multipart body directly to Groq
    const formData = await req.formData();
    const audioFile = formData.get("file");
    if (!audioFile || !(audioFile instanceof File)) {
      return new Response(JSON.stringify({ error: "No audio file provided" }), { status: 400 });
    }

    const groqForm = new FormData();
    groqForm.append("model", "whisper-large-v3");
    groqForm.append("response_format", "text");
    groqForm.append("file", audioFile, audioFile.name);

    const groqResp = await fetch("https://api.groq.com/openai/v1/audio/transcriptions", {
      method: "POST",
      headers: { "Authorization": `Bearer ${groqKey}` },
      body: groqForm,
    });

    if (!groqResp.ok) {
      const errBody = await groqResp.text();
      return new Response(JSON.stringify({ error: `Groq error (${groqResp.status}): ${errBody}` }), { status: 502 });
    }

    const transcript = (await groqResp.text()).trim();

    return new Response(JSON.stringify({ transcript }), {
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 500 });
  }
});
