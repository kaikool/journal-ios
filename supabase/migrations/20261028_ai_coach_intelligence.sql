-- ==============================================================================
-- Trade Journal Database Migration: 20261028_ai_coach_intelligence.sql
-- Enables Supabase Cloud Synchronization for:
-- 1. AI Long-term Memory (ai_memories: Preferences, Decisions, Research, Failure, Context)
-- 2. Trade Excursions Cache (trade_excursions: MAE / MFE Excursion Metrics)
-- 3. Trade Lesson Evaluations (trade_lesson_evaluations: Failure Taxonomy & Compliance)
-- 4. AI Research Projects (ai_research_projects: Hypotheses & Validation Checkpoints)
-- ==============================================================================

-- 1. AI Long-term Memory Table
CREATE TABLE IF NOT EXISTS public.ai_memories (
    id TEXT PRIMARY KEY NOT NULL,
    user_id UUID DEFAULT auth.uid(),
    category TEXT NOT NULL CHECK (category IN ('preference', 'decision', 'research', 'failure', 'context')),
    symbol TEXT,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    confidence NUMERIC(3,2) DEFAULT 1.00 NOT NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'verified', 'deprecated', 'refuted')),
    superseded_by TEXT REFERENCES public.ai_memories(id) ON DELETE SET NULL,
    source_type TEXT NOT NULL DEFAULT 'manual' CHECK (source_type IN ('pre_trade', 'trade_audit', 'chat', 'research', 'manual')),
    source_id TEXT,
    metadata_json TEXT DEFAULT '{}' NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

ALTER TABLE IF EXISTS public.ai_memories ADD COLUMN IF NOT EXISTS user_id UUID DEFAULT auth.uid();
ALTER TABLE IF EXISTS public.ai_memories ADD COLUMN IF NOT EXISTS category TEXT DEFAULT 'context';
ALTER TABLE IF EXISTS public.ai_memories ADD COLUMN IF NOT EXISTS confidence NUMERIC(3,2) DEFAULT 1.00;
ALTER TABLE IF EXISTS public.ai_memories ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active';
ALTER TABLE IF EXISTS public.ai_memories ADD COLUMN IF NOT EXISTS source_type TEXT DEFAULT 'manual';
ALTER TABLE IF EXISTS public.ai_memories ADD COLUMN IF NOT EXISTS metadata_json TEXT DEFAULT '{}';

CREATE INDEX IF NOT EXISTS idx_ai_memories_user_cat ON public.ai_memories(user_id, category, status);
CREATE INDEX IF NOT EXISTS idx_ai_memories_symbol ON public.ai_memories(user_id, symbol);
CREATE INDEX IF NOT EXISTS idx_ai_memories_source ON public.ai_memories(user_id, source_id);

ALTER TABLE public.ai_memories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can only manage own ai_memories" ON public.ai_memories;
DROP POLICY IF EXISTS "Allow All For Anon ai_memories" ON public.ai_memories;
CREATE POLICY "Allow All For Anon ai_memories" ON public.ai_memories
    FOR ALL USING (true) WITH CHECK (true);

GRANT ALL ON TABLE public.ai_memories TO anon, authenticated, service_role;


-- 2. Trade Excursions Table (MAE / MFE Metrics Form)
-- Note: Table might already exist from earlier schema; patch columns safely!
CREATE TABLE IF NOT EXISTS public.trade_excursions (
    trade_key TEXT PRIMARY KEY NOT NULL,
    user_id UUID DEFAULT auth.uid(),
    fingerprint TEXT NOT NULL DEFAULT '',
    provider TEXT NOT NULL DEFAULT 'oanda',
    symbol TEXT NOT NULL DEFAULT '',
    resolution TEXT NOT NULL DEFAULT '15m',
    mae_dollar NUMERIC(38,10),
    mfe_dollar NUMERIC(38,10),
    mae_points NUMERIC(38,10),
    mfe_points NUMERIC(38,10),
    estimate_json TEXT NOT NULL DEFAULT '{}',
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

ALTER TABLE IF EXISTS public.trade_excursions ADD COLUMN IF NOT EXISTS user_id UUID DEFAULT auth.uid();
ALTER TABLE IF EXISTS public.trade_excursions ADD COLUMN IF NOT EXISTS mae_dollar NUMERIC(38,10);
ALTER TABLE IF EXISTS public.trade_excursions ADD COLUMN IF NOT EXISTS mfe_dollar NUMERIC(38,10);
ALTER TABLE IF EXISTS public.trade_excursions ADD COLUMN IF NOT EXISTS mae_points NUMERIC(38,10);
ALTER TABLE IF EXISTS public.trade_excursions ADD COLUMN IF NOT EXISTS mfe_points NUMERIC(38,10);
ALTER TABLE IF EXISTS public.trade_excursions ADD COLUMN IF NOT EXISTS estimate_json TEXT DEFAULT '{}';
ALTER TABLE IF EXISTS public.trade_excursions ADD COLUMN IF NOT EXISTS fetched_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now());

