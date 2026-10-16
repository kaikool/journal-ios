-- ==============================================================================
-- TRADE JOURNAL SUPABASE POSTGRESQL SCHEMA WITH RLS & MULTI-TENANCY
-- Generated for Native iOS + Supabase Architecture
-- ==============================================================================

-- 1. BẢNG ACCOUNTS (Tài khoản giao dịch)
CREATE TABLE IF NOT EXISTS public.accounts (
    id TEXT NOT NULL,
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    broker TEXT NOT NULL DEFAULT '',
    kind TEXT NOT NULL CHECK (kind IN ('sync', 'import', 'manual')),
    currency TEXT NOT NULL DEFAULT 'USD',
    initial_balance DOUBLE PRECISION NOT NULL DEFAULT 0,
    profit_calc_method TEXT NOT NULL DEFAULT 'fifo' CHECK (profit_calc_method IN ('fifo', 'lifo', 'wavg')),
    credentials_enc TEXT,
    auto_sync BOOLEAN NOT NULL DEFAULT false,
    last_sync_at TIMESTAMPTZ,
    ibkr_sync_time_zone TEXT,
    snapshot_json TEXT,
    archived_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    PRIMARY KEY (user_id, id)
);

CREATE INDEX IF NOT EXISTS idx_accounts_user ON public.accounts(user_id);
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can only manage own accounts" ON public.accounts
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- 2. BẢNG EXECUTIONS (Các lần khớp lệnh nguyên tử)
CREATE TABLE IF NOT EXISTS public.executions (
    id TEXT NOT NULL,
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    account_id TEXT NOT NULL,
    symbol TEXT NOT NULL,
    side TEXT NOT NULL CHECK (side IN ('buy', 'sell')),
    quantity DOUBLE PRECISION NOT NULL,
    price DOUBLE PRECISION NOT NULL,
    fee DOUBLE PRECISION NOT NULL DEFAULT 0,
    executed_at TIMESTAMPTZ NOT NULL,
    asset_class TEXT,
    source TEXT NOT NULL CHECK (source IN ('sync', 'import', 'manual')),
    import_metadata_json TEXT,
    content_hash TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    PRIMARY KEY (user_id, id),
    CONSTRAINT executions_unique_content UNIQUE (user_id, account_id, content_hash),
    CONSTRAINT fk_executions_account FOREIGN KEY (user_id, account_id) REFERENCES public.accounts(user_id, id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_executions_account_symbol ON public.executions(user_id, account_id, symbol);
CREATE INDEX IF NOT EXISTS idx_executions_time ON public.executions(user_id, executed_at);
ALTER TABLE public.executions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can only manage own executions" ON public.executions
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- 3. BẢNG TRADES (Vòng đời vị thế dẫn xuất Flat-to-Flat)
CREATE TABLE IF NOT EXISTS public.trades (
    key TEXT NOT NULL,
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    account_id TEXT NOT NULL,
    symbol TEXT NOT NULL,
    asset_class TEXT,
    direction TEXT NOT NULL CHECK (direction IN ('long', 'short')),
    status TEXT NOT NULL CHECK (status IN ('open', 'win', 'loss', 'breakeven')),
    opened_at TIMESTAMPTZ NOT NULL,
    closed_at TIMESTAMPTZ,
    quantity DOUBLE PRECISION NOT NULL,
    open_quantity DOUBLE PRECISION NOT NULL,
    avg_entry DOUBLE PRECISION NOT NULL,
    avg_exit DOUBLE PRECISION,
    gross_pnl DOUBLE PRECISION NOT NULL,
    fees DOUBLE PRECISION NOT NULL,
    net_pnl DOUBLE PRECISION NOT NULL,
    execution_count INTEGER NOT NULL,
    execution_ids_json TEXT NOT NULL,
    exits_json TEXT NOT NULL,
    duration_ms BIGINT,
    notes TEXT,
    tags_json TEXT,
    mistakes_json TEXT,
    playbook_id TEXT,
    rating INTEGER,
    stop_loss DOUBLE PRECISION,
    profit_target DOUBLE PRECISION,
    reviewed_at TIMESTAMPTZ,
    PRIMARY KEY (user_id, key),
    CONSTRAINT fk_trades_account FOREIGN KEY (user_id, account_id) REFERENCES public.accounts(user_id, id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_trades_user_closed ON public.trades(user_id, account_id, closed_at);
CREATE INDEX IF NOT EXISTS idx_trades_user_symbol ON public.trades(user_id, symbol);
ALTER TABLE public.trades ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can only manage own trades" ON public.trades
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- 4. BẢNG JOURNAL_DAYS (Nhật ký theo ngày)
CREATE TABLE IF NOT EXISTS public.journal_days (
    date TEXT NOT NULL,
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    note TEXT NOT NULL DEFAULT '',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    PRIMARY KEY (user_id, date)
);

ALTER TABLE public.journal_days ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only manage own journal days" ON public.journal_days
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- 5. BẢNG FOLDERS & NOTES (Notebook)
CREATE TABLE IF NOT EXISTS public.folders (
    id TEXT NOT NULL,
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    kind TEXT NOT NULL DEFAULT 'user' CHECK (kind IN ('system', 'user')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ,
    PRIMARY KEY (user_id, id)
);

ALTER TABLE public.folders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only manage own folders" ON public.folders
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.notes (
    id TEXT NOT NULL,
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    folder_id TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    content TEXT NOT NULL DEFAULT '',
    tags_json TEXT,
    trade_key TEXT,
    day_date TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    PRIMARY KEY (user_id, id),
    CONSTRAINT fk_notes_folder FOREIGN KEY (user_id, folder_id) REFERENCES public.folders(user_id, id) ON DELETE CASCADE
);

ALTER TABLE public.notes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only manage own notes" ON public.notes
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- 6. BẢNG PLAYBOOKS & RULES
CREATE TABLE IF NOT EXISTS public.playbooks (
    id TEXT NOT NULL,
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    rules_json TEXT NOT NULL DEFAULT '[]',
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    PRIMARY KEY (user_id, id)
);

ALTER TABLE public.playbooks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only manage own playbooks" ON public.playbooks
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.trade_rule_checks (
    id TEXT NOT NULL,
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    trade_key TEXT NOT NULL,
    playbook_id TEXT NOT NULL,
    rule TEXT NOT NULL,
    followed BOOLEAN NOT NULL,
    PRIMARY KEY (user_id, id)
);

ALTER TABLE public.trade_rule_checks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only manage own rule checks" ON public.trade_rule_checks
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- 7. BẢNG PROP FIRM LEDGER (Sổ cái Quỹ)
CREATE TABLE IF NOT EXISTS public.prop_accounts (
    id TEXT NOT NULL,
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    firm TEXT NOT NULL,
    name TEXT NOT NULL,
    program TEXT NOT NULL,
    status TEXT NOT NULL,
    currency TEXT NOT NULL,
    size_minor BIGINT,
    parent_id TEXT,
    journal_account_id TEXT,
    opened_on TEXT NOT NULL,
    closed_on TEXT,
    renewal_on TEXT,
    renewal_minor BIGINT,
    notes TEXT NOT NULL DEFAULT '',
    archived BOOLEAN NOT NULL DEFAULT false,
    revision INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    PRIMARY KEY (user_id, id)
);

ALTER TABLE public.prop_accounts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only manage own prop accounts" ON public.prop_accounts
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.prop_entries (
    id TEXT NOT NULL,
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    account_id TEXT,
    firm TEXT NOT NULL,
    kind TEXT NOT NULL,
    category TEXT NOT NULL,
    currency TEXT NOT NULL,
    amount_minor BIGINT NOT NULL,
    split_bps INTEGER NOT NULL,
    fee_minor BIGINT NOT NULL,
    occurred_on TEXT NOT NULL,
    due_on TEXT,
    status TEXT NOT NULL,
    parent_id TEXT,
    reference TEXT NOT NULL DEFAULT '',
    notes TEXT NOT NULL DEFAULT '',
    voided BOOLEAN NOT NULL DEFAULT false,
    revision INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    PRIMARY KEY (user_id, id)
);

ALTER TABLE public.prop_entries ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only manage own prop entries" ON public.prop_entries
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.prop_receipts (
    id TEXT NOT NULL,
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    payout_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    amount_minor BIGINT NOT NULL,
    occurred_on TEXT NOT NULL,
    reference TEXT NOT NULL DEFAULT '',
    notes TEXT NOT NULL DEFAULT '',
    voided BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    PRIMARY KEY (user_id, id)
);

ALTER TABLE public.prop_receipts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only manage own prop receipts" ON public.prop_receipts
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- 8. BẢNG SETTINGS & ATTACHMENTS
CREATE TABLE IF NOT EXISTS public.settings (
    key TEXT NOT NULL,
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    value TEXT NOT NULL,
    PRIMARY KEY (user_id, key)
);

ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only manage own settings" ON public.settings
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.attachments (
    id TEXT NOT NULL,
    user_id UUID NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    owner_type TEXT NOT NULL,
    owner_id TEXT NOT NULL,
    name TEXT NOT NULL,
    mime TEXT NOT NULL,
    size INTEGER NOT NULL,
    storage_path TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'ready' CHECK (status IN ('pending', 'ready')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    PRIMARY KEY (user_id, id),
    CONSTRAINT attachments_unique_path UNIQUE (user_id, storage_path)
);

ALTER TABLE public.attachments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only manage own attachments" ON public.attachments
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ==============================================================================
-- STORAGE BUCKETS SETUP
-- ==============================================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('journal-attachments', 'journal-attachments', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('market-data', 'market-data', false)
ON CONFLICT (id) DO NOTHING;

-- Storage Policies
CREATE POLICY "Users can upload their own attachments"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'journal-attachments' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Users can view their own attachments"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'journal-attachments' AND (storage.foldername(name))[1] = auth.uid()::text);
