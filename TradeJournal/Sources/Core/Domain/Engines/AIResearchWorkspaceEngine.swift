import Foundation

// MARK: - Persistent Research Workspace Engine (Module E)
/// Manages continuous, multi-session research projects and empirical hypothesis testing.
/// Preserves project state, sample criteria, and validation checkpoints across app launches.
/// Zero hardcoded judgments; strictly provides quantitative research parameters to AI prompts.
public final class AIResearchWorkspaceEngine: @unchecked Sendable {
    public static let shared = AIResearchWorkspaceEngine()
    
    private var projects: [AIResearchProject] = []
    private let lock = NSLock()
    
    private let diskUrl: URL? = {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("TradeJournal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ai_research_projects.json")
    }()
    
    private init() {
        loadFromDisk()
    }
    
    // MARK: - CRUD Operations
    
    @discardableResult
    public func createProject(
        title: String,
        hypothesis: String,
        criteria: AIResearchSampleCriteria = AIResearchSampleCriteria()
    ) -> AIResearchProject {
        lock.lock()
        let project = AIResearchProject(
            title: title,
            hypothesis: hypothesis,
            criteria: criteria
        )
        projects.append(project)
        lock.unlock()
        
        saveToDisk()
        Task { await syncWithRemote() }
        return project
    }
    
    public func updateProject(_ project: AIResearchProject) {
        lock.lock()
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            var updated = project
            updated.updatedAt = Date()
            projects[idx] = updated
        }
        lock.unlock()
        
