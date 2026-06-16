import SwiftUI

/// The marketing aggregator dashboard: one view over every connected platform,
/// with on-device AI for performance summaries and ad copy.
struct MarketingDashboardView: View {
    @State private var model = MarketingDashboardModel()
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    rangePicker

                    if let error = model.loadError {
                        banner(error, system: "exclamationmark.triangle.fill", tint: .yellow)
                    }

                    if model.rows.isEmpty {
                        emptyState
                    } else {
                        kpiGrid
                        intelligenceSection
                        channelsSection
                    }
                }
                .padding()
            }
            .background(BLBTheme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Marketing")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "key.fill").foregroundStyle(BLBTheme.gold)
                    }
                }
                ToolbarItem(placement: .automatic) {
                    if model.isLoading { ProgressView().tint(BLBTheme.gold) }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsSheet(model: model)
            }
        }
        .tint(BLBTheme.gold)
        .preferredColorScheme(.dark)
        .task {
            model.loadStoredKey()
            if model.hasKey { await model.refresh() } else { model.loadSampleData() }
        }
    }

    // MARK: Sections

    private var rangePicker: some View {
        Picker("Range", selection: $model.range) {
            ForEach(MarketingDateRange.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .onChange(of: model.range) { _, _ in
            Task { if model.hasKey { await model.refresh() } }
        }
    }

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            KPICard(title: "Spend", value: Format.money(model.totals.spend), system: "dollarsign.circle.fill")
            KPICard(title: "Conversions", value: Format.int(model.totals.conversions), system: "checkmark.seal.fill")
            KPICard(title: "Clicks", value: Format.int(model.totals.clicks), system: "cursorarrow.click")
            KPICard(title: "CTR", value: Format.percent(model.totals.ctr), system: "chart.line.uptrend.xyaxis")
            KPICard(title: "CPC", value: Format.money(model.totals.cpc), system: "arrow.down.right.circle")
            KPICard(title: "CPA", value: Format.money(model.totals.cpa), system: "target")
        }
    }

    @ViewBuilder
    private var intelligenceSection: some View {
        SectionCard(title: "AI Performance Insight", system: "sparkles") {
            if let reason = model.modelUnavailableReason {
                Text(reason).font(.footnote).foregroundStyle(.secondary)
            } else if let insight = model.insight {
                VStack(alignment: .leading, spacing: 10) {
                    Text(insight.summary).font(.callout)
                    ForEach(insight.recommendations, id: \.self) { rec in
                        Label(rec, systemImage: "arrow.right.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Summarize this window's performance on-device.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            if model.isModelAvailable {
                Button {
                    Task { await model.generateInsight() }
                } label: {
                    HStack {
                        if model.isSummarizing { ProgressView().tint(.black) }
                        Text(model.insight == nil ? "Generate insight" : "Regenerate")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(BLBTheme.gold, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.black)
                }
                .disabled(model.isSummarizing)
            }
        }
    }

    private var channelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CHANNELS")
                .font(.caption.weight(.bold)).tracking(2)
                .foregroundStyle(BLBTheme.gold.opacity(0.8))
            ForEach(model.sources) { source in
                ChannelRow(source: source, model: model)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis").font(.largeTitle).foregroundStyle(BLBTheme.gold)
            Text("No data yet").font(.headline)
            Text("Add a Windsor.ai API key to pull every connected channel, or explore with sample data.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Load sample data") { model.loadSampleData() }
                .buttonStyle(.bordered).tint(BLBTheme.gold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func banner(_ text: String, system: String, tint: Color) -> some View {
        Label(text, systemImage: system)
            .font(.footnote)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(BLBTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Channel row (with ad generation)

private struct ChannelRow: View {
    let source: SourceSummary
    @Bindable var model: MarketingDashboardModel
    @State private var brief = ""
    @State private var expanded = false

    var body: some View {
        SectionCard(title: source.displayName, system: "antenna.radiowaves.left.and.right") {
            HStack {
                stat("Spend", Format.money(source.totals.spend))
                Spacer()
                stat("Conv", Format.int(source.totals.conversions))
                Spacer()
                stat("CTR", Format.percent(source.totals.ctr))
            }

            DisclosureGroup("Make ads", isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Optional brief (product, offer, audience)", text: $brief, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(BLBTheme.background, in: RoundedRectangle(cornerRadius: 10))

                    if model.isModelAvailable {
                        Button {
                            Task { await model.generateAds(for: source, brief: brief) }
                        } label: {
                            HStack {
                                if model.generatingAdsSource == source.source { ProgressView().tint(.black) }
                                Text("Generate ad concepts")
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(BLBTheme.gold, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.black)
                        }
                        .disabled(model.generatingAdsSource != nil)
                    } else if let reason = model.modelUnavailableReason {
                        Text(reason).font(.footnote).foregroundStyle(.secondary)
                    }

                    ForEach(Array((model.ads[source.source] ?? []).enumerated()), id: \.offset) { _, ad in
                        AdCard(ad: ad)
                    }
                }
                .padding(.top, 6)
            }
            .tint(BLBTheme.gold)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
        }
    }
}

// MARK: - Reusable pieces

private struct KPICard: View {
    let title: String
    let value: String
    let system: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: system)
                .font(.caption).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
            Text(value).font(.title3.weight(.bold)).foregroundStyle(BLBTheme.goldBright)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(BLBTheme.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    let system: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: system)
                .font(.headline).foregroundStyle(BLBTheme.goldBright)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(BLBTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct AdCard: View {
    let ad: AdCreative

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ad.headline).font(.subheadline.weight(.bold)).foregroundStyle(.white)
            Text(ad.body).font(.footnote).foregroundStyle(.secondary)
            Text(ad.callToAction.uppercased())
                .font(.caption2.weight(.heavy)).tracking(1)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(BLBTheme.gold, in: Capsule())
                .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(BLBTheme.background, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SettingsSheet: View {
    @Bindable var model: MarketingDashboardModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Windsor.ai API key", text: $model.apiKey)
                } header: {
                    Text("Data source")
                } footer: {
                    Text("One key unlocks every channel you've connected in Windsor.ai. Stored securely in the Keychain.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.saveKey()
                        dismiss()
                        Task { await model.refresh() }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Formatting

private enum Format {
    static func money(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = value >= 100 ? 0 : 2
        return f.string(from: value as NSNumber) ?? "$\(Int(value))"
    }

    static func int(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: value as NSNumber) ?? "\(Int(value))"
    }

    static func percent(_ value: Double) -> String { String(format: "%.2f%%", value * 100) }
}

#Preview {
    MarketingDashboardView()
}
