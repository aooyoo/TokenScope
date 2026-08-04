import Foundation
import XCTest
@testable import TokenScopeCore

final class CodexOAuthUsageTests: XCTestCase {
    func testDecodesSnakeCaseRateLimitWindows() throws {
        let response = try JSONDecoder().decode(CodexUsageResponse.self, from: Data(Self.usageJSON.utf8))

        XCTAssertEqual(response.rateLimit?.primaryWindow?.usedPercent, 22)
        XCTAssertEqual(response.rateLimit?.primaryWindow?.limitWindowSeconds, 18_000)
        XCTAssertEqual(response.rateLimit?.secondaryWindow?.usedPercent, 43)
        XCTAssertEqual(response.rateLimit?.secondaryWindow?.limitWindowSeconds, 604_800)
    }

    func testBuildsVisibleUsageWindowsFromCodexResponse() throws {
        let response = try JSONDecoder().decode(CodexUsageResponse.self, from: Data(Self.usageJSON.utf8))
        let credentials = CodexOAuthCredentials(
            accessToken: "access",
            refreshToken: "refresh",
            idToken: nil,
            accountId: nil,
            lastRefresh: nil
        )

        let snapshot = CodexOAuthSnapshotBuilder.build(
            response: response,
            credentials: credentials,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(snapshot.windows.map(\.id), ["session", "weekly"])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [22, 43])
        XCTAssertEqual(snapshot.windows.map(\.resetsAt), [
            Date(timeIntervalSince1970: 1_766_948_068),
            Date(timeIntervalSince1970: 1_767_407_914),
        ])
    }

    private static let usageJSON = #"""
    {
      "plan_type": "pro",
      "rate_limit": {
        "primary_window": {
          "used_percent": 22,
          "reset_at": 1766948068,
          "limit_window_seconds": 18000
        },
        "secondary_window": {
          "used_percent": 43,
          "reset_at": 1767407914,
          "limit_window_seconds": 604800
        }
      }
    }
    """#
}
