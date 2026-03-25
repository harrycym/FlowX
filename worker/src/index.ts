export interface Env {
  GROQ_API_KEY: string;
  SUPABASE_URL: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
  DEMO_RATE_LIMITER: DurableObjectNamespace;
}

// Cache JWKS keys in memory (persists across requests on same isolate)
let cachedJWKS: Record<string, CryptoKey> = {};
let jwksFetchedAt = 0;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const origin = request.headers.get("Origin") || "*";

    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": origin,
          "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
          "Access-Control-Allow-Headers": "authorization, content-type",
          "Access-Control-Allow-Credentials": "true",
        },
      });
    }

    const url = new URL(request.url);
    const path = url.pathname;

    // Public demo endpoint — no auth, IP rate-limited
    if (path === "/demo") {
      try {
        return await handleDemo(request, env, origin);
      } catch (err) {
        return jsonResponse({ error: (err as Error).message }, 500, origin);
      }
    }

    try {
      const authHeader = request.headers.get("Authorization");
      if (!authHeader?.startsWith("Bearer ")) {
        return jsonResponse({ error: "Missing authorization" }, 401, origin);
      }
      const token = authHeader.slice(7);

      const payload = await verifyJWT(token, env.SUPABASE_URL);
      if (!payload) {
        return jsonResponse({ error: "Invalid token" }, 401, origin);
      }
      const userId = payload.sub as string;

      switch (path) {
        case "/transcribe":
          return await handleTranscribe(request, env, userId, origin);
        case "/process":
          return await handleProcess(request, env, userId, origin);
        case "/user-status":
          return await handleUserStatus(env, userId, origin);
        case "/create-checkout":
          return await handleCreateCheckout(request, env, userId, origin);
        default:
          return jsonResponse({ error: "Not found" }, 404, origin);
      }
    } catch (err) {
      return jsonResponse({ error: (err as Error).message }, 500, origin);
    }
  },
};

// ============================================================
// USER STATUS
// ============================================================

async function handleUserStatus(env: Env, userId: string, origin = "*"): Promise<Response> {
  try {
    // Fetch profile
    const profileResp = await fetch(
      `${env.SUPABASE_URL}/rest/v1/profiles?id=eq.${userId}&select=email,display_name,avatar_url`,
      {
        headers: {
          apikey: env.SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        },
      }
    );
    const profiles = (await profileResp.json()) as { email: string; display_name: string; avatar_url: string }[];
    const profile = profiles?.[0];

    // Fetch subscription
    const subResp = await fetch(
      `${env.SUPABASE_URL}/rest/v1/subscriptions?user_id=eq.${userId}&select=plan,words_used,word_limit,status,current_period_end`,
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
      user_id: userId,
      email: profile?.email ?? "",
      display_name: profile?.display_name ?? null,
      avatar_url: profile?.avatar_url ?? null,
      plan: sub?.plan ?? "free",
      words_used: sub?.words_used ?? 0,
      word_limit: sub?.word_limit ?? 2000,
      subscription_status: sub?.status ?? "active",
      current_period_end: sub?.current_period_end ?? null,
    }, 200, origin);
  } catch (err) {
    return jsonResponse({ error: (err as Error).message }, 500, origin);
  }
}

// ============================================================
// CREATE CHECKOUT (Stripe — proxied through Worker)
// ============================================================

