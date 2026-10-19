import Foundation

/// Synchronization provider for Spotware cTrader Open API v2
@MainActor
public final class CTraderSyncProvider: SyncProvider {
    public let id: String = "ctrader"
    public let displayName: String = "cTrader Open API"
    public let iconName: String = "chart.xyaxis.line"
    
    public var isConfigured: Bool {
        CTraderService.shared.isConfigured
    }
    
    public var capabilities: Set<SyncCapability> {
        [
            .dateRangeFilter,
            .accountSelection,
            .openPositions,
            .historicalExecutions
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
                message: "cTrader Access Token is not configured. Configure in Settings -> Connections.",
                error: "Not configured"
            )
        }
        
        progressHandler(SyncProgressUpdate(providerId: id, providerName: displayName, message: "Connecting to cTrader Open API..."))
        
        let interval = options.dateRangeMode.dateInterval(customStart: options.customStartDate, customEnd: options.customEndDate)
        let fromTs: Int64? = interval.start.map { Int64($0.timeIntervalSince1970 * 1000) }
        let toTs: Int64? = interval.end.map { Int64($0.timeIntervalSince1970 * 1000) }
        
        // Map selectedAccountIds from journal account IDs (e.g. "ctrader_5123491") back to raw ctidTraderAccountId
        var targetCtids: Set<Int64>? = nil
        if let selected = options.selectedAccountIds, !selected.isEmpty {
            var ctids = Set<Int64>()
            for accId in selected {
                if accId.hasPrefix("ctrader_"), let num = Int64(accId.dropFirst(8)) {
                    ctids.insert(num)
                } else if let num = Int64(accId) {
                    ctids.insert(num)
                }
            }
            if !ctids.isEmpty {
                targetCtids = ctids
            }
        }
        
        let summary = try await CTraderService.shared.syncWithTradeStore(
            dataStore: TradeDataStore.shared,
            fromTimestamp: fromTs,
            toTimestamp: toTs,
            targetAccountIds: targetCtids
        )
        
        progressHandler(SyncProgressUpdate(providerId: id, providerName: displayName, message: summary.message, isCompleted: true))
        
        return SyncResult(
            providerId: id,
            providerName: displayName,
            success: true,
            importedExecutionsCount: summary.dealsImported,
            updatedPositionsCount: summary.tradesRebuilt,
            updatedAccountsCount: summary.accountsSynced,
            message: summary.message
        )
    }
}
