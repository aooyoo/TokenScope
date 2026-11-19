import Foundation

/// Desktop Chat and Cowork audit logs contain streaming snapshots and SDK result
/// totals. Results replace the snapshots for that run; each system/init starts
/// a new ledger, even when the CLI session ID is reused.
public struct ClaudeDesktopParser: Sendable {
    public init() {}

    public func parse(fileURL: URL) throws -> ClaudeCodeParseResult {
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { throw ClaudeCodeParseError.emptyFile }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainISO = ISO8601DateFormatter()
        let fallbackDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date(timeIntervalSince1970: 0)
        var sessionID: String?
        var projectPath: String?
        var startedAt: Date?
        var endedAt: Date?
        var model = "unknown"
        var events: [AuditUsageEvent] = []
        var run = AuditRun()
        var messageCount = 0
        var seenResults: Set<String> = []
        var recognizedEvent = false

        for (lineIndex, line) in data.split(separator: UInt8(ascii: "\n")).enumerated() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = object["type"] as? String,
                  ["system", "user", "assistant", "result"].contains(type)
            else { continue }
            recognizedEvent = true
            sessionID = sessionID ?? nonemptyString(object["session_id"]) ?? nonemptyString(object["sessionId"])
            projectPath = nonemptyString(object["cwd"]) ?? projectPath
            let rawTimestamp = (object["_audit_timestamp"] as? String) ?? (object["timestamp"] as? String)
            let timestamp = rawTimestamp.flatMap { iso.date(from: $0) ?? plainISO.date(from: $0) }
                ?? endedAt ?? fallbackDate
            startedAt = min(startedAt ?? timestamp, timestamp)
            endedAt = max(endedAt ?? timestamp, timestamp)

            if type == "system", object["subtype"] as? String == "init" {
                events.append(contentsOf: run.pendingEvents)
                messageCount += run.messageCount
                run = AuditRun()
                model = normalizedModel(nonemptyString(object["model"]) ?? model)
                continue
            }

            if type == "assistant", let message = object["message"] as? [String: Any] {
                model = normalizedModel(nonemptyString(message["model"]) ?? model)
                let messageID = nonemptyString(message["id"]) ?? nonemptyString(object["uuid"])
                    ?? "line:\(lineIndex)"
                let requestID = nonemptyString(object["requestId"]) ?? nonemptyString(object["request_id"]) ?? ""
                let key = "\(requestID):\(messageID)"
                run.messageIDs.insert(key)
                guard let rawUsage = message["usage"] as? [String: Any] else { continue }
                let usage = snakeCaseUsage(rawUsage)
                guard usage.totalTokens > 0 else { continue }
                let previous = run.pending[key]?.usage ?? .zero
                // Each streamed content block can repeat the same response's
                // cumulative counters. Keep one snapshot per API response.
                let snapshot = maximum(previous, usage)
                if run.pending[key] == nil { run.pendingOrder.append(key) }
                run.pending[key] = AuditUsageEvent(model: model, timestamp: timestamp, usage: snapshot)
                continue
            }

            guard type == "result" else { continue }
            if let uuid = nonemptyString(object["uuid"]), !seenResults.insert(uuid).inserted { continue }
            var totals: [String: TokenUsage] = [:]
            if let modelUsage = object["modelUsage"] as? [String: [String: Any]] {
                for (name, rawUsage) in modelUsage {
                    let name = normalizedModel(nonemptyString(rawUsage["canonicalModel"]) ?? name)
                    let usage = TokenUsage(
                        inputTokens: integer(rawUsage["inputTokens"]),
                        outputTokens: integer(rawUsage["outputTokens"]),
                        cacheCreationTokens: integer(rawUsage["cacheCreationInputTokens"]),
                        cacheReadTokens: integer(rawUsage["cacheReadInputTokens"])
                    )
                    totals[name, default: .zero] += usage
                }
            }
            if totals.isEmpty, let rawUsage = object["usage"] as? [String: Any] {
                totals[model] = snakeCaseUsage(rawUsage)
            }
            guard !totals.isEmpty else { continue }

            // A result covers the assistant messages preceding it, including
            // subagents. Later cumulative results contribute only their delta.
            run.pending.removeAll()
            run.pendingOrder.removeAll()
            run.reportedTurns = max(run.reportedTurns, integer(object["num_turns"]))
            for name in totals.keys.sorted() {
                let current = totals[name]!
                let previous = run.resultTotals[name] ?? .zero
                let delta = difference(current, previous)
                run.resultTotals[name] = maximum(previous, current)
                if delta.totalTokens > 0 {
                    events.append(AuditUsageEvent(model: name, timestamp: timestamp, usage: delta))
                }
            }
        }
        guard recognizedEvent else { throw ClaudeCodeParseError.invalidFormat("No Claude Desktop audit events") }
        events.append(contentsOf: run.pendingEvents)
        messageCount += run.messageCount