        saveToDisk()
        Task { await syncWithRemote() }
    }
    
    public func addCheckpoint(projectId: String, checkpoint: AIResearchCheckpoint) {
        lock.lock()
        if let idx = projects.firstIndex(where: { $0.id == projectId }) {
            var p = projects[idx]
            p.checkpoints.append(checkpoint)
            p.sampleCount = checkpoint.sampleCount
            if let wr = checkpoint.winRate { p.winRate = wr }
            if let pf = checkpoint.profitFactor { p.profitFactor = pf }
            p.updatedAt = Date()
            projects[idx] = p
        }
        lock.unlock()
        
        saveToDisk()
        Task { await syncWithRemote() }
    }
    
    public func updateStatus(
        projectId: String,
        status: AIResearchProjectStatus,
        conclusion: String? = nil
    ) {
        lock.lock()
        if let idx = projects.firstIndex(where: { $0.id == projectId }) {
            var p = projects[idx]
            p.status = status
            if let c = conclusion { p.conclusion = c }
            p.updatedAt = Date()
            projects[idx] = p
        }
        lock.unlock()
        
        saveToDisk()
        Task { await syncWithRemote() }
    }
    
    public func deleteProject(projectId: String) {
        lock.lock()
        projects.removeAll(where: { $0.id == projectId })
        lock.unlock()
        
        saveToDisk()
        Task {
            try? await SupabaseService.shared.deleteAIResearchProject(id: projectId)
        }
    }
    
    public func getActiveProjects(symbol: String? = nil) -> [AIResearchProject] {
        lock.lock()
        defer { lock.unlock() }
        
        let active = projects.filter { $0.status == .active }
        guard let s = symbol?.uppercased().replacingOccurrences(of: "/", with: "").replacingOccurrences(of: "_", with: ""), !s.isEmpty else {
            return active
        }
        
        return active.filter { p in
            if p.criteria.symbols.isEmpty { return true }
            return p.criteria.symbols.contains { sym in
                let clean = sym.replacingOccurrences(of: "/", with: "").replacingOccurrences(of: "_", with: "")
                return clean == s || s.hasPrefix(clean) || clean.hasPrefix(s)
            }
        }
    }
    
    public var allProjects: [AIResearchProject] {
        getAllProjects()
    }
    
    public func getAllProjects() -> [AIResearchProject] {
        lock.lock()
        defer { lock.unlock() }
        return projects
    }
    
    // MARK: - Markdown Formatter for AI Context (Zero Hardcoding)
    
    public func formatProjectsForPrompt(symbol: String? = nil, isVi: Bool = true) -> String {
        let relevant = getActiveProjects(symbol: symbol)
        guard !relevant.isEmpty else { return "" }
        
        if isVi {
            var lines: [String] = [
                "",
                "[DỰ ÁN NGHIÊN CỨU DÀI HẠN ĐANG TRIỂN KHAI (ACTIVE RESEARCH WORKSPACE)]:"
            ]
            for p in relevant.prefix(2) {
                let syms = p.criteria.symbols.isEmpty ? "Toàn bộ thị trường" : p.criteria.symbols.joined(separator: ", ")
                let tfs = p.criteria.timeframes.isEmpty ? "Đa khung" : p.criteria.timeframes.joined(separator: ", ")
                let wrStr = p.winRate.map { String(format: "%.1f%%", $0) } ?? "Đang thu thập"
                let pfStr = p.profitFactor.map { String(format: "%.2f", $0) } ?? "Đang thu thập"
                
                lines.append("• Dự án: [\(p.title)] | Trạng thái: [\(p.status.titleVi)]")
                lines.append("  - Giả thuyết kiểm chứng: \"\(p.hypothesis)\"")
                lines.append("  - Tiêu chí mẫu: Cặp: [\(syms)] | Khung: [\(tfs)] | Số mẫu hiện tại: \(p.sampleCount)/\(p.criteria.minSampleSize)")
                lines.append("  - Kết quả sơ bộ: Win Rate = [\(wrStr)] | Profit Factor = [\(pfStr)]")
                if let lastChk = p.checkpoints.last, !lastChk.notes.isEmpty {
                    lines.append("  - Checkpoint gần nhất: \(lastChk.notes)")
                }
            }
            return lines.joined(separator: "\n")
        } else {
            var lines: [String] = [
                "",
                "[ACTIVE RESEARCH WORKSPACE & HYPOTHESIS TESTING]:"
            ]
            for p in relevant.prefix(2) {
                let syms = p.criteria.symbols.isEmpty ? "All Symbols" : p.criteria.symbols.joined(separator: ", ")
                let tfs = p.criteria.timeframes.isEmpty ? "Multi-TF" : p.criteria.timeframes.joined(separator: ", ")
                let wrStr = p.winRate.map { String(format: "%.1f%%", $0) } ?? "Gathering"
                let pfStr = p.profitFactor.map { String(format: "%.2f", $0) } ?? "Gathering"
                
                lines.append("• Project: [\(p.title)] | Status: [\(p.status.titleEn)]")
                lines.append("  - Working Hypothesis: \"\(p.hypothesis)\"")
                lines.append("  - Sample Scope: Pairs: [\(syms)] | TF: [\(tfs)] | Sample Progress: \(p.sampleCount)/\(p.criteria.minSampleSize)")
                lines.append("  - Empirical Metrics: Win Rate = [\(wrStr)] | Profit Factor = [\(pfStr)]")
                if let lastChk = p.checkpoints.last, !lastChk.notes.isEmpty {
                    lines.append("  - Latest Checkpoint: \(lastChk.notes)")
                }
            }
            return lines.joined(separator: "\n")
        }
    }
    
    // MARK: - Disk Persistence
    
    private func saveToDisk() {
        guard let url = diskUrl else { return }
        lock.lock()
        let copy = projects
        lock.unlock()
        
        if let data = try? JSONEncoder().encode(copy) {
            try? data.write(to: url, options: .atomic)
        }
    }
    
    private func loadFromDisk() {
        guard let url = diskUrl, FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([AIResearchProject].self, from: data) else {
            return
        }
        self.projects = decoded
    }
    
    // MARK: - Supabase Synchronization
    
    public func syncWithRemote() async {
        do {
            let remote = try await SupabaseService.shared.fetchAIResearchProjects()
            guard !remote.isEmpty else { return }
            
            var modified = false
            lock.lock()
            for r in remote {
                if let idx = projects.firstIndex(where: { $0.id == r.id }) {
                    if r.updatedAt > projects[idx].updatedAt {
                        projects[idx] = r
                        modified = true
                    }
                } else {
                    projects.append(r)
                    modified = true
                }
            }
            lock.unlock()
            
            if modified {
                saveToDisk()
            }
            
            // Upload local newer projects
            lock.lock()
            let localCopy = projects
            lock.unlock()
            let toUpload = localCopy.filter { local in
                !remote.contains(where: { $0.id == local.id && $0.updatedAt >= local.updatedAt })
            }
            if !toUpload.isEmpty {
                try? await SupabaseService.shared.upsertAIResearchProjects(toUpload)
            }
        } catch {
            AppLogger.warning("AIResearchWorkspaceEngine sync notice: \(error.localizedDescription)")
        }
    }
}
