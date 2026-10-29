-- ==============================================================================
-- Trade Journal Database Migration: 20261028_trade_mae_mfe_and_rpc.sql
-- 1. Safely adds user_id, mae, mfe, mae_points, mfe_points to public.trades
-- 2. Creates resilient indexes without crashing on missing columns
-- 3. Creates ultra-fast server-side PostgreSQL aggregation RPC for tens of thousands of trades
-- ==============================================================================

-- 1. Safely add missing columns to public.trades (including user_id for multi-tenancy & auth safety)
ALTER TABLE IF EXISTS public.trades ADD COLUMN IF NOT EXISTS user_id UUID DEFAULT auth.uid();
ALTER TABLE IF EXISTS public.trades ADD COLUMN IF NOT EXISTS mae NUMERIC(38, 10);
ALTER TABLE IF EXISTS public.trades ADD COLUMN IF NOT EXISTS mfe NUMERIC(38, 10);
ALTER TABLE IF EXISTS public.trades ADD COLUMN IF NOT EXISTS mae_points NUMERIC(38, 10);
ALTER TABLE IF EXISTS public.trades ADD COLUMN IF NOT EXISTS mfe_points NUMERIC(38, 10);

-- 2. Performance Indexes (Safe for both single-tenant and multi-tenant setups)
CREATE INDEX IF NOT EXISTS idx_trades_mae_mfe ON public.trades(mae, mfe);
CREATE INDEX IF NOT EXISTS idx_trades_account_id ON public.trades(account_id);
CREATE INDEX IF NOT EXISTS idx_trades_user_id ON public.trades(user_id);

