export interface Env {
  GROQ_API_KEY: string;
  SUPABASE_URL: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
}

// ============================================================
// CORS — strict allowlist (issue #1)
// ============================================================

const ALLOWED_ORIGINS = new Set([
  "https://nimbusglide.ai",
  "https://www.nimbusglide.ai",
]);

function getCORSHeaders(origin: string | null): Record<string, string> {
  // No Origin = native macOS app (no CORS enforcement by browser)
  if (!origin) return {};
  if (!ALLOWED_ORIGINS.has(origin)) return {}; // unknown origin — return nothing; browser blocks it
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, content-type",
    "Access-Control-Allow-Credentials": "true",
  };
}

// ============================================================
// CONSTANTS
// ============================================================

// Allowed models for /process (issue #7, #12)
const ALLOWED_MODELS = new Set([
  "llama-3.3-70b-versatile",
  "llama-3.1-8b-instant",
  "llama-3.1-70b-versatile",
  "mixtral-8x7b-32768",
  "gemma2-9b-it",
]);
const DEFAULT_MODEL = "llama-3.3-70b-versatile";
const MAX_TOKENS_LIMIT = 4096;

// Allowed audio MIME types for /transcribe (issue #11)
const ALLOWED_AUDIO_TYPES = new Set([
  "audio/wav", "audio/wave", "audio/x-wav",
  "audio/mp4", "audio/m4a", "audio/x-m4a",
  "audio/mpeg", "audio/mp3",
  "audio/ogg", "audio/webm",
  "audio/flac", "audio/x-flac",
]);

// Max audio size: 25 MB (issue #5)
const MAX_AUDIO_BYTES = 25 * 1024 * 1024;

// Supabase project ref for JWT validation (issue #4)
const SUPABASE_PROJECT_REF = "zduzcyamdnepufjxbnwe";

// Cache JWKS keys in memory
let cachedJWKS: Record<string, CryptoKey> = {};
let jwksFetchedAt = 0;

// ============================================================
// MAIN FETCH HANDLER
// ============================================================

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const origin = request.headers.get("Origin");
    const corsHeaders = getCORSHeaders(origin);

    if (request.method === "OPTIONS") {
      if (Object.keys(corsHeaders).length === 0 && origin) {
        // Unknown origin preflight — reject
        return new Response(null, { status: 403 });
      }
      return new Response(null, {
        headers: {
          ...corsHeaders,
          "Access-Control-Max-Age": "86400",
        },
      });
    }

    const url = new URL(request.url);
    const path = url.pathname;

    // Public demo endpoint — no auth, IP rate-limited
    if (path === "/demo") {
      try {
        return await handleDemo(request, env, corsHeaders);
      } catch (err) {
        return jsonResponse({ error: "Request failed" }, 500, corsHeaders);
      }
    }

    try {
      const authHeader = request.headers.get("Authorization");
      if (!authHeader?.startsWith("Bearer ")) {
        return jsonResponse({ error: "Missing authorization" }, 401, corsHeaders);
      }
      const token = authHeader.slice(7);

      const payload = await verifyJWT(token, env.SUPABASE_URL);
      if (!payload) {
        return jsonResponse({ error: "Invalid token" }, 401, corsHeaders);
      }
      const userId = payload.sub as string;

      // URL-encode userId to prevent Supabase query injection (issue #8)
      const safeUserId = encodeURIComponent(userId);

      switch (path) {
        case "/transcribe":
          return await handleTranscribe(request, env, safeUserId, corsHeaders);
        case "/process":
          return await handleProcess(request, env, safeUserId, corsHeaders);
        case "/user-status":
          return await handleUserStatus(env, safeUserId, corsHeaders);
        case "/create-checkout":
          return await handleCreateCheckout(request, env, safeUserId, corsHeaders);
        default:
          return jsonResponse({ error: "Not found" }, 404, corsHeaders);
      }
    } catch (err) {
      return jsonResponse({ error: "Internal server error" }, 500, corsHeaders);
    }
  },
};

// ============================================================
// USER STATUS
// ============================================================

