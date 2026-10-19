import XCTest
@testable import TradeJournal

final class PersistenceSafetyTests: XCTestCase {
    private var tempDirectory: URL!
    private var primaryUrl: URL!
    private var backupUrl: URL!
    
    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        primaryUrl = tempDirectory.appendingPathComponent("trade_journal_store_v1.json")
        backupUrl = tempDirectory.appendingPathComponent("trade_journal_store_v1.json.bak")
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }
    
    func testDecodeStoreFromValidPrimaryFile() throws {
        let store = TradeDataStore.PersistedStore(
            schemaVersion: 1,
            accounts: [Account(id: "acc-1", name: "Main MT5", currency: "USD", initialBalance: 10000)],
            executions: [],
            trades: [],
            selectedAccountId: "acc-1",
            defaults: JournalDefaults(feePerUnit: 0, defaultMultiplier: 1),
            multipliers: nil,
            folders: nil,
            notebookNotes: nil,
            journalDays: nil,
            propAccounts: nil,
            propEntries: nil,
            propReceipts: nil,
            propAudits: nil,
            attachments: nil,
            playbooks: nil,
            playbookAssessments: nil,
            calendarNotes: nil,
            missedTrades: nil,
            progressRules: nil,
            progressChecks: nil,
            generalSettings: nil,
            currencyConversion: nil,
            marketConnections: nil,
            aiSettings: nil,
            deletedPlaybookIds: nil
        )
        
        let data = try JSONEncoder().encode(store)
        try data.write(to: primaryUrl)
        
        let result = TradeDataStore.decodeStoreFromDisk(primaryUrl: primaryUrl, backupUrl: backupUrl)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.store.schemaVersion, 1)
        XCTAssertEqual(result?.store.accounts.count, 1)
        XCTAssertEqual(result?.store.accounts[0].name, "Main MT5")
    }
    
    func testCorruptedPrimaryRecoversFromBackupFile() throws {
        let backupStore = TradeDataStore.PersistedStore(
            schemaVersion: 1,
            accounts: [Account(id: "acc-backup", name: "Backup Account", currency: "USD", initialBalance: 50000)],
            executions: [],
            trades: [],
            selectedAccountId: "acc-backup",
            defaults: JournalDefaults(feePerUnit: 0, defaultMultiplier: 1),
            multipliers: nil,
            folders: nil,
            notebookNotes: nil,
            journalDays: nil,
            propAccounts: nil,
            propEntries: nil,
            propReceipts: nil,
            propAudits: nil,
            attachments: nil,
            playbooks: nil,
            playbookAssessments: nil,
            calendarNotes: nil,
            missedTrades: nil,
            progressRules: nil,
            progressChecks: nil,
            generalSettings: nil,
            currencyConversion: nil,
            marketConnections: nil,
            aiSettings: nil,
            deletedPlaybookIds: nil
        )
        let backupData = try JSONEncoder().encode(backupStore)
        try backupData.write(to: backupUrl)
        
        // Write corrupted bytes to primary file
        let corruptedBytes = Data("CORRUPTED_JSON_DATA_!!!".utf8)
        try corruptedBytes.write(to: primaryUrl)
        
        let result = TradeDataStore.decodeStoreFromDisk(primaryUrl: primaryUrl, backupUrl: backupUrl)
        XCTAssertNotNil(result, "Store should successfully recover from backup file")
        XCTAssertEqual(result?.store.accounts[0].id, "acc-backup")
        
        // Check quarantine file was created in the directory
        let files = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)
        let quarantineFiles = files.filter { $0.hasPrefix("trade_journal_corrupt_") }
        XCTAssertEqual(quarantineFiles.count, 1, "Corrupted file must be quarantined to prevent data loss")
    }
}
