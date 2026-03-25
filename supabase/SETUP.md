# NimbusGlide Supabase Setup

## 1. Create a Supabase Project

1. Go to https://supabase.com and create a new project
2. Note your **Project URL** (e.g. `https://abcdefgh.supabase.co`)
3. Note your **anon (public) key** from Settings > API
4. Note your **service_role key** (keep this secret — only for Edge Functions)

## 2. Run the Database Schema

1. Go to **SQL Editor** in the Supabase dashboard
2. Paste the contents of `schema.sql` and run it
3. Go to **Database > Extensions**, enable `pg_cron`
4. Then run the commented-out cron schedule from the bottom of `schema.sql`

## 3. Configure Google OAuth

1. Go to **Authentication > Providers > Google**
2. Enable it
3. Create OAuth credentials at https://console.cloud.google.com/apis/credentials
   - Application type: **Web application**
   - Authorized redirect URI: `https://<your-project>.supabase.co/auth/v1/callback`
4. Copy the **Client ID** and **Client Secret** into Supabase

## 4. Configure Apple Sign-In

1. Go to **Authentication > Providers > Apple**
2. Enable it
3. In the Apple Developer Portal (https://developer.apple.com):
   - Create a **Services ID** for web/desktop sign-in
   - Configure the **Return URL**: `https://<your-project>.supabase.co/auth/v1/callback`
   - Create a **Sign In with Apple private key**
4. Enter the **Services ID**, **Team ID**, **Key ID**, and upload the **private key** in Supabase

## 5. Configure Redirect URLs

1. Go to **Authentication > URL Configuration**
2. Add to **Redirect URLs**:
   - `nimbusglide://auth/callback` (for the macOS app)
   - `https://nimbusglide.ai` (for the website)

## 6. Set Up Edge Function Secrets

Deploy secrets that the Edge Functions need:

```bash
supabase secrets set GROQ_API_KEY=gsk_your_groq_api_key_here
supabase secrets set STRIPE_SECRET_KEY=sk_test_your_stripe_key_here
supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_your_webhook_secret_here
```

## 7. Deploy Edge Functions

From the project root:

```bash
supabase functions deploy transcribe
supabase functions deploy process
supabase functions deploy user-status
supabase functions deploy create-checkout
supabase functions deploy stripe-webhook
```

## 8. Configure Stripe Webhook

1. In the Stripe Dashboard, go to **Developers > Webhooks**
2. Add endpoint: `https://<your-project>.supabase.co/functions/v1/stripe-webhook`
3. Select events:
   - `checkout.session.completed`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `invoice.payment_failed`
4. Copy the **Signing secret** and set it as `STRIPE_WEBHOOK_SECRET` (step 6)

## 9. Create Stripe Product

1. In Stripe Dashboard, create a **Product**: "NimbusGlide Pro"
2. Add two **Prices**:
   - $5/month (monthly recurring)
   - $36/year (annual recurring — works out to $3/month)
3. Note both **Price IDs** (e.g. `price_xxxxx`) — these go in the `create-checkout` Edge Function

## 10. Update the App Config

Replace the contents of `Resources/Secrets.plist` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>SupabaseURL</key>
    <string>https://YOUR_PROJECT.supabase.co</string>
    <key>SupabaseAnonKey</key>
    <string>YOUR_ANON_KEY_HERE</string>
</dict>
</plist>
```