async function handleUserStatus(env: Env, safeUserId: string, cors: Record<string, string>): Promise<Response> {
  try {
    const profileResp = await fetch(
      `${env.SUPABASE_URL}/rest/v1/profiles?id=eq.${safeUserId}&select=email,display_name,avatar_url`,
      {
        headers: {
          apikey: env.SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        },
      }
    );
    const profiles = (await profileResp.json()) as { email: string; display_name: string; avatar_url: string }[];
    const profile = profiles?.[0];

    const subResp = await fetch(
      `${env.SUPABASE_URL}/rest/v1/subscriptions?user_id=eq.${safeUserId}&select=plan,words_used,word_limit,status,current_period_end`,
      {
        headers: {
          apikey: env.SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        },
      }
    );
    const subs = (await subResp.json()) as { plan: string; words_used: number; word_limit: number | null; status: string; current_period_end: string | null }[];
    const sub = subs?.[0];

    return jsonResponse({
      user_id: decodeURIComponent(safeUserId),
      email: profile?.email ?? "",
      display_name: profile?.display_name ?? null,
      avatar_url: profile?.avatar_url ?? null,
      plan: sub?.plan ?? "free",
      words_used: sub?.words_used ?? 0,
      word_limit: sub?.word_limit ?? 2000,
      subscription_status: sub?.status ?? "active",
      current_period_end: sub?.current_period_end ?? null,
    }, 200, cors);
  } catch {
    return jsonResponse({ error: "Failed to fetch user status" }, 500, cors);
  }
}

// ============================================================
// CREATE CHECKOUT
// ============================================================

async function handleCreateCheckout(request: Request, env: Env, safeUserId: string, cors: Record<string, string>): Promise<Response> {
  const STRIPE_SECRET_KEY = (env as Record<string, string>)["STRIPE_SECRET_KEY"];
  if (!STRIPE_SECRET_KEY) {
    return jsonResponse({ error: "Payments coming soon!" }, 503, cors);
  }

  try {
    const profileResp = await fetch(
      `${env.SUPABASE_URL}/rest/v1/profiles?id=eq.${safeUserId}&select=email,stripe_customer_id`,
      {
        headers: {
          apikey: env.SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        },
      }
    );
    const profiles = (await profileResp.json()) as { email: string; stripe_customer_id: string | null }[];
    const profile = profiles?.[0];

    let body: Record<string, unknown> = {};
    try { body = (await request.json()) as Record<string, unknown>; } catch {}

    const priceId = (body.price_id as string) || (env as Record<string, string>)["STRIPE_PRO_PRICE_ID"] || "";

    const params = new URLSearchParams();
    params.append("mode", "subscription");
    params.append("line_items[0][price]", priceId);
    params.append("line_items[0][quantity]", "1");
    params.append("success_url", "https://nimbusglide.ai/success?session_id={CHECKOUT_SESSION_ID}");
    params.append("cancel_url", "https://nimbusglide.ai/cancel");
    params.append("metadata[supabase_user_id]", decodeURIComponent(safeUserId));
    if (profile?.email) params.append("customer_email", profile.email);

    const stripeResp = await fetch("https://api.stripe.com/v1/checkout/sessions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: params.toString(),
    });

    if (!stripeResp.ok) {
      // issue #3: do NOT forward Stripe error body
      return jsonResponse({ error: "Failed to create checkout session" }, 502, cors);
    }

    const session = (await stripeResp.json()) as { url: string };
    return jsonResponse({ checkout_url: session.url }, 200, cors);
  } catch {
    return jsonResponse({ error: "Checkout failed" }, 500, cors);
  }
}

// ============================================================
// USAGE CHECK
// ============================================================

async function checkUsageLimit(env: Env, safeUserId: string): Promise<{ allowed: boolean; wordsUsed: number; wordLimit: number | null }> {
  try {
    const resp = await fetch(
      `${env.SUPABASE_URL}/rest/v1/subscriptions?user_id=eq.${safeUserId}&select=words_used,word_limit,plan`,
      {
        headers: {
          apikey: env.SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        },
      }
    );
    const rows = (await resp.json()) as { words_used: number; word_limit: number | null; plan: string }[];
    if (!rows?.[0]) return { allowed: true, wordsUsed: 0, wordLimit: 2000 };

    const { words_used, word_limit } = rows[0];
    if (word_limit === null) return { allowed: true, wordsUsed: words_used, wordLimit: null };
    return { allowed: words_used < word_limit, wordsUsed: words_used, wordLimit: word_limit };
  } catch {
    return { allowed: true, wordsUsed: 0, wordLimit: 2000 };
  }
}