async function handleCreateCheckout(request: Request, env: Env, userId: string, origin = "*"): Promise<Response> {
  // For now, return a friendly message until Stripe is fully wired
  // When Stripe is set up, this will create a Checkout Session
  const STRIPE_SECRET_KEY = (env as Record<string, string>)["STRIPE_SECRET_KEY"];
  if (!STRIPE_SECRET_KEY) {
    return jsonResponse({ error: "Payments coming soon!" }, 503, origin);
  }

  try {
    // Get user email
    const profileResp = await fetch(
      `${env.SUPABASE_URL}/rest/v1/profiles?id=eq.${userId}&select=email,stripe_customer_id`,
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

    // Create Stripe Checkout Session via Stripe API
    const params = new URLSearchParams();
    params.append("mode", "subscription");
    params.append("line_items[0][price]", priceId);
    params.append("line_items[0][quantity]", "1");
    params.append("success_url", "https://nimbusglide.ai/success?session_id={CHECKOUT_SESSION_ID}");
    params.append("cancel_url", "https://nimbusglide.ai/cancel");
    params.append("metadata[supabase_user_id]", userId);
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
      const err = await stripeResp.text();
      return jsonResponse({ error: `Stripe error: ${err}` }, 502, origin);
    }

    const session = (await stripeResp.json()) as { url: string };
    return jsonResponse({ checkout_url: session.url }, 200, origin);
  } catch (err) {
    return jsonResponse({ error: (err as Error).message }, 500, origin);
  }
}

// ============================================================
// USAGE CHECK (fast Supabase REST call)
// ============================================================

async function checkUsageLimit(env: Env, userId: string): Promise<{ allowed: boolean; wordsUsed: number; wordLimit: number | null }> {
  try {
    const resp = await fetch(
      `${env.SUPABASE_URL}/rest/v1/subscriptions?user_id=eq.${userId}&select=words_used,word_limit,plan`,
      {
        headers: {
          apikey: env.SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        },
      }
    );
    const rows = (await resp.json()) as { words_used: number; word_limit: number | null; plan: string }[];
    if (!rows?.[0]) return { allowed: true, wordsUsed: 0, wordLimit: 2000 }; // no subscription = allow (new user)

    const { words_used, word_limit } = rows[0];
    if (word_limit === null) return { allowed: true, wordsUsed: words_used, wordLimit: null }; // pro = unlimited
    return { allowed: words_used < word_limit, wordsUsed: words_used, wordLimit: word_limit };
  } catch {
    return { allowed: true, wordsUsed: 0, wordLimit: 2000 }; // on error, allow (don't block paying users)
  }
}

// ============================================================
// TRANSCRIBE
// ============================================================

async function handleTranscribe(request: Request, env: Env, userId: string, origin = "*"): Promise<Response> {
  // Check usage limit before wasting a Groq call
  const usage = await checkUsageLimit(env, userId);
  if (!usage.allowed) {
    return jsonResponse({
      error: "usage_limit_reached",
      words_used: usage.wordsUsed,
      word_limit: usage.wordLimit,
    }, 403, origin);
  }

  const formData = await request.formData();
  const audioFile = formData.get("file");
  if (!audioFile || !(audioFile instanceof File)) {
    return jsonResponse({ error: "No audio file" }, 400, origin);
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
    const errBody = await groqResp.text();
    return jsonResponse({ error: `Groq error (${groqResp.status}): ${errBody}` }, 502, origin);
  }

  const transcript = (await groqResp.text()).trim();
  return jsonResponse({ transcript }, 200, origin);
}

// ============================================================
// PROCESS
// ============================================================

