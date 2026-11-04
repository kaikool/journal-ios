-- ==============================================================================
-- Trade Journal Database Migration: 20261104_session_footprint_profiles.sql
-- Stores completed Footprint Volume Profiles & Key Levels (POC, VAH, VAL, Naked POCs)
-- Prevents repeated OANDA API candle requests and saves API quotas
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.session_footprint_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID DEFAULT auth.uid(),
    symbol TEXT NOT NULL,
    session_type TEXT NOT NULL, -- 'tokyo', 'london', 'new_york', 'daily', 'weekly', 'monthly'
    session_date DATE NOT NULL,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    poc_price NUMERIC(15, 5) NOT NULL,
    vah_price NUMERIC(15, 5) NOT NULL,
    val_price NUMERIC(15, 5) NOT NULL,
    profile_high NUMERIC(15, 5) NOT NULL,
    profile_low NUMERIC(15, 5) NOT NULL,
    total_volume NUMERIC(20, 2) NOT NULL,
    is_naked BOOLEAN DEFAULT TRUE NOT NULL,
    mitigated_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT uq_session_footprint_profile UNIQUE (symbol, session_type, session_date)
);

CREATE INDEX IF NOT EXISTS idx_session_footprint_lookup 
ON public.session_footprint_profiles (symbol, session_type, session_date DESC);

CREATE INDEX IF NOT EXISTS idx_session_footprint_naked 
ON public.session_footprint_profiles (symbol, is_naked) WHERE is_naked = TRUE;

-- Enable Row Level Security
ALTER TABLE public.session_footprint_profiles ENABLE ROW LEVEL SECURITY;

-- Allow authenticated and anon users to read session footprint profiles
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'session_footprint_profiles' AND policyname = 'Allow read on session_footprint_profiles'
    ) THEN
        CREATE POLICY "Allow read on session_footprint_profiles"
        ON public.session_footprint_profiles FOR SELECT
        TO authenticated, anon
        USING (true);
    END IF;
END $$;

-- Allow authenticated and anon users to upsert session footprint profiles
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'session_footprint_profiles' AND policyname = 'Allow write on session_footprint_profiles'
    ) THEN
        CREATE POLICY "Allow write on session_footprint_profiles"
        ON public.session_footprint_profiles FOR ALL
        TO authenticated, anon
        USING (true)
        WITH CHECK (true);
    END IF;
END $$;
