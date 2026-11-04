import Foundation

// MARK: - Supabase PostgreSQL DDL Schemas
// Modular SQL partitions for database initialization and hotfix migration
extension SupabaseMigrationHelper {
    
    internal var coreSchemaSql: String {
        return """
        -- ========================================================
        -- Trade Journal: Supabase PostgreSQL DDL Initialization
        -- 1:1 Parity with schema.pg.ts and drizzle migrations
        -- ========================================================

        CREATE TABLE IF NOT EXISTS "accounts" (
            "id" text PRIMARY KEY NOT NULL,
            "name" text NOT NULL,
            "broker" text DEFAULT '' NOT NULL,
            "kind" text DEFAULT 'trading' NOT NULL,
            "currency" text DEFAULT 'USD' NOT NULL,
            "initial_balance" numeric(38,10) DEFAULT 0 NOT NULL,
            "profit_calc_method" text DEFAULT 'fifo' NOT NULL,
            "credentials_enc" text,
            "auto_sync" boolean DEFAULT false NOT NULL,
            "last_sync_at" text,
            "ibkr_sync_time_zone" text,
            "snapshot_json" text,
            "archived_at" text,
            "created_at" text NOT NULL
        );

        CREATE TABLE IF NOT EXISTS "executions" (
            "id" text PRIMARY KEY NOT NULL,
            "account_id" text NOT NULL,
            "symbol" text NOT NULL,
            "side" text NOT NULL,
            "quantity" numeric(38,10) NOT NULL,
            "price" numeric(38,10) NOT NULL,
            "fee" numeric(38,10) DEFAULT 0 NOT NULL,
            "swap" numeric(38,10) DEFAULT 0 NOT NULL,
            "executed_at" text NOT NULL,
            "asset_class" text,
            "source" text NOT NULL,
            "import_metadata_json" text,
            "content_hash" text NOT NULL,
            "created_at" text NOT NULL
        );

        CREATE TABLE IF NOT EXISTS "trades" (
            "key" text PRIMARY KEY NOT NULL,
            "account_id" text NOT NULL,
            "symbol" text NOT NULL,
            "asset_class" text,
            "direction" text NOT NULL,
            "status" text NOT NULL,
            "opened_at" text NOT NULL,
            "closed_at" text,
            "duration_ms" bigint,
            "quantity" numeric(38,10) NOT NULL,
            "open_quantity" numeric(38,10) DEFAULT 0 NOT NULL,
            "avg_entry" numeric(38,10) NOT NULL,
            "avg_exit" numeric(38,10),
            "gross_pnl" numeric(38,10) NOT NULL,
            "fees" numeric(38,10) DEFAULT 0 NOT NULL,
            "swap" numeric(38,10) DEFAULT 0 NOT NULL,
            "net_pnl" numeric(38,10) NOT NULL,
            "r_multiple" numeric(10,2),
            "notes" text,
            "tags_json" text,
            "mistakes_json" text,
            "playbook_id" text,
            "rating" integer,
            "stop_loss" numeric(38,10),
            "profit_target" numeric(38,10),
            "reviewed_at" text
        );

        CREATE TABLE IF NOT EXISTS "folders" (
            "id" text PRIMARY KEY NOT NULL,
            "name" text NOT NULL,
            "kind" text DEFAULT 'user' NOT NULL,
            "created_at" text NOT NULL,
            "deleted_at" text
        );

        CREATE TABLE IF NOT EXISTS "notes" (
            "id" text PRIMARY KEY NOT NULL,
            "folder_id" text NOT NULL,
            "title" text NOT NULL,
            "content" text NOT NULL,
            "tags_json" text,
            "pinned" boolean DEFAULT false NOT NULL,
            "archived" boolean DEFAULT false NOT NULL,
            "created_at" text NOT NULL,
            "updated_at" text NOT NULL
        );

        CREATE TABLE IF NOT EXISTS "playbooks" (
            "id" text PRIMARY KEY NOT NULL,
            "name" text NOT NULL,
            "description" text NOT NULL,
            "rules_json" text NOT NULL,
            "created_at" text NOT NULL
        );
        """
    }