        let id = sessionID ?? fileURL.deletingLastPathComponent().lastPathComponent
        let records = events.enumerated().map { index, event in
            UsageRecord(
                sessionId: id, messageIndex: index, provider: .claudeCode, accountId: nil,
                model: event.model, timestamp: event.timestamp, usage: event.usage
            )
        }
        let session = SessionRecord(
            id: id, provider: .claudeCode, accountId: nil, projectPath: projectPath,
            sourceFile: fileURL, startedAt: startedAt ?? fallbackDate, endedAt: endedAt ?? fallbackDate,
            modelsUsed: Array(Set(records.map(\.model))).sorted(),
            totalUsage: records.reduce(.zero) { $0 + $1.usage }, messageCount: messageCount
        )
        return ClaudeCodeParseResult(session: session, usageRecords: records)
    }

    private func nonemptyString(_ value: Any?) -> String? {
        guard let value = value as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private func normalizedModel(_ model: String) -> String {
        String(model.prefix { $0 != "[" })
    }

    private func integer(_ value: Any?) -> Int {
        max(0, (value as? Int) ?? 0)
    }

    private func snakeCaseUsage(_ raw: [String: Any]) -> TokenUsage {
        TokenUsage(
            inputTokens: integer(raw["input_tokens"]), outputTokens: integer(raw["output_tokens"]),
            cacheCreationTokens: integer(raw["cache_creation_input_tokens"]),
            cacheReadTokens: integer(raw["cache_read_input_tokens"])
        )
    }

    private func maximum(_ lhs: TokenUsage, _ rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: max(lhs.inputTokens, rhs.inputTokens), outputTokens: max(lhs.outputTokens, rhs.outputTokens),
            cacheCreationTokens: max(lhs.cacheCreationTokens, rhs.cacheCreationTokens),
            cacheReadTokens: max(lhs.cacheReadTokens, rhs.cacheReadTokens)
        )
    }

    private func difference(_ current: TokenUsage, _ previous: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: max(0, current.inputTokens - previous.inputTokens),
            outputTokens: max(0, current.outputTokens - previous.outputTokens),
            cacheCreationTokens: max(0, current.cacheCreationTokens - previous.cacheCreationTokens),
            cacheReadTokens: max(0, current.cacheReadTokens - previous.cacheReadTokens)
        )
    }
}

private struct AuditUsageEvent {
    let model: String
    let timestamp: Date
    let usage: TokenUsage
}

private struct AuditRun {
    var resultTotals: [String: TokenUsage] = [:]
    var pending: [String: AuditUsageEvent] = [:]
    var pendingOrder: [String] = []
    var messageIDs: Set<String> = []
    var reportedTurns = 0

    var pendingEvents: [AuditUsageEvent] { pendingOrder.compactMap { pending[$0] } }
    var messageCount: Int { max(messageIDs.count, reportedTurns) }
}
