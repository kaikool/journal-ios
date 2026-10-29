import XCTest
@testable import TradeJournal

final class AIMemoryTests: XCTestCase {
    
    func testAIMemoryRecordInitialization() {
        let memory = AIMemoryRecord(
            category: .preference,
            symbol: "XAUUSD",
            title: "Rule 1",
            content: "Never risk more than 1%",
            confidence: 0.95,
            status: .active,
            sourceType: .manual
        )
        
        XCTAssertEqual(memory.category, .preference)
        XCTAssertEqual(memory.symbol, "XAUUSD")
        XCTAssertEqual(memory.title, "Rule 1")
        XCTAssertEqual(memory.content, "Never risk more than 1%")
        XCTAssertEqual(memory.confidence, 0.95)
        XCTAssertEqual(memory.status, .active)
        XCTAssertEqual(memory.sourceType, .manual)
    }
    
    func testTraderAILessonBidirectionalConversion() {
        let lesson = TraderAILesson(
            id: "lesson-123",
            symbol: "EURUSD",
            timestamp: Date(timeIntervalSince1970: 1700000000),
            setupType: "London Sweep",
            mistakeTag: "FOMO",
            lesson: "Do not enter before sweep completes",
            context: "Morning session"
        )
        
        // Convert to AIMemoryRecord
        let memory = AIMemoryRecord.from(lesson: lesson)
        XCTAssertEqual(memory.id, "lesson-123")
        XCTAssertEqual(memory.category, .failure)
        XCTAssertEqual(memory.symbol, "EURUSD")
        XCTAssertEqual(memory.title, "London Sweep")
        XCTAssertEqual(memory.content, "Do not enter before sweep completes")
        XCTAssertEqual(memory.status, .active)
        
        // Convert back to TraderAILesson
        let reconstructed = memory.toTraderAILesson()
        XCTAssertEqual(reconstructed.id, lesson.id)
        XCTAssertEqual(reconstructed.symbol, lesson.symbol)
        XCTAssertEqual(reconstructed.setupType, lesson.setupType)
        XCTAssertEqual(reconstructed.mistakeTag, lesson.mistakeTag)
        XCTAssertEqual(reconstructed.lesson, lesson.lesson)
        XCTAssertEqual(reconstructed.context, lesson.context)
    }
    
    func testAdvisorCommitmentRecordBidirectionalConversion() {
        let commitment = AdvisorCommitmentRecord(
            id: "commit-456",
            symbol: "BTCUSD",
            timestamp: Date(timeIntervalSince1970: 1700000000),
            bias: "BUY",
            plannedEntry: "68000",
            invalidationSL: "67200",
            targetTP: "70000",
            triggerCondition: "M15 MSS Confirmation",
            thesisSummary: "Bullish continuation after liquidity sweep",
            linkedOrderTicket: "T123456",
            linkedTradeKey: "trade-789"
        )
        
        // Convert to AIMemoryRecord
        let memory = AIMemoryRecord.from(commitment: commitment)
        XCTAssertEqual(memory.id, "commit-456")
        XCTAssertEqual(memory.category, .decision)
        XCTAssertEqual(memory.symbol, "BTCUSD")
        XCTAssertEqual(memory.sourceType, .preTrade)
        XCTAssertEqual(memory.content, commitment.thesisSummary)
        
        // Convert back to AdvisorCommitmentRecord
        let reconstructed = memory.toAdvisorCommitmentRecord()
        XCTAssertNotNil(reconstructed)
        XCTAssertEqual(reconstructed?.id, commitment.id)
        XCTAssertEqual(reconstructed?.symbol, commitment.symbol)
        XCTAssertEqual(reconstructed?.bias, commitment.bias)
        XCTAssertEqual(reconstructed?.plannedEntry, commitment.plannedEntry)
        XCTAssertEqual(reconstructed?.invalidationSL, commitment.invalidationSL)
        XCTAssertEqual(reconstructed?.targetTP, commitment.targetTP)
        XCTAssertEqual(reconstructed?.triggerCondition, commitment.triggerCondition)
        XCTAssertEqual(reconstructed?.thesisSummary, commitment.thesisSummary)
        XCTAssertEqual(reconstructed?.linkedOrderTicket, commitment.linkedOrderTicket)
        XCTAssertEqual(reconstructed?.linkedTradeKey, commitment.linkedTradeKey)
    }
    
    func testMemoryEngineSupersedingAndStatusUpdate() {
        let engine = AIAdvisorMemoryEngine.shared
        let initialMemory = AIMemoryRecord(
            id: "mem-old",
            category: .preference,
            symbol: "XAUUSD",
            title: "Max Risk 2%",
            content: "Allow 2% risk on A+ setups",
            status: .active
        )
        engine.saveMemory(initialMemory)
        
        XCTAssertEqual(engine.getMemory(id: "mem-old")?.status, .active)
        
        let newMemory = AIMemoryRecord(
            id: "mem-new",
            category: .preference,
            symbol: "XAUUSD",
            title: "Max Risk 1%",
            content: "Strictly reduce max risk to 1% following prop audit",
            status: .active
        )
        engine.supersedeMemory(oldId: "mem-old", newRecord: newMemory)
        
        // Old memory should now be deprecated with link to new
        let oldFetched = engine.getMemory(id: "mem-old")
        XCTAssertEqual(oldFetched?.status, .deprecated)
        XCTAssertEqual(oldFetched?.supersededBy, "mem-new")
        
        // New memory should be active
        let newFetched = engine.getMemory(id: "mem-new")
        XCTAssertEqual(newFetched?.status, .active)
        
        // Clean up test data
        engine.deleteMemory(id: "mem-old")
        engine.deleteMemory(id: "mem-new")
    }
    
    func testSelectivePromptMemoryFormatting() {
        let engine = AIAdvisorMemoryEngine.shared
        
        // Add a verified rule
        let rule = AIMemoryRecord(
            id: "test-rule-1",
            category: .preference,
            title: "Discipline",
            content: "Never revenge trade after 2 losses",
            status: .verified
        )
        engine.saveMemory(rule)
        
        let promptText = engine.formatMemoriesForPrompt(symbol: "XAUUSD", isVi: true, maxItems: 3)
        XCTAssertTrue(promptText.contains("[TRÍ NHỚ DÀI HẠN & BÀI HỌC KINH NGHIỆM ĐÃ LƯU]"))
        XCTAssertTrue(promptText.contains("Never revenge trade after 2 losses"))
        
        engine.deleteMemory(id: "test-rule-1")
    }
    
    func testAICoachSessionStorePersistence() {
        let store = AICoachSessionStore.shared
        let sessionKey = "test_session_key_\(UUID().uuidString)"
        let msgs = [
            AICoachMessage(role: "user", content: "Is this trade valid?"),
            AICoachMessage(role: "assistant", content: "Valid if M15 MSS confirms.")
        ]
        
        store.save(key: sessionKey, result: "Summary of thesis", followUps: msgs)
        
        let retrieved = store.get(key: sessionKey)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.result, "Summary of thesis")
        XCTAssertEqual(retrieved?.followUps.count, 2)
        XCTAssertEqual(retrieved?.followUps.first?.content, "Is this trade valid?")
        
        store.clear(key: sessionKey)
        XCTAssertNil(store.get(key: sessionKey))
    }
}