    internal var propFirmSchemaSql: String {
        return """
        CREATE TABLE IF NOT EXISTS "prop_accounts" (
            "id" text PRIMARY KEY NOT NULL,
            "firm" text NOT NULL,
            "name" text NOT NULL,
            "program" text NOT NULL,
            "status" text NOT NULL,
            "currency" text NOT NULL,
            "size_minor" bigint,
            "parent_id" text,
            "journal_account_id" text,
            "opened_on" text NOT NULL,
            "closed_on" text,
            "renewal_on" text,
            "renewal_minor" bigint,
            "notes" text DEFAULT '' NOT NULL,
            "archived" boolean DEFAULT false NOT NULL,
            "revision" integer DEFAULT 1 NOT NULL,
            "created_at" text,
            "updated_at" text
        );

        CREATE TABLE IF NOT EXISTS "prop_entries" (
            "id" text PRIMARY KEY NOT NULL,
            "account_id" text,
            "firm" text NOT NULL,
            "kind" text NOT NULL,
            "category" text DEFAULT '' NOT NULL,
            "currency" text NOT NULL,
            "amount_minor" bigint NOT NULL,
            "split_bps" integer DEFAULT 8000 NOT NULL,
            "fee_minor" bigint DEFAULT 0 NOT NULL,
            "occurred_on" text NOT NULL,
            "due_on" text,
            "status" text DEFAULT 'completed' NOT NULL,
            "parent_id" text,
            "reference" text DEFAULT '' NOT NULL,
            "notes" text DEFAULT '' NOT NULL,
            "voided" boolean DEFAULT false NOT NULL,
            "revision" integer DEFAULT 1 NOT NULL,
            "created_at" text,
            "updated_at" text
        );

        CREATE TABLE IF NOT EXISTS "prop_receipts" (
            "id" text PRIMARY KEY NOT NULL,
            "payout_id" text DEFAULT '' NOT NULL,
            "kind" text DEFAULT 'payout' NOT NULL,
            "amount_minor" bigint DEFAULT 0 NOT NULL,
            "occurred_on" text NOT NULL,
            "reference" text DEFAULT '' NOT NULL,
            "notes" text DEFAULT '' NOT NULL,
            "voided" boolean DEFAULT false NOT NULL,
            "created_at" text
        );

        CREATE TABLE IF NOT EXISTS "prop_audit" (
            "id" text PRIMARY KEY NOT NULL,
            "entity_id" text NOT NULL,
            "entity_type" text NOT NULL,
            "action" text NOT NULL,
            "payload_json" text NOT NULL,
            "created_at" text NOT NULL
        );

        CREATE TABLE IF NOT EXISTS "attachments" (
            "id" text PRIMARY KEY NOT NULL,
            "owner_id" text NOT NULL,
            "owner_type" text NOT NULL,
            "name" text NOT NULL,
            "mime" text NOT NULL,
            "byte_size" integer NOT NULL,
            "storage_path" text NOT NULL,
            "sha256" text NOT NULL,
            "status" text DEFAULT 'ready' NOT NULL,
            "created_at" text
        );

        CREATE TABLE IF NOT EXISTS "settings" (
            "key" text PRIMARY KEY NOT NULL,
            "value" text NOT NULL
        );

        CREATE TABLE IF NOT EXISTS "journal_days" (
            "date" text PRIMARY KEY NOT NULL,
            "note" text DEFAULT '' NOT NULL,
            "updated_at" text NOT NULL
        );
        """
    }

