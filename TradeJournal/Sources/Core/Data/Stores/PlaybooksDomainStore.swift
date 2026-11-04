import Foundation
import Combine

/// Dedicated domain store managing trading playbooks, rules, assessments, and discipline tracking.
/// Part of Item 1: TradeDataStore God Object decomposition into domain stores.
@MainActor
public final class PlaybooksDomainStore: ObservableObject {
    @Published public var playbooks: [Playbook] = []
    @Published public var playbookAssessments: [PlaybookRuleAssessment] = []
    @Published public var progressRules: [ProgressRule] = []
    @Published public var progressChecks: [ProgressCheck] = []

    public init(
        playbooks: [Playbook] = [],
        playbookAssessments: [PlaybookRuleAssessment] = [],
        progressRules: [ProgressRule] = [],
        progressChecks: [ProgressCheck] = []
    ) {
        self.playbooks = playbooks
        self.playbookAssessments = playbookAssessments
        self.progressRules = progressRules
        self.progressChecks = progressChecks
    }
}
