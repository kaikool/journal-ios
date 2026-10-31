import Foundation

// MARK: - Advisor Commitment Record
/// Represents an immutable historical commitment of analysis & advice given by AI Coach to the trader.
public struct AdvisorCommitmentRecord: Codable, Identifiable, Sendable {
    public let id: String
    public let symbol: String
    public let timestamp: Date
    public let bias: String // "BUY", "SELL", "FLAT"
    public let plannedEntry: String?
    public let invalidationSL: String?
    public let targetTP: String?
    public let takeProfit1: String?
    public let takeProfit2: String?
    public let volume: String?
    public let balance: String?
    public let triggerCondition: String?
    public let thesisSummary: String
    public var linkedOrderTicket: String?
    public var linkedTradeKey: String?
    
    public init(
        id: String = JournalIds.newId(),
        symbol: String,
        timestamp: Date = Date(),
        bias: String,
        plannedEntry: String? = nil,
        invalidationSL: String? = nil,
        targetTP: String? = nil,
        takeProfit1: String? = nil,
        takeProfit2: String? = nil,
        volume: String? = nil,
        balance: String? = nil,
        triggerCondition: String? = nil,
        thesisSummary: String,
        linkedOrderTicket: String? = nil,
        linkedTradeKey: String? = nil
    ) {
        self.id = id
        self.symbol = symbol.uppercased()
        self.timestamp = timestamp
        self.bias = bias
        self.plannedEntry = plannedEntry
        self.invalidationSL = invalidationSL
        self.targetTP = targetTP
        self.takeProfit1 = takeProfit1 ?? targetTP
        self.takeProfit2 = takeProfit2
        self.volume = volume
        self.balance = balance
        self.triggerCondition = triggerCondition
        self.thesisSummary = thesisSummary
        self.linkedOrderTicket = linkedOrderTicket
        self.linkedTradeKey = linkedTradeKey
    }
}

// MARK: - Trader AI Lesson Record
/// Persisted lessons extracted from losing trades, stopped out setups, or post-trade reviews.
public struct TraderAILesson: Codable, Identifiable, Sendable {
    public let id: String
    public let symbol: String?
    public let timestamp: Date
    public let setupType: String
    public let mistakeTag: String?
    public let lesson: String
    public let context: String?
    
    public init(
        id: String = JournalIds.newId(),
        symbol: String? = nil,
        timestamp: Date = Date(),
        setupType: String,
        mistakeTag: String? = nil,
        lesson: String,
        context: String? = nil
    ) {
        self.id = id
        self.symbol = symbol?.uppercased()
        self.timestamp = timestamp
        self.setupType = setupType
        self.mistakeTag = mistakeTag
        self.lesson = lesson
        self.context = context
    }
}

// MARK: - AI Advisor Memory Engine
/// Thread-safe central engine managing AI long-term memory across 5 knowledge categories,
/// advisor commitments, cross-session continuity, trade linking (PreTrade -> InTrade),
/// and adaptive lesson learning.
public final class AIAdvisorMemoryEngine: @unchecked Sendable {
    public static let shared = AIAdvisorMemoryEngine()
    
    private var memories: [AIMemoryRecord] = []
    private var commitments: [AdvisorCommitmentRecord] = []
    private var lessons: [TraderAILesson] = []
    private let lock = NSLock()
    
    private let persistenceUrl: URL? = {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("TradeJournal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ai_advisor_memory.json")
    }()
    
    private init() {
        loadFromDisk()
    }
    
    // MARK: - 1. Unified AI Long-Term Memory Management (Module A)
    
    /// Returns all persisted memories across all 5 categories, sorted newest first
    public var allMemories: [AIMemoryRecord] {
        lock.lock()
        defer { lock.unlock() }
        return memories.sorted { $0.createdAt > $1.createdAt }
    }
    
