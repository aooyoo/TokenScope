import XCTest
@testable import TokenScopeCore

final class ClaudeDesktopChatLedgerTests: XCTestCase {
    func testChatDeltasIncludeAllTokenBucketsAcrossDaysAndRotatedFiles() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let ledger = root.appendingPathComponent("usage-ledger")
        let first = event(session: "local_chat", input: 100, output: 20)
        try write([
            first,
            event(surface: "cowork", session: "cowork", input: 9000, output: 1),
            event(surface: "code", session: "code", input: 9000, output: 1),
            "{partial",
            #"{"v":1,"ts":1794191468808,"surface":"chat","models":{"claude-opus-4-8":{"max_output_tokens":128000,"context_window_tokens":1000000}}}"#,
        ], to: ledger.appendingPathComponent("2026-11-09.ndjson"))
        try write([first, event(session: "local_chat", input: 50, output: 10, ts: 1794277868808)],
                  to: ledger.appendingPathComponent("2026-11-10.1.ndjson"))
        // Files that are not Desktop's daily ledger are not imported.
        try write([event(session: "fake", input: 99999, output: 0)], to: ledger.appendingPathComponent("example.ndjson"))
        let results = ClaudeDesktopChatLedgerParser().parse(directory: ledger)
        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(result.session.id, "local_chat")
        XCTAssertEqual(result.session.provider, .claudeCode)
        XCTAssertEqual(result.session.totalUsage, TokenUsage(inputTokens: 150, outputTokens: 30, cacheCreationTokens: 6, cacheReadTokens: 14))
        XCTAssertEqual(result.session.modelsUsed, ["claude-opus-4-8"])
        XCTAssertEqual(result.session.messageCount, 2)
        XCTAssertEqual(result.usageRecords.map(\.messageIndex), [0, 1])
        XCTAssertEqual(result.session.endedAt.timeIntervalSince(result.session.startedAt), 86400)
        let detail = try SessionDetailLoader().loadDetail(for: result.session, usageRecords: result.usageRecords)
        XCTAssertEqual(detail.mode, .usageOnly)
        XCTAssertEqual(detail.usageRecords, result.usageRecords)
    }

    func testScannerDeduplicatesChatAuditLedgerAndCLICopyAndSurvivesDeletion() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let desktop = root.appendingPathComponent("Claude/local-agent-mode-sessions")
        let account = desktop.appendingPathComponent("account/org")
        let cli = root.appendingPathComponent("cli")
        let metadata = account.appendingPathComponent("local_chat.json")
        try write([#"{"sessionId":"local_chat","cliSessionId":"cli-chat","sessionType":"chat","cwd":"/tmp/chat"}"#], to: metadata)
        let audit = account.appendingPathComponent("local_chat/audit.jsonl")
        try write([
            #"{"type":"system","subtype":"init","session_id":"cli-chat","_audit_timestamp":"2026-11-09T06:00:00Z"}"#,
            #"{"type":"result","session_id":"cli-chat","_audit_timestamp":"2026-11-09T06:01:00Z","modelUsage":{"claude-opus-4-8":{"inputTokens":100,"outputTokens":20,"cacheCreationInputTokens":3,"cacheReadInputTokens":7}}}"#,
        ], to: audit)
        let native = cli.appendingPathComponent("project/cli-chat.jsonl")
        try write([#"{"type":"assistant","timestamp":"2026-11-09T06:01:00.000Z","message":{"model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":20,"cache_creation_input_tokens":3,"cache_read_input_tokens":7}}}"#], to: native)
        try write([event(session: "local_chat", input: 100, output: 20)],
                  to: account.appendingPathComponent("usage-ledger/2026-11-09.ndjson"))
        let scanner = ClaudeCodeScanner(root: cli, desktopRoots: [desktop])
        let scanned = scanner.scan()
        let session = try XCTUnwrap(scanned.first)
        XCTAssertEqual(scanned.count, 1)
        XCTAssertEqual(session.session.id, "local_chat")
        XCTAssertEqual(session.session.sourceFile.lastPathComponent, "audit.jsonl")
        XCTAssertEqual(session.session.totalUsage.totalTokens, 130)
        XCTAssertTrue(session.usageRecords.allSatisfy { $0.sessionId == "local_chat" })

        // Deleting a conversation leaves the usage ledger behind. Its stable
        // Desktop ID must replace the cached audit session instead of adding it.
        try FileManager.default.removeItem(at: metadata)
        try FileManager.default.removeItem(at: audit.deletingLastPathComponent())
        try FileManager.default.removeItem(at: native)
        let retained = scanner.scan()
        let merged = UsageCache.merge(
            cached: UsageCacheSnapshot(updatedAt: Date(), sessions: scanned.map(\.session), records: scanned.flatMap(\.usageRecords)),
            scannedSessions: retained.map(\.session), scannedRecords: retained.flatMap(\.usageRecords)
        )
        XCTAssertEqual(merged.sessions.count, 1)
        XCTAssertEqual(merged.records.reduce(0) { $0 + $1.usage.totalTokens }, 130)
    }

    func testChatLedgerIsScannedInBothDesktopDirectories() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let stores = ["Claude", "Claude-3p"].map { root.appendingPathComponent("\($0)/local-agent-mode-sessions") }
        for (index, store) in stores.enumerated() {
            try write([event(session: "local_chat_\(index)", input: 100, output: 20)],
                      to: store.appendingPathComponent("account/org/usage-ledger/2026-11-09.ndjson"))
        }
        let results = ClaudeCodeScanner(root: root.appendingPathComponent("missing-cli"), desktopRoots: stores).scan()
        XCTAssertEqual(Set(results.map(\.session.id)), ["local_chat_0", "local_chat_1"])
        XCTAssertEqual(results.reduce(0) { $0 + $1.session.totalUsage.totalTokens }, 260)
    }

    func testBackgroundChatCallsHaveStableAccountScopedIDsAndErrorsStillCount() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("account-a/usage-ledger")
        let second = root.appendingPathComponent("account-b/usage-ledger")
        for ledger in [first, second] {
            try write([
                #"{"v":1,"ts":1794191468808,"surface":"chat","origin":"title","isError":true,"models":{"claude-haiku-4-5":{"inputTokens":10,"outputTokens":5,"cacheReadTokens":0,"cacheWriteTokens":0}}}"#,
                #"{"v":2,"ts":1794191468808,"surface":"chat","models":{"unknown":{"inputTokens":9999}}}"#,
            ], to: ledger.appendingPathComponent("2026-11-09.ndjson"))
        }
        let parser = ClaudeDesktopChatLedgerParser()
        let a = try XCTUnwrap(parser.parse(directory: first).first)
        let b = try XCTUnwrap(parser.parse(directory: second).first)
        XCTAssertNotEqual(a.session.id, b.session.id)
        XCTAssertEqual(a.session.totalUsage.totalTokens, 15)
        try write([event(session: nil, input: 10, output: 5)], to: first.appendingPathComponent("2026-11-10.ndjson"))
        let refreshed = try XCTUnwrap(parser.parse(directory: first).first)
        XCTAssertEqual(refreshed.session.id, a.session.id)
        XCTAssertEqual(refreshed.session.totalUsage.totalTokens, 40)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("chat-ledger-tests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ lines: [String], to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    private func event(surface: String = "chat", session: String?, input: Int, output: Int, ts: Int = 1794191468808) -> String {
        let sessionField = session.map { ",\"sessionId\":\"\($0)\"" } ?? ""
        return "{\"v\":1,\"ts\":\(ts),\"surface\":\"\(surface)\",\"origin\":\"turn\"\(sessionField),\"models\":{\"claude-opus-4-8[1m]\":{\"inputTokens\":\(input),\"outputTokens\":\(output),\"cacheReadTokens\":7,\"cacheWriteTokens\":3}}}"
    }
}