async function handleProcess(request: Request, env: Env, userId: string, origin = "*"): Promise<Response> {
  // Check usage limit
  const usage = await checkUsageLimit(env, userId);
  if (!usage.allowed) {
    return jsonResponse({
      error: "usage_limit_reached",
      words_used: usage.wordsUsed,
      word_limit: usage.wordLimit,
    }, 403, origin);
  }

  const body = (await request.json()) as Record<string, unknown>;
  const { model, messages, temperature, max_tokens } = body;

  if (!messages || !Array.isArray(messages)) {
    return jsonResponse({ error: "messages required" }, 400, origin);
  }

  const groqResp = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.GROQ_API_KEY}`,
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
    return jsonResponse({ error: `Groq error: ${errBody}` }, 502, origin);
  }

  const groqJson = (await groqResp.json()) as {
    choices?: { message?: { content?: string } }[];
  };
  const resultText = groqJson.choices?.[0]?.message?.content?.trim() ?? "";
  const wordCount = resultText.split(/\s+/).filter((w) => w.length > 0).length;

  // Update usage SYNCHRONOUSLY before returning — so the next request sees the updated count
  await updateUsageSync(env, userId, wordCount);

  return jsonResponse({ result: resultText, words: wordCount }, 200, origin);
}

// ============================================================
// USAGE UPDATE (synchronous — must complete before response)
// ============================================================

async function updateUsageSync(env: Env, userId: string, words: number) {
  try {
    // Get current count
    const resp = await fetch(
      `${env.SUPABASE_URL}/rest/v1/subscriptions?user_id=eq.${userId}&select=words_used`,
      {
        headers: {
          apikey: env.SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        },
      }
    );
    const rows = (await resp.json()) as { words_used: number }[];
    const currentCount = rows?.[0]?.words_used ?? 0;
    const newCount = currentCount + words;

    // Update count
    await fetch(
      `${env.SUPABASE_URL}/rest/v1/subscriptions?user_id=eq.${userId}`,
      {
        method: "PATCH",
        headers: {
          apikey: env.SUPABASE_SERVICE_ROLE_KEY,
          Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
          "Content-Type": "application/json",
          Prefer: "return=minimal",
        },
        body: JSON.stringify({ words_used: newCount }),
      }
    );

    // Log usage
    await fetch(`${env.SUPABASE_URL}/rest/v1/usage_log`, {
      method: "POST",
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ user_id: userId, words, action: "dictation" }),
    });
  } catch {
    // Don't block the response if usage tracking fails
  }
}

// ============================================================
// USAGE REPORTING (fire-and-forget — kept for transcribe endpoint)
// ============================================================

function reportUsageAsync(env: Env, userId: string, words: number) {
  // Log usage (always works, no increment needed)
  fetch(`${env.SUPABASE_URL}/rest/v1/usage_log`, {
    method: "POST",
    headers: {
      apikey: env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ user_id: userId, words, action: "dictation" }),
  }).catch(() => {});

  // Increment words_used via raw SQL (Supabase supports this via RPC)
  // Fall back to fetching current value and updating
  fetch(`${env.SUPABASE_URL}/rest/v1/subscriptions?user_id=eq.${userId}&select=words_used`, {
    headers: {
      apikey: env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
    },
  })
    .then((r) => r.json())
    .then((data: unknown) => {
      const rows = data as { words_used: number }[];
      if (rows?.[0]) {
        const newCount = rows[0].words_used + words;
        fetch(`${env.SUPABASE_URL}/rest/v1/subscriptions?user_id=eq.${userId}`, {
          method: "PATCH",
          headers: {
            apikey: env.SUPABASE_SERVICE_ROLE_KEY,
            Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
            "Content-Type": "application/json",
            Prefer: "return=minimal",
          },
          body: JSON.stringify({ words_used: newCount }),
        }).catch(() => {});
      }
    })
    .catch(() => {});
}

// ============================================================
// DEMO RATE LIMITER (Durable Object — atomic, single-threaded)
// ============================================================

const DEMO_MAX_PER_USER = 5;        // per fingerprint or IP, per hour
const DEMO_GLOBAL_MAX = 500;         // total demo requests per hour across all users
const DEMO_MAX_AUDIO_BYTES = 5 * 1024 * 1024; // 5MB (~30s of audio)

export class DemoRateLimiter {
  private counts: Map<string, number> = new Map();
  private currentHour: number = 0;

  constructor(private state: DurableObjectState) {
    // Restore persisted state on wake
    state.blockConcurrencyWhile(async () => {
      const stored = await state.storage.get<{ counts: [string, number][]; hour: number }>("data");
      if (stored) {
        const nowHour = Math.floor(Date.now() / 3_600_000);
        if (stored.hour === nowHour) {
          this.counts = new Map(stored.counts);
          this.currentHour = stored.hour;
        }
        // else: stale data from a previous hour, start fresh
      }
    });
  }

  async fetch(request: Request): Promise<Response> {
    const { keys } = (await request.json()) as { keys: string[] };
    const nowHour = Math.floor(Date.now() / 3_600_000);

    // Reset all counters when the hour rolls over
    if (nowHour !== this.currentHour) {
      this.counts = new Map();
      this.currentHour = nowHour;
    }

    // Atomically increment each key and check limits
    const results: Record<string, { count: number; allowed: boolean }> = {};
    for (const key of keys) {
      const prev = this.counts.get(key) ?? 0;
      const next = prev + 1;
      this.counts.set(key, next);

      const limit = key.startsWith("global:") ? DEMO_GLOBAL_MAX : DEMO_MAX_PER_USER;
      results[key] = { count: next, allowed: next <= limit };
    }

    // Persist to durable storage (survives eviction)
    await this.state.storage.put("data", {
      counts: Array.from(this.counts.entries()),
      hour: this.currentHour,
    });

    return new Response(JSON.stringify(results), {
      headers: { "Content-Type": "application/json" },
    });
  }
}

// ============================================================
// DEMO ENDPOINT (public, rate-limited via Durable Object, no auth)
// ============================================================

// Build a composite fingerprint from multiple request signals.
async function buildFingerprint(request: Request): Promise<string> {
  const ip = request.headers.get("CF-Connecting-IP") || request.headers.get("X-Forwarded-For") || "unknown";
  const asn = (request as unknown as { cf?: { asn?: number } }).cf?.asn ?? 0;
  const ua = request.headers.get("User-Agent") || "";
  const lang = request.headers.get("Accept-Language") || "";
  const raw = `${ip}|${asn}|${ua}|${lang}`;
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(raw));
  return Array.from(new Uint8Array(hash)).map(b => b.toString(16).padStart(2, "0")).join("");
}

async function checkDemoRateLimit(
  env: Env,
  request: Request,
): Promise<{ allowed: boolean; reason?: string }> {
  const ip = request.headers.get("CF-Connecting-IP") || request.headers.get("X-Forwarded-For") || "unknown";
  const fingerprint = await buildFingerprint(request);

  // All rate limit checks go to a single DO instance for atomic consistency
  const id = env.DEMO_RATE_LIMITER.idFromName("singleton");
  const stub = env.DEMO_RATE_LIMITER.get(id);

  const keys = [`global:hour`, `ip:${ip}`, `fp:${fingerprint}`];
  const resp = await stub.fetch("https://rate-limiter/check", {
    method: "POST",
    body: JSON.stringify({ keys }),
  });

  const results = (await resp.json()) as Record<string, { count: number; allowed: boolean }>;

  if (!results["global:hour"].allowed) {
    return { allowed: false, reason: "Demo is busy right now. Please try again later." };
  }
  if (!results[`ip:${ip}`].allowed) {
    return { allowed: false, reason: "Rate limit exceeded. Try again in an hour." };
  }
  if (!results[`fp:${fingerprint}`].allowed) {
    return { allowed: false, reason: "Rate limit exceeded. Try again in an hour." };
  }
  return { allowed: true };
}

async function handleDemo(request: Request, env: Env, origin: string): Promise<Response> {
  if (request.method !== "POST") {
    return jsonResponse({ error: "POST required" }, 405, origin);
  }

  // Atomic rate limit check via Durable Object
  const rateCheck = await checkDemoRateLimit(env, request);
  if (!rateCheck.allowed) {
    return jsonResponse({ error: rateCheck.reason }, 429, origin);
  }

  const formData = await request.formData();
  const audioFile = formData.get("file");
  if (!audioFile || !(audioFile instanceof File)) {
    return jsonResponse({ error: "No audio file" }, 400, origin);
  }

  if (audioFile.size > DEMO_MAX_AUDIO_BYTES) {
    return jsonResponse({ error: "Audio too long (30s max)" }, 413, origin);
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
    const errBody = await transcribeResp.text();
    return jsonResponse({ error: `Transcription failed: ${errBody}` }, 502, origin);
  }

  const transcript = (await transcribeResp.text()).trim();
  if (!transcript) {
    return jsonResponse({ error: "No speech detected" }, 400, origin);
  }

  // Step 2: Detect wake word with fuzzy phonetic matching
  // Whisper often mistranscribes "Nimbus Glide" as "Nimbus Blood", "Nimbus Guide", etc.
  const nimbusVariants = "nimbus|nimbis|nimbes|nimba|nimbas|nimbus's|nimbus'";
  const glideVariants = "glide|guide|blood|flood|slide|glade|glyde|glied|glad|cloud|clide|clyde|glined|glowed|slied|glite|gloid|blude|blide|glood";
  const wakeRegex = new RegExp(`(${nimbusVariants})[\\s,\\-.]*(?:${glideVariants})`, "i");
  const wakeMatch = wakeRegex.exec(transcript);

  let systemPrompt: string;
  let userContent: string;

  if (wakeMatch) {
    const wakeIndex = wakeMatch.index;
    const wakeLength = wakeMatch[0].length;
    // Split: content before wake word = context, after = command
    const beforeWake = transcript.slice(0, wakeIndex).trim();
    const afterWake = transcript.slice(wakeIndex + wakeLength).trim();
    // Remove leading punctuation/comma from the command
    const command = afterWake.replace(/^[,.\s]+/, "").trim();

    systemPrompt = `You are NimbusGlide, an AI dictation assistant with a wake word feature.

