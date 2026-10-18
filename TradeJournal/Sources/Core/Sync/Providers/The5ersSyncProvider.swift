import Foundation

/// Synchronization provider for The5ers Model Context Protocol (MCP) Hub
public final class The5ersSyncProvider: SyncProvider {
    public let id: String = "the5ers"
    public let displayName: String = "The5ers MCP Hub"
    public let iconName: String = "building.columns"
    
    public var isConfigured: Bool {
        The5ersService.shared.isConfigured
    }
    
    public var capabilities: Set<SyncCapability> {
        [
            .accountSelection,
            .openPositions,
            .payoutsAndChallenges
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
                message: "The5ers MCP Token is not configured. Configure in Settings -> Connections.",
                error: "Not configured"
            )
        }
        
        progressHandler(SyncProgressUpdate(providerId: id, providerName: displayName, message: "Connecting to The5ers MCP Hub..."))
        
        let count = try await The5ersService.shared.syncWithTradeStore(dataStore: TradeDataStore.shared)
        let msg = "Successfully synchronized \(count) accounts & positions from The5ers Hub."
        
        progressHandler(SyncProgressUpdate(providerId: id, providerName: displayName, message: msg, isCompleted: true))
        
        return SyncResult(
            providerId: id,
            providerName: displayName,
            success: true,
            importedExecutionsCount: count,
            updatedPositionsCount: count,
            updatedAccountsCount: count,
            message: msg
        )
    }
}
