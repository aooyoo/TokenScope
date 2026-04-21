import Foundation

public struct CodexParseResult: Sendable {
    public let session: SessionRecord
    public let usageRecords: [UsageRecord]
}

public struct CodexParser: Sendable {
    public init() {}

    public func parse(fileURL: URL) throws -> CodexParseResult {
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { throw ClaudeCodeParseError.emptyFile }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var sessionId = fileURL.deletingPathExtension().lastPathComponent
        var projectCwd: String?
        var startedAt: Date?
        var endedAt: Date?
        var currentModel: String = "gpt-5"
        var modelsSet: Set<String> = []
        var usageRecords: [UsageRecord] = []
        var total = TokenUsage.zero
        var messageIndex = 0

        let lines = data.split(separator: UInt8(ascii: "\n"))
        for rawLine in lines {
            guard !rawLine.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: Data(rawLine)) as? [String: Any]
            else { continue }

            let eventType = (obj["type"] as? String) ?? ""
            let payload = obj["payload"] as? [String: Any]
            let tsStr = obj["timestamp"] as? String
            let ts = tsStr.flatMap { iso.date(from: $0) }
            if let d = ts {
                if startedAt == nil { startedAt = d }
                endedAt = d
            }

            switch eventType {
            case "session_meta":
                if let p = payload {
                    if let sid = p["id"] as? String { sessionId = sid }
                    if let cwd = p["cwd"] as? String { projectCwd = cwd }
                    if let startStr = p["timestamp"] as? String,
                       let d = iso.date(from: startStr) {
                        startedAt = d
                    }
                }
            case "turn_context":
                if let p = payload, let model = p["model"] as? String, !model.isEmpty {
                    currentModel = model
                    modelsSet.insert(model)
                }
            case "event_msg":
                guard let p = payload,
                      (p["type"] as? String) == "token_count",
                      let info = p["info"] as? [String: Any],
                      let last = info["last_token_usage"] as? [String: Any]
                else { continue }

                let inputAll = (last["input_tokens"] as? Int) ?? 0
                let cached = (last["cached_input_tokens"] as? Int) ?? 0
                let output = (last["output_tokens"] as? Int) ?? 0
                let reasoning = (last["reasoning_output_tokens"] as? Int) ?? 0
                let effectiveInput = max(0, inputAll - cached)
                let effectiveOutput = output + reasoning

                let usage = TokenUsage(
                    inputTokens: effectiveInput,
                    outputTokens: effectiveOutput,
                    cacheCreationTokens: 0,
                    cacheReadTokens: cached
                )
                guard usage.totalTokens > 0 else { continue }

                usageRecords.append(UsageRecord(
                    sessionId: sessionId,
                    messageIndex: messageIndex,
                    provider: .codex,
                    accountId: nil,
                    model: currentModel,
                    timestamp: ts ?? endedAt ?? Date(),
                    usage: usage
                ))
                messageIndex += 1
                modelsSet.insert(currentModel)
                total += usage

            default:
                continue
            }
        }

        let start = startedAt ?? Date()
        let end = endedAt ?? start
        let session = SessionRecord(
            id: sessionId,
            provider: .codex,
            accountId: nil,
            projectPath: projectCwd,
            sourceFile: fileURL,
            startedAt: start,
            endedAt: end,
            modelsUsed: Array(modelsSet).sorted(),
            totalUsage: total,
            messageCount: messageIndex
        )
        return CodexParseResult(session: session, usageRecords: usageRecords)
    }
}

public struct CodexScanner: Sendable {
    public let roots: [URL]
    public let parser: CodexParser

    public init(roots: [URL]? = nil, parser: CodexParser = CodexParser()) {
        if let roots { self.roots = roots } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.roots = [
                home.appendingPathComponent(".codex/sessions", isDirectory: true),
                home.appendingPathComponent(".codex/archived_sessions", isDirectory: true),
            ]
        }
        self.parser = parser
    }

    public func scan() -> [CodexParseResult] {
        let fm = FileManager.default
        var results: [CodexParseResult] = []
        for root in roots {
            guard fm.fileExists(atPath: root.path),
                  let enumerator = fm.enumerator(
                      at: root,
                      includingPropertiesForKeys: [.isRegularFileKey],
                      options: [.skipsHiddenFiles]
                  )
            else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                if let res = try? parser.parse(fileURL: url) {
                    results.append(res)
                }
            }
        }
        return results
    }
}