    /// Saves or updates a memory record
    /// Saves or updates a memory record.
    /// Strictly enforces that only 1 latest Decision & Commitment (.decision) is retained per unique symbol.
    public func saveMemory(_ record: AIMemoryRecord) {
        lock.lock()
        defer {
            lock.unlock()
            saveToDisk()
        }
        
        var supersededIds: [String] = []
        if record.category == .decision {
            let targetSym = record.symbol?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                .replacingOccurrences(of: "/", with: "")
                .replacingOccurrences(of: "_", with: "") ?? ""
            
            supersededIds = memories.filter { mem in
                guard mem.category == .decision, mem.id != record.id else { return false }
                let memSym = mem.symbol?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    .replacingOccurrences(of: "/", with: "")
                    .replacingOccurrences(of: "_", with: "") ?? ""
                return memSym == targetSym
            }.map { $0.id }
            
            if !supersededIds.isEmpty {
                memories.removeAll(where: { supersededIds.contains($0.id) })
                commitments.removeAll(where: { supersededIds.contains($0.id) })
            }
        }
        
        memories.removeAll(where: { $0.id == record.id })
        memories.append(record)
        
        // Sync to backward-compatible lists if applicable
        if record.category == .decision, let commitment = record.toAdvisorCommitmentRecord() {
            commitments.removeAll(where: { $0.id == commitment.id })
            commitments.append(commitment)
            if commitments.count > 100 { commitments.removeFirst(commitments.count - 100) }
        } else if record.category == .failure {
            let lesson = record.toTraderAILesson()
            lessons.removeAll(where: { $0.id == lesson.id })
            lessons.append(lesson)
            if lessons.count > 100 { lessons.removeFirst(lessons.count - 100) }
        }
        
        // Cap overall memory count to prevent unbounded local file growth (keep 300 newest)
        if memories.count > 300 {
            memories.sort { $0.createdAt < $1.createdAt }
            memories.removeFirst(memories.count - 300)
        }
        
        // Instant async cloud sync (upsert new record & purge superseded decision records)
        Task.detached(priority: .utility) {
            try? await SupabaseService.shared.upsertAIMemories([record])
            for oldId in supersededIds {
                try? await SupabaseService.shared.deleteAIMemory(id: oldId)
            }
        }
    }
    
    /// Retrieves memories filtered by category, status, and symbol
    public func getMemories(
        category: AIMemoryCategory? = nil,
        status: AIMemoryStatus? = .active,
        symbol: String? = nil,
        limit: Int = 100
    ) -> [AIMemoryRecord] {
        lock.lock()
        defer { lock.unlock() }
        
        let cleanSym = symbol?.uppercased()
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "_", with: "")
        
