import Foundation
import FoundationModels

// MARK: - Generated shapes

/// A performance read-out the on-device model writes from pre-computed numbers.
/// The model never does the math — it only narrates and advises.
@Generable(description: "A concise marketing performance read-out written for a busy marketer.")
struct PerformanceInsight: Equatable {
    @Guide(description: "One or two sentences summarizing how spend is performing overall.")
    var summary: String

    @Guide(description: "Specific, actionable optimization recommendations.", .maximumCount(3))
    var recommendations: [String]
}

/// A single ad concept the model writes for a given platform and audience.
@Generable(description: "A short, high-converting ad concept for a paid marketing channel.")
struct AdCreative: Equatable {
    @Guide(description: "A punchy headline, at most 8 words.")
    var headline: String

    @Guide(description: "One or two sentences of primary ad text.")
    var body: String

    @Guide(description: "A short call-to-action button label, 2-4 words.")
    var callToAction: String
}

// MARK: - On-device intelligence

/// Wraps Apple's on-device foundation model for two marketing jobs:
/// summarizing performance and drafting ad copy. Runs entirely on device.
@MainActor
struct MarketingIntelligence {

    /// Whether the on-device model is usable right now.
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// A human-readable reason the model is unavailable, if any.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to use AI features."
        case .unavailable(.modelNotReady):
            return "The on-device model is still getting ready. Try again shortly."
        case .unavailable:
            return "The on-device model is currently unavailable."
        }
    }

    /// Summarize already-computed totals and per-source spend into advice.
    func summarize(totals: KPITotals, sources: [SourceSummary], range: MarketingDateRange) async throws -> PerformanceInsight {
        let session = LanguageModelSession {
            "You are a sharp performance-marketing analyst."
            "You receive already-computed metrics. Never recalculate or invent numbers."
            "Be specific and practical. Reference channels by name."
        }
        return try await session.respond(to: prompt(totals: totals, sources: sources, range: range), generating: PerformanceInsight.self).content
    }

    /// Draft ad concepts for one platform, grounded in its performance context.
    func generateAds(for source: SourceSummary, brief: String, count: Int = 3) async throws -> [AdCreative] {
        let session = LanguageModelSession {
            "You are a senior direct-response copywriter."
            "Write concise, benefit-led ad copy tailored to the platform's audience."
            "Avoid hype words, emojis, and ALL CAPS."
        }

        let brief = brief.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = """
        Write \(count) distinct ad concepts for the \(source.displayName) channel.
        Recent performance: \(Self.money(source.totals.spend)) spend, \
        \(Self.int(source.totals.conversions)) conversions, \
        \(Self.percent(source.totals.ctr)) CTR.
        \(brief.isEmpty ? "Product: a general consumer offer." : "Product / brief: \(brief)")
        """

        return try await session.respond(to: prompt, generating: [AdCreative].self).content
    }

    // MARK: Prompt construction

    private func prompt(totals: KPITotals, sources: [SourceSummary], range: MarketingDateRange) -> String {
        let breakdown = sources.prefix(6).map {
            "- \($0.displayName): \(Self.money($0.totals.spend)) spend, \(Self.int($0.totals.conversions)) conv, \(Self.percent($0.totals.ctr)) CTR"
        }.joined(separator: "\n")

        return """
        Window: \(range.label).
        Totals: \(Self.money(totals.spend)) spend, \(Self.int(totals.clicks)) clicks, \
        \(Self.int(totals.conversions)) conversions, \(Self.money(totals.cpa)) CPA, \(Self.percent(totals.ctr)) CTR.
        By channel:
        \(breakdown)

        Summarize performance and recommend up to three optimizations.
        """
    }

    // MARK: Formatting (so the model reads clean numbers, never raw doubles)

    private static func money(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = value >= 100 ? 0 : 2
        return formatter.string(from: value as NSNumber) ?? "$\(Int(value))"
    }

    private static func int(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: value as NSNumber) ?? "\(Int(value))"
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.2f%%", value * 100)
    }
}
