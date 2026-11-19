import Foundation

/// Desktop's daily usage ledger stores per-call deltas. Only Chat rows are
/// imported here; Code and Cowork continue to use their session transcripts.
public struct ClaudeDesktopChatLedgerParser: Sendable {
    public init() {}

    public func parse(directory: URL) -> [ClaudeCodeParseResult] {
        let fm = FileManager.default
        let accountDirectory = directory.deletingLastPathComponent()
        var projectPaths: [String: String] = [:]
        let metadataFiles = (try? fm.contentsOfDirectory(
            at: accountDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        for file in metadataFiles where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let metadata = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let localID = nonemptyString(metadata["sessionId"])
            else { continue }
            if let cwd = nonemptyString(metadata["cwd"]) { projectPaths[localID] = cwd }
        }

        let files = ((try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        )) ?? []).filter {
            $0.lastPathComponent.range(of: #"^\d{4}-\d{2}-\d{2}(?:\.\d+)?\.ndjson$"#, options: .regularExpression) != nil
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        var bySession: [String: ChatLedgerSession] = [:]
        var seenEvents: Set<Data> = []
        for file in files {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  let data = try? Data(contentsOf: file) else { continue }
            for line in data.split(separator: UInt8(ascii: "\n")) {
                guard let event = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      event["v"] as? Int == 1, event["surface"] as? String == "chat",
                      let milliseconds = event["ts"] as? Double, milliseconds.isFinite, milliseconds > 0,
                      let models = event["models"] as? [String: [String: Any]],
                      let identity = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]),
                      seenEvents.insert(identity).inserted
                else { continue }

                let localID = nonemptyString(event["sessionId"])
                // Background Chat calls can omit a session ID. Keep their
                // account scope stable across days and file rotation.
                let id = localID
                    ?? "desktop-chat-ledger:\(directory.standardizedFileURL.path)"
                let timestamp = Date(timeIntervalSince1970: milliseconds / 1_000)
                var session = bySession[id] ?? ChatLedgerSession(sourceFile: file)
                var hasUsage = false
                for name in models.keys.sorted() {
                    let raw = models[name]!
                    let usage = TokenUsage(
                        inputTokens: integer(raw["inputTokens"]), outputTokens: integer(raw["outputTokens"]),
                        cacheCreationTokens: integer(raw["cacheWriteTokens"]),
                        cacheReadTokens: integer(raw["cacheReadTokens"])
                    )
                    guard usage.totalTokens > 0 else { continue }
                    let model = String(name.prefix { $0 != "[" })
                    session.records.append(UsageRecord(
                        sessionId: id, messageIndex: session.records.count, provider: .claudeCode,
                        accountId: nil, model: model, timestamp: timestamp, usage: usage
                    ))
                    hasUsage = true
                }
                if hasUsage { session.eventCount += 1 }
                bySession[id] = session
            }
        }

        return bySession.compactMap { id, parsed in
            guard let start = parsed.records.map(\.timestamp).min(),
                  let end = parsed.records.map(\.timestamp).max() else { return nil }
            let session = SessionRecord(
                id: id, provider: .claudeCode, accountId: nil, projectPath: projectPaths[id],
                sourceFile: parsed.sourceFile, startedAt: start, endedAt: end,
                modelsUsed: Array(Set(parsed.records.map(\.model))).sorted(),
                totalUsage: parsed.records.reduce(.zero) { $0 + $1.usage }, messageCount: parsed.eventCount
            )
            return ClaudeCodeParseResult(session: session, usageRecords: parsed.records)
        }.sorted { $0.session.startedAt > $1.session.startedAt }
    }

    private func nonemptyString(_ raw: Any?) -> String? {
        guard let value = raw as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private func integer(_ raw: Any?) -> Int { max(0, (raw as? Int) ?? 0) }
}

private struct ChatLedgerSession {
    let sourceFile: URL
    var records: [UsageRecord] = []
    var eventCount = 0
}
