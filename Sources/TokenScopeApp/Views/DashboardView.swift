import SwiftUI
import Charts
import TokenScopeCore

struct DashboardView: View {
    @EnvironmentObject var store: AppStore
    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: Date()))!
    @State private var endDate: Date = Date()
    @State private var selectedModels: Set<String> = []
    @State private var selectedProviders: Set<Provider> = []
    @State private var includeInput = true
    @State private var includeOutput = true
    @State private var includeCacheRead = true
    @State private var includeCacheCreate = true

    @State private var buckets: [DailyBucket] = []
    @State private var monthlyBuckets: [MonthlyBucket] = []
    @State private var totals: (usage: TokenUsage, costUSD: Double) = (.zero, 0)
    @State private var availableModels: [String] = []
    @State private var modelPalette: [String: Color] = [:]
    @State private var sourceTotals: [Provider: (usage: TokenUsage, cost: Double)] = [:]
    @State private var expandedMonths: Set<Date> = []

    @State private var hoveredDay: Date?

    private var filter: AggregationFilter {
        let cal = Calendar.current
        let lower = cal.startOfDay(for: min(startDate, endDate))
        let upperDay = cal.startOfDay(for: max(startDate, endDate))
        let upper = cal.date(byAdding: .day, value: 1, to: upperDay) ?? upperDay
        return AggregationFilter(
            dateRange: lower...upper,
            providers: selectedProviders.isEmpty ? nil : selectedProviders,
            models: selectedModels.isEmpty ? nil : selectedModels
        )
    }

    private var sourceFilter: AggregationFilter {
        let cal = Calendar.current
        let lower = cal.startOfDay(for: min(startDate, endDate))
        let upperDay = cal.startOfDay(for: max(startDate, endDate))
        let upper = cal.date(byAdding: .day, value: 1, to: upperDay) ?? upperDay
        return AggregationFilter(
            dateRange: lower...upper,
            models: selectedModels.isEmpty ? nil : selectedModels
        )
    }

    private var filterKey: String {
        let providers = selectedProviders.map(\.rawValue).sorted().joined(separator: ",")
        return "\(startDate.timeIntervalSince1970)|\(endDate.timeIntervalSince1970)|\(selectedModels.sorted().joined(separator: ","))|\(providers)|\(store.usageRecords.count)"
    }

    private func displayedTokens(for usage: TokenUsage) -> Int {
        var v = 0
        if includeInput { v += usage.inputTokens }
        if includeOutput { v += usage.outputTokens }
        if includeCacheRead { v += usage.cacheReadTokens }
        if includeCacheCreate { v += usage.cacheCreationTokens }
        return v
    }

    private func recompute() {
        let f = filter
        let newBuckets = store.aggregator.dailyBuckets(records: store.usageRecords, filter: f)
        let newMonthlyBuckets = store.aggregator.monthlyBuckets(records: store.usageRecords, filter: f)
        let newTotals = store.aggregator.totals(records: store.usageRecords, filter: f)
        let models = Array(Set(store.usageRecords.map(\.model))).sorted()
        var palette: [String: Color] = [:]
        let baseColors: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .yellow, .indigo, .red, .mint, .cyan, .brown]
        for (i, m) in models.enumerated() {
            palette[m] = baseColors[i % baseColors.count]
        }
        let sourceBuckets = store.aggregator.dailyBuckets(records: store.usageRecords, filter: sourceFilter)
        var byProvider: [Provider: (usage: TokenUsage, cost: Double)] = [:]
        for b in sourceBuckets {
            let existing = byProvider[b.provider] ?? (.zero, 0)
            byProvider[b.provider] = (existing.usage + b.usage, existing.cost + b.costUSD)
        }
        self.buckets = newBuckets
        self.monthlyBuckets = newMonthlyBuckets
        self.totals = newTotals
        self.availableModels = models
        self.modelPalette = palette
        self.sourceTotals = byProvider
        self.expandedMonths = expandedMonths.intersection(Set(newMonthlyBuckets.map(\.monthStart)))
    }

    private var hoveredBuckets: [DailyBucket] {
        guard let day = hoveredDay else { return [] }
        let cal = Calendar.current
        return buckets.filter { cal.isDate($0.day, inSameDayAs: day) }
    }

    private func toggleProvider(_ p: Provider) {
        if selectedProviders.contains(p) {
            selectedProviders.remove(p)
        } else {
            selectedProviders.insert(p)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerStats
                sourceBreakdownView
                filters
                chart
                monthlyUsageSection
            }
            .padding(24)
        }
        .navigationTitle("Dashboard")
        .onAppear { recompute() }
        .onChange(of: filterKey) { _, _ in recompute() }
        .onChange(of: includeInput) { _, _ in }
        .onChange(of: includeOutput) { _, _ in }
        .onChange(of: includeCacheRead) { _, _ in }
        .onChange(of: includeCacheCreate) { _, _ in }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await store.loadAll() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.isLoading)
            }
        }
    }

    private var headerStats: some View {
        HStack(spacing: 16) {
            StatCard(title: "Sessions", value: "\(store.sessions.count)")
            StatCard(title: "Total Tokens", value: formatMillions(totals.usage.totalTokens))
            StatCard(title: "Input", value: formatMillions(totals.usage.inputTokens))
            StatCard(title: "Output", value: formatMillions(totals.usage.outputTokens))
            StatCard(title: "Cache R", value: formatMillions(totals.usage.cacheReadTokens))
            StatCard(title: "Cost (est.)", value: String(format: "$%.2f", totals.costUSD))
        }
    }

    private var sourceBreakdownView: some View {
        let sources: [Provider] = [.claudeCode, .codex, .openCode]
        return HStack(spacing: 12) {
            ForEach(sources, id: \.self) { p in
                let entry = sourceTotals[p]
                SourceCard(
                    title: p.displayName,
                    tokens: displayedTokens(for: entry?.usage ?? .zero),
                    cost: entry?.cost ?? 0,
                    color: sourceColor(p),
                    isSelected: selectedProviders.isEmpty || selectedProviders.contains(p),
                    hasFilter: !selectedProviders.isEmpty,
                    action: { toggleProvider(p) }
                )
            }
            if !selectedProviders.isEmpty {
                Button("Clear") { selectedProviders.removeAll() }
                    .buttonStyle(.link)
            }
            Spacer()
        }
    }

    private func sourceColor(_ p: Provider) -> Color {
        switch p {
        case .claudeCode: return .orange
        case .codex: return .green
        case .openCode: return .purple
        default: return .secondary
        }
    }

    private func applyPreset(_ preset: DatePreset) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let range: (Date, Date)
        switch preset {
        case .all:
            let earliest = store.usageRecords.map(\.timestamp).min().map { cal.startOfDay(for: $0) } ?? today
            range = (earliest, today)
        case .today:
            range = (today, today)
        case .yesterday:
            let y = cal.date(byAdding: .day, value: -1, to: today) ?? today
            range = (y, y)
        case .thisWeek:
            let interval = cal.dateInterval(of: .weekOfYear, for: today)
            let start = interval.map { cal.startOfDay(for: $0.start) } ?? today
            range = (start, today)
        case .last7Days:
            let start = cal.date(byAdding: .day, value: -6, to: today) ?? today
            range = (start, today)
        case .thisMonth:
            let interval = cal.dateInterval(of: .month, for: today)
            let start = interval.map { cal.startOfDay(for: $0.start) } ?? today
            range = (start, today)
        case .lastMonth:
            guard let lastMonthDay = cal.date(byAdding: .month, value: -1, to: today),
                  let interval = cal.dateInterval(of: .month, for: lastMonthDay) else {
                range = (today, today); break
            }
            let start = cal.startOfDay(for: interval.start)
            let end = cal.date(byAdding: .day, value: -1, to: interval.end).map { cal.startOfDay(for: $0) } ?? start
            range = (start, end)
        case .last30Days:
            let start = cal.date(byAdding: .day, value: -29, to: today) ?? today
            range = (start, today)
        case .thisYear:
            let interval = cal.dateInterval(of: .year, for: today)
            let start = interval.map { cal.startOfDay(for: $0.start) } ?? today
            range = (start, today)
        case .lastYear:
            guard let lastYearDay = cal.date(byAdding: .year, value: -1, to: today),
                  let interval = cal.dateInterval(of: .year, for: lastYearDay) else {
                range = (today, today); break
            }
            let start = cal.startOfDay(for: interval.start)
            let end = cal.date(byAdding: .day, value: -1, to: interval.end).map { cal.startOfDay(for: $0) } ?? start
            range = (start, end)
        }
        if range.1 >= startDate {
            endDate = range.1
            startDate = range.0
        } else {
            startDate = range.0
            endDate = range.1
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                DatePicker("From", selection: $startDate, in: ...endDate, displayedComponents: .date)
                DatePicker("To", selection: $endDate, in: startDate..., displayedComponents: .date)
                Menu {
                    ForEach(DatePreset.allCases, id: \.self) { p in
                        Button(p.label) { applyPreset(p) }
                    }
                } label: {
                    Label("Quick", systemImage: "calendar")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
            }
            HStack(spacing: 16) {
                Toggle("Input", isOn: $includeInput)
                Toggle("Output", isOn: $includeOutput)
                Toggle("Cache Read", isOn: $includeCacheRead)
                Toggle("Cache Create", isOn: $includeCacheCreate)
            }
            .toggleStyle(.checkbox)
            if !availableModels.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHGrid(
                            rows: [GridItem(.fixed(28), spacing: 6), GridItem(.fixed(28), spacing: 6)],
                            alignment: .center,
                            spacing: 6
                        ) {
                            ForEach(availableModels, id: \.self) { m in
                                ModelChip(
                                    title: m,
                                    color: modelPalette[m] ?? .accentColor,
                                    isOn: selectedModels.isEmpty || selectedModels.contains(m)
                                ) {
                                    if selectedModels.contains(m) {
                                        selectedModels.remove(m)
                                    } else {
                                        selectedModels.insert(m)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(height: 64)

                    if !selectedModels.isEmpty {
                        Button("Clear") { selectedModels.removeAll() }
                            .buttonStyle(.link)
                            .padding(.top, 4)
                    }
                }
            }
        }
    }

    private var chart: some View {
        ChartContent(
            buckets: buckets,
            palette: modelPalette,
            hoveredDay: $hoveredDay,
            hoveredBuckets: hoveredBuckets,
            displayedTokens: displayedTokens
        )
        .frame(minHeight: 320)
    }

    private var monthlyUsageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monthly Usage")
                .font(.title2).bold()

            if monthlyBuckets.isEmpty {
                Text("No usage in selected range")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(monthlyBuckets) { month in
                        MonthlyBucketCard(
                            bucket: month,
                            isExpanded: expandedMonths.contains(month.monthStart),
                            displayedTokens: displayedTokens,
                            toggle: {
                                if expandedMonths.contains(month.monthStart) {
                                    expandedMonths.remove(month.monthStart)
                                } else {
                                    expandedMonths.insert(month.monthStart)
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}

private struct ChartContent: View {
    let buckets: [DailyBucket]
    let palette: [String: Color]
    @Binding var hoveredDay: Date?
    let hoveredBuckets: [DailyBucket]
    let displayedTokens: (TokenUsage) -> Int

    private var sortedModels: [String] {
        Array(Set(buckets.map(\.model))).sorted()
    }

    var body: some View {
        Chart {
            ForEach(buckets) { b in
                BarMark(
                    x: .value("Day", b.day, unit: .day),
                    y: .value("Tokens", displayedTokens(b.usage))
                )
                .foregroundStyle(by: .value("Model", b.model))
            }
            if let hoveredDay {
                RuleMark(x: .value("Day", hoveredDay, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartForegroundStyleScale(domain: sortedModels, range: sortedModels.map { palette[$0] ?? .accentColor })
        .animation(nil, value: hoveredDay)
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let n = value.as(Int.self) {
                        Text(formatMillions(n)).monospacedDigit()
                    }
                }
            }
        }
        .chartXSelection(value: $hoveredDay)
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let hoveredDay,
                   !hoveredBuckets.isEmpty,
                   let plotFrameAnchor = proxy.plotFrame {
                    let plot = geo[plotFrameAnchor]
                    if let xPos = proxy.position(forX: hoveredDay) {
                        TooltipView(
                            day: hoveredDay,
                            buckets: hoveredBuckets,
                            palette: palette,
                            formatTokens: displayedTokens
                        )
                        .fixedSize()
                        .position(
                            x: min(max(plot.minX + xPos + 8, plot.minX + 130), plot.maxX - 130),
                            y: plot.minY + 80
                        )
                        .allowsHitTesting(false)
                    }
                }
            }
        }
    }
}

private enum DatePreset: CaseIterable {
    case all, today, yesterday, thisWeek, last7Days, thisMonth, lastMonth, last30Days, thisYear, lastYear

    var label: String {
        switch self {
        case .all: return "All"
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This Week"
        case .last7Days: return "Last 7 Days"
        case .thisMonth: return "This Month"
        case .lastMonth: return "Last Month"
        case .last30Days: return "Last 30 Days"
        case .thisYear: return "This Year"
        case .lastYear: return "Last Year"
        }
    }
}

private func formatMillions(_ n: Int) -> String {
    if n == 0 { return "0" }
    let v = Double(n) / 1_000_000
    if abs(v) >= 100 { return String(format: "%.0fM", v) }
    if abs(v) >= 10 { return String(format: "%.1fM", v) }
    return String(format: "%.2fM", v)
}

private struct TooltipView: View {
    let day: Date
    let buckets: [DailyBucket]
    let palette: [String: Color]
    let formatTokens: (TokenUsage) -> Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(day.formatted(date: .abbreviated, time: .omitted))
                .font(.caption).bold()
            Divider()
            ForEach(buckets) { b in
                HStack(spacing: 10) {
                    Circle().fill(palette[b.model] ?? .accentColor).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(b.model).font(.caption)
                        Text("\(formatMillions(formatTokens(b.usage))) tok · $\(String(format: "%.4f", b.costUSD))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.2)))
        .shadow(radius: 6)
    }
}

private struct MonthlyBucketCard: View {
    let bucket: MonthlyBucket
    let isExpanded: Bool
    let displayedTokens: (TokenUsage) -> Int
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(alignment: .center, spacing: 16) {
                    Text(bucket.monthStart.formatted(.dateTime.year().month(.wide)))
                        .font(.headline)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatMillions(displayedTokens(bucket.usage)))
                            .font(.body).monospacedDigit()
                        Text("$\(String(format: "%.2f", bucket.costUSD)) · \(bucket.messageCount) msgs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 14)
                VStack(spacing: 0) {
                    ForEach(bucket.days) { day in
                        MonthlyDayRow(bucket: day, displayedTokens: displayedTokens)
                        if day.id != bucket.days.last?.id {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.15)))
    }
}

private struct MonthlyDayRow: View {
    let bucket: MonthlyDayBucket
    let displayedTokens: (TokenUsage) -> Int

    var body: some View {
        HStack(spacing: 16) {
            Text(bucket.day.formatted(.dateTime.month(.abbreviated).day()))
                .font(.subheadline)
                .frame(width: 80, alignment: .leading)
            Spacer()
            Text(formatMillions(displayedTokens(bucket.usage)))
                .font(.subheadline)
                .monospacedDigit()
                .frame(width: 90, alignment: .trailing)
            Text(String(format: "$%.2f", bucket.costUSD))
                .font(.subheadline)
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)
            Text("\(bucket.messageCount)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3).monospacedDigit()
        }
        .padding(12)
        .frame(minWidth: 120, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ModelChip: View {
    let title: String
    let color: Color
    let isOn: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 140, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isOn ? color.opacity(0.18) : Color.secondary.opacity(0.08))
            .clipShape(Capsule())
            .opacity(isOn ? 1.0 : 0.55)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isHovering, arrowEdge: .bottom) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct SourceCard: View {
    let title: String
    let tokens: Int
    let cost: Double
    let color: Color
    let isSelected: Bool
    let hasFilter: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle().fill(color).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text(formatMillions(tokens)).font(.callout).monospacedDigit()
                        Text(String(format: "$%.2f", cost))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 150, alignment: .leading)
            .background(color.opacity(isSelected ? 0.15 : 0.05), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color.opacity(isSelected ? 0.45 : 0.15), lineWidth: isSelected && hasFilter ? 1.5 : 1)
            )
            .opacity(isSelected ? 1.0 : 0.55)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
