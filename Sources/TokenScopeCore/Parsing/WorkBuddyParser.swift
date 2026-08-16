import Foundation

public struct WorkBuddyParseResult: Sendable {
    public let session: SessionRecord
    public let usageRecords: [UsageRecord]
}

/// Parses WorkBuddy's local project transcripts.
///
/// WorkBuddy stores one JSON object per line under `~/.workbuddy/projects`.
/// Token usage can be attached to both final assistant messages and tool-call
/// records, so every record with `providerData.rawUsage` is considered.
public struct WorkBuddyParser: Sendable {
    public init() {}

    public func parse(fileURL: URL) throws -> WorkBuddyParseResult {
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { throw ClaudeCodeParseError.emptyFile }

        let fractionalISO = ISO8601DateFormatter()
        fractionalISO.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let regularISO = ISO8601DateFormatter()
        regularISO.formatOptions = [.withInternetDateTime]

        var sessionID: String?
        var projectCwd: String?
        var startedAt: Date?
        var endedAt: Date?
        var models: Set<String> = []
        var usageRecords: [UsageRecord] = []
        var total = TokenUsage.zero
        var seenEventIDs: Set<String> = []

        for rawLine in data.split(separator: UInt8(ascii: "\n")) {
            guard !rawLine.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(rawLine)) as? [String: Any]
            else { continue }

            if sessionID == nil, let value = nonemptyString(object["sessionId"]) {
                sessionID = value
            }
            if projectCwd == nil, let value = nonemptyString(object["cwd"]) {
                projectCwd = value
            }

            let timestamp = parseTimestamp(
                object["timestamp"],
                fractionalISO: fractionalISO,
                regularISO: regularISO
            )
            if let timestamp {
                if startedAt == nil || timestamp < startedAt! { startedAt = timestamp }
                if endedAt == nil || timestamp > endedAt! { endedAt = timestamp }
            }

            guard let providerData = object["providerData"] as? [String: Any],
                  let usageObject = (providerData["rawUsage"] as? [String: Any])
                    ?? (providerData["usage"] as? [String: Any])
            else { continue }

            let usage = parseUsage(usageObject)
            guard usage.totalTokens > 0 else { continue }

            if let eventID = nonemptyString(providerData["messageId"])
                ?? nonemptyString(object["id"]) {
                guard seenEventIDs.insert(eventID).inserted else { continue }
            }

            let recordSessionID = nonemptyString(object["sessionId"])
                ?? sessionID
                ?? fileURL.deletingPathExtension().lastPathComponent
            let model = nonemptyString(providerData["model"])
                ?? nonemptyString(providerData["requestModelName"])
                ?? nonemptyString(providerData["requestModelId"])
                ?? "unknown"

            usageRecords.append(UsageRecord(
                sessionId: recordSessionID,
                messageIndex: usageRecords.count,
                provider: .workBuddy,
                accountId: nil,
                model: model,
                timestamp: timestamp ?? endedAt ?? Date(),
                usage: usage
            ))
            models.insert(model)
            total += usage
        }

        let resolvedSessionID = sessionID ?? fileURL.deletingPathExtension().lastPathComponent
        let start = startedAt ?? usageRecords.first?.timestamp ?? Date()
        let end = endedAt ?? usageRecords.last?.timestamp ?? start
        let session = SessionRecord(
            id: resolvedSessionID,
            provider: .workBuddy,
            accountId: nil,
            projectPath: projectCwd,
            sourceFile: fileURL,
            startedAt: start,
            endedAt: end,
            modelsUsed: Array(models).sorted(),
            totalUsage: total,
            messageCount: usageRecords.count
        )
        return WorkBuddyParseResult(session: session, usageRecords: usageRecords)
    }

    private func parseUsage(_ object: [String: Any]) -> TokenUsage {
        let input = maximumInt(in: object, keys: ["prompt_tokens", "input_tokens", "inputTokens"])
        let output = maximumInt(in: object, keys: ["completion_tokens", "output_tokens", "outputTokens"])

        let promptDetails = object["prompt_tokens_details"] as? [String: Any]
        let rawCacheRead = max(
            maximumInt(in: object, keys: [
                "prompt_cache_hit_tokens",
                "cache_read_input_tokens",
                "cached_tokens",
                "cacheReadTokens",
            ]),
            maximumInt(in: promptDetails ?? [:], keys: ["cached_tokens"]),
            detailsTotal(object["inputTokensDetails"], key: "cached_tokens")
        )

        let claudeCacheCreate = maximumInt(
            in: object,
            keys: ["claude_cache_creation_5_m_tokens"]
        ) + maximumInt(in: object, keys: ["claude_cache_creation_1_h_tokens"])
        let rawCacheCreate = max(
            maximumInt(in: object, keys: [
                "prompt_cache_write_tokens",
                "cache_creation_input_tokens",
                "cacheCreationTokens",
            ]),
            claudeCacheCreate
        )

        // WorkBuddy's prompt/input total includes cache reads and writes.
        // Split them into TokenScope's mutually exclusive four dimensions.
        let cacheRead = min(input, rawCacheRead)
        let cacheCreate = min(max(0, input - cacheRead), rawCacheCreate)
        return TokenUsage(
            inputTokens: max(0, input - cacheRead - cacheCreate),
            outputTokens: output,
            cacheCreationTokens: cacheCreate,
            cacheReadTokens: cacheRead
        )
    }

    private func maximumInt(in object: [String: Any], keys: [String]) -> Int {
        keys.reduce(0) { max($0, intValue(object[$1])) }
    }

    private func detailsTotal(_ raw: Any?, key: String) -> Int {
        if let object = raw as? [String: Any] {
            return intValue(object[key])
        }
        if let objects = raw as? [[String: Any]] {
            return objects.reduce(0) { $0 + intValue($1[key]) }
        }
        return 0
    }

    private func intValue(_ raw: Any?) -> Int {
        if let number = raw as? NSNumber {
            return max(0, number.intValue)
        }
        if let string = raw as? String, let value = Int(string) {
            return max(0, value)
        }
        return 0
    }

    private func nonemptyString(_ raw: Any?) -> String? {
        guard let value = raw as? String, !value.isEmpty else { return nil }
        return value
    }

    private func parseTimestamp(
        _ raw: Any?,
        fractionalISO: ISO8601DateFormatter,
        regularISO: ISO8601DateFormatter
    ) -> Date? {
        if let number = raw as? NSNumber {
            var seconds = number.doubleValue
            if seconds > 100_000_000_000_000 { seconds /= 1_000_000 }
            else if seconds > 100_000_000_000 { seconds /= 1_000 }
            guard seconds > 0 else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        guard let string = raw as? String else { return nil }
        if let numeric = Double(string) {
            return parseTimestamp(
                NSNumber(value: numeric),
                fractionalISO: fractionalISO,
                regularISO: regularISO
            )
        }
        return fractionalISO.date(from: string) ?? regularISO.date(from: string)
    }
}

public struct WorkBuddyScanner: Sendable {
    public let root: URL
    public let parser: WorkBuddyParser

    public init(root: URL? = nil, parser: WorkBuddyParser = WorkBuddyParser()) {
        if let root {
            self.root = root
        } else {
            self.root = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".workbuddy/projects", isDirectory: true)
        }
        self.parser = parser
    }

    public func scan() -> [WorkBuddyParseResult] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path),
              let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              )
        else { return [] }

        var results: [WorkBuddyParseResult] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            if let result = try? parser.parse(fileURL: url) {
                results.append(result)
            }
        }
        return results
    }
}