        return memories.filter { record in
            if let cat = category, record.category != cat { return false }
            if let st = status, record.status != st { return false }
            if let targetSym = cleanSym, !targetSym.isEmpty {
                guard let recSym = record.symbol?
                    .replacingOccurrences(of: "/", with: "")
                    .replacingOccurrences(of: "_", with: "") else {
                    return true // General memory applies to all symbols
                }
                return recSym == targetSym || targetSym.hasPrefix(recSym) || recSym.hasPrefix(targetSym)
            }
            return true
        }
        .sorted { $0.createdAt > $1.createdAt }
        .prefix(limit)
        .map { $0 }
    }
    
    /// Finds memory by ID
    public func getMemory(id: String) -> AIMemoryRecord? {
        lock.lock()
        defer { lock.unlock() }
        return memories.first(where: { $0.id == id })
    }
    
    /// Supersedes an old memory with a newer one, marking old as deprecated and linking supersededBy
    public func supersedeMemory(oldId: String, newRecord: AIMemoryRecord) {
        lock.lock()
        defer {
            lock.unlock()
            saveToDisk()
        }
        if let idx = memories.firstIndex(where: { $0.id == oldId }) {
            var old = memories[idx]
            old.status = .deprecated
            old.supersededBy = newRecord.id
            old.updatedAt = Date()
            memories[idx] = old
        }
        memories.removeAll(where: { $0.id == newRecord.id })
        memories.append(newRecord)
    }
    
    /// Updates memory status (e.g. .verified or .refuted)
    public func updateMemoryStatus(id: String, status: AIMemoryStatus) {
        lock.lock()
        defer {
            lock.unlock()
            saveToDisk()
        }
        if let idx = memories.firstIndex(where: { $0.id == id }) {
            var updated = memories[idx]
            updated.status = status
            updated.updatedAt = Date()
            memories[idx] = updated
        }
    }
    
    /// Deletes a memory by ID
    public func deleteMemory(id: String) {
        lock.lock()
        defer {
            lock.unlock()
            saveToDisk()
        }
        memories.removeAll(where: { $0.id == id })
        commitments.removeAll(where: { $0.id == id })
        lessons.removeAll(where: { $0.id == id })
        
        Task.detached(priority: .utility) {
            try? await SupabaseService.shared.deleteAIMemory(id: id)
        }
    }
    
    // MARK: - 1b. Cloud Synchronization (Two-Way Background Sync)
    
    /// Synchronizes local memory store with Supabase ai_memories table
    public func syncWithRemote() async {
        guard SupabaseService.shared.isConfigured else { return }
        
        do {
            let remoteMemories = try await SupabaseService.shared.fetchAIMemories()
            var modified = false
            var memoriesToUpload: [AIMemoryRecord] = []
            
            lock.lock()
            for remote in remoteMemories {
                if let idx = memories.firstIndex(where: { $0.id == remote.id }) {
                    // Conflict resolution: latest updatedAt wins
                    if remote.updatedAt > memories[idx].updatedAt {
                        memories[idx] = remote
                        modified = true
                    }
                } else {
                    memories.append(remote)
                    modified = true
                }
            }
            
            // Reconcile backward-compatible commitments & lessons and prune duplicate decisions
            if modified {
                pruneDuplicateDecisions()
                commitments = memories.compactMap { $0.toAdvisorCommitmentRecord() }
                lessons = memories.filter { $0.category == .failure }.map { $0.toTraderAILesson() }
            }
            
            // Find local memories that need uploading to Supabase
            for local in memories {
                if !remoteMemories.contains(where: { $0.id == local.id && $0.updatedAt >= local.updatedAt }) {
                    memoriesToUpload.append(local)
                }
            }
            lock.unlock()
            
            if modified {
                saveToDisk()
            }
            
            if !memoriesToUpload.isEmpty {
                try? await SupabaseService.shared.upsertAIMemories(memoriesToUpload)
            }
        } catch {
            AppLogger.warning("AIAdvisorMemoryEngine sync notice: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 1c. Selective Memory Retrieval for AI Context (Module A & Module F)
    
    /// Retrieves top 3-5 most pertinent active memories across categories for a given symbol or context
    public func getSelectiveMemoriesForPrompt(symbol: String?, maxItems: Int = 4) -> [AIMemoryRecord] {
        lock.lock()
        defer { lock.unlock() }
        
        let cleanSym = symbol?.uppercased()
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "_", with: "")
        
        // Exclude deprecated or refuted memories
        let eligible = memories.filter { $0.status == .active || $0.status == .verified }
        
        // 1. Symbol-specific failures & lessons (up to 2)
        var selected: [AIMemoryRecord] = []
        let symbolFailures = eligible.filter { record in
            guard let clean = cleanSym, record.category == .failure, let recSym = record.symbol?.replacingOccurrences(of: "/", with: "").replacingOccurrences(of: "_", with: "") else {
                return false
            }
            return recSym == clean || clean.hasPrefix(recSym) || recSym.hasPrefix(clean)
        }.sorted { ($0.confidence, $0.createdAt) > ($1.confidence, $1.createdAt) }
        
        selected.append(contentsOf: symbolFailures.prefix(2))
        
        // 2. High-priority Preferences & Discipline Rules (up to 2)
        let preferences = eligible.filter { $0.category == .preference }
            .sorted { ($0.confidence, $0.createdAt) > ($1.confidence, $1.createdAt) }
        selected.append(contentsOf: preferences.prefix(2))
        
        // 3. Relevant Decisions or Active Context (up to 1)
        if selected.count < maxItems {
            let contextOrDecisions = eligible.filter {
                $0.category == .context || ($0.category == .decision && (cleanSym.map { clean in $0.symbol?.contains(clean) == true } ?? false))
            }.sorted { $0.createdAt > $1.createdAt }
            selected.append(contentsOf: contextOrDecisions.prefix(maxItems - selected.count))
        }
        
        // 4. Fallback to general lessons if still under maxItems
        if selected.count < maxItems {
            let generalLessons = eligible.filter { rec in
                rec.category == .failure && !selected.contains(where: { $0.id == rec.id })
            }.sorted { $0.createdAt > $1.createdAt }
            selected.append(contentsOf: generalLessons.prefix(maxItems - selected.count))
        }
        
        return Array(selected.prefix(maxItems))
    }
    
    /// Formats selected memories into clean markdown for prompt injection
    public func formatMemoriesForPrompt(symbol: String?, isVi: Bool, maxItems: Int = 4) -> String {
        let items = getSelectiveMemoriesForPrompt(symbol: symbol, maxItems: maxItems)
        guard !items.isEmpty else { return "" }
        
        if isVi {
            var lines = ["[TRÍ NHỚ DÀI HẠN & BÀI HỌC KINH NGHIỆM ĐÃ LƯU]:"]
            for item in items {
                let symTag = item.symbol.map { " (\($0))" } ?? ""
                lines.append("• [\(item.category.localizedTitle)]\(symTag): \(item.content)")
            }
            lines.append("⚠️ YÊU CẦU: Đối chiếu nghiêm ngặt với các bài học và nguyên tắc đã lưu ở trên để giữ vững kỷ luật và phòng thủ rủi ro.")
            return "\n\n" + lines.joined(separator: "\n")
        } else {
            var lines = ["[LONG-TERM MEMORY & HISTORICAL LESSONS]:"]
            for item in items {
                let symTag = item.symbol.map { " (\($0))" } ?? ""
                lines.append("• [\(item.category.rawValue.capitalized)]\(symTag): \(item.content)")
            }
            lines.append("⚠️ REQUIREMENT: Strictly align recommendations with the above verified principles and past lessons.")
            return "\n\n" + lines.joined(separator: "\n")
        }
    }
    
    // MARK: - 2. Commitment Management (100% Backward Compatible)
    
    public var activeCommitments: [AdvisorCommitmentRecord] {
        lock.lock()
        defer { lock.unlock() }
        return commitments
    }
    
    public func saveCommitment(_ record: AdvisorCommitmentRecord) {
        lock.lock()
        defer {
            lock.unlock()
            saveToDisk()
        }
        let targetSym = record.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "_", with: "")
        
        let supersededCommitmentIds = commitments.filter { c in
            guard c.id != record.id else { return false }
            let cSym = c.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                .replacingOccurrences(of: "/", with: "")
                .replacingOccurrences(of: "_", with: "")
            return cSym == targetSym
        }.map { $0.id }
        
        commitments.removeAll(where: { supersededCommitmentIds.contains($0.id) || $0.id == record.id })
        commitments.append(record)
        if commitments.count > 100 {
            commitments.removeFirst(commitments.count - 100)
        }
        
        // Also synchronize to unified memories list and prune older decision memories
        let memory = AIMemoryRecord.from(commitment: record)
        memories.removeAll(where: { supersededCommitmentIds.contains($0.id) || $0.id == memory.id })
        memories.append(memory)
        
        if !supersededCommitmentIds.isEmpty {
            Task.detached(priority: .utility) {
                for oldId in supersededCommitmentIds {
                    try? await SupabaseService.shared.deleteAIMemory(id: oldId)
                }
            }
        }
    }
    
    /// Ensures that only ONE latest Decision & Commitment (.decision) is retained per unique symbol.
    public func pruneDuplicateDecisions() {
        var seenDecisionSymbols = Set<String>()
        var deduplicated: [AIMemoryRecord] = []
        var supersededIds: [String] = []
        
        let sorted = memories.sorted { $0.createdAt > $1.createdAt }
        for mem in sorted {
            if mem.category == .decision {
                let symKey = mem.symbol?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    .replacingOccurrences(of: "/", with: "")
                    .replacingOccurrences(of: "_", with: "") ?? "__GENERAL__"
                if seenDecisionSymbols.contains(symKey) {
                    supersededIds.append(mem.id)
                    continue
                }
                seenDecisionSymbols.insert(symKey)
                deduplicated.append(mem)
            } else {
                deduplicated.append(mem)
            }
        }
        self.memories = deduplicated
        if !supersededIds.isEmpty {
            self.commitments.removeAll(where: { supersededIds.contains($0.id) })
            Task.detached(priority: .utility) {
                for oldId in supersededIds {
                    try? await SupabaseService.shared.deleteAIMemory(id: oldId)
                }
            }
        }
    }
    
    /// Finds the latest Pre-Trade commitment given to the trader for a given symbol,
    /// within a specified lookback window (default 24 hours).
    public func getLatestCommitment(
        for symbol: String,
        beforeOrNear date: Date? = nil,
        maxLookbackHours: Double = 24.0
    ) -> AdvisorCommitmentRecord? {
        lock.lock()
        defer { lock.unlock() }
        
        let targetSymbol = symbol.uppercased()
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "_", with: "")
        let refDate = date ?? Date()
        let maxLookbackSec = maxLookbackHours * 3600.0
        
        return commitments
            .filter { record in
                let recSym = record.symbol
                    .replacingOccurrences(of: "/", with: "")
                    .replacingOccurrences(of: "_", with: "")
                guard recSym == targetSymbol || targetSymbol.hasPrefix(recSym) || recSym.hasPrefix(targetSymbol) else {
                    return false
                }
                let diff = refDate.timeIntervalSince(record.timestamp)
                return diff >= -1800.0 && diff <= maxLookbackSec
            }
            .sorted(by: { $0.timestamp > $1.timestamp })
            .first
    }
    
    /// Explicitly binds an AdvisorCommitmentRecord with an executed Trade and Order Ticket.
    public func linkCommitment(commitmentId: String, tradeKey: String, orderTicket: String?) {
        lock.lock()
        defer {
            lock.unlock()
            saveToDisk()
        }
        if let idx = commitments.firstIndex(where: { $0.id == commitmentId }) {
            var updated = commitments[idx]
            updated.linkedTradeKey = tradeKey
            if let t = orderTicket, !t.isEmpty {
                updated.linkedOrderTicket = t
            }
            commitments[idx] = updated
            
            // Also update in unified memories
            if let mIdx = memories.firstIndex(where: { $0.id == commitmentId }) {
                let updatedMem = AIMemoryRecord.from(commitment: updated)
                memories[mIdx] = updatedMem
            }
        }
    }
    
    /// Retrieves all historical commitments for a given symbol, sorted newest first.
    public func getCommitments(for symbol: String) -> [AdvisorCommitmentRecord] {
        lock.lock()
        defer { lock.unlock() }
        let targetSymbol = symbol.uppercased()
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "_", with: "")
        return commitments.filter { record in
            let recSym = record.symbol
                .replacingOccurrences(of: "/", with: "")
                .replacingOccurrences(of: "_", with: "")
            return recSym == targetSymbol || targetSymbol.hasPrefix(recSym) || recSym.hasPrefix(targetSymbol)
        }.sorted(by: { $0.timestamp > $1.timestamp })
    }
    
    /// Finds commitment by Trade Key
    public func getCommitment(byTradeKey tradeKey: String) -> AdvisorCommitmentRecord? {
        lock.lock()
        defer { lock.unlock() }
        return commitments.first(where: { $0.linkedTradeKey == tradeKey })
    }
    
    /// Finds commitment by Order Ticket
    public func getCommitment(byOrderTicket ticket: String) -> AdvisorCommitmentRecord? {
        lock.lock()
        defer { lock.unlock() }
        let cleanTicket = ticket.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
        return commitments.first(where: {
            if let l = $0.linkedOrderTicket?.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces) {
                return l == cleanTicket
            }
            return false
        })
    }
    
    /// Retrieves the commitment associated with a trade (either explicitly linked or matching ticket)
    public func getCommitmentForTrade(tradeKey: String, executionIds: [String]) -> AdvisorCommitmentRecord? {
        lock.lock()
        defer { lock.unlock() }
        if let match = commitments.first(where: { $0.linkedTradeKey == tradeKey }) {
            return match
        }
        for execId in executionIds {
            let clean = execId.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
            if let match = commitments.first(where: {
                if let l = $0.linkedOrderTicket?.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces) {
                    return l == clean
                }
                return false
            }) {
                return match
            }
        }
        return nil
    }
    
    /// Convenience helper for Trade model
    public func getCommitmentForTrade(_ trade: Trade) -> AdvisorCommitmentRecord? {
        return getCommitmentForTrade(tradeKey: trade.key, executionIds: trade.executionIds)
    }
    
    // MARK: - 3. Lesson & Mistake Memory Management (100% Backward Compatible)
    
    public func saveLesson(_ lesson: TraderAILesson) {
        lock.lock()
        defer {
            lock.unlock()
            saveToDisk()
        }
        lessons.removeAll(where: { $0.id == lesson.id })
        lessons.append(lesson)
        if lessons.count > 100 {
            lessons.removeFirst(lessons.count - 100)
        }
        
        // Also synchronize to unified memories list
        let memory = AIMemoryRecord.from(lesson: lesson)
        memories.removeAll(where: { $0.id == memory.id })
        memories.append(memory)
    }
    
    public func getRelevantLessons(for symbol: String?, limit: Int = 3) -> [TraderAILesson] {
        lock.lock()
        defer { lock.unlock() }
        
        let cleanSym = symbol?.uppercased()
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "_", with: "")
        
        let symbolMatched = lessons.filter { l in
            guard let clean = cleanSym, let lSym = l.symbol else { return false }
            let c = lSym.replacingOccurrences(of: "/", with: "").replacingOccurrences(of: "_", with: "")
            return c == clean || clean.hasPrefix(c) || c.hasPrefix(clean)
        }
        
        if !symbolMatched.isEmpty {
            return Array(symbolMatched.suffix(limit))
        }
        
        // Fallback to recent general lessons
        return Array(lessons.suffix(limit))
    }
    
    // MARK: - 3b. Lesson Evaluation & Compliance Tracking (Module D)
    
    /// Records an evaluated trade failure/lesson with full taxonomy and tracking metadata
    public func saveLessonEvaluation(_ evaluation: TradeLessonEvaluation) {
        lock.lock()
        let mem = AIMemoryRecord.from(evaluation: evaluation)
        memories.removeAll(where: { $0.id == mem.id })
        memories.append(mem)
        
        // Also keep legacy lessons list in sync
        let legacyLesson = mem.toTraderAILesson()
        lessons.removeAll(where: { $0.id == legacyLesson.id })
        lessons.append(legacyLesson)
        lock.unlock()
        
        saveToDisk()
        Task {
            await syncWithRemote()
        }
    }
    
    /// Retrieves all recorded lesson evaluations, optionally filtered by symbol
    public func getLessonEvaluations(for symbol: String? = nil) -> [TradeLessonEvaluation] {
        lock.lock()
        defer { lock.unlock() }
        
        let evals = memories
            .filter { $0.category == .failure }
            .map { $0.toTradeLessonEvaluation() }
        
        guard let s = symbol?.uppercased().replacingOccurrences(of: "/", with: "").replacingOccurrences(of: "_", with: ""), !s.isEmpty else {
            return evals
        }
        
        return evals.filter { e in
            let clean = e.symbol.replacingOccurrences(of: "/", with: "").replacingOccurrences(of: "_", with: "")
            return clean == s || s.hasPrefix(clean) || clean.hasPrefix(s)
        }
    }
    
    /// Records whether a subsequent trade complied with or repeated a past lesson
    public func recordLessonAdherence(evaluationId: String, complied: Bool) {
        lock.lock()
        guard let idx = memories.firstIndex(where: { $0.id == evaluationId }) else {
            lock.unlock()
            return
        }
        var evaluation = memories[idx].toTradeLessonEvaluation()
        if complied {
            evaluation.verifiedCount += 1
        } else {
            evaluation.violatedCount += 1
        }
        evaluation.updatedAt = Date()
        
        let updatedMem = AIMemoryRecord.from(evaluation: evaluation)
        memories[idx] = updatedMem
        lock.unlock()
        
        saveToDisk()
        Task {
            await syncWithRemote()
        }
    }
    
    /// Computes summary of compliance & recurrence for a given symbol or globally
    public func getComplianceSummary(symbol: String? = nil) -> AIComplianceTracker.ComplianceSummary {
        let evals = getLessonEvaluations(for: symbol)
        return AIComplianceTracker.computeSummary(evaluations: evals)
    }
    
    /// Formats compliance statistics for prompt inclusion (Zero hardcoding)
    public func formatComplianceBlock(symbol: String? = nil, isVi: Bool = true) -> String {
        let summary = getComplianceSummary(symbol: symbol)
        return AIComplianceTracker.formatComplianceForPrompt(summary, isVi: isVi)
    }
    
    // MARK: - 4. Parsing & Extraction Helpers
    
    /// Parses an AI analysis output string into a structured AdvisorCommitmentRecord with discrete setup fields.
    public func extractCommitment(
        from analysisText: String,
        symbol: String,
        fallbackBalance: String? = nil,
        fallbackVolume: String? = nil
    ) -> AdvisorCommitmentRecord {
        let lines = analysisText.components(separatedBy: .newlines)
        var bias = "FLAT"
        var entry: String? = nil
        var sl: String? = nil
        var tp1: String? = nil
        var tp2: String? = nil
        var volume: String? = fallbackVolume
        var balance: String? = fallbackBalance
        var trigger: String? = nil
        
        func cleanField(_ raw: String) -> String {
            var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            s = s.replacingOccurrences(of: "^[-•*\\s>\\[\\]]+", with: "", options: .regularExpression)
            if let colonIdx = s.firstIndex(of: ":") {
                let after = s[s.index(after: colonIdx)...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !after.isEmpty { s = after }
            }
            s = s.replacingOccurrences(of: "[*`\\[\\]]", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            return s
        }
        
        for line in lines {
            let lower = line.lowercased()
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 1. Direction / Bias
            if lower.contains("direction:") || lower.contains("hướng:") || lower.contains("bias:") || lower.contains("kết luận:") || lower.contains("verdict:") {
                if lower.contains("sell") || lower.contains("short") || lower.contains("bán") {
                    bias = "SELL"
                } else if lower.contains("buy") || lower.contains("long") || lower.contains("mua") {
                    bias = "BUY"
                } else if lower.contains("flat") || lower.contains("đứng ngoài") || lower.contains("stand aside") {
                    bias = "FLAT"
                }
            }
            
            // 2. Balance
            if lower.contains("balance:") || lower.contains("số dư:") || lower.contains("vốn:") {
                let val = cleanField(trimmed)
                if !val.isEmpty && val != "N/A" {
                    balance = val
                }
            }
            
            // 3. Entry
            if lower.contains("entry:") || lower.contains("optimal entry") || lower.contains("điểm vào") || lower.contains("vùng vào lệnh") || lower.contains("vào lệnh tại:") {
                let val = cleanField(trimmed)
                if !val.isEmpty && val != "N/A" {
                    entry = val
                }
            }
            
            // 4. Stop Loss
            if lower.contains("stop loss:") || lower.contains("sl:") || lower.contains("cắt lỗ:") || lower.contains("invalidation:") {
                let val = cleanField(trimmed)
                if !val.isEmpty && val != "N/A" {
                    sl = val
                }
            }
            
            // 5. Take Profit 1
            if lower.contains("take profit 1:") || lower.contains("tp 1:") || lower.contains("tp1:") || lower.contains("chốt lời 1:") || lower.contains("mục tiêu 1:") {
                let val = cleanField(trimmed)
                if !val.isEmpty && val != "N/A" {
                    tp1 = val
                }
            } else if tp1 == nil && (lower.contains("target tp:") || lower.contains("targets:") || lower.contains("mục tiêu chốt lời:") || lower.contains("take profit:")) && !lower.contains("tp 2") && !lower.contains("tp2") {
                let val = cleanField(trimmed)
                if !val.isEmpty && val != "N/A" {
                    tp1 = val
                }
            }
            
            // 6. Take Profit 2 (nếu có)
            if lower.contains("take profit 2:") || lower.contains("tp 2:") || lower.contains("tp2:") || lower.contains("chốt lời 2:") || lower.contains("mục tiêu 2:") {
                let val = cleanField(trimmed)
                if !val.isEmpty && !val.lowercased().contains("không") && !val.lowercased().contains("none") && !val.lowercased().contains("n/a") {
                    tp2 = val
                }
            }
            
            // 7. Volume
            if lower.contains("volume:") || lower.contains("khối lượng:") || lower.contains("lot:") || lower.contains("size:") {
                let val = cleanField(trimmed)
                if !val.isEmpty && val != "N/A" {
                    volume = val
                }
            }
            
            // 8. Trigger
            if lower.contains("điều kiện kích hoạt:") || lower.contains("trigger:") || lower.contains("điều kiện cần chờ:") {
                trigger = cleanField(trimmed)
            }
        }
        
        // Summary
        let nonHeaders = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#") }
        let summary = nonHeaders.prefix(3).joined(separator: " ")
        
        return AdvisorCommitmentRecord(
            symbol: symbol,
            bias: bias,
            plannedEntry: entry,
            invalidationSL: sl,
            targetTP: tp1,
            takeProfit1: tp1,
            takeProfit2: tp2,
            volume: volume,
            balance: balance,
            triggerCondition: trigger,
            thesisSummary: summary.isEmpty ? analysisText.prefix(200).description : summary
        )
    }
    
    // MARK: - 5. Persistence & Automatic Migration
    private struct PersistedMemoryV2: Codable {
        let memories: [AIMemoryRecord]?
        let commitments: [AdvisorCommitmentRecord]?
        let lessons: [TraderAILesson]?
    }
    
    private struct PersistedMemoryLegacy: Codable {
        let commitments: [AdvisorCommitmentRecord]
        let lessons: [TraderAILesson]
    }
    
    private func saveToDisk() {
        guard let url = persistenceUrl else { return }
        let payload = PersistedMemoryV2(memories: memories, commitments: commitments, lessons: lessons)
        if let encoded = try? JSONEncoder().encode(payload) {
            try? encoded.write(to: url, options: .atomic)
        }
    }
    
    private func loadFromDisk() {
        guard let url = persistenceUrl, FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        
        let decoder = JSONDecoder()
        
        // 1. Attempt V2 Decode
        if let decodedV2 = try? decoder.decode(PersistedMemoryV2.self, from: data) {
            self.memories = decodedV2.memories ?? []
            self.commitments = decodedV2.commitments ?? []
            self.lessons = decodedV2.lessons ?? []
            
            // If memories is empty but legacy lists exist, migrate them to memories
            if self.memories.isEmpty {
                for c in self.commitments {
                    self.memories.append(AIMemoryRecord.from(commitment: c))
                }
                for l in self.lessons {
                    self.memories.append(AIMemoryRecord.from(lesson: l))
                }
            }
            pruneDuplicateDecisions()
            saveToDisk()
            return
        }
        
        // 2. Fallback to Legacy Decode
        if let decodedLegacy = try? decoder.decode(PersistedMemoryLegacy.self, from: data) {
            self.commitments = decodedLegacy.commitments
            self.lessons = decodedLegacy.lessons
            self.memories = []
            for c in self.commitments {
                self.memories.append(AIMemoryRecord.from(commitment: c))
            }
            for l in self.lessons {
                self.memories.append(AIMemoryRecord.from(lesson: l))
            }
            saveToDisk()
        }
    }
}