The user dictated some content, then said "NimbusGlide" followed by a formatting command.

CONTENT (what the user dictated before the wake word):
"${beforeWake}"

COMMAND (what the user said after "NimbusGlide"):
"${command}"

Execute the command on the content. For example:
- "draft this as an email" → reformat the content as a professional email
- "make this an AI prompt" → reformat as a detailed AI prompt
- "format as meeting notes" → reformat as structured meeting notes
- "make this a Slack message" → reformat as a concise Slack message
- "format as a clinical note" → reformat as a medical clinical note
- Any other instruction → follow it faithfully

Output ONLY the reformatted text. No explanations, no preamble.`;
    userContent = beforeWake;
  } else {
    // No wake word — just polish
    systemPrompt = "You are an expert transcription copyeditor. Fix stutters, filler words (um, uh, like), and grammar. Add proper punctuation and capitalization. Keep the original meaning and tone exactly. Output ONLY the polished text, nothing else.";
    userContent = transcript;
  }

  const processResp = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.GROQ_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "llama-3.3-70b-versatile",
      temperature: 0.0,
      max_tokens: 1024,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userContent },
      ],
    }),
  });

  if (!processResp.ok) {
    return jsonResponse({ transcript, polished: transcript, wakeWordDetected: !!wakeMatch }, 200, origin);
  }

  const processJson = (await processResp.json()) as {
    choices?: { message?: { content?: string } }[];
  };
  const polished = processJson.choices?.[0]?.message?.content?.trim() ?? transcript;

  return jsonResponse({ transcript, polished, wakeWordDetected: !!wakeMatch }, 200, origin);
}

// ============================================================
// JWT VERIFICATION via JWKS (supports ECC P-256 + HS256)
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

    // Check expiry first (cheap, no crypto)
    const exp = payload.exp as number;
    if (exp && Date.now() / 1000 > exp) return null;

    const signatureInput = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
    const signature = base64UrlDecode(parts[2]);

    if (header.alg === "ES256") {
      // ECC P-256 — verify via JWKS
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

    // Unsupported algorithm
    return null;
  } catch {
    return null;
  }
}

async function getJWKSKey(supabaseURL: string, kid?: string): Promise<CryptoKey | null> {
  // Cache JWKS for 5 minutes
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
        // If no specific kid requested, use the first one
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

function jsonResponse(data: unknown, status = 200, origin = "*"): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Credentials": "true",
    },
  });
}
