import Foundation

// MARK: - Supabase Database Migration & Remote Wipe Helper
extension SupabaseService {
    // MARK: - Database Wipe / Truncate Operations
    
    /// Generates safe TRUNCATE SQL for Supabase SQL Editor that wipes all rows across 20 tables while keeping table structures and RLS intact.
    public func generateTruncateAllSql() -> String {
        return """
        -- ========================================================
        -- Trade Journal: Clean Wipe All Records (Preserve Schemas)
        -- ========================================================
        TRUNCATE TABLE 
            "ai_memories",
            "trade_lesson_evaluations",
            "ai_research_projects",
            "prop_audit",
            "prop_receipts",
            "prop_entries",
            "prop_accounts",
            "trade_excursions",
            "trade_rule_checks",
            "trades",
            "executions",
            "import_batches",
            "import_source_aliases",
            "import_sources",
            "notes",
            "folders",
            "journal_days",
            "playbooks",
            "progress_checks",
            "progress_rules",
            "missed_trades",
            "attachments",
            "accounts"
        CASCADE;
        """
    }
    
    /// Wipes all remote application records across all PostgreSQL tables on Supabase PostgREST.
    /// Preserves database tables, DDL structures, indexes, and RLS policies.
    public func wipeAllRemoteData() async throws {
        guard isConfigured else { throw SupabaseError.notConfigured }
        
        let tablesToWipe = [
            "ai_memories",
            "trade_lesson_evaluations",
            "ai_research_projects",
            "prop_audit",
            "prop_receipts",
            "prop_entries",
            "prop_accounts",
            "trade_excursions",
            "trade_rule_checks",
            "trades",
            "executions",
            "import_batches",
            "import_source_aliases",
            "import_sources",
            "notes",
            "folders",
            "journal_days",
            "playbooks",
            "progress_checks",
            "progress_rules",
            "missed_trades",
            "attachments",
            "accounts"
        ]
        
        for table in tablesToWipe {
            let endpoint: String
            switch table {
            case "trades":
                endpoint = "trades?key=not.is.null"
            case "journal_days":
                endpoint = "journal_days?date=not.is.null"
            default:
                endpoint = "\(table)?id=not.is.null"
            }
            
            do {
                let req = try makeRequest(endpoint: endpoint, method: "DELETE")
                let (data, response) = try await session.data(for: req)
                try validateResponse(response, data: data, endpoint: endpoint)
                AppLogger.info("Successfully wiped Supabase table: \(table)")
            } catch {
                AppLogger.warning("Supabase table wipe notice for \(table): \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - SQL Migration Script Generator
    
    /// Generates idempotent PostgreSQL DDL schema matching web parity
    public func generateDatabaseInitSql() -> String {
        [coreSchemaSql, propFirmSchemaSql, progressAndAISchemaSql, patchesAndRlsSql].joined(separator: "\n\n")
    }
    
    /// Generates quick hotfix SQL script resolving missing columns (e.g. 'swap') and RLS violations
    public func generateQuickFixPatchSql() -> String {
        return """
        -- ========================================================
        -- Trade Journal: Hotfix Migration for Missing Columns & RLS
        -- Paste into Supabase SQL Editor and click 'Run'
        -- ========================================================

        -- 1. Ensure 'swap' column exists in trades and executions
        ALTER TABLE IF EXISTS trades ADD COLUMN IF NOT EXISTS swap numeric(38,10) DEFAULT 0 NOT NULL;
        ALTER TABLE IF EXISTS executions ADD COLUMN IF NOT EXISTS swap numeric(38,10) DEFAULT 0 NOT NULL;
        ALTER TABLE IF EXISTS trades ADD COLUMN IF NOT EXISTS asset_class text;
        ALTER TABLE IF EXISTS executions ADD COLUMN IF NOT EXISTS asset_class text;

        -- 2. Ensure 'prop_audit' table exists
        CREATE TABLE IF NOT EXISTS "prop_audit" (
            "id" text PRIMARY KEY NOT NULL,
            "entity_type" text NOT NULL,
            "entity_id" text NOT NULL,
            "before_json" text,
            "after_json" text NOT NULL,
            "reason" text NOT NULL,
            "created_at" text
        );

        -- 3. Fix Row Level Security (RLS) policies for anon and authenticated
        ALTER TABLE prop_audit ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS "Allow All For Anon" ON prop_audit;
        CREATE POLICY "Allow All For Anon" ON prop_audit FOR ALL USING (true) WITH CHECK (true);

        ALTER TABLE trades ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS "Allow All For Anon" ON trades;
        CREATE POLICY "Allow All For Anon" ON trades FOR ALL USING (true) WITH CHECK (true);

        ALTER TABLE executions ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS "Allow All For Anon" ON executions;
        CREATE POLICY "Allow All For Anon" ON executions FOR ALL USING (true) WITH CHECK (true);

        -- 4. Grant table access to anon, authenticated, and service_role
        GRANT ALL ON TABLE prop_audit TO anon, authenticated, service_role;
        GRANT ALL ON TABLE trades TO anon, authenticated, service_role;
        GRANT ALL ON TABLE executions TO anon, authenticated, service_role;
        GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;

        -- 5. Reload PostgREST schema cache immediately
        NOTIFY pgrst, 'reload schema';
        """
    }
}
