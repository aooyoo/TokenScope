import SwiftUI
import TokenScopeCore

private struct SessionRow: Identifiable, Hashable {
    let id: String
    let sessionID: String
    let providerRaw: String
    let startedAt: Date
    let provider: String
    let projectName: String
    let models: String
    let messageCount: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cost: Double
}

struct SessionsView: View {
    @EnvironmentObject var store: AppStore
    @State private var rows: [SessionRow] = []
    @State private var sortOrder: [KeyPathComparator<SessionRow>] = [
        KeyPathComparator(\.startedAt, order: .reverse)
    ]
    @State private var selectedID: String?
    @State private var detail: SessionDetail?
    @State private var isLoadingDetail = false
    @State private var searchText = ""
    @AppStorage("sessions.hideZeroMessage") private var hideZeroMessage = false

    private var filteredRows: [SessionRow] {
        var result = rows
        if hideZeroMessage {
            result = result.filter { $0.messageCount > 0 }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            result = result.filter { $0.projectName.localizedCaseInsensitiveContains(q) }
        }
        return result
    }

    private var sortedRows: [SessionRow] {
        filteredRows.sorted(using: sortOrder)
    }

    var body: some View {
        Table(sortedRows, selection: $selectedID, sortOrder: $sortOrder) {
            TableColumn("Started", value: \.startedAt) { r in
                Text(r.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .monospacedDigit()
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { openDetail(for: r) }
            }
            TableColumn("Provider", value: \.provider) { r in
                Text(r.provider)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { openDetail(for: r) }
            }
            TableColumn("Project", value: \.projectName) { r in
                Text(r.projectName)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { openDetail(for: r) }
            }
            TableColumn("Models", value: \.models) { r in
                Text(r.models)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { openDetail(for: r) }
            }
            TableColumn("Msgs", value: \.messageCount) { r in
                Text("\(r.messageCount)")
                    .monospacedDigit()
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { openDetail(for: r) }
            }
            TableColumn("In", value: \.inputTokens) { r in
                Text(formatMillions(r.inputTokens))
                    .monospacedDigit()
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { openDetail(for: r) }
            }
            TableColumn("Out", value: \.outputTokens) { r in
                Text(formatMillions(r.outputTokens))
                    .monospacedDigit()
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { openDetail(for: r) }
            }
            TableColumn("Cache R", value: \.cacheReadTokens) { r in
                Text(formatMillions(r.cacheReadTokens))
                    .monospacedDigit()
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { openDetail(for: r) }
            }
            TableColumn("Cost", value: \.cost) { r in
                Text(String(format: "$%.4f", r.cost))
                    .monospacedDigit()
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { openDetail(for: r) }
            }
        }
        .overlay {
            if isLoadingDetail {
                ProgressView("Loading session…")
                    .padding(20)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .sheet(item: $detail) { detail in
            SessionDetailView(detail: detail)
                .environmentObject(store)
        }
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Toggle("Hide sessions with 0 messages", isOn: $hideZeroMessage)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    TextField("Search project", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
            }
        }
        .onAppear { rebuild() }
        .onChange(of: store.sessions) { _, _ in rebuild() }
    }

    private func rebuild() {
        var seen = Set<String>()
        var out: [SessionRow] = []
        for s in store.sessions {
            let uid = "\(s.provider.rawValue):\(s.id)"
            if seen.contains(uid) { continue }
            seen.insert(uid)
            let model = s.modelsUsed.first ?? ""
            let projectName: String = {
                if s.id.hasPrefix("subagent:"), let last = s.projectPath?.components(separatedBy: "/").last {
                    return "\(last) · subagent"
                }
                return s.projectPath?.components(separatedBy: "/").last ?? "—"
            }()
            out.append(SessionRow(
                id: uid,
                sessionID: s.id,
                providerRaw: s.provider.rawValue,
                startedAt: s.startedAt,
                provider: s.provider.displayName,
                projectName: projectName,
                models: s.modelsUsed.joined(separator: ", "),
                messageCount: s.messageCount,
                inputTokens: s.totalUsage.inputTokens,
                outputTokens: s.totalUsage.outputTokens,
                cacheReadTokens: s.totalUsage.cacheReadTokens,
                cost: store.priceBook.cost(for: s.totalUsage, model: model)
            ))
        }
        rows = out
    }

    private func openDetail(for row: SessionRow) {
        selectedID = row.id
        guard let session = store.sessions.first(where: { $0.id == row.sessionID && $0.provider.rawValue == row.providerRaw }) else {
            return
        }
        isLoadingDetail = true
        Task {
            let loaded = await store.loadDetail(for: session)
            await MainActor.run {
                detail = loaded
                isLoadingDetail = false
            }
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
