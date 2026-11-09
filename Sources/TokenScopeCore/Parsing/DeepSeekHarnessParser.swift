import Foundation

public struct DeepSeekHarnessParseResult: Sendable {
    public let session: SessionRecord
    public let usageRecords: [UsageRecord]
}

public enum DeepSeekHarnessParseError: Error {
    case invalidCache
    case invalidTranscript
}

/// Parses DeepSeek Harness's per-session projection cache.
///
/// Harness stores compressed event transcripts under `~/.dsh/sessions`, but it
/// also maintains a session-list projection under `~/.dsh/storages`, either in
/// a single JSON file or one file per session. The projection provides totals
/// for sessions whose transcripts cannot supply model-attributed usage.
public struct DeepSeekHarnessParser: Sendable {
    public init() {}

    public func parse(fileURL: URL) throws -> [DeepSeekHarnessParseResult] {
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { throw DeepSeekHarnessParseError.invalidCache }

        let decoder = JSONDecoder()
        guard let cache = try? decoder.decode(CacheFile.self, from: data) else {
            throw DeepSeekHarnessParseError.invalidCache
        }

        return cache.tables.sessions.map { sessionID, cached in
            makeResult(sessionID: sessionID, cached: cached, fileURL: fileURL)
        }
        .sorted { $0.session.startedAt > $1.session.startedAt }
    }

    fileprivate func parseSessionProjection(fileURL: URL) throws -> DeepSeekHarnessParseResult {
        let data = try Data(contentsOf: fileURL)
        let projection = try JSONDecoder().decode(SessionProjectionFile.self, from: data)
        let sessionID = fileURL.deletingPathExtension().lastPathComponent
        return makeResult(sessionID: sessionID, cached: projection.record, fileURL: fileURL)
    }

    private func makeResult(
        sessionID: String,
        cached: CachedSession,
        fileURL: URL
    ) -> DeepSeekHarnessParseResult {
        let usage = cached.rows.tokenUsage?.val.totals.tokenUsage ?? .zero
        let startedAt = date(milliseconds: cached.identity.createdAt)
            ?? (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            ?? Date(timeIntervalSince1970: 0)
        let reportedEnd = date(milliseconds: cached.rows.sessionListMetadata?.val.lastPromptAt)
            ?? startedAt
        let endedAt = max(startedAt, reportedEnd)
        let messageCount = max(0, cached.rows.sessionStats?.val.steps ?? 0)

        let records: [UsageRecord]
        if usage.totalTokens > 0 {
            records = [UsageRecord(
                sessionId: sessionID,
                messageIndex: 0,
                provider: .deepSeekHarness,
                accountId: nil,
                model: "DeepSeek Harness",
                timestamp: endedAt,
                usage: usage
            )]
        } else {
            records = []
        }

        let session = SessionRecord(
            id: sessionID,
            provider: .deepSeekHarness,
            accountId: nil,
            projectPath: cached.identity.cwd,
            sourceFile: fileURL,
            startedAt: startedAt,
            endedAt: endedAt,
            modelsUsed: usage.totalTokens > 0 ? ["DeepSeek Harness"] : [],
            totalUsage: usage,
            messageCount: messageCount
        )
        return DeepSeekHarnessParseResult(session: session, usageRecords: records)
    }

    private func date(milliseconds: Double?) -> Date? {
        guard let milliseconds, milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }
}

public struct DeepSeekHarnessTranscriptParseResult: Sendable {
    public let sessionID: String
    public let projectPath: String?
    public let startedAt: Date
    public let endedAt: Date
    public let modelsUsed: [String]
    public let totalUsage: TokenUsage
    public let messageCount: Int
    public let usageRecords: [UsageRecord]
    public let sourceFile: URL
    public let delegationDepth: Int
    public let parentSessionID: String?
}

/// Parses model-attributed usage from a compressed DeepSeek Harness transcript.
/// Only final `assistant/message` events are counted. Harness writes an
/// equivalent `assistant/chunk` usage event for the same model call, so counting
/// both would double every token bucket.
public struct DeepSeekHarnessTranscriptParser: Sendable {
    private let decompressor: ZstandardDecompressor

    public init(maximumDecompressedSize: Int = 256 * 1_024 * 1_024) {
        self.decompressor = ZstandardDecompressor(maximumOutputSize: maximumDecompressedSize)
    }

