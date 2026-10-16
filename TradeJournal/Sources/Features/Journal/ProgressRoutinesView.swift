import SwiftUI

/// Màn hình quản lý và theo dõi thói quen kỷ luật giao dịch hàng ngày
/// Port 1:1 từ `source-repo/apps/web/src/app/progress/page.tsx`
public struct ProgressRoutinesView: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @EnvironmentObject private var env: AppEnvironment
    
    @State private var selectedDate: String = ""
    @State private var showAddRoutineSheet: Bool = false
    @State private var ruleToArchive: ProgressRule? = nil
    @State private var showArchiveAlert: Bool = false
    
    public static let stages = ["Trước khi giao dịch", "Trong khi giao dịch", "Sau khi giao dịch"]
    
    public init() {}
    
    private var todayKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = env.currentTimeZone
        return formatter.string(from: Date())
    }
    
    private var activeDate: String {
        selectedDate.isEmpty ? todayKey : selectedDate
    }
    
    private var score: (completed: Int, total: Int, percent: Double) {
        dataStore.progressScore(for: activeDate)
    }
    
    /// 91 ngày gần nhất (13 tuần) phục vụ streak heatmap
    private var past91Days: [(date: String, percent: Double, completed: Int, total: Int)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = env.currentTimeZone
        
        let calendar = Calendar.current
        let today = Date()
        
        return (0..<91).reversed().compactMap { offset in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let dStr = formatter.string(from: d)
            let s = dataStore.progressScore(for: dStr)
            return (date: dStr, percent: s.percent, completed: s.completed, total: s.total)
        }
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header Bar
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Thói Quen Kỷ Luật")
                                .font(AppTypography.title2)
                                .foregroundColor(AppColors.primaryText)
                            Text("Xây dựng quy trình giao dịch có tính lặp lại và đo lường kỷ luật")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        
                        Spacer()
                        
                        Button {
                            showAddRoutineSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("Thêm thói quen")
                            }
                            .font(AppTypography.captionBold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppColors.accent)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    // Card 1: Tổng kết hoàn thành ngày (Daily completion & Date selector)
                    completionScoreCard
                    
                    // Card 2: 3 Stages checklist (Trước, Trong, Sau khi giao dịch)
                    stagesSection
                    
                    // Card 3: 13-week heatmap streak (Ma trận kỷ luật 90 ngày)
                    heatmapCard
                }
                .padding(.bottom, 32)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAddRoutineSheet) {
                AddProgressRoutineSheet()
            }
            .alert("Lưu trữ thói quen", isPresented: $showArchiveAlert, presenting: ruleToArchive) { rule in
                Button("Lưu trữ (Xoá)", role: .destructive) {
                    dataStore.deleteProgressRule(id: rule.id)
                }
                Button("Huỷ", role: .cancel) {}
            } message: { rule in
                Text("Bạn có chắc chắn muốn ngừng theo dõi thói quen “\(rule.title)”? Dữ liệu ngày trước vẫn được lưu giữ.")
            }
        }
    }
    
    // MARK: - Subviews
    
    private var completionScoreCard: some View {
        AppCard {
            VStack(spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mức độ hoàn thành")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        Text("\(Int(score.percent * 100))%")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(score.percent >= 0.8 ? AppColors.profit : (score.percent >= 0.5 ? AppColors.accent : AppColors.secondaryText))
                        
                        Text("Đã làm \(score.completed)/\(score.total) thói quen trong ngày")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Spacer()
                    
                    // Bộ chọn ngày đánh giá
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Ngày xem xét")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .foregroundColor(AppColors.accent)
                            Text(activeDate == todayKey ? "Hôm nay (\(activeDate))" : activeDate)
                                .font(AppTypography.bodyBold)
                                .foregroundColor(AppColors.primaryText)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppColors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                
                // Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColors.secondaryBackground)
                            .frame(height: 8)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(score.percent >= 0.8 ? AppColors.profit : AppColors.accent)
                            .frame(width: max(0, min(geo.size.width * CGFloat(score.percent), geo.size.width)), height: 8)
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(.horizontal, 16)
    }
    
    private var stagesSection: some View {
        VStack(spacing: 12) {
            ForEach(Self.stages, id: \.self) { stage in
                stageCard(stage)
            }
        }
        .padding(.horizontal, 16)
    }
    
    @ViewBuilder
    private func stageCard(_ stage: String) -> some View {
        let rulesForStage = dataStore.progressRules.filter { r in
            r.archivedAt == nil && (r.stage == stage || (stage == "Trước khi giao dịch" && r.stage == "Before trading") || (stage == "Trong khi giao dịch" && r.stage == "During trading") || (stage == "Sau khi giao dịch" && r.stage == "After trading"))
        }
        
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: stageIcon(stage))
                        .foregroundColor(AppColors.accent)
                    Text(stage)
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                    Text("\(rulesForStage.filter { isRuleChecked($0.id) }.count)/\(rulesForStage.count)")
                        .font(AppTypography.captionBold)
                        .foregroundColor(AppColors.secondaryText)
                }
                
                Divider()
                
                if rulesForStage.isEmpty {
                    Text("Chưa có thói quen nào trong giai đoạn này.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 10) {
                        ForEach(rulesForStage) { rule in
                            HStack(alignment: .center, spacing: 12) {
                                Button {
                                    dataStore.toggleProgressCheck(ruleId: rule.id, date: activeDate)
                                } label: {
                                    Image(systemName: isRuleChecked(rule.id) ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 20))
                                        .foregroundColor(isRuleChecked(rule.id) ? AppColors.accent : AppColors.secondaryText)
                                }
                                .buttonStyle(.plain)
                                
                                Text(rule.title)
                                    .font(AppTypography.body)
                                    .foregroundColor(isRuleChecked(rule.id) ? AppColors.secondaryText : AppColors.primaryText)
                                    .strikethrough(isRuleChecked(rule.id))
                                
                                Spacer()
                                
                                Button {
                                    ruleToArchive = rule
                                    showArchiveAlert = true
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13))
                                        .foregroundColor(AppColors.secondaryText.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                            }
                            
                            if rule.id != rulesForStage.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func isRuleChecked(_ ruleId: String) -> Bool {
        dataStore.progressChecks.contains { $0.ruleId == ruleId && $0.date == activeDate && $0.done }
    }
    
    private func stageIcon(_ stage: String) -> String {
        switch stage {
        case "Trước khi giao dịch": return "sunrise.fill"
        case "Trong khi giao dịch": return "waveform.path.ecg"
        case "Sau khi giao dịch": return "moon.stars.fill"
        default: return "checklist"
        }
    }
    
    private var heatmapCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Kỷ luật 13 tuần qua (91 ngày)")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                }
                
                Text("Màu càng sáng thể hiện tỷ lệ hoàn thành thói quen càng cao. Chạm vào ô bất kỳ để xem và kiểm tra lại ngày đó.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                
                // Lưới 91 ô chia theo tuần (13 cột x 7 hàng)
                ScrollView(.horizontal, showsIndicators: false) {
                    let columns = Array(repeating: GridItem(.fixed(18), spacing: 4), count: 13)
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(past91Days, id: \.date) { item in
                            Button {
                                selectedDate = item.date
                            } label: {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(cellColor(percent: item.percent, total: item.total))
                                    .frame(width: 18, height: 18)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(activeDate == item.date ? AppColors.primaryText : Color.clear, lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.horizontal, 16)
    }
    
    private func cellColor(percent: Double, total: Int) -> Color {
        if total == 0 {
            return AppColors.secondaryBackground
        }
        if percent == 0 {
            return AppColors.secondaryBackground.opacity(0.8)
        }
        return AppColors.accent.opacity(0.2 + (percent * 0.8))
    }
}

/// Sheet thêm thói quen mới
public struct AddProgressRoutineSheet: View {
    @ObservedObject private var dataStore = TradeDataStore.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var stage: String = ProgressRoutinesView.stages[0]
    @State private var selectedDays: Set<Int> = [1, 2, 3, 4, 5] // Thứ 2 - Thứ 6 mặc định
    
    private let weekdayNames = [
        (0, "CN"),
        (1, "T2"),
        (2, "T3"),
        (3, "T4"),
        (4, "T5"),
        (5, "T6"),
        (6, "T7")
    ]
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Tên thói quen")) {
                    TextField("VD: Đọc tin vĩ mô, Kiểm tra Forex Factory...", text: $title)
                        .font(AppTypography.body)
                }
                
                Section(header: Text("Giai đoạn áp dụng")) {
                    Picker("Giai đoạn", selection: $stage) {
                        ForEach(ProgressRoutinesView.stages, id: \.self) { st in
                            Text(st).tag(st)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section(header: Text("Các ngày áp dụng trong tuần")) {
                    HStack {
                        ForEach(weekdayNames, id: \.0) { day in
                            let isSelected = selectedDays.contains(day.0)
                            Button {
                                if isSelected {
                                    selectedDays.remove(day.0)
                                } else {
                                    selectedDays.insert(day.0)
                                }
                            } label: {
                                Text(day.1)
                                    .font(AppTypography.captionBold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(isSelected ? AppColors.accent : AppColors.secondaryBackground)
                                    .foregroundColor(isSelected ? .white : AppColors.primaryText)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Thêm thói quen mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Huỷ") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Lưu") {
                        saveRoutine()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedDays.isEmpty)
                    .font(AppTypography.headline)
                }
            }
        }
    }
    
    private func saveRoutine() {
        let daysArr = Array(selectedDays).sorted()
        let jsonStr = "[\(daysArr.map(String.init).joined(separator: ","))]"
        let rule = ProgressRule(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            stage: stage,
            weekdaysJson: jsonStr
        )
        dataStore.saveProgressRule(rule)
        dismiss()
    }
}
