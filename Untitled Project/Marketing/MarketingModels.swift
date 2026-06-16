import Foundation

// MARK: - Date ranges

/// Reporting windows, mapped to Windsor.ai `date_preset` values.
enum MarketingDateRange: String, CaseIterable, Identifiable {
    case last7 = "last_7d"
    case last14 = "last_14d"
    case last30 = "last_30d"
    case thisMonth = "this_month"
    case lastMonth = "last_month"

    var id: String { rawValue }

    /// A short, human-readable label for pickers.
    var label: String {
        switch self {
        case .last7: return "Last 7 days"
        case .last14: return "Last 14 days"
        case .last30: return "Last 30 days"
        case .thisMonth: return "This month"
        case .lastMonth: return "Last month"
        }
    }
}

// MARK: - Raw metric row

/// A single row of marketing data returned by Windsor.ai's unified connector.
///
/// Windsor returns numeric fields inconsistently — sometimes as JSON numbers,
/// sometimes as strings — so each metric is decoded flexibly and defaults to `0`.
struct MetricRow: Identifiable, Equatable, Decodable {
    let id = UUID()

    /// The marketing platform this row came from (e.g. "facebook", "google_ads").
    var source: String
    var campaign: String
    var clicks: Double
    var impressions: Double
    var spend: Double
    var conversions: Double

    private enum CodingKeys: String, CodingKey {
        case source, campaign, clicks, impressions, spend, conversions
    }

    init(
        source: String,
        campaign: String,
        clicks: Double,
        impressions: Double,
        spend: Double,
        conversions: Double
    ) {
        self.source = source
        self.campaign = campaign
        self.clicks = clicks
        self.impressions = impressions
        self.spend = spend
        self.conversions = conversions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = (try? c.decode(String.self, forKey: .source)) ?? "unknown"
        campaign = (try? c.decode(String.self, forKey: .campaign)) ?? "—"
        clicks = MetricRow.flexible(c, .clicks)
        impressions = MetricRow.flexible(c, .impressions)
        spend = MetricRow.flexible(c, .spend)
        conversions = MetricRow.flexible(c, .conversions)
    }

    /// Decode a value that may arrive as a number or a numeric string.
    private static func flexible(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double {
        if let value = try? c.decode(Double.self, forKey: key) { return value }
        if let string = try? c.decode(String.self, forKey: key), let value = Double(string) { return value }
        return 0
    }
}

// MARK: - Aggregates (computed in Swift, never by the model)

/// Roll-up totals across every row, plus derived performance ratios.
struct KPITotals: Equatable {
    var clicks: Double = 0
    var impressions: Double = 0
    var spend: Double = 0
    var conversions: Double = 0

    /// Click-through rate (clicks ÷ impressions).
    var ctr: Double { impressions > 0 ? clicks / impressions : 0 }
    /// Cost per click.
    var cpc: Double { clicks > 0 ? spend / clicks : 0 }
    /// Cost per acquisition.
    var cpa: Double { conversions > 0 ? spend / conversions : 0 }

    static func total(of rows: [MetricRow]) -> KPITotals {
        rows.reduce(into: KPITotals()) { totals, row in
            totals.clicks += row.clicks
            totals.impressions += row.impressions
            totals.spend += row.spend
            totals.conversions += row.conversions
        }
    }
}

/// Per-platform roll-up, sorted by spend so the biggest channels surface first.
struct SourceSummary: Identifiable, Equatable {
    var id: String { source }
    var source: String
    var totals: KPITotals

    /// A nicely cased display name ("google_ads" -> "Google Ads").
    var displayName: String {
        source
            .split(whereSeparator: { $0 == "_" || $0 == "-" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    static func summaries(from rows: [MetricRow]) -> [SourceSummary] {
        Dictionary(grouping: rows, by: \.source)
            .map { SourceSummary(source: $0.key, totals: KPITotals.total(of: $0.value)) }
            .sorted { $0.totals.spend > $1.totals.spend }
    }
}

// MARK: - Sample data (previews / no-key state)

extension MetricRow {
    static let sample: [MetricRow] = [
        MetricRow(source: "google_ads", campaign: "Search — Brand", clicks: 4210, impressions: 98120, spend: 1820.40, conversions: 312),
        MetricRow(source: "google_ads", campaign: "Performance Max", clicks: 2890, impressions: 142300, spend: 2410.10, conversions: 198),
        MetricRow(source: "facebook", campaign: "Retargeting — 30d", clicks: 5320, impressions: 210400, spend: 1640.00, conversions: 405),
        MetricRow(source: "facebook", campaign: "Prospecting — Lookalike", clicks: 1980, impressions: 188900, spend: 1290.75, conversions: 121),
        MetricRow(source: "tiktok", campaign: "Spark Ads — Launch", clicks: 7640, impressions: 512000, spend: 980.50, conversions: 233),
        MetricRow(source: "linkedin", campaign: "ABM — Enterprise", clicks: 640, impressions: 41200, spend: 2210.00, conversions: 54)
    ]
}