CREATE INDEX IF NOT EXISTS idx_trade_excursions_user ON public.trade_excursions(user_id);
CREATE INDEX IF NOT EXISTS idx_trade_excursions_symbol ON public.trade_excursions(user_id, symbol);

ALTER TABLE public.trade_excursions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can only manage own trade_excursions" ON public.trade_excursions;
DROP POLICY IF EXISTS "Allow All For Anon trade_excursions" ON public.trade_excursions;
CREATE POLICY "Allow All For Anon trade_excursions" ON public.trade_excursions
    FOR ALL USING (true) WITH CHECK (true);

GRANT ALL ON TABLE public.trade_excursions TO anon, authenticated, service_role;


-- 3. Trade Lesson Evaluations Table (Module D: Experience & Verification Form)
CREATE TABLE IF NOT EXISTS public.trade_lesson_evaluations (
    id TEXT PRIMARY KEY NOT NULL,
    user_id UUID DEFAULT auth.uid(),
    trade_id TEXT NOT NULL,
    symbol TEXT NOT NULL,
    taxonomy TEXT NOT NULL CHECK (taxonomy IN ('bad_execution', 'flawed_plan', 'regime_shift', 'random_loss', 'unclassified')),
    deviation_points NUMERIC(38,10),
    planned_rr NUMERIC(10,2),
    realized_rr NUMERIC(10,2),
    rule_broken TEXT,
    lesson_text TEXT NOT NULL,
    verified_count INT DEFAULT 0 NOT NULL,
    violated_count INT DEFAULT 0 NOT NULL,
    metadata_json TEXT DEFAULT '{}' NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

ALTER TABLE IF EXISTS public.trade_lesson_evaluations ADD COLUMN IF NOT EXISTS user_id UUID DEFAULT auth.uid();

CREATE INDEX IF NOT EXISTS idx_trade_lesson_eval_user ON public.trade_lesson_evaluations(user_id, symbol);
CREATE INDEX IF NOT EXISTS idx_trade_lesson_eval_tax ON public.trade_lesson_evaluations(user_id, taxonomy);

ALTER TABLE public.trade_lesson_evaluations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can only manage own trade_lesson_evaluations" ON public.trade_lesson_evaluations;
DROP POLICY IF EXISTS "Allow All For Anon trade_lesson_evaluations" ON public.trade_lesson_evaluations;
CREATE POLICY "Allow All For Anon trade_lesson_evaluations" ON public.trade_lesson_evaluations
    FOR ALL USING (true) WITH CHECK (true);

GRANT ALL ON TABLE public.trade_lesson_evaluations TO anon, authenticated, service_role;


-- 4. AI Research Projects Table (Module E: Persistent Research Workspace)
CREATE TABLE IF NOT EXISTS public.ai_research_projects (
    id TEXT PRIMARY KEY NOT NULL,
    user_id UUID DEFAULT auth.uid(),
    title TEXT NOT NULL,
    hypothesis TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'validated', 'invalidated', 'archived')),
    sample_criteria_json TEXT DEFAULT '{}' NOT NULL,
    sample_count INT DEFAULT 0 NOT NULL,
    win_rate NUMERIC(5,2),
    profit_factor NUMERIC(10,2),
    conclusion TEXT,
    metadata_json TEXT DEFAULT '{}' NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

ALTER TABLE IF EXISTS public.ai_research_projects ADD COLUMN IF NOT EXISTS user_id UUID DEFAULT auth.uid();

CREATE INDEX IF NOT EXISTS idx_ai_research_projects_user ON public.ai_research_projects(user_id, status);

ALTER TABLE public.ai_research_projects ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can only manage own ai_research_projects" ON public.ai_research_projects;
DROP POLICY IF EXISTS "Allow All For Anon ai_research_projects" ON public.ai_research_projects;
CREATE POLICY "Allow All For Anon ai_research_projects" ON public.ai_research_projects
    FOR ALL USING (true) WITH CHECK (true);

GRANT ALL ON TABLE public.ai_research_projects TO anon, authenticated, service_role;
