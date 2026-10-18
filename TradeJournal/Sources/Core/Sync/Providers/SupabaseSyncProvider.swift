import Foundation

/// Synchronization provider for Supabase Cloud Database & Storage
public final class SupabaseSyncProvider: SyncProvider {
    public let id: String = "supabase"
    public let displayName: String = "Supabase Cloud"
    public let iconName: String = "cylinder.split.1x2"
    
    public var isConfigured: Bool {
        SupabaseService.shared.isConfigured
    }
    
    public var capabilities: Set<SyncCapability> {
        [
            .cloudBackup
        ]
    }
    
    public init() {}
    
    public func performSync(
        options: SyncOptions,
        progressHandler: @escaping (SyncProgressUpdate) -> Void
    ) async throws -> SyncResult {
        guard isConfigured else {
            return SyncResult(
                providerId: id,
                providerName: displayName,
                success: false,
                message: "Supabase credentials are not configured. Configure in Settings -> Data & backups.",
                error: "Not configured"
            )
        }
        
        progressHandler(SyncProgressUpdate(providerId: id, providerName: displayName, message: "Backing up data to Supabase Cloud Database..."))
        
        await TradeDataStore.shared.syncWithSupabase()
        
        if let err = await MainActor.run(body: { TradeDataStore.shared.lastSyncError }) {
            return SyncResult(
                providerId: id,
                providerName: displayName,
                success: false,
                message: "Supabase Cloud sync error: \(err)",
                error: err
            )
        }
        
        let summary = await MainActor.run(body: { TradeDataStore.shared.lastSyncSummary }) ?? "Supabase Cloud database synchronization completed."
        progressHandler(SyncProgressUpdate(providerId: id, providerName: displayName, message: summary, isCompleted: true))
        
        return SyncResult(
            providerId: id,
            providerName: displayName,
            success: true,
            message: summary
        )
    }
}
