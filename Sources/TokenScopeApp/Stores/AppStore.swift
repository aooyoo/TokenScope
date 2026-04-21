import Foundation
import SwiftUI
import TokenScopeCore

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var sessions: [SessionRecord] = []
    @Published private(set) var usageRecords: [UsageRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var cacheUpdatedAt: Date?

    let priceBook = PriceBook()
    let usageCache = UsageCache()
    let detailLoader = SessionDetailLoader()
    lazy var aggregator = UsageAggregator(priceBook: priceBook)

    @Published var pricesRevision: Int = 0

    func upsertPrice(_ price: ModelPrice) {
        priceBook.upsert(price)
        pricesRevision &+= 1
    }

    func removePrice(model: String) {
        priceBook.remove(modelName: model)
        pricesRevision &+= 1
    }

    func loadCached() {
        guard let snapshot = usageCache.load() else { return }
        self.sessions = snapshot.sessions.sorted { $0.startedAt > $1.startedAt }
        self.usageRecords = snapshot.records
        self.cacheUpdatedAt = snapshot.updatedAt
    }

    func loadAll() async {
        isLoading = true
        defer { isLoading = false }

        let cached = usageCache.load()
        let scanned = await Task.detached(priority: .userInitiated) {
            let claude = ClaudeCodeScanner().scan()
            let codex = CodexScanner().scan()
            let opencode = OpenCodeScanner().scan()
            let sessions: [SessionRecord] = claude.map(\.session) + codex.map(\.session) + opencode.map(\.session)
            var records: [UsageRecord] = []
            records.append(contentsOf: claude.flatMap(\.usageRecords))
            records.append(contentsOf: codex.flatMap(\.usageRecords))
            records.append(contentsOf: opencode.flatMap(\.usageRecords))
            return (sessions, records)
        }.value

        let merged = UsageCache.merge(
            cached: cached,
            scannedSessions: scanned.0,
            scannedRecords: scanned.1
        )
        self.sessions = merged.sessions
        self.usageRecords = merged.records

        let sessionsCopy = merged.sessions
        let recordsCopy = merged.records
        let cache = usageCache
        Task.detached(priority: .background) {
            cache.save(sessions: sessionsCopy, records: recordsCopy)
        }
        self.cacheUpdatedAt = Date()
    }

    func loadDetail(for session: SessionRecord) async -> SessionDetail {
        let records = usageRecords
        let loader = detailLoader
        return await Task.detached(priority: .userInitiated) {
            (try? loader.loadDetail(for: session, usageRecords: records))
                ?? SessionDetail(
                    session: session,
                    mode: .usageOnly,
                    usageRecords: records.filter { $0.provider == session.provider && $0.sessionId == session.id }.sorted { $0.timestamp < $1.timestamp },
                    notice: "Failed to load detailed session records."
                )
        }.value
    }
}