    internal var progressAndAISchemaSql: String {
        return """
        CREATE TABLE IF NOT EXISTS "progress_rules" (
            "id" text PRIMARY KEY NOT NULL,
            "title" text NOT NULL,
            "stage" text NOT NULL,
            "weekdays_json" text DEFAULT '[1,2,3,4,5]' NOT NULL,
            "created_at" text NOT NULL,
            "archived_at" text
        );

        CREATE TABLE IF NOT EXISTS "progress_checks" (
            "id" text PRIMARY KEY NOT NULL,
            "rule_id" text NOT NULL,
            "date" text NOT NULL,
            "done" boolean DEFAULT true NOT NULL
        );

        CREATE TABLE IF NOT EXISTS "missed_trades" (
            "id" text PRIMARY KEY NOT NULL,
            "symbol" text NOT NULL,
            "direction" text NOT NULL,
            "observed_at" text NOT NULL,
            "playbook_id" text,
            "entry" numeric(38,10),
            "stop" numeric(38,10),
            "target" numeric(38,10),
            "notes" text DEFAULT '' NOT NULL,
            "created_at" text NOT NULL
        );

        CREATE TABLE IF NOT EXISTS "ai_memories" (
            "id" text PRIMARY KEY NOT NULL,
            "user_id" text,
            "kind" text NOT NULL,
            "symbol" text,
            "category" text DEFAULT 'general' NOT NULL,
            "content" text NOT NULL,
            "metadata_json" text DEFAULT '{}' NOT NULL,
            "importance" integer DEFAULT 3 NOT NULL,
            "created_at" text NOT NULL,
            "updated_at" text NOT NULL
        );

        CREATE TABLE IF NOT EXISTS "trade_lesson_evaluations" (
            "id" text PRIMARY KEY NOT NULL,
            "lesson_id" text NOT NULL,
            "trade_key" text NOT NULL,
            "followed" boolean NOT NULL,
            "pnl_impact" numeric(12,2),
            "notes" text,
            "evaluated_at" text NOT NULL
        );

        CREATE TABLE IF NOT EXISTS "ai_research_projects" (
            "id" text PRIMARY KEY NOT NULL,
            "user_id" text,
            "title" text NOT NULL,
            "hypothesis" text NOT NULL,
            "status" text DEFAULT 'active' NOT NULL,
            "sample_criteria_json" text DEFAULT '{}' NOT NULL,
            "sample_count" integer DEFAULT 0 NOT NULL,
            "win_rate" numeric(5,2),
            "profit_factor" numeric(10,2),
            "conclusion" text,
            "metadata_json" text DEFAULT '{}' NOT NULL,
            "created_at" text NOT NULL,
            "updated_at" text NOT NULL
        );
        """
    }

