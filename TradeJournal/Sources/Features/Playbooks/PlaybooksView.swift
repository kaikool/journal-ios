import SwiftUI

/// Playbooks screen matching iOS 27 design standards:
/// - FilterBar with title "Playbooks" and "New playbook" button
/// - Empty state with Apple-standard typography and action button
/// - Interactive Playbook cards with expandable rules checklist (+ N more rules accordion)
/// - Modernized New & Edit Playbook sheets with dynamic numbered checklist rows (1, 2, 3...)
/// - Progressive disclosure: entering line 1 automatically spawns line 2
public struct PlaybooksView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    
    @State private var showNewPlaybookSheet: Bool = false
    @State private var playbookToEdit: Playbook? = nil
    @State private var playbookToDelete: Playbook? = nil
    @State private var showDeleteConfirmation: Bool = false
    
    public init() {}
    
    private var adherenceSummaries: [PlaybookAdherenceSummary] {
        AdherenceEngine.analyzeAdherence(
            playbooks: dataStore.playbooks,
            trades: dataStore.filteredTrades,
            assessments: dataStore.playbookAssessments
        )
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    if dataStore.playbooks.isEmpty {
                        emptyState
                    } else {
                        HStack {
                            Text("\(adherenceSummaries.count) Playbooks")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.secondaryText)
                            Spacer()
                            Button {
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                #endif
                                showNewPlaybookSheet = true
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("New Playbook")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(AppColors.brandPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                        .padding(.top, 4)
                        
                        playbooksList
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 88)
            }
            .background(AppColors.background)
        }
        .sheet(isPresented: $showNewPlaybookSheet) {
            NewPlaybookSheet { newPb in
                dataStore.savePlaybook(newPb)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
        .sheet(item: $playbookToEdit) { pb in
            EditPlaybookSheet(playbook: pb)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .alert("Delete “\(playbookToDelete?.title ?? "")”?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { playbookToDelete = nil }
            Button("Delete", role: .destructive) {
                if let pb = playbookToDelete {
                    dataStore.deletePlaybook(id: pb.id)
                    playbookToDelete = nil
                }
            }
        } message: {
            Text("Trades keep their data, just lose the link.")
        }
    }
    
    @ViewBuilder
    private var emptyState: some View {
        AppleCard {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AppColors.brand.opacity(0.12))
                        .frame(width: 64, height: 64)
                    Image(systemName: "book.pages")
                        .font(.system(size: 28))
                        .foregroundColor(AppColors.brand)
                }
                .padding(.top, 8)
                
                Text("Build Trading Playbooks")
                    .font(AppTypography.subheadlineBold)
                    .foregroundColor(AppColors.primaryText)
                
                Text("A playbook is a setup you trade on purpose — name it, write its checklist rules, then tag trades with it and let Reports reveal its true edge.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    showNewPlaybookSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("New Playbook")
                    }
                    .font(AppTypography.captionBold)
                    .foregroundColor(AppColors.brandTextOnDark)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(AppColors.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(ApplePressableButtonStyle())
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 16)
    }
    
    @ViewBuilder
    private var playbooksList: some View {
        ForEach(adherenceSummaries) { summary in
            let pbTrades = tradesForPlaybook(summary.playbook.id)
            NavigationLink(destination: PlaybookDetailView(
                playbook: summary.playbook,
                summary: summary,
                trades: pbTrades
            )) {
                PlaybookCardView(
                    summary: summary,
                    currency: env.currentCurrency,
                    onEdit: {
                        playbookToEdit = summary.playbook
                    },
                    onDelete: {
                        playbookToDelete = summary.playbook
                        showDeleteConfirmation = true
                    }
                )
            }
            .buttonStyle(ApplePressableButtonStyle())
        }
    }
    
    private func tradesForPlaybook(_ playbookId: String) -> [Trade] {
        dataStore.filteredTrades.filter { $0.playbookId == playbookId }
    }
}