// ============================================================
// TRANSCRIBE
// ============================================================

async function handleTranscribe(request: Request, env: Env, safeUserId: string, cors: Record<string, string>): Promise<Response> {
  // Check usage before anything else
  const usage = await checkUsageLimit(env, safeUserId);
  if (!usage.allowed) {
    return jsonResponse({
      error: "usage_limit_reached",
      words_used: usage.wordsUsed,
      word_limit: usage.wordLimit,
    }, 403, cors);
  }

  // issue #5: enforce payload size limit
  const contentLength = parseInt(request.headers.get("Content-Length") || "0", 10);
  if (contentLength > MAX_AUDIO_BYTES) {
    return jsonResponse({ error: "Audio file too large (25 MB max)" }, 413, cors);
  }

  const formData = await request.formData();
  const audioFile = formData.get("file");
  if (!audioFile || !(audioFile instanceof File)) {
    return jsonResponse({ error: "No audio file provided" }, 400, cors);
  }

  // issue #5: also check actual size after reading
  if (audioFile.size > MAX_AUDIO_BYTES) {
    return jsonResponse({ error: "Audio file too large (25 MB max)" }, 413, cors);
  }

  // issue #11: validate MIME type
  const mimeType = audioFile.type.toLowerCase().split(";")[0].trim();
  if (!ALLOWED_AUDIO_TYPES.has(mimeType)) {
    return jsonResponse({ error: "Unsupported audio format" }, 415, cors);
  }

  const groqForm = new FormData();
  groqForm.append("model", "whisper-large-v3");
  groqForm.append("response_format", "text");
  groqForm.append("file", audioFile, audioFile.name);

  const groqResp = await fetch("https://api.groq.com/openai/v1/audio/transcriptions", {
    method: "POST",
    headers: { Authorization: `Bearer ${env.GROQ_API_KEY}` },
    body: groqForm,
  });

  if (!groqResp.ok) {
    // issue #3: don't leak Groq error body
    return jsonResponse({ error: "Transcription failed" }, 502, cors);
  }

  const transcript = (await groqResp.text()).trim();
  return jsonResponse({ transcript }, 200, cors);
}

// ============================================================
// PROCESS
// ============================================================

async function handleProcess(request: Request, env: Env, safeUserId: string, cors: Record<string, string>): Promise<Response> {
  const usage = await checkUsageLimit(env, safeUserId);
  if (!usage.allowed) {
    return jsonResponse({
      error: "usage_limit_reached",
      words_used: usage.wordsUsed,
      word_limit: usage.wordLimit,
    }, 403, cors);
  }

  const body = (await request.json()) as Record<string, unknown>;
  const { model, messages, temperature, max_tokens } = body;

  if (!messages || !Array.isArray(messages) || messages.length === 0) {
    return jsonResponse({ error: "messages required" }, 400, cors);
  }

  // issue #12: validate message structure — only allow string role+content pairs
  const validRoles = new Set(["system", "user", "assistant"]);
  for (const msg of messages) {
    if (
      typeof msg !== "object" || msg === null ||
      typeof (msg as Record<string, unknown>).role !== "string" ||
      typeof (msg as Record<string, unknown>).content !== "string" ||
      !validRoles.has((msg as Record<string, unknown>).role as string)
    ) {
      return jsonResponse({ error: "Invalid message format" }, 400, cors);
    }
  }

  // issue #7: restrict model to allowlist
  const requestedModel = typeof model === "string" ? model : DEFAULT_MODEL;
  const safeModel = ALLOWED_MODELS.has(requestedModel) ? requestedModel : DEFAULT_MODEL;

  // issue #7: cap max_tokens
  const requestedTokens = typeof max_tokens === "number" ? max_tokens : 2048;
  const safeMaxTokens = Math.min(Math.max(1, requestedTokens), MAX_TOKENS_LIMIT);

  // issue #2: prevent prompt injection — fence user-controlled content in messages
  // The system prompt is built client-side and passed as the first system message.
  // We strip any messages that try to override system context after the first system message.
  const systemMessages = messages.filter((m: Record<string, unknown>) => m.role === "system");
  const nonSystemMessages = messages.filter((m: Record<string, unknown>) => m.role !== "system");

  // Only allow one system message (the legitimate one from the app)
  const safeMessages = [
    ...(systemMessages.slice(0, 1)), // at most one system message
    ...nonSystemMessages,
  ];

  const groqResp = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.GROQ_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: safeModel,
      messages: safeMessages,
      temperature: typeof temperature === "number" ? Math.min(Math.max(0, temperature), 2) : 0.0,
      max_tokens: safeMaxTokens,
    }),
  });

  if (!groqResp.ok) {
    // issue #3: don't leak Groq error body
    return jsonResponse({ error: "Processing failed" }, 502, cors);
  }

  const groqJson = (await groqResp.json()) as {
    choices?: { message?: { content?: string } }[];
  };
  const resultText = groqJson.choices?.[0]?.message?.content?.trim() ?? "";
  const wordCount = resultText.split(/\s+/).filter((w) => w.length > 0).length;

  // Atomic usage increment (issue #6)
  await incrementUsageAtomic(env, safeUserId, wordCount);

  return jsonResponse({ result: resultText, words: wordCount }, 200, cors);
}

