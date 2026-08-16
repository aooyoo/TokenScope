import XCTest
@testable import TokenScopeCore

final class WorkBuddyParserTests: XCTestCase {
    func testParsesToolCallsMessagesCacheAndLegacyUsage() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("workbuddy_\(UUID().uuidString).jsonl")
        let lines = [
            #"{"type":"message","role":"user","sessionId":"wb-session","cwd":"/tmp/workbuddy-project","timestamp":1779000000000}"#,
            #"{"type":"function_call","id":"tool-1","sessionId":"wb-session","cwd":"/tmp/workbuddy-project","timestamp":1779000001000,"providerData":{"messageId":"usage-1","model":"auto","rawUsage":{"prompt_tokens":100,"completion_tokens":20,"total_tokens":120,"prompt_cache_hit_tokens":60,"prompt_cache_write_tokens":10}}}"#,
            #"{"type":"function_call","id":"tool-1-copy","sessionId":"wb-session","cwd":"/tmp/workbuddy-project","timestamp":1779000001000,"providerData":{"messageId":"usage-1","model":"auto","rawUsage":{"prompt_tokens":100,"completion_tokens":20,"total_tokens":120,"prompt_cache_hit_tokens":60,"prompt_cache_write_tokens":10}}}"#,
            #"{"type":"message","role":"assistant","id":"assistant-1","sessionId":"wb-session","cwd":"/tmp/workbuddy-project","timestamp":1779000002000,"providerData":{"messageId":"usage-2","model":"hy3","rawUsage":{"prompt_tokens":50,"completion_tokens":5,"total_tokens":55,"prompt_tokens_details":{"cached_tokens":20}}}}"#,
            #"{"type":"message","role":"assistant","id":"assistant-legacy","sessionId":"wb-session","cwd":"/tmp/workbuddy-project","timestamp":1779000003000,"providerData":{"model":"kimi-k2.5","usage":{"input_tokens":40,"output_tokens":7,"total_tokens":47}}}"#,
        ].joined(separator: "\n")
        try lines.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let result = try WorkBuddyParser().parse(fileURL: file)

        XCTAssertEqual(result.session.id, "wb-session")
        XCTAssertEqual(result.session.provider, .workBuddy)
        XCTAssertEqual(result.session.projectPath, "/tmp/workbuddy-project")
        XCTAssertEqual(result.session.messageCount, 3)
        XCTAssertEqual(result.session.modelsUsed, ["auto", "hy3", "kimi-k2.5"])
        XCTAssertEqual(result.usageRecords.map(\.messageIndex), [0, 1, 2])

        XCTAssertEqual(result.session.totalUsage.inputTokens, 100)
        XCTAssertEqual(result.session.totalUsage.outputTokens, 32)
        XCTAssertEqual(result.session.totalUsage.cacheCreationTokens, 10)
        XCTAssertEqual(result.session.totalUsage.cacheReadTokens, 80)
        XCTAssertEqual(result.session.totalUsage.totalTokens, 222)
    }

    func testScannerFindsNestedSubagentTranscript() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workbuddy-root-\(UUID().uuidString)", isDirectory: true)
        let nested = root
            .appendingPathComponent("project/session/subagents", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let file = nested.appendingPathComponent("agent-test.jsonl")
        let line = #"{"type":"function_call","id":"call-1","sessionId":"subagent-session","timestamp":"2026-05-18T08:10:39.640Z","providerData":{"model":"glm-5.2","rawUsage":{"prompt_tokens":25,"completion_tokens":3,"total_tokens":28}}}"#
        try line.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let results = WorkBuddyScanner(root: root).scan()

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.session.id, "subagent-session")
        XCTAssertEqual(results.first?.usageRecords.first?.usage.totalTokens, 28)
    }
}
