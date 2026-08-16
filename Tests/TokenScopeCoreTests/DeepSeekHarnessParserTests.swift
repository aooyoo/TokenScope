import XCTest
@testable import TokenScopeCore
import libzstd

final class DeepSeekHarnessParserTests: XCTestCase {
    func testParsesProjectionCacheAndMapsTokenBuckets() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("session_projcache_\(UUID().uuidString).json")
        let json = #"""
        {
          "unit": {"name": "session_projcache", "version": 3},
          "global": null,
          "tables": {
            "sessions": {
              "session-new": {
                "identity": {"createdAt": 1786881220963, "cwd": "/tmp/new-project"},
                "rows": {
                  "sessionStats": {"ver": 1, "seq": 10, "val": {"steps": 9}},
                  "tokenUsage": {"ver": 1, "seq": 10, "val": {
                    "totals": {
                      "uncachedInputTokens": 120,
                      "outputTokens": 30,
                      "cacheReadTokens": 400,
                      "cacheWriteTokens": 50
                    }
                  }},
                  "sessionListMetadata": {"ver": 1, "seq": 10, "val": {
                    "blank": false,
                    "lastPromptAt": 1786881427242
                  }}
                }
              },
              "session-empty": {
                "identity": {"createdAt": 1786671773620, "cwd": "/tmp/empty-project"},
                "rows": {
                  "sessionStats": {"ver": 1, "seq": 0, "val": {"steps": 0}},
                  "tokenUsage": {"ver": 1, "seq": 0, "val": {
                    "totals": {
                      "uncachedInputTokens": 0,
                      "outputTokens": 0,
                      "cacheReadTokens": 0,
                      "cacheWriteTokens": 0
                    }
                  }},
                  "sessionListMetadata": {"ver": 1, "seq": 0, "val": {
                    "blank": true,
                    "lastPromptAt": null
                  }}
                }
              }
            }
          }
        }
        """#
        try json.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let results = try DeepSeekHarnessParser().parse(fileURL: file)

        XCTAssertEqual(results.map(\.session.id), ["session-new", "session-empty"])
        let parsed = try XCTUnwrap(results.first)
        XCTAssertEqual(parsed.session.provider, .deepSeekHarness)
        XCTAssertEqual(parsed.session.projectPath, "/tmp/new-project")
        XCTAssertEqual(parsed.session.messageCount, 9)
        XCTAssertEqual(parsed.session.modelsUsed, ["DeepSeek Harness"])
        XCTAssertEqual(parsed.session.startedAt.timeIntervalSince1970, 1_786_881_220.963, accuracy: 0.001)
        XCTAssertEqual(parsed.session.endedAt.timeIntervalSince1970, 1_786_881_427.242, accuracy: 0.001)
        XCTAssertEqual(parsed.session.totalUsage.inputTokens, 120)
        XCTAssertEqual(parsed.session.totalUsage.outputTokens, 30)
        XCTAssertEqual(parsed.session.totalUsage.cacheReadTokens, 400)
        XCTAssertEqual(parsed.session.totalUsage.cacheCreationTokens, 50)
        XCTAssertEqual(parsed.session.totalUsage.totalTokens, 600)
        XCTAssertEqual(parsed.usageRecords.count, 1)
        XCTAssertEqual(parsed.usageRecords.first?.provider, .deepSeekHarness)
        XCTAssertEqual(parsed.usageRecords.first?.usage, parsed.session.totalUsage)

        let empty = try XCTUnwrap(results.last)
        XCTAssertEqual(empty.session.totalUsage, .zero)
        XCTAssertTrue(empty.usageRecords.isEmpty)
    }

    func testScannerReadsDshStorageLocation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-root-\(UUID().uuidString)", isDirectory: true)
        let storage = root.appendingPathComponent("storages", isDirectory: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let file = storage.appendingPathComponent("session_projcache.json")
        let json = #"""
        {"tables":{"sessions":{"session-one":{
          "identity":{"createdAt":1786881220963,"cwd":"/tmp/project"},
          "rows":{"tokenUsage":{"val":{"totals":{
            "uncachedInputTokens":1,"outputTokens":2,"cacheReadTokens":3,"cacheWriteTokens":4
          }}}}
        }}}}
        """#
        try json.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let results = DeepSeekHarnessScanner(root: root).scan()

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.session.id, "session-one")
        XCTAssertEqual(results.first?.session.totalUsage.totalTokens, 10)
    }

    func testParsesConcatenatedTranscriptFramesWithoutDoubleCountingChunks() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-raw-\(UUID().uuidString).jsonl.zstd")
        let frameOne = [
            #"{"type":"session","id":"session-raw","createdAt":1786881000000,"cwd":"/tmp/raw-project","delegationDepth":1,"parentSession":"session-parent"}"#,
            #"{"type":"assistant/chunk","time":1786881001000,"data":{"chunk":{"usage":{"inputTokens":10,"outputTokens":4,"cacheReadTokens":20,"reasoningTokens":3}}}}"#,
            #"{"type":"assistant/message","time":1786881001000,"data":{"message":{"id":"message-1","role":"assistant","source":{"kind":"model","provider":"deepseek-official","model":"deepseek-v4-flash"}},"usage":{"inputTokens":10,"outputTokens":4,"cacheReadTokens":20,"reasoningTokens":3}}}"#,
        ].joined(separator: "\n") + "\n"
        let frameTwo = #"{"type":"assistant/message","time":1786881002000,"data":{"message":{"id":"message-2","role":"assistant","source":{"kind":"model","provider":"kimi-coding","model":"k3"}},"usage":{"inputTokens":5,"outputTokens":2,"cacheReadTokens":0,"cacheWriteTokens":7}}}"# + "\n"
        let compressed = try compressFrame(Data(frameOne.utf8)) + compressFrame(Data(frameTwo.utf8))
        try compressed.write(to: file, options: .atomic)
        defer { try? FileManager.default.removeItem(at: file) }

        let result = try DeepSeekHarnessTranscriptParser().parse(fileURL: file)

        XCTAssertEqual(result.sessionID, "session-raw")
        XCTAssertEqual(result.projectPath, "/tmp/raw-project")
        XCTAssertEqual(result.delegationDepth, 1)
        XCTAssertEqual(result.parentSessionID, "session-parent")
        XCTAssertEqual(result.messageCount, 2)
        XCTAssertEqual(result.modelsUsed, ["deepseek-v4-flash", "k3"])
        XCTAssertEqual(result.usageRecords.map(\.model), ["deepseek-v4-flash", "k3"])
        XCTAssertEqual(result.totalUsage.inputTokens, 15)
        XCTAssertEqual(result.totalUsage.outputTokens, 6)
        XCTAssertEqual(result.totalUsage.cacheReadTokens, 20)
        XCTAssertEqual(result.totalUsage.cacheCreationTokens, 7)
        XCTAssertEqual(result.totalUsage.totalTokens, 48)
        XCTAssertEqual(result.endedAt.timeIntervalSince1970, 1_786_881_002, accuracy: 0.001)
    }

    func testScannerPrefersModelAttributedTranscriptUsageOverProjectionAggregate() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-raw-root-\(UUID().uuidString)", isDirectory: true)
        let storage = root.appendingPathComponent("storages", isDirectory: true)
        let transcriptDirectory = root
            .appendingPathComponent("sessions/project/session-joined", isDirectory: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: transcriptDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let cache = #"""
        {"tables":{"sessions":{"session-joined":{
          "identity":{"createdAt":1786881000000,"cwd":"/tmp/cache-project"},
          "rows":{
            "sessionStats":{"val":{"steps":99}},
            "tokenUsage":{"val":{"totals":{
              "uncachedInputTokens":999,"outputTokens":999,"cacheReadTokens":999,"cacheWriteTokens":999
            }}},
            "sessionListMetadata":{"val":{"lastPromptAt":1786881000500}}
          }
        }}}}
        """#
        try cache.write(
            to: storage.appendingPathComponent("session_projcache.json"),
            atomically: true,
            encoding: .utf8
        )

        let transcript = [
            #"{"type":"session","id":"session-joined","createdAt":1786881000000,"cwd":"/tmp/raw-project","delegationDepth":0}"#,
            #"{"type":"assistant/message","time":1786881001000,"data":{"message":{"id":"m1","source":{"model":"glm-5.3"}},"usage":{"inputTokens":4,"outputTokens":3,"cacheReadTokens":2}}}"#,
            #"{"type":"assistant/message","time":1786881002000,"data":{"message":{"id":"m2","source":{"model":"k3"}},"usage":{"inputTokens":8,"outputTokens":7,"cacheReadTokens":6}}}"#,
        ].joined(separator: "\n") + "\n"
        let transcriptFile = transcriptDirectory.appendingPathComponent("session.jsonl.zstd")
        try compressFrame(Data(transcript.utf8)).write(to: transcriptFile, options: .atomic)

        let results = DeepSeekHarnessScanner(root: root).scan()
        let result = try XCTUnwrap(results.first)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(result.session.modelsUsed, ["glm-5.3", "k3"])
        XCTAssertEqual(result.session.messageCount, 2)
        XCTAssertEqual(result.session.projectPath, "/tmp/raw-project")
        XCTAssertEqual(
            result.session.sourceFile.resolvingSymlinksInPath(),
            transcriptFile.resolvingSymlinksInPath()
        )
        XCTAssertEqual(result.session.totalUsage.inputTokens, 12)
        XCTAssertEqual(result.session.totalUsage.outputTokens, 10)
        XCTAssertEqual(result.session.totalUsage.cacheReadTokens, 8)
        XCTAssertEqual(result.session.totalUsage.cacheCreationTokens, 0)
        XCTAssertEqual(result.usageRecords.map(\.model), ["glm-5.3", "k3"])
    }

    private func compressFrame(_ input: Data) throws -> Data {
        var output = [UInt8](repeating: 0, count: Int(ZSTD_compressBound(input.count)))
        let written = input.withUnsafeBytes { inputBytes in
            output.withUnsafeMutableBytes { outputBytes in
                ZSTD_compress(
                    outputBytes.baseAddress,
                    outputBytes.count,
                    inputBytes.baseAddress,
                    inputBytes.count,
                    1
                )
            }
        }
        guard ZSTD_isError(written) == 0 else {
            throw NSError(domain: "DeepSeekHarnessParserTests", code: 1)
        }
        return Data(output[0..<written])
    }
}
