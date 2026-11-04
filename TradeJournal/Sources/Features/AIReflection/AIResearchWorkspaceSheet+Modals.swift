import SwiftUI

// MARK: - New Research Project Sheet (Clean Dark Terminal Styling)
internal struct NewResearchProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let onCreated: (AIResearchProject) -> Void
    
    @State private var title: String = ""
    @State private var hypothesis: String = ""
    @State private var symbols: String = "XAUUSD, EURUSD"
    @State private var timeframes: String = "15m, 4h"
    @State private var minSampleSize: Int = 30
    
    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !hypothesis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            AppSectionHeader("Title & working hypothesis")
                            
                            AppFormField(
                                "Project Title",
                                text: $title,
                                placeholder: "e.g. H4 Breaker Block + M15 FVG",
                                height: 42
                            )
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Hypothesis Description")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                
                                TextEditor(text: $hypothesis)
                                    .font(AppTypography.inputText)
                                    .frame(minHeight: 100)
                                    .appSubCardStyle(cornerRadius: 10, padding: 8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(AppColors.border.opacity(0.45), lineWidth: 0.6)
                                    )
                            }
                        }
                    }
                    
                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            AppSectionHeader("Scope & sample criteria")
                            
                            AppFormField(
                                "Target Symbols",
                                text: $symbols,
                                placeholder: "e.g. XAUUSD, EURUSD",
                                height: 42
                            )
                            
                            AppFormField(
                                "Timeframes",
                                text: $timeframes,
                                placeholder: "e.g. 15m, 4h",
                                height: 42
                            )
                            
                            HStack {
                                Text("Minimum Sample Size:")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                Text("\(minSampleSize) trades")
                                    .font(AppTypography.numberSmall)
                                    .foregroundColor(AppColors.primaryText)
                                Stepper("", value: $minSampleSize, in: 10...200, step: 5)
                                    .labelsHidden()
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(AppColors.background)
            .navigationTitle("New Research Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ModalDismissButton { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ModalPrimaryButton("Create", isEnabled: isFormValid) {
                        let symArr = symbols.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                            .filter { !$0.isEmpty }
                        let tfArr = timeframes.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        
                        let criteria = AIResearchSampleCriteria(
                            symbols: symArr,
                            timeframes: tfArr,
                            minSampleSize: minSampleSize
                        )
                        
                        let newProj = AIResearchWorkspaceEngine.shared.createProject(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            hypothesis: hypothesis.trimmingCharacters(in: .whitespacesAndNewlines),
                            criteria: criteria
                        )
                        onCreated(newProj)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Add Research Checkpoint Sheet (Clean Dark Terminal Styling)
internal struct AddResearchCheckpointSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let project: AIResearchProject
    let onSaved: () -> Void
    
    @State private var sampleCount: Int = 10
    @State private var winRateText: String = ""
    @State private var profitFactorText: String = ""
    @State private var notes: String = ""
    
    init(project: AIResearchProject, onSaved: @escaping () -> Void) {
        self.project = project
        self.onSaved = onSaved
        _sampleCount = State(initialValue: max(project.sampleCount + 1, 1))
        _winRateText = State(initialValue: project.winRate.map { Formatters.formatDecimalInput(Decimal($0), maxDecimals: 1) } ?? "")
        _profitFactorText = State(initialValue: project.profitFactor.map { Formatters.formatDecimalInput(Decimal($0), maxDecimals: 2) } ?? "")
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    AppCard {
                        VStack(alignment: .leading, spacing: 12) {
                            AppSectionHeader("Sample & performance metrics")
                            
                            HStack {
                                Text("Trades Sampled:")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                Text("\(sampleCount) trades")
                                    .font(AppTypography.numberSmall)
                                    .foregroundColor(AppColors.primaryText)
                                Stepper("", value: $sampleCount, in: 1...500)
                                    .labelsHidden()
                            }
                            
                            HStack(spacing: 10) {
                                AppNumericField(
                                    "Win Rate %",
                                    text: $winRateText,
                                    placeholder: "e.g. 62.5",
                                    unit: "%",
                                    height: 38
                                )
                                
                                AppNumericField(
                                    "Profit Factor",
                                    text: $profitFactorText,
                                    placeholder: "e.g. 1.85",
                                    height: 38
                                )
                            }
                        }
                    }
                    
                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            AppSectionHeader("Observations & qualitative notes")
                            
                            TextEditor(text: $notes)
                                .font(AppTypography.inputText)
                                .frame(minHeight: 100)
                                .appSubCardStyle(cornerRadius: 10, padding: 8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(AppColors.border.opacity(0.45), lineWidth: 0.6)
                                )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(AppColors.background)
            .navigationTitle("Record Checkpoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ModalDismissButton { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ModalPrimaryButton("Save") {
                        let wr = Double(winRateText.replacingOccurrences(of: ",", with: "."))
                        let pf = Double(profitFactorText.replacingOccurrences(of: ",", with: "."))
                        
                        let chk = AIResearchCheckpoint(
                            sampleCount: sampleCount,
                            winRate: wr,
                            profitFactor: pf,
                            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        
                        AIResearchWorkspaceEngine.shared.addCheckpoint(projectId: project.id, checkpoint: chk)
                        onSaved()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Conclude Research Project Sheet (Clean Dark Terminal Styling)
internal struct ConcludeResearchProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let project: AIResearchProject
    let targetStatus: AIResearchProjectStatus
    let onSaved: () -> Void
    
    @State private var conclusionText: String = ""
    
    init(project: AIResearchProject, targetStatus: AIResearchProjectStatus, onSaved: @escaping () -> Void) {
        self.project = project
        self.targetStatus = targetStatus
        self.onSaved = onSaved
        _conclusionText = State(initialValue: project.conclusion ?? "")
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("EMPIRICAL CONCLUSION")
                                .font(AppTypography.cardHeader)
                                .foregroundColor(AppColors.secondaryText)
                            
                            HStack(spacing: 6) {
                                Image(systemName: targetStatus == .validated ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(AppTypography.captionBold)
                                Text(targetStatus == .validated ? "Confirming hypothesis as validated rule" : "Refuting hypothesis due to adverse metrics")
                                    .font(AppTypography.captionBold)
                            }
                            .foregroundColor(targetStatus == .validated ? AppColors.profit : AppColors.loss)
                            
                            TextEditor(text: $conclusionText)
                                .font(AppTypography.inputText)
                                .frame(minHeight: 120)
                                .appSubCardStyle(cornerRadius: 8, padding: 8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border.opacity(0.6), lineWidth: 0.8))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(AppColors.background)
            .navigationTitle(targetStatus == .validated ? "Validate Hypothesis" : "Invalidate Hypothesis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ModalDismissButton { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ModalPrimaryButton("Save") {
                        AIResearchWorkspaceEngine.shared.updateStatus(
                            projectId: project.id,
                            status: targetStatus,
                            conclusion: conclusionText.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        onSaved()
                        dismiss()
                    }
                }
            }
        }
    }
}
