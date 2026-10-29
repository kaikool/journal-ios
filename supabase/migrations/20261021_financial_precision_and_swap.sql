-- ==============================================================================
-- FINANCIAL PRECISION + SWAP SUPPORT
--
-- 1. Monetary columns move from DOUBLE PRECISION to NUMERIC(38,10) so that the
--    "exact Decimal" guarantee of the app also holds for cloud synced data.
-- 2. New `swap` columns store the signed overnight interest booked by brokers
--    (negative = cost, positive = credit) for executions and trades.
-- ==============================================================================

-- 1. ACCOUNTS
ALTER TABLE public.accounts
    ALTER COLUMN initial_balance TYPE NUMERIC(38,10) USING initial_balance::NUMERIC;

-- 2. EXECUTIONS
ALTER TABLE public.executions
    ALTER COLUMN quantity TYPE NUMERIC(38,10) USING quantity::NUMERIC,
    ALTER COLUMN price TYPE NUMERIC(38,10) USING price::NUMERIC,
    ALTER COLUMN fee TYPE NUMERIC(38,10) USING fee::NUMERIC;

ALTER TABLE public.executions
    ADD COLUMN IF NOT EXISTS swap NUMERIC(38,10) NOT NULL DEFAULT 0;

-- 3. TRADES
ALTER TABLE public.trades
    ALTER COLUMN quantity TYPE NUMERIC(38,10) USING quantity::NUMERIC,
    ALTER COLUMN open_quantity TYPE NUMERIC(38,10) USING open_quantity::NUMERIC,
    ALTER COLUMN avg_entry TYPE NUMERIC(38,10) USING avg_entry::NUMERIC,
    ALTER COLUMN avg_exit TYPE NUMERIC(38,10) USING avg_exit::NUMERIC,
    ALTER COLUMN gross_pnl TYPE NUMERIC(38,10) USING gross_pnl::NUMERIC,
    ALTER COLUMN fees TYPE NUMERIC(38,10) USING fees::NUMERIC,
    ALTER COLUMN net_pnl TYPE NUMERIC(38,10) USING net_pnl::NUMERIC,
    ALTER COLUMN stop_loss TYPE NUMERIC(38,10) USING stop_loss::NUMERIC,
    ALTER COLUMN profit_target TYPE NUMERIC(38,10) USING profit_target::NUMERIC;

ALTER TABLE public.trades
    ADD COLUMN IF NOT EXISTS swap NUMERIC(38,10) NOT NULL DEFAULT 0;