-- 3. Server-side Aggregation RPC for High-Volume Historical Analysis (Module B)
CREATE OR REPLACE FUNCTION public.get_trade_performance_analytics(
    p_account_id TEXT DEFAULT NULL,
    p_symbol TEXT DEFAULT NULL,
    p_start_date TIMESTAMPTZ DEFAULT NULL,
    p_end_date TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id UUID;
    v_result JSONB;
BEGIN
    v_user_id := auth.uid();
    
    WITH scoped_trades AS (
        SELECT 
            t.*,
            EXTRACT(ISODOW FROM (CASE 
                WHEN t.opened_at IS NULL OR t.opened_at::text = '' THEN NOW()
                ELSE t.opened_at::text::timestamptz 
            END)) AS day_of_week,
            EXTRACT(HOUR FROM (CASE 
                WHEN t.opened_at IS NULL OR t.opened_at::text = '' THEN NOW()
                ELSE t.opened_at::text::timestamptz 
            END) AT TIME ZONE 'UTC') AS utc_hour
        FROM public.trades t
        WHERE (v_user_id IS NULL OR t.user_id IS NULL OR t.user_id = v_user_id)
          AND (p_account_id IS NULL OR p_account_id = '' OR t.account_id = p_account_id)
          AND (p_symbol IS NULL OR p_symbol = '' OR UPPER(t.symbol) = UPPER(p_symbol))
          AND (p_start_date IS NULL OR (CASE WHEN t.opened_at IS NULL OR t.opened_at::text = '' THEN NOW() ELSE t.opened_at::text::timestamptz END) >= p_start_date)
          AND (p_end_date IS NULL OR (CASE WHEN t.opened_at IS NULL OR t.opened_at::text = '' THEN NOW() ELSE t.opened_at::text::timestamptz END) <= p_end_date)
    ),
    closed_trades AS (
        SELECT * FROM scoped_trades 
        WHERE LOWER(status) NOT IN ('open', 'pending') 
          AND closed_at IS NOT NULL 
          AND closed_at::text != ''
    ),
    overall_stats AS (
        SELECT
            COUNT(*)::INT AS total_closed,
            COUNT(*) FILTER (WHERE net_pnl > 0)::INT AS wins,
            COUNT(*) FILTER (WHERE net_pnl < 0)::INT AS losses,
            COUNT(*) FILTER (WHERE net_pnl = 0)::INT AS breakevens,
            COALESCE(SUM(gross_pnl), 0) AS total_gross_pnl,
            COALESCE(SUM(fees), 0) AS total_fees,
            COALESCE(SUM(swap), 0) AS total_swap,
            COALESCE(SUM(net_pnl), 0) AS total_net_pnl,
            COALESCE(SUM(net_pnl) FILTER (WHERE net_pnl > 0), 0) AS gross_profit,
            COALESCE(SUM(ABS(net_pnl)) FILTER (WHERE net_pnl < 0), 0) AS gross_loss,
            COALESCE(AVG(net_pnl) FILTER (WHERE net_pnl > 0), 0) AS avg_win,
            COALESCE(AVG(net_pnl) FILTER (WHERE net_pnl < 0), 0) AS avg_loss,
            COALESCE(AVG(mae), 0) AS avg_mae,
            COALESCE(AVG(mfe), 0) AS avg_mfe
        FROM closed_trades
    ),
    session_stats AS (
        SELECT
            jsonb_build_object(
                'asian', jsonb_build_object(
                    'count', COUNT(*) FILTER (WHERE utc_hour >= 0 AND utc_hour < 8)::INT,
                    'net_pnl', COALESCE(SUM(net_pnl) FILTER (WHERE utc_hour >= 0 AND utc_hour < 8), 0),
                    'win_rate', ROUND(CASE WHEN COUNT(*) FILTER (WHERE utc_hour >= 0 AND utc_hour < 8) > 0 
                        THEN (COUNT(*) FILTER (WHERE utc_hour >= 0 AND utc_hour < 8 AND net_pnl > 0)::NUMERIC / COUNT(*) FILTER (WHERE utc_hour >= 0 AND utc_hour < 8)::NUMERIC) * 100 
                        ELSE 0 END, 2)
                ),
                'london', jsonb_build_object(
                    'count', COUNT(*) FILTER (WHERE utc_hour >= 8 AND utc_hour < 13)::INT,
                    'net_pnl', COALESCE(SUM(net_pnl) FILTER (WHERE utc_hour >= 8 AND utc_hour < 13), 0),
                    'win_rate', ROUND(CASE WHEN COUNT(*) FILTER (WHERE utc_hour >= 8 AND utc_hour < 13) > 0 
                        THEN (COUNT(*) FILTER (WHERE utc_hour >= 8 AND utc_hour < 13 AND net_pnl > 0)::NUMERIC / COUNT(*) FILTER (WHERE utc_hour >= 8 AND utc_hour < 13)::NUMERIC) * 100 
                        ELSE 0 END, 2)
                ),
                'new_york', jsonb_build_object(
                    'count', COUNT(*) FILTER (WHERE utc_hour >= 13)::INT,
                    'net_pnl', COALESCE(SUM(net_pnl) FILTER (WHERE utc_hour >= 13), 0),
                    'win_rate', ROUND(CASE WHEN COUNT(*) FILTER (WHERE utc_hour >= 13) > 0 
                        THEN (COUNT(*) FILTER (WHERE utc_hour >= 13 AND net_pnl > 0)::NUMERIC / COUNT(*) FILTER (WHERE utc_hour >= 13)::NUMERIC) * 100 
                        ELSE 0 END, 2)
                )
            ) AS sessions
        FROM closed_trades
    ),
    direction_stats AS (
        SELECT
            jsonb_build_object(
                'long', jsonb_build_object(
                    'count', COUNT(*) FILTER (WHERE LOWER(direction) = 'long')::INT,
                    'net_pnl', COALESCE(SUM(net_pnl) FILTER (WHERE LOWER(direction) = 'long'), 0),
                    'win_rate', ROUND(CASE WHEN COUNT(*) FILTER (WHERE LOWER(direction) = 'long') > 0 
                        THEN (COUNT(*) FILTER (WHERE LOWER(direction) = 'long' AND net_pnl > 0)::NUMERIC / COUNT(*) FILTER (WHERE LOWER(direction) = 'long')::NUMERIC) * 100 
                        ELSE 0 END, 2)
                ),
                'short', jsonb_build_object(
                    'count', COUNT(*) FILTER (WHERE LOWER(direction) = 'short')::INT,
                    'net_pnl', COALESCE(SUM(net_pnl) FILTER (WHERE LOWER(direction) = 'short'), 0),
                    'win_rate', ROUND(CASE WHEN COUNT(*) FILTER (WHERE LOWER(direction) = 'short') > 0 
                        THEN (COUNT(*) FILTER (WHERE LOWER(direction) = 'short' AND net_pnl > 0)::NUMERIC / COUNT(*) FILTER (WHERE LOWER(direction) = 'short')::NUMERIC) * 100 
                        ELSE 0 END, 2)
                )
            ) AS directions
        FROM closed_trades
    )
    SELECT jsonb_build_object(
        'total_trades', (SELECT COUNT(*)::INT FROM scoped_trades),
        'closed_trades', o.total_closed,
        'wins', o.wins,
        'losses', o.losses,
        'breakevens', o.breakevens,
        'win_rate', ROUND(CASE WHEN o.total_closed > 0 THEN (o.wins::NUMERIC / o.total_closed::NUMERIC) * 100 ELSE 0 END, 2),
        'profit_factor', ROUND(CASE WHEN o.gross_loss > 0 THEN (o.gross_profit / o.gross_loss) ELSE CASE WHEN o.gross_profit > 0 THEN 999 ELSE 0 END END, 2),
        'expectancy', ROUND(CASE WHEN o.total_closed > 0 THEN (o.total_net_pnl / o.total_closed::NUMERIC) ELSE 0 END, 2),
        'total_gross_pnl', o.total_gross_pnl,
        'total_net_pnl', o.total_net_pnl,
        'total_fees', o.total_fees,
        'total_swap', o.total_swap,
        'avg_win', o.avg_win,
        'avg_loss', o.avg_loss,
        'avg_mae', o.avg_mae,
        'avg_mfe', o.avg_mfe,
        'sessions', s.sessions,
        'directions', d.directions
    ) INTO v_result
    FROM overall_stats o
    CROSS JOIN session_stats s
    CROSS JOIN direction_stats d;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_trade_performance_analytics TO anon, authenticated, service_role;