// ============================================================
// ATOMIC USAGE INCREMENT (issue #6)
// Uses Supabase RPC for atomic increment to avoid race conditions.
// Falls back to read-write if RPC not available.
// ============================================================

async function incrementUsageAtomic(env: Env, safeUserId: string, words: number) {
  try {
    // Try atomic RPC first (requires `increment_words_used` stored function in Supabase)
    const rpcResp = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/increment_words_used`, {
      method: "POST",
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ p_user_id: decodeURIComponent(safeUserId), p_words: words }),
    });

    if (rpcResp.ok) {
      // Also log usage
      await logUsage(env, safeUserId, words);
      return;
    }

    // Fallback: read-write (non-atomic, acceptable for now)
    const resp = await fetch(
      `${env.SUPABASE_URL}/rest/v1/subscriptions?user_id=eq.${safeUserId}&select=words_used`,
      {
        headers: {
          apikey: env.SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        },
      }
    );
    const rows = (await resp.json()) as { words_used: number }[];
    const currentCount = rows?.[0]?.words_used ?? 0;

    await fetch(`${env.SUPABASE_URL}/rest/v1/subscriptions?user_id=eq.${safeUserId}`, {
      method: "PATCH",
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        "Content-Type": "application/json",
        Prefer: "return=minimal",
      },
      body: JSON.stringify({ words_used: currentCount + words }),
    });

    await logUsage(env, safeUserId, words);
  } catch {
    // Don't block response if tracking fails
  }
}

async function logUsage(env: Env, safeUserId: string, words: number) {
  await fetch(`${env.SUPABASE_URL}/rest/v1/usage_log`, {
    method: "POST",
    headers: {
      apikey: env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ user_id: decodeURIComponent(safeUserId), words, action: "dictation" }),
  }).catch(() => {});
}

// ============================================================
// DEMO ENDPOINT (public, rate-limited, no auth)
// ============================================================

const demoRateLimit: Map<string, { count: number; resetAt: number }> = new Map();
const DEMO_MAX_REQUESTS = 5;
const DEMO_WINDOW_MS = 60 * 60 * 1000;
const DEMO_MAX_AUDIO_BYTES = 5 * 1024 * 1024;

function checkDemoRate(key: string): boolean {
  const now = Date.now();
  const entry = demoRateLimit.get(key);
  if (!entry || now > entry.resetAt) {
    demoRateLimit.set(key, { count: 1, resetAt: now + DEMO_WINDOW_MS });
    return true;
  }
  if (entry.count >= DEMO_MAX_REQUESTS) return false;
  entry.count++;
  return true;
}

function getDeviceId(request: Request): string | null {
  const cookie = request.headers.get("Cookie") || "";
  const match = cookie.match(/ng_device=([a-f0-9-]+)/);
  return match ? match[1] : null;
}

function generateDeviceId(): string {
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === "x" ? r : (r & 0x3) | 0x8).toString(16);
  });
}

async function handleDemo(request: Request, env: Env, cors: Record<string, string>): Promise<Response> {
  if (request.method !== "POST") {
    return jsonResponse({ error: "POST required" }, 405, cors);
  }

  // issue #9: only use CF-Connecting-IP, never X-Forwarded-For (client-spoofable)
  const ip = request.headers.get("CF-Connecting-IP") || "unknown";
  let deviceId = getDeviceId(request);
  const isNewDevice = !deviceId;
  if (!deviceId) deviceId = generateDeviceId();

  const ipAllowed = checkDemoRate(`ip:${ip}`);
  const deviceAllowed = checkDemoRate(`dev:${deviceId}`);
  if (!ipAllowed || !deviceAllowed) {
    return jsonResponse({ error: "Rate limit exceeded. Try again in an hour." }, 429, cors);
  }

  const formData = await request.formData();
  const audioFile = formData.get("file");
  if (!audioFile || !(audioFile instanceof File)) {
    return jsonResponse({ error: "No audio file" }, 400, cors);
  }

  if (audioFile.size > DEMO_MAX_AUDIO_BYTES) {
    return jsonResponse({ error: "Audio too long (30s max)" }, 413, cors);
  }

  // issue #11: validate MIME type for demo too
  const mimeType = audioFile.type.toLowerCase().split(";")[0].trim();
  if (!ALLOWED_AUDIO_TYPES.has(mimeType)) {
    return jsonResponse({ error: "Unsupported audio format" }, 415, cors);
  }

  // Step 1: Transcribe
  const groqForm = new FormData();
  groqForm.append("model", "whisper-large-v3");
  groqForm.append("response_format", "text");
  groqForm.append("file", audioFile, audioFile.name);

  const transcribeResp = await fetch("https://api.groq.com/openai/v1/audio/transcriptions", {
    method: "POST",
    headers: { Authorization: `Bearer ${env.GROQ_API_KEY}` },
    body: groqForm,
  });

  if (!transcribeResp.ok) {
    return jsonResponse({ error: "Transcription failed" }, 502, cors);
  }

  const transcript = (await transcribeResp.text()).trim();
  if (!transcript) {
    return jsonResponse({ error: "No speech detected" }, 400, cors);
  }

  // Step 2: Detect wake word with fuzzy phonetic matching
  const nimbusVariants = "nimbus|nimbis|nimbes|nimba|nimbas|nimbus's|nimbus'";
  const glideVariants = "glide|guide|blood|flood|slide|glade|glyde|glied|glad|cloud|clide|clyde|glined|glowed|slied|glite|gloid|blude|blide|glood";
  const wakeRegex = new RegExp(`(${nimbusVariants})[\\s,\\-.]*(?:${glideVariants})`, "i");
  const wakeMatch = wakeRegex.exec(transcript);

  // issue #2: separate user content from system prompt using XML-fenced delimiters
  // so the transcript cannot escape into the instruction context
  let systemPrompt: string;
  let userContent: string;

  if (wakeMatch) {
    const wakeIndex = wakeMatch.index;
    const wakeLength = wakeMatch[0].length;
    const beforeWake = transcript.slice(0, wakeIndex).trim();
    const afterWake = transcript.slice(wakeIndex + wakeLength).trim();
    const command = afterWake.replace(/^[,.\s]+/, "").trim();

    // issue #2: use XML delimiters to prevent prompt injection
    systemPrompt = `You are NimbusGlide, an AI dictation assistant. Execute the command on the content inside <content> tags and output ONLY the result.`;
    userContent = `<content>${beforeWake}</content>\n<command>${command}</command>\nOUTPUT ONLY THE RESULT:`;
  } else {
    systemPrompt = "You are an expert transcription copyeditor. Fix stutters, filler words (um, uh, like), and grammar. Add proper punctuation and capitalization. Keep the original meaning and tone exactly. Output ONLY the polished text, nothing else.";
    // issue #2: fence the transcript so injected instructions cannot escape
    userContent = `<transcript>${transcript}</transcript>\nOUTPUT ONLY THE POLISHED VERSION:`;
  }

  const processResp = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.GROQ_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: DEFAULT_MODEL,
      temperature: 0.0,
      max_tokens: 1024,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userContent },
      ],
    }),
  });

  if (!processResp.ok) {
    return demoResponse({ transcript, polished: transcript, wakeWordDetected: !!wakeMatch }, deviceId, isNewDevice, cors);
  }

  const processJson = (await processResp.json()) as {
    choices?: { message?: { content?: string } }[];
  };
  const polished = processJson.choices?.[0]?.message?.content?.trim() ?? transcript;

  return demoResponse({ transcript, polished, wakeWordDetected: !!wakeMatch }, deviceId, isNewDevice, cors);
}

function demoResponse(data: unknown, deviceId: string, setCookie: boolean, cors: Record<string, string>): Response {
  const resp = jsonResponse(data, 200, cors);
  if (setCookie) {
    resp.headers.set(
      "Set-Cookie",
      `ng_device=${deviceId}; Path=/; Max-Age=31536000; SameSite=None; Secure`
    );
  }
  return resp;
}

// ============================================================
// JWT VERIFICATION via JWKS (issue #4 — validate iss + aud + exp)
// ============================================================

async function verifyJWT(
  token: string,
  supabaseURL: string
): Promise<Record<string, unknown> | null> {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;

    const headerStr = base64UrlDecodeStr(parts[0]);
    const header = JSON.parse(headerStr) as { alg: string; kid?: string };

    const payloadStr = base64UrlDecodeStr(parts[1]);
    const payload = JSON.parse(payloadStr) as Record<string, unknown>;

    // issue #4: require exp claim and reject expired tokens
    const exp = payload.exp;
    if (typeof exp !== "number") return null; // missing exp — reject
    if (Date.now() / 1000 > exp) return null;  // expired

    // issue #4: validate issuer — must match this Supabase project
    const iss = payload.iss as string | undefined;
    if (!iss || !iss.includes(SUPABASE_PROJECT_REF)) return null;

    // issue #4: validate audience — must be "authenticated"
    const aud = payload.aud;
    const audOk = aud === "authenticated" ||
      (Array.isArray(aud) && aud.includes("authenticated"));
    if (!audOk) return null;

    const signatureInput = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
    const signature = base64UrlDecode(parts[2]);

    if (header.alg === "ES256") {
      const key = await getJWKSKey(supabaseURL, header.kid);
      if (!key) return null;

      const valid = await crypto.subtle.verify(
        { name: "ECDSA", hash: "SHA-256" },
        key,
        signature.buffer as ArrayBuffer,
        signatureInput
      );
      return valid ? payload : null;
    }

    return null; // unsupported algorithm
  } catch {
    return null;
  }
}

async function getJWKSKey(supabaseURL: string, kid?: string): Promise<CryptoKey | null> {
  const now = Date.now();
  if (kid && cachedJWKS[kid] && now - jwksFetchedAt < 300_000) {
    return cachedJWKS[kid];
  }

  try {
    const resp = await fetch(`${supabaseURL}/auth/v1/.well-known/jwks.json`);
    if (!resp.ok) return null;

    const jwks = (await resp.json()) as { keys: JWK[] };

    cachedJWKS = {};
    for (const jwk of jwks.keys) {
      if (jwk.kty === "EC" && jwk.crv === "P-256" && jwk.use === "sig") {
        const key = await crypto.subtle.importKey(
          "jwk",
          jwk,
          { name: "ECDSA", namedCurve: "P-256" },
          false,
          ["verify"]
        );
        if (jwk.kid) cachedJWKS[jwk.kid] = key;
        if (!kid) return key;
      }
    }

    jwksFetchedAt = now;
    return kid ? cachedJWKS[kid] ?? null : null;
  } catch {
    return null;
  }
}

interface JWK {
  kty: string;
  crv?: string;
  use?: string;
  kid?: string;
  x?: string;
  y?: string;
  [key: string]: unknown;
}

function base64UrlDecode(str: string): Uint8Array {
  let base64 = str.replace(/-/g, "+").replace(/_/g, "/");
  while (base64.length % 4 !== 0) base64 += "=";
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function base64UrlDecodeStr(str: string): string {
  let base64 = str.replace(/-/g, "+").replace(/_/g, "/");
  while (base64.length % 4 !== 0) base64 += "=";
  return atob(base64);
}

function jsonResponse(data: unknown, status = 200, cors: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...cors,
    },
  });
}
