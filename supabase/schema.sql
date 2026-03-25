-- NimbusGlide Database Schema
-- Run this in the Supabase SQL Editor after creating your project.

-- ============================================================
-- TABLES
-- ============================================================

-- Public profiles (auto-created on signup via trigger)
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    display_name TEXT,
    avatar_url TEXT,
    stripe_customer_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Subscriptions (auto-created on signup via trigger, starts on free plan)
CREATE TABLE public.subscriptions (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    plan TEXT NOT NULL DEFAULT 'free' CHECK (plan IN ('free', 'pro')),
    words_used INTEGER NOT NULL DEFAULT 0,
    word_limit INTEGER DEFAULT 2000,  -- NULL = unlimited (pro)
    stripe_subscription_id TEXT,
    stripe_price_id TEXT,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'canceled', 'past_due', 'trialing')),
    current_period_start TIMESTAMPTZ,
    current_period_end TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Usage log (audit trail for every dictation)
CREATE TABLE public.usage_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    words INTEGER NOT NULL,
    action TEXT NOT NULL DEFAULT 'dictation',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Waitlist (website sign-ups)
CREATE TABLE public.waitlist (
    email TEXT PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX idx_usage_log_user_created ON public.usage_log(user_id, created_at DESC);
CREATE INDEX idx_subscriptions_stripe ON public.subscriptions(stripe_subscription_id) WHERE stripe_subscription_id IS NOT NULL;

-- ============================================================
-- AUTO-CREATE PROFILE + SUBSCRIPTION ON SIGNUP
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email, display_name, avatar_url)
    VALUES (
        NEW.id,
        COALESCE(NEW.email, ''),
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', NEW.email),
        NEW.raw_user_meta_data->>'avatar_url'
    );
    INSERT INTO public.subscriptions (user_id, plan, words_used, word_limit)
    VALUES (NEW.id, 'free', 0, 2000);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.usage_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.waitlist ENABLE ROW LEVEL SECURITY;

-- Users can read their own profile
CREATE POLICY "Users read own profile"
    ON public.profiles FOR SELECT
    USING (auth.uid() = id);

-- Users can update their own display_name/avatar
CREATE POLICY "Users update own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- Users can read their own subscription
CREATE POLICY "Users read own subscription"
    ON public.subscriptions FOR SELECT
    USING (auth.uid() = user_id);

-- Users can read their own usage log
CREATE POLICY "Users read own usage"
    ON public.usage_log FOR SELECT
    USING (auth.uid() = user_id);

-- Anyone can insert into waitlist (anon key)
CREATE POLICY "Anyone can join waitlist"
    ON public.waitlist FOR INSERT
    WITH CHECK (true);

-- Prevent reading waitlist from anon key
CREATE POLICY "No public waitlist reads"
    ON public.waitlist FOR SELECT
    USING (false);

-- ============================================================
-- MONTHLY USAGE RESET (requires pg_cron extension)
-- ============================================================
-- Enable pg_cron first: go to Database > Extensions and enable pg_cron
-- Then run:

-- SELECT cron.schedule(
--     'reset-monthly-usage',
--     '0 0 1 * *',
--     $$UPDATE public.subscriptions SET words_used = 0, updated_at = now()$$
-- );

-- ============================================================
-- HELPER: updated_at trigger
-- ============================================================

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_subscriptions_updated_at
    BEFORE UPDATE ON public.subscriptions
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
