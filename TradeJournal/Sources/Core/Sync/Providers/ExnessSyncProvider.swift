import Foundation

/// Synchronization provider for Exness REST API integration
@MainActor
public final class ExnessSyncProvider: SyncProvider {
    public let id: String = "exness"
    public let displayName: String = "Exness"
    public let iconName: String = "chart.line.uptrend.xyaxis"
    
    public var isConfigured: Bool {
        ExnessService.shared.isConnected || !ExnessService.shared.accountId.isEmpty
    }
    
    public var capabilities: Set<SyncCapability> {
        [
            .openPositions,
            .orderHistory
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
                message: "Tài khoản Exness chưa được cấu hình.",
                error: "Not configured"
            )
        }
        
        progressHandler(SyncProgressUpdate(providerId: id, providerName: displayName, message: "Đang kết nối Exness API..."))
        
        let count = try await ExnessService.shared.syncTrades()
        let msg = "Đã đồng bộ \(count) giao dịch từ Exness."
        
        progressHandler(SyncProgressUpdate(providerId: id, providerName: displayName, message: msg, isCompleted: true))
        
        return SyncResult(
            providerId: id,
            providerName: displayName,
            success: true,
            importedExecutionsCount: count,
            updatedPositionsCount: count,
            updatedAccountsCount: 1,
            message: msg
        )
    }
}