    public func parse(fileURL: URL) throws -> DeepSeekHarnessTranscriptParseResult {
        let compressed = try Data(contentsOf: fileURL)
        let data = try decompressor.decompress(compressed)
        guard !data.isEmpty else { throw DeepSeekHarnessParseError.invalidTranscript }

        var sessionID: String?
        var projectPath: String?
        var createdAt: Date?
        var delegationDepth = 0
        var parentSessionID: String?
        var models: Set<String> = []
        var usageRecords: [UsageRecord] = []
        var totalUsage = TokenUsage.zero
        var messageCount = 0
        var firstMessageAt: Date?
        var lastMessageAt: Date?

        for rawLine in data.split(separator: UInt8(ascii: "\n")) {
            guard !rawLine.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(rawLine)) as? [String: Any],
                  let type = object["type"] as? String
            else { continue }

            if type == "session" {
                sessionID = nonemptyString(object["id"]) ?? sessionID
                projectPath = nonemptyString(object["cwd"]) ?? projectPath
                createdAt = date(milliseconds: doubleValue(object["createdAt"])) ?? createdAt
                delegationDepth = max(0, intValue(object["delegationDepth"]))
                parentSessionID = nonemptyString(object["parentSession"])
                continue
            }

            guard type == "assistant/message",
                  let eventData = object["data"] as? [String: Any],
                  let rawUsage = eventData["usage"] as? [String: Any]
            else { continue }

            messageCount += 1
            let message = eventData["message"] as? [String: Any]
            let source = message?["source"] as? [String: Any]
            let model = nonemptyString(source?["model"]) ?? "unknown"
            let timestamp = date(milliseconds: doubleValue(object["time"]))
                ?? date(milliseconds: doubleValue(object["time0"]))
                ?? createdAt
                ?? Date(timeIntervalSince1970: 0)
            if firstMessageAt == nil || timestamp < firstMessageAt! { firstMessageAt = timestamp }
            if lastMessageAt == nil || timestamp > lastMessageAt! { lastMessageAt = timestamp }
            models.insert(model)

            // `outputTokens` already includes reasoning tokens in Harness's
            // projection totals, so `reasoningTokens` must not be added again.
            let usage = TokenUsage(
                inputTokens: max(0, intValue(rawUsage["inputTokens"])),
                outputTokens: max(0, intValue(rawUsage["outputTokens"])),
                cacheCreationTokens: max(0, intValue(rawUsage["cacheWriteTokens"])),
                cacheReadTokens: max(0, intValue(rawUsage["cacheReadTokens"]))
            )
            guard usage.totalTokens > 0 else { continue }

            let resolvedID = sessionID ?? fileURL.deletingLastPathComponent().lastPathComponent
            usageRecords.append(UsageRecord(
                sessionId: resolvedID,
                messageIndex: messageCount - 1,
                provider: .deepSeekHarness,
                accountId: nil,
                model: model,
                timestamp: timestamp,
                usage: usage
            ))
            totalUsage += usage
        }

        let resolvedID = sessionID ?? fileURL.deletingLastPathComponent().lastPathComponent
        guard !resolvedID.isEmpty else { throw DeepSeekHarnessParseError.invalidTranscript }
        let fallbackDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date(timeIntervalSince1970: 0)
        let start = createdAt ?? firstMessageAt ?? fallbackDate
        let end = max(start, lastMessageAt ?? start)

        return DeepSeekHarnessTranscriptParseResult(
            sessionID: resolvedID,
            projectPath: projectPath,
            startedAt: start,
            endedAt: end,
            modelsUsed: Array(models).sorted(),
            totalUsage: totalUsage,
            messageCount: messageCount,
            usageRecords: usageRecords,
            sourceFile: fileURL,
            delegationDepth: delegationDepth,
            parentSessionID: parentSessionID
        )
    }

    private func date(milliseconds: Double?) -> Date? {
        guard let milliseconds, milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }

    private func doubleValue(_ raw: Any?) -> Double? {
        if let number = raw as? NSNumber { return number.doubleValue }
        if let string = raw as? String { return Double(string) }
        return nil
    }

    private func intValue(_ raw: Any?) -> Int {
        if let number = raw as? NSNumber { return number.intValue }
        if let string = raw as? String { return Int(string) ?? 0 }
        return 0
    }

    private func nonemptyString(_ raw: Any?) -> String? {
        guard let value = raw as? String, !value.isEmpty else { return nil }
        return value
    }
}

public struct DeepSeekHarnessScanner: Sendable {
    public let root: URL
    public let parser: DeepSeekHarnessParser
    public let transcriptParser: DeepSeekHarnessTranscriptParser