    internal var patchesAndRlsSql: String {
        return """
        -- Automatically patch columns if tables were created previously
        DO $$
        BEGIN
            -- accounts
            ALTER TABLE IF EXISTS accounts ADD COLUMN IF NOT EXISTS broker text DEFAULT '' NOT NULL;
            ALTER TABLE IF EXISTS accounts ADD COLUMN IF NOT EXISTS kind text DEFAULT 'trading' NOT NULL;
            ALTER TABLE IF EXISTS accounts ADD COLUMN IF NOT EXISTS currency text DEFAULT 'USD' NOT NULL;
            ALTER TABLE IF EXISTS accounts ADD COLUMN IF NOT EXISTS initial_balance numeric(38,10) DEFAULT 0 NOT NULL;
            ALTER TABLE IF EXISTS accounts ADD COLUMN IF NOT EXISTS profit_calc_method text DEFAULT 'fifo' NOT NULL;
            ALTER TABLE IF EXISTS accounts ADD COLUMN IF NOT EXISTS auto_sync boolean DEFAULT false NOT NULL;
            ALTER TABLE IF EXISTS accounts ADD COLUMN IF NOT EXISTS last_sync_at text;
            ALTER TABLE IF EXISTS accounts ADD COLUMN IF NOT EXISTS archived_at text;
            ALTER TABLE IF EXISTS accounts ADD COLUMN IF NOT EXISTS created_at text DEFAULT '';
            ALTER TABLE IF EXISTS accounts ALTER COLUMN initial_balance TYPE numeric(38,10) USING initial_balance::numeric;

            -- executions
            ALTER TABLE IF EXISTS executions ADD COLUMN IF NOT EXISTS asset_class text;
            ALTER TABLE IF EXISTS executions ADD COLUMN IF NOT EXISTS fee numeric(38,10) DEFAULT 0 NOT NULL;
            ALTER TABLE IF EXISTS executions ADD COLUMN IF NOT EXISTS swap numeric(38,10) DEFAULT 0 NOT NULL;
            ALTER TABLE IF EXISTS executions ADD COLUMN IF NOT EXISTS import_metadata_json text;
            ALTER TABLE IF EXISTS executions ALTER COLUMN quantity TYPE numeric(38,10) USING quantity::numeric;
            ALTER TABLE IF EXISTS executions ALTER COLUMN price TYPE numeric(38,10) USING price::numeric;
            ALTER TABLE IF EXISTS executions ALTER COLUMN fee TYPE numeric(38,10) USING fee::numeric;

            -- trades
            ALTER TABLE IF EXISTS trades ADD COLUMN IF NOT EXISTS asset_class text;
            ALTER TABLE IF EXISTS trades ADD COLUMN IF NOT EXISTS duration_ms bigint;
            ALTER TABLE IF EXISTS trades ADD COLUMN IF NOT EXISTS notes text;
            ALTER TABLE IF EXISTS trades ADD COLUMN IF NOT EXISTS tags_json text;
            ALTER TABLE IF EXISTS trades ADD COLUMN IF NOT EXISTS mistakes_json text;
            ALTER TABLE IF EXISTS trades ADD COLUMN IF NOT EXISTS playbook_id text;
            ALTER TABLE IF EXISTS trades ADD COLUMN IF NOT EXISTS rating integer;
            ALTER TABLE IF EXISTS trades ADD COLUMN IF NOT EXISTS stop_loss numeric(38,10);
            ALTER TABLE IF EXISTS trades ADD COLUMN IF NOT EXISTS profit_target numeric(38,10);
            ALTER TABLE IF EXISTS trades ADD COLUMN IF NOT EXISTS reviewed_at text;
            ALTER TABLE IF EXISTS trades ADD COLUMN IF NOT EXISTS swap numeric(38,10) DEFAULT 0 NOT NULL;
            ALTER TABLE IF EXISTS trades ALTER COLUMN quantity TYPE numeric(38,10) USING quantity::numeric;
            ALTER TABLE IF EXISTS trades ALTER COLUMN open_quantity TYPE numeric(38,10) USING open_quantity::numeric;
            ALTER TABLE IF EXISTS trades ALTER COLUMN avg_entry TYPE numeric(38,10) USING avg_entry::numeric;
            ALTER TABLE IF EXISTS trades ALTER COLUMN avg_exit TYPE numeric(38,10) USING avg_exit::numeric;
            ALTER TABLE IF EXISTS trades ALTER COLUMN gross_pnl TYPE numeric(38,10) USING gross_pnl::numeric;
            ALTER TABLE IF EXISTS trades ALTER COLUMN fees TYPE numeric(38,10) USING fees::numeric;
            ALTER TABLE IF EXISTS trades ALTER COLUMN net_pnl TYPE numeric(38,10) USING net_pnl::numeric;
            ALTER TABLE IF EXISTS trades ALTER COLUMN stop_loss TYPE numeric(38,10) USING stop_loss::numeric;
            ALTER TABLE IF EXISTS trades ALTER COLUMN profit_target TYPE numeric(38,10) USING profit_target::numeric;

            -- prop_entries
            ALTER TABLE IF EXISTS prop_entries ADD COLUMN IF NOT EXISTS category text DEFAULT '' NOT NULL;
            ALTER TABLE IF EXISTS prop_entries ADD COLUMN IF NOT EXISTS split_bps integer DEFAULT 8000 NOT NULL;
            ALTER TABLE IF EXISTS prop_entries ADD COLUMN IF NOT EXISTS fee_minor bigint DEFAULT 0 NOT NULL;
            ALTER TABLE IF EXISTS prop_entries ADD COLUMN IF NOT EXISTS occurred_on text DEFAULT '' NOT NULL;
            ALTER TABLE IF EXISTS prop_entries ADD COLUMN IF NOT EXISTS due_on text;
            ALTER TABLE IF EXISTS prop_entries ADD COLUMN IF NOT EXISTS status text DEFAULT 'completed' NOT NULL;
            ALTER TABLE IF EXISTS prop_entries ADD COLUMN IF NOT EXISTS reference text DEFAULT '' NOT NULL;
            ALTER TABLE IF EXISTS prop_entries ADD COLUMN IF NOT EXISTS voided boolean DEFAULT false NOT NULL;
            ALTER TABLE IF EXISTS prop_entries ADD COLUMN IF NOT EXISTS revision integer DEFAULT 1 NOT NULL;
            ALTER TABLE IF EXISTS prop_entries ADD COLUMN IF NOT EXISTS created_at text;
            ALTER TABLE IF EXISTS prop_entries ADD COLUMN IF NOT EXISTS updated_at text;

            -- prop_receipts
            ALTER TABLE IF EXISTS prop_receipts ADD COLUMN IF NOT EXISTS payout_id text DEFAULT '' NOT NULL;
            ALTER TABLE IF EXISTS prop_receipts ADD COLUMN IF NOT EXISTS kind text DEFAULT 'payout' NOT NULL;
            ALTER TABLE IF EXISTS prop_receipts ADD COLUMN IF NOT EXISTS amount_minor bigint DEFAULT 0 NOT NULL;
            ALTER TABLE IF EXISTS prop_receipts ADD COLUMN IF NOT EXISTS occurred_on text DEFAULT '' NOT NULL;
            ALTER TABLE IF EXISTS prop_receipts ADD COLUMN IF NOT EXISTS reference text DEFAULT '' NOT NULL;
            ALTER TABLE IF EXISTS prop_receipts ADD COLUMN IF NOT EXISTS voided boolean DEFAULT false NOT NULL;
        END $$;

        -- Remove legacy restrictive RLS policies if present (from user_id schema)
        DROP POLICY IF EXISTS "Users can only manage own accounts" ON accounts;
        DROP POLICY IF EXISTS "Users can only manage own executions" ON executions;
        DROP POLICY IF EXISTS "Users can only manage own trades" ON trades;
        DROP POLICY IF EXISTS "Users can only manage own folders" ON folders;
        DROP POLICY IF EXISTS "Users can only manage own notes" ON notes;
        DROP POLICY IF EXISTS "Users can only manage own playbooks" ON playbooks;
        DROP POLICY IF EXISTS "Users can only manage own prop_accounts" ON prop_accounts;
        DROP POLICY IF EXISTS "Users can only manage own journal days" ON journal_days;

        -- Enable RLS and grant access for anon, authenticated, and service_role
        ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;
        ALTER TABLE executions ENABLE ROW LEVEL SECURITY;
        ALTER TABLE trades ENABLE ROW LEVEL SECURITY;
        ALTER TABLE folders ENABLE ROW LEVEL SECURITY;
        ALTER TABLE notes ENABLE ROW LEVEL SECURITY;
        ALTER TABLE playbooks ENABLE ROW LEVEL SECURITY;
        ALTER TABLE prop_accounts ENABLE ROW LEVEL SECURITY;
        ALTER TABLE prop_entries ENABLE ROW LEVEL SECURITY;
        ALTER TABLE prop_receipts ENABLE ROW LEVEL SECURITY;
        ALTER TABLE prop_audit ENABLE ROW LEVEL SECURITY;
        ALTER TABLE attachments ENABLE ROW LEVEL SECURITY;
        ALTER TABLE settings ENABLE ROW LEVEL SECURITY;
        ALTER TABLE journal_days ENABLE ROW LEVEL SECURITY;
        ALTER TABLE progress_rules ENABLE ROW LEVEL SECURITY;
        ALTER TABLE progress_checks ENABLE ROW LEVEL SECURITY;
        ALTER TABLE missed_trades ENABLE ROW LEVEL SECURITY;
        ALTER TABLE ai_memories ENABLE ROW LEVEL SECURITY;
        ALTER TABLE trade_lesson_evaluations ENABLE ROW LEVEL SECURITY;
        ALTER TABLE ai_research_projects ENABLE ROW LEVEL SECURITY;

        DROP POLICY IF EXISTS "Allow All For Anon" ON accounts;
        CREATE POLICY "Allow All For Anon" ON accounts FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON executions;
        CREATE POLICY "Allow All For Anon" ON executions FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON trades;
        CREATE POLICY "Allow All For Anon" ON trades FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON folders;
        CREATE POLICY "Allow All For Anon" ON folders FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON notes;
        CREATE POLICY "Allow All For Anon" ON notes FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON playbooks;
        CREATE POLICY "Allow All For Anon" ON playbooks FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON prop_accounts;
        CREATE POLICY "Allow All For Anon" ON prop_accounts FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON prop_entries;
        CREATE POLICY "Allow All For Anon" ON prop_entries FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON prop_receipts;
        CREATE POLICY "Allow All For Anon" ON prop_receipts FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON prop_audit;
        CREATE POLICY "Allow All For Anon" ON prop_audit FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON attachments;
        CREATE POLICY "Allow All For Anon" ON attachments FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON settings;
        CREATE POLICY "Allow All For Anon" ON settings FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON journal_days;
        CREATE POLICY "Allow All For Anon" ON journal_days FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON progress_rules;
        CREATE POLICY "Allow All For Anon" ON progress_rules FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON progress_checks;
        CREATE POLICY "Allow All For Anon" ON progress_checks FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON missed_trades;
        CREATE POLICY "Allow All For Anon" ON missed_trades FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON ai_memories;
        CREATE POLICY "Allow All For Anon" ON ai_memories FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON trade_lesson_evaluations;
        CREATE POLICY "Allow All For Anon" ON trade_lesson_evaluations FOR ALL USING (true) WITH CHECK (true);
        DROP POLICY IF EXISTS "Allow All For Anon" ON ai_research_projects;
        CREATE POLICY "Allow All For Anon" ON ai_research_projects FOR ALL USING (true) WITH CHECK (true);

        -- Grant full table permissions to anon, authenticated, and service_role
        GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
        """
    }
}
