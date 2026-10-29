-- ==============================================================================
-- Trade Journal Database Migration: 20261026_progress_notes_missed_trades.sql
-- Enables Supabase Cloud Synchronization for:
-- 1. Notebook (Folders & Notes)
-- 2. Progress Rules (Disciplined Routines) & Daily Progress Checks
-- 3. Missed Trades (Opportunity Tracking)
-- ==============================================================================

-- 1. Notebook Folders
CREATE TABLE IF NOT EXISTS public.folders (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    kind TEXT DEFAULT 'user' NOT NULL,
    created_at TEXT NOT NULL,
    deleted_at TEXT
);

-- 2. Notebook Notes
CREATE TABLE IF NOT EXISTS public.notes (
    id TEXT PRIMARY KEY NOT NULL,
    folder_id TEXT NOT NULL,
    title TEXT DEFAULT '' NOT NULL,
    content TEXT DEFAULT '' NOT NULL,
    tags_json TEXT,
    trade_key TEXT,
    day_date TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- 3. Progress Rules (Routines)
CREATE TABLE IF NOT EXISTS public.progress_rules (
    id TEXT PRIMARY KEY NOT NULL,
    title TEXT NOT NULL,
    stage TEXT NOT NULL,
    weekdays_json TEXT DEFAULT '[1,2,3,4,5]' NOT NULL,
    created_at TEXT NOT NULL,
    archived_at TEXT
);

-- 4. Daily Progress Checks
CREATE TABLE IF NOT EXISTS public.progress_checks (
    id TEXT PRIMARY KEY NOT NULL,
    rule_id TEXT NOT NULL,
    date TEXT NOT NULL,
    done BOOLEAN DEFAULT true NOT NULL
);

-- 5. Missed Trades
CREATE TABLE IF NOT EXISTS public.missed_trades (
    id TEXT PRIMARY KEY NOT NULL,
    symbol TEXT NOT NULL,
    direction TEXT NOT NULL,
    observed_at TEXT NOT NULL,
    playbook_id TEXT,
    entry NUMERIC(38,10),
    stop NUMERIC(38,10),
    target NUMERIC(38,10),
    notes TEXT DEFAULT '' NOT NULL,
    created_at TEXT NOT NULL,
    archived_at TEXT
);

-- 6. Row Level Security & Access Policies
ALTER TABLE public.folders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.progress_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.progress_checks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.missed_trades ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow All For Anon" ON public.folders;
CREATE POLICY "Allow All For Anon" ON public.folders FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow All For Anon" ON public.notes;
CREATE POLICY "Allow All For Anon" ON public.notes FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow All For Anon" ON public.progress_rules;
CREATE POLICY "Allow All For Anon" ON public.progress_rules FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow All For Anon" ON public.progress_checks;
CREATE POLICY "Allow All For Anon" ON public.progress_checks FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow All For Anon" ON public.missed_trades;
CREATE POLICY "Allow All For Anon" ON public.missed_trades FOR ALL USING (true) WITH CHECK (true);

GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
