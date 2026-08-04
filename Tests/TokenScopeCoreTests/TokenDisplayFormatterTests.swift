import XCTest
@testable import TokenScopeCore

final class TokenDisplayFormatterTests: XCTestCase {
    func testFormatsEnglishTokenCountsInMillions() {
        XCTAssertEqual(TokenDisplayFormatter.localized(0, language: .english), "0")
        XCTAssertEqual(TokenDisplayFormatter.localized(1_000_000, language: .english), "1.00M")
        XCTAssertEqual(TokenDisplayFormatter.localized(12_345_678, language: .english), "12.3M")
        XCTAssertEqual(TokenDisplayFormatter.localized(123_456_789, language: .english), "123M")
        XCTAssertEqual(TokenDisplayFormatter.localized(1_234_567_890, language: .english), "1235M")
    }

    func testFormatsTokenCountsInHundredMillions() {
        XCTAssertEqual(TokenDisplayFormatter.hundredMillions(0), "0")
        XCTAssertEqual(TokenDisplayFormatter.hundredMillions(1_000_000), "0.01亿")
        XCTAssertEqual(TokenDisplayFormatter.hundredMillions(12_345_678), "0.12亿")
        XCTAssertEqual(TokenDisplayFormatter.hundredMillions(123_456_789), "1.23亿")
        XCTAssertEqual(TokenDisplayFormatter.hundredMillions(1_234_567_890), "12.3亿")
        XCTAssertEqual(TokenDisplayFormatter.hundredMillions(12_345_678_900), "123亿")
    }

    func testFormatsSmallNonzeroCountsWithoutRoundingToZero() {
        XCTAssertEqual(TokenDisplayFormatter.hundredMillions(10_000), "0.0001亿")
        XCTAssertEqual(TokenDisplayFormatter.hundredMillions(1_000), "<0.0001亿")
    }

    func testLocalizedFormatterKeepsChineseHundredMillionUnit() {
        XCTAssertEqual(TokenDisplayFormatter.localized(123_456_789, language: .simplifiedChinese), "1.23亿")
    }
}