    public init(
        root: URL? = nil,
        parser: DeepSeekHarnessParser = DeepSeekHarnessParser(),
        transcriptParser: DeepSeekHarnessTranscriptParser = DeepSeekHarnessTranscriptParser()
    ) {
        self.root = root ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".dsh", isDirectory: true)
        self.parser = parser
        self.transcriptParser = transcriptParser
    }

    public func scan() -> [DeepSeekHarnessParseResult] {
        let storage = root.appendingPathComponent("storages", isDirectory: true)
        let cacheFile = storage.appendingPathComponent("session_projcache.json")
        var cachedByID = Dictionary(
            uniqueKeysWithValues: ((try? parser.parse(fileURL: cacheFile)) ?? [])
                .map { ($0.session.id, $0) }
        )
        let projections = storage.appendingPathComponent("session_projcache/sessions", isDirectory: true)
        let projectionFiles = (try? FileManager.default.contentsOfDirectory(
            at: projections, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        for file in projectionFiles where file.pathExtension == "json" {
            guard let projection = try? parser.parseSessionProjection(fileURL: file) else { continue }
            cachedByID[projection.session.id] = projection
        }

        var transcriptByID: [String: (version: Int, result: DeepSeekHarnessTranscriptParseResult)] = [:]

        let transcriptRoot = root.appendingPathComponent("sessions", isDirectory: true)
        if let enumerator = FileManager.default.enumerator(
            at: transcriptRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let file as URL in enumerator {
                guard let version = transcriptVersion(file.lastPathComponent),
                      let transcript = try? transcriptParser.parse(fileURL: file) else { continue }
                if let existing = transcriptByID[transcript.sessionID] {
                    let oldCount = existing.result.usageRecords.count
                    let newCount = transcript.usageRecords.count
                    if oldCount > newCount || (oldCount == newCount && existing.version >= version) {
                        continue
                    }
                }
                transcriptByID[transcript.sessionID] = (version, transcript)
            }
        }

        var results: [DeepSeekHarnessParseResult] = []
        for (_, transcript) in transcriptByID.values {
            let cached = cachedByID.removeValue(forKey: transcript.sessionID)
            results.append(merge(cached: cached, transcript: transcript))
        }
        results.append(contentsOf: cachedByID.values)
        return results.sorted { $0.session.startedAt > $1.session.startedAt }
    }

    private func transcriptVersion(_ name: String) -> Int? {
        switch name {
        case "session.jsonl.zstd": return 0
        case "session.v3.jsonl.zstd": return 3
        case "session.v4.jsonl.zstd": return 4
        default: return nil
        }
    }

    private func merge(
        cached: DeepSeekHarnessParseResult?,
        transcript: DeepSeekHarnessTranscriptParseResult
    ) -> DeepSeekHarnessParseResult {
        let cacheUsage = cached?.session.totalUsage ?? .zero
        let useTranscriptUsage = transcript.totalUsage.totalTokens > 0 || cacheUsage.totalTokens == 0
        let usage = useTranscriptUsage ? transcript.totalUsage : cacheUsage
        let records = useTranscriptUsage
            ? transcript.usageRecords
            : (cached?.usageRecords ?? [])
        let models = useTranscriptUsage
            ? transcript.modelsUsed
            : (cached?.session.modelsUsed ?? [])
        let cachedStart = cached?.session.startedAt ?? transcript.startedAt
        let cachedEnd = cached?.session.endedAt ?? transcript.endedAt

        let session = SessionRecord(
            id: transcript.sessionID,
            provider: .deepSeekHarness,
            accountId: nil,
            projectPath: transcript.projectPath ?? cached?.session.projectPath,
            sourceFile: transcript.sourceFile,
            startedAt: min(cachedStart, transcript.startedAt),
            endedAt: max(cachedEnd, transcript.endedAt),
            modelsUsed: models,
            totalUsage: usage,
            messageCount: useTranscriptUsage
                ? transcript.messageCount
                : (cached?.session.messageCount ?? 0)
        )
        return DeepSeekHarnessParseResult(session: session, usageRecords: records)
    }
}

private struct CacheFile: Decodable {
    let tables: CacheTables
}

private struct SessionProjectionFile: Decodable {
    let record: CachedSession
}

private struct CacheTables: Decodable {
    let sessions: [String: CachedSession]
}

private struct CachedSession: Decodable {
    let identity: SessionIdentity
    let rows: SessionRows
}

private struct SessionIdentity: Decodable {
    let createdAt: Double?
    let cwd: String?
}

private struct SessionRows: Decodable {
    let sessionStats: VersionedRow<SessionStats>?
    let tokenUsage: VersionedRow<TokenUsageProjection>?
    let sessionListMetadata: VersionedRow<SessionListMetadata>?
}

private struct VersionedRow<Value: Decodable>: Decodable {
    let val: Value
}

private struct SessionStats: Decodable {
    let steps: Int?
}

private struct SessionListMetadata: Decodable {
    let lastPromptAt: Double?
}

private struct TokenUsageProjection: Decodable {
    let totals: HarnessTokenTotals
}

private struct HarnessTokenTotals: Decodable {
    let uncachedInputTokens: Int?
    let outputTokens: Int?
    let cacheReadTokens: Int?
    let cacheWriteTokens: Int?

    var tokenUsage: TokenUsage {
        TokenUsage(
            inputTokens: max(0, uncachedInputTokens ?? 0),
            outputTokens: max(0, outputTokens ?? 0),
            cacheCreationTokens: max(0, cacheWriteTokens ?? 0),
            cacheReadTokens: max(0, cacheReadTokens ?? 0)
        )
    }
}
