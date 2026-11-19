import XCTest
@testable import TokenScopeCore

final class ClaudeDesktopParserTests: XCTestCase {
    func testResultTotalsReplaceStreamingSnapshotsAndNormalizeModels() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let audit = try write([
            #"{"type":"system","subtype":"init","session_id":"cowork-a","cwd":"/tmp/work","model":"claude-opus-4-7","_audit_timestamp":"2026-05-01T10:00:00Z"}"#,
            assistant(id: "m1", input: 100, output: 0),
            assistant(id: "m1", input: 100, output: 0),
            #"{"type":"result","uuid":"r1","session_id":"cowork-a","num_turns":1,"_audit_timestamp":"2026-05-01T10:01:00Z","usage":{"input_tokens":999},"modelUsage":{"claude-opus-4-7[1m]":{"inputTokens":100,"outputTokens":25,"cacheCreationInputTokens":10,"cacheReadInputTokens":50},"claude-haiku-4-5-20251001":{"inputTokens":5,"outputTokens":2,"cacheReadInputTokens":3}}}"#,
        ], to: directory.appendingPathComponent("audit.jsonl"))

        let result = try ClaudeDesktopParser().parse(fileURL: audit)
        XCTAssertEqual(result.session.id, "cowork-a")
        XCTAssertEqual(result.session.provider, .claudeCode)
        XCTAssertEqual(result.session.projectPath, "/tmp/work")
        XCTAssertEqual(result.session.messageCount, 1)
        XCTAssertEqual(result.session.totalUsage, TokenUsage(inputTokens: 105, outputTokens: 27, cacheCreationTokens: 10, cacheReadTokens: 53))
        XCTAssertEqual(result.session.modelsUsed, ["claude-haiku-4-5-20251001", "claude-opus-4-7"])
        XCTAssertEqual(result.usageRecords.count, 2)
        XCTAssertEqual(result.session.endedAt.timeIntervalSince(result.session.startedAt), 60)
        XCTAssertTrue(result.usageRecords.allSatisfy { $0.sessionId == "cowork-a" && $0.provider == .claudeCode })
        XCTAssertGreaterThan(PriceBook(storageURL: nil).cost(for: result.session.totalUsage, model: "claude-opus-4-7"), 0)
    }

    func testCumulativeResultsDeduplicateButNewInitStartsANewLedger() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let second = result(id: "r2", input: 160, output: 40, time: "2026-05-02T00:00:00Z")
        let audit = try write([
            #"{"type":"system","subtype":"init","session_id":"s1","_audit_timestamp":"2026-05-01T10:00:00Z"}"#,
            result(id: "r1", input: 100, output: 20),
            second,
            second,
            #"{"type":"system","subtype":"init","session_id":"s1","_audit_timestamp":"2026-05-03T10:00:00Z"}"#,
            result(id: "r3", input: 200, output: 50, time: "2026-05-03T10:01:00Z"),
        ], to: directory.appendingPathComponent("audit.jsonl"))

        let parsed = try ClaudeDesktopParser().parse(fileURL: audit)
        XCTAssertEqual(parsed.session.totalUsage, TokenUsage(inputTokens: 360, outputTokens: 90))
        XCTAssertEqual(parsed.usageRecords.map(\.usage.inputTokens), [100, 60, 200])
        XCTAssertEqual(parsed.usageRecords.map(\.messageIndex), [0, 1, 2])
        let buckets = UsageAggregator(priceBook: PriceBook(storageURL: nil), calendar: utcCalendar())
            .dailyBuckets(records: parsed.usageRecords)
        XCTAssertEqual(buckets.count, 3)
        XCTAssertEqual(buckets.reduce(0) { $0 + $1.usage.totalTokens }, 450)
    }

    func testUnfinishedRunUsesOneSnapshotPerResponse() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let audit = try write([
            #"{"type":"system","subtype":"init","session_id":"live","_audit_timestamp":"2026-05-01T10:00:00Z"}"#,
            assistant(id: "m1", input: 100, output: 0),
            assistant(id: "m1", input: 100, output: 20),
            "{incomplete line",
            assistant(id: "m2", input: 50, output: 10),
        ], to: directory.appendingPathComponent("audit.jsonl"))
        let parsed = try ClaudeDesktopParser().parse(fileURL: audit)
        XCTAssertEqual(parsed.session.totalUsage, TokenUsage(inputTokens: 150, outputTokens: 30))
        XCTAssertEqual(parsed.session.messageCount, 2)
        XCTAssertEqual(parsed.usageRecords.count, 2)
    }

    func testPendingMessagesAfterResultAreIncludedAndReplacedOnRefresh() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lines = [
            #"{"type":"system","subtype":"init","session_id":"live","_audit_timestamp":"2026-05-01T10:00:00Z"}"#,
            assistant(id: "m1", input: 100, output: 0),
            result(id: "r1", input: 100, output: 20),
            assistant(id: "m2", input: 50, output: 0),
        ]
        let audit = try write(lines, to: directory.appendingPathComponent("audit.jsonl"))
        let pending = try ClaudeDesktopParser().parse(fileURL: audit)
        XCTAssertEqual(pending.session.totalUsage, TokenUsage(inputTokens: 150, outputTokens: 20))
        try write(lines + [result(id: "r2", input: 150, output: 30)], to: audit)
        let completed = try ClaudeDesktopParser().parse(fileURL: audit)
        let merged = UsageCache.merge(
            cached: UsageCacheSnapshot(updatedAt: Date(), sessions: [pending.session], records: pending.usageRecords),
            scannedSessions: [completed.session], scannedRecords: completed.usageRecords
        )
        XCTAssertEqual(merged.sessions.count, 1)
        XCTAssertEqual(merged.records.reduce(TokenUsage.zero) { $0 + $1.usage }, TokenUsage(inputTokens: 150, outputTokens: 30))
    }

    func testLegacyResultUsageFallbackAndAuditDetails() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let audit = try write([
            #"{"type":"system","subtype":"init","session_id":"legacy","model":"claude-opus-4-7","_audit_timestamp":"2026-05-01T10:00:00Z"}"#,
            #"{"type":"result","session_id":"legacy","_audit_timestamp":"2026-05-01T10:01:00Z","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":20,"cache_creation_input_tokens":30}}"#,
        ], to: directory.appendingPathComponent("audit.jsonl"))
        let parsed = try ClaudeDesktopParser().parse(fileURL: audit)
        XCTAssertEqual(parsed.session.totalUsage, TokenUsage(inputTokens: 10, outputTokens: 5, cacheCreationTokens: 30, cacheReadTokens: 20))
        let detail = try SessionDetailLoader().loadDetail(for: parsed.session, usageRecords: parsed.usageRecords)
        XCTAssertEqual(detail.mode, .usageOnly)
        XCTAssertEqual(detail.usageRecords, parsed.usageRecords)
        XCTAssertNotNil(detail.notice)
    }

    func testScannerCombinesBothDesktopStoresWithCLIWithoutCountingCopies() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cli = directory.appendingPathComponent("cli/projects")
        let desktop = directory.appendingPathComponent("Claude/local-agent-mode-sessions")
        let thirdParty = directory.appendingPathComponent("Claude-3p/local-agent-mode-sessions")
        try write([assistant(id: "cli", input: 10, output: 5)], to: cli.appendingPathComponent("project/cli-session.jsonl"))
        for (root, id, input) in [(desktop, "cowork-a", 100), (thirdParty, "cowork-b", 200)] {
            let session = root.appendingPathComponent("account/org/local_\(id)")
            try write([
                "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"\(id)\",\"_audit_timestamp\":\"2026-05-01T10:00:00Z\"}",
                result(id: "result-\(id)", input: input, output: 20),
            ], to: session.appendingPathComponent("audit.jsonl"))
            // Embedded transcript and subagent are already covered by results.
            try write([assistant(id: id, input: input, output: 0)], to: session.appendingPathComponent(".claude/projects/proj/\(id).jsonl"))
            try write([assistant(id: "agent", input: 500, output: 0)], to: session.appendingPathComponent(".claude/projects/proj/\(id)/subagents/agent-a.jsonl"))
            // An output file is not a usage source.
            try write([assistant(id: "output", input: 9999, output: 9999)], to: session.appendingPathComponent("outputs/example.jsonl"))
        }
        // A shared native copy must not add another session or token record.
        try write([assistant(id: "copy", input: 100, output: 20)], to: cli.appendingPathComponent("project/cowork-a.jsonl"))
        let scanner = ClaudeCodeScanner(root: cli, desktopRoots: [desktop, thirdParty, desktop])
        let scanned = scanner.scan()
        XCTAssertEqual(Set(scanned.map(\.session.id)), ["cli-session", "cowork-a", "cowork-b"])
        XCTAssertEqual(scanned.reduce(0) { $0 + $1.session.totalUsage.totalTokens }, 355)
        XCTAssertEqual(scanned.flatMap(\.usageRecords).reduce(0) { $0 + $1.usage.totalTokens }, 355)
        let snapshot = try await ClaudeCodeUsageProvider(sessions: scanned.map(\.session)).fetchSnapshot()
        XCTAssertEqual(snapshot.windows.first?.usedValue, 355)
        XCTAssertEqual(ClaudeCodeScanner(root: cli).desktopRoots, [])
    }

    func testScannerFindsHiddenEmbeddedTranscriptsWhenAuditMissingOrCorrupt() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let desktop = directory.appendingPathComponent("Claude/claude-code-sessions")
        let session = desktop.appendingPathComponent("account/org/local_fallback")
        try write(["invalid JSON"], to: session.appendingPathComponent("audit.jsonl"))
        try write([assistant(id: "m1", input: 30, output: 5)], to: session.appendingPathComponent(".claude/projects/proj/fallback.jsonl"))
        try write([assistant(id: "m2", input: 10, output: 2)], to: session.appendingPathComponent(".claude/projects/proj/fallback/subagents/agent-a.jsonl"))
        let scanned = ClaudeCodeScanner(root: directory.appendingPathComponent("missing"), desktopRoots: [desktop]).scan()
        XCTAssertEqual(Set(scanned.map(\.session.id)), ["fallback", "subagent:agent-a"])
        XCTAssertEqual(scanned.reduce(0) { $0 + $1.session.totalUsage.totalTokens }, 47)
    }

    func testDefaultRootsIncludeClaudeAndClaude3pForCoworkAndCode() {
        let paths = ClaudeCodeScanner().desktopRoots.map(\.path)
        for app in ["Claude", "Claude-3p"] {
            for store in ["local-agent-mode-sessions", "claude-code-sessions"] {
                XCTAssertTrue(paths.contains { $0.hasSuffix("/\(app)/\(store)") })
            }
        }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cowork-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @discardableResult
    private func write(_ lines: [String], to file: URL) throws -> URL {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private func assistant(id: String, input: Int, output: Int) -> String {
        "{\"type\":\"assistant\",\"timestamp\":\"2026-05-01T10:00:10.000Z\",\"message\":{\"id\":\"\(id)\",\"model\":\"claude-opus-4-7\",\"usage\":{\"input_tokens\":\(input),\"output_tokens\":\(output)}}}"
    }

    private func result(id: String, input: Int, output: Int, time: String = "2026-05-01T10:01:00Z") -> String {
        "{\"type\":\"result\",\"uuid\":\"\(id)\",\"_audit_timestamp\":\"\(time)\",\"modelUsage\":{\"claude-opus-4-7[1m]\":{\"inputTokens\":\(input),\"outputTokens\":\(output)}}}"
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
