import SwiftUI
import UIKit

// MARK: - Pre-Trade Multi-Timeframe Market Structure & Bias Analyzer (Apple HIG)
// Coordinates D1 macro regime, H4 order blocks, and M15 execution structure to deliver actionable setups
public struct PreTradeAnalysisSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var dataStore = TradeDataStore.shared
    @StateObject private var viewModel: PreTradeAnalysisViewModel
    
    public init(initialSymbol: String = "XAUUSD") {
        self._viewModel = StateObject(wrappedValue: PreTradeAnalysisViewModel(initialSymbol: initialSymbol))
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // 1. Symbol Selection & Quick Switcher
                    PreTradeSymbolSelectorCard(
                        selectedSymbol: $viewModel.selectedSymbol,
                        customSymbolText: $viewModel.customSymbolText,
                        onSelectSymbol: { sym in
                            viewModel.onSymbolSelected(sym, dataStore: dataStore)
                        },
                        onSubmitCustom: {
                            viewModel.submitCustomSymbol(dataStore: dataStore)
                        }
                    )
                    
                    // 2. Multi-Timeframe Chart Vision Card
                    PreTradeChartCard(
                        symbol: viewModel.selectedSymbol,
                        selectedTimeframe: $viewModel.selectedTimeframe,
                        activeBars: viewModel.activeBars,
                        d1Bars: viewModel.d1Bars,
                        h4Bars: viewModel.h4Bars,
                        h1Bars: viewModel.h1Bars,
                        m15Bars: viewModel.m15Bars,
                        activeProvider: viewModel.activeProvider,
                        onEnlarge: {
                            if let snapshot = viewModel.userAttachedImage ?? viewModel.activeChartSnapshot {
                                viewModel.activeChartSnapshot = snapshot
                                viewModel.activeFullScreenModal = .lightbox(snapshot)
                            } else {
                                viewModel.activeFullScreenModal = .landscapeChart
                            }
                        },
                        onAttachPhoto: { viewModel.showPhotoPicker = true },
                        onInteractionChanged: { isInteracting in
                            viewModel.isChartInteracting = isInteracting
                        }
                    )
                    
                    // 3. Quantitative Dynamic EMA Trend & Key Levels Summary
                    if !viewModel.d1Bars.isEmpty || !viewModel.h4Bars.isEmpty || !viewModel.h1Bars.isEmpty || !viewModel.m15Bars.isEmpty {
                        PreTradeContextMetricsCard(
                            d1Bars: viewModel.d1Bars,
                            h4Bars: viewModel.h4Bars,
                            h1Bars: viewModel.h1Bars,
                            m15Bars: viewModel.m15Bars,
                            symbol: viewModel.selectedSymbol
                        )
                    }
                    
                    // 4. Loading, Error, AI Decision Document, or Action CTA Card
                    if viewModel.isAnalyzing || viewModel.isLoadingData {
                        PreTradeLoadingCard(isLoadingData: viewModel.isLoadingData)
                    } else if let error = viewModel.errorMessage {
                        PreTradeErrorCard(message: error, onRetry: {
                            Task {
                                await viewModel.fetchAllTimeframeBars(for: viewModel.selectedSymbol, forceRefresh: true, dataStore: dataStore)
                                await viewModel.runFullAnalysis(dataStore: dataStore)
                            }
                        })
                    } else if !viewModel.analysisResult.isEmpty {
                        // 5. Pre-Trade Action Bar (Save Note, Link Trade, Copy, Regenerate) - Placed RIGHT ON TOP of AI Result
                        PreTradeActionBar(
                            isSavedToNotebook: viewModel.isSavedToNotebook,
                            showCopiedAlert: viewModel.showCopiedAlert,
                            onSaveNotebook: {
                                viewModel.saveToNotebook(dataStore: dataStore)
                            },
                            onLinkTicket: {
                                viewModel.showLinkTicketSheet = true
                            },
                            onCopy: {
                                viewModel.copyToClipboard()
                            },
                            onRegenerate: {
                                viewModel.followUpMessages = []
                                Task {
                                    await viewModel.fetchAllTimeframeBars(for: viewModel.selectedSymbol, forceRefresh: true, dataStore: dataStore)
                                    await viewModel.runFullAnalysis(dataStore: dataStore)
                                }
                            }
                        )
                        
                        // 6. Structured Section Cards Reader
                        AIDocumentReaderView(text: AIDocumentParser.stripTechnicalMetadata(from: viewModel.analysisResult))
                        
                        // 6.1 Dedicated Pre-Trade Setup Card (Placed below AI analysis, only when actionable setup exists)
                        if let plan = viewModel.currentCommitment, plan.hasActionableSetup {
                            PreTradeSetupCard(
                                plan: plan,
                                timeZone: dataStore.generalSettings.displayTimeZone
                            )
                        }
                        
                        // 7. Follow-up conversation turns (message bubbles in scroll view)
                        PreTradeFollowUpSection(
                            analysisResult: viewModel.analysisResult,
                            followUpMessages: viewModel.followUpMessages
                        )
                    } else {
                        // User-triggered analysis card (no unprompted AI executions)
                        analyzeCtaCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 24)
            }
            .scrollDisabled(viewModel.isChartInteracting)
            .safeAreaInset(edge: .bottom) {
                if !viewModel.analysisResult.isEmpty && !viewModel.isAnalyzing && !viewModel.isLoadingData {
                    PreTradeBottomFloatingInput(
                        followUpQuery: $viewModel.followUpQuery,
                        isSubmitting: viewModel.isSubmittingFollowUp,
                        hasHistory: !viewModel.followUpMessages.isEmpty,
                        onResetThread: {
                            viewModel.followUpMessages = []
                            viewModel.followUpQuery = ""
                            let cacheKey = "pretrade_\(viewModel.selectedSymbol)"
                            AICoachSessionStore.shared.save(key: cacheKey, result: viewModel.analysisResult, followUps: [])
                        },
                        onSubmit: {
                            viewModel.submitFollowUp(dataStore: dataStore)
                        }
                    )
                }
            }
            .background(AppColors.background)
            .navigationTitle("Market Structure Bias")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ModalDismissButton { dismiss() }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    ModalPrimaryButton("Done") { dismiss() }
                }
            }
            .fullScreenCover(item: $viewModel.activeFullScreenModal) { modal in
                switch modal {
                case .lightbox(let img):
                    FullScreenChartLightboxView(image: img)
                case .landscapeChart:
                    MarketCandleLandscapeSheet(
                        bars: viewModel.activeBars,
                        symbol: viewModel.selectedSymbol,
                        selectedTimeframe: $viewModel.selectedTimeframe,
                        timeframeOptions: ["15m", "1h", "4h", "1d"],
                        timeframeTitle: { MarketResolution.label(for: $0) },
                        onDismiss: { viewModel.activeFullScreenModal = nil }
                    )
                }
            }
            .sheet(isPresented: $viewModel.showPhotoPicker) {
                UIKitImagePicker(isPresented: $viewModel.showPhotoPicker) { data, _ in
                    if let img = UIImage(data: data) {
                        viewModel.userAttachedImage = img
                        viewModel.activeChartSnapshot = img
                        Task { await viewModel.runFullAnalysis(dataStore: dataStore) }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showLinkTicketSheet) {
                if let noteId = viewModel.createdNoteId {
                    LinkNoteToTradeSheet(
                        noteId: noteId,
                        noteTitle: "[Pre-Trade Bias] \(viewModel.selectedSymbol)",
                        currentTradeKey: nil
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
        .task {
            viewModel.onSymbolSelected(viewModel.selectedSymbol, dataStore: dataStore)
        }
    }
    
    // MARK: - Action CTA Card
    private var analyzeCtaCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Institutional Structure Audit")
                            .font(AppTypography.cardHeader)
                            .foregroundColor(AppColors.primaryText)
                        
                        Text("Cross-references D1 macro trend, H4 swing structure, and M15 execution trigger.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    Spacer()
                }
                
                AppPrimaryButton("Analyze Market Bias", icon: "sparkles") {
                    Task { await viewModel.runFullAnalysis(dataStore: dataStore) }
                }
            }
            .padding(.vertical, 4)
        }
    }
}
