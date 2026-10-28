-- ==============================================================================
-- OPTIONAL MIGRATION: DEDICATED ECONOMIC CALENDAR TABLE
-- TradeJournal currently saves month groups directly into public.settings.
-- If you prefer a standalone relational table in PostgreSQL, run this script.
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.economic_calendar (
    id TEXT NOT NULL,
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    country TEXT NOT NULL DEFAULT 'USD',
    date_str TEXT NOT NULL,
    impact TEXT NOT NULL,
    forecast TEXT NOT NULL DEFAULT '',
    previous TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    PRIMARY KEY (user_id, id)
);

CREATE INDEX IF NOT EXISTS idx_economic_calendar_user_date ON public.economic_calendar(user_id, date_str);
ALTER TABLE public.economic_calendar ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can only manage own economic calendar" ON public.economic_calendar
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
