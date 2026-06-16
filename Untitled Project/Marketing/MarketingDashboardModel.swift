import Foundation
import Observation

/// Drives the marketing dashboard: pulls unified data from Windsor.ai, computes
/// aggregates locally, and asks the on-device model for narrative + ad copy.
@MainActor
@Observable
final class MarketingDashboardModel {

    // MARK: Account

    /// Keychain account name for the Windsor.ai key (reuses `KeychainStore`).
    private static let keyAccount = "windsor_api_key"

    /// Bound to the Settings field; persisted to the Keychain on save.
    var apiKey: String = ""

    var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: Data

    var range: MarketingDateRange = .last7
    private(set) var rows: [MetricRow] = []
    private(set) var totals = KPITotals()
    private(set) var sources: [SourceSummary] = []

    var isLoading = false
    var loadError: String?

    // MARK: Intelligence

    private(set) var insight: PerformanceInsight?
    var isSummarizing = false

    /// Ad concepts keyed by the source they were written for.
    private(set) var ads: [String: [AdCreative]] = [:]
    var generatingAdsSource: String?
    var aiError: String?

    var isModelAvailable: Bool { MarketingIntelligence.isAvailable }
    var modelUnavailableReason: String? { MarketingIntelligence.unavailableReason }

    private let client = WindsorClient()
    private let intelligence = MarketingIntelligence()

    // MARK: Lifecycle

    func loadStoredKey() {
        apiKey = KeychainStore.get(Self.keyAccount) ?? ""
    }

    func saveKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(Self.keyAccount)
        } else {
            KeychainStore.set(trimmed, for: Self.keyAccount)
        }
    }

    /// Load realistic sample rows so the UI is explorable before a key is added.
    func loadSampleData() {
        apply(rows: MetricRow.sample)
        loadError = nil
    }

    // MARK: Fetch

    func refresh() async {
        guard hasKey else {
            loadError = WindsorClient.WindsorError.missingKey.errorDescription
            return
        }

        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let fetched = try await client.fetch(apiKey: apiKey, range: range)
            apply(rows: fetched)
            // New data invalidates prior AI output.
            insight = nil
            ads.removeAll()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func apply(rows: [MetricRow]) {
        self.rows = rows
        totals = KPITotals.total(of: rows)
        sources = SourceSummary.summaries(from: rows)
    }

    // MARK: AI actions

    func generateInsight() async {
        guard isModelAvailable, !rows.isEmpty else { return }
        isSummarizing = true
        aiError = nil
        defer { isSummarizing = false }

        do {
            insight = try await intelligence.summarize(totals: totals, sources: sources, range: range)
        } catch {
            aiError = "Couldn't generate the summary. (\(error.localizedDescription))"
        }
    }

    func generateAds(for source: SourceSummary, brief: String) async {
        guard isModelAvailable else { return }
        generatingAdsSource = source.source
        aiError = nil
        defer { generatingAdsSource = nil }

        do {
            ads[source.source] = try await intelligence.generateAds(for: source, brief: brief)
        } catch {
            aiError = "Couldn't generate ads for \(source.displayName). (\(error.localizedDescription))"
        }
    }
}
