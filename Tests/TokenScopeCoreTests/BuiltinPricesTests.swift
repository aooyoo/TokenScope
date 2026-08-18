import XCTest
@testable import TokenScopeCore

final class BuiltinPricesTests: XCTestCase {
    func testLatestModelsAreIncluded() throws {
        let book = PriceBook(storageURL: nil)
        let expected: [(String, Provider, Double, Double, Double, Double)] = [
            ("claude-fable-5", .anthropicAPI, 10.0, 50.0, 1.0, 12.5),
            ("claude-opus-5", .anthropicAPI, 5.0, 25.0, 0.5, 6.25),
            ("claude-sonnet-5", .anthropicAPI, 2.0, 10.0, 0.2, 2.5),
            ("gpt-5.6-sol", .openAIAPI, 5.0, 30.0, 0.5, 6.25),
            ("gpt-5.6-terra", .openAIAPI, 2.0, 12.0, 0.2, 2.5),
            ("gpt-5.6-luna", .openAIAPI, 0.2, 1.2, 0.02, 0.25),
            ("glm-5.2", .glmAPI, 1.4, 4.4, 0.26, 0.0),
            ("kimi-k3", .moonshotAPI, 3.0, 15.0, 0.3, 0.0),
            ("MiniMax-M3", .miniMaxAPI, 0.3, 1.2, 0.06, 0.0),
            ("hy3", .tencentTokenHub, 0.132, 0.528, 0.033, 0.0),
        ]

        for (model, provider, input, output, cacheRead, cacheCreation) in expected {
            let price = try XCTUnwrap(book.price(forModel: model), "Missing price for \(model)")
            XCTAssertEqual(price.provider, provider)
            XCTAssertEqual(price.inputPerMillion, input, accuracy: 0.000_001)
            XCTAssertEqual(price.outputPerMillion, output, accuracy: 0.000_001)
            XCTAssertEqual(price.cacheReadPerMillion, cacheRead, accuracy: 0.000_001)
            XCTAssertEqual(price.cacheCreationPerMillion, cacheCreation, accuracy: 0.000_001)
        }
    }

    func testLongestPrefixSelectsSpecificGPT56Tier() throws {
        let book = PriceBook(storageURL: nil)
        let price = try XCTUnwrap(book.price(forModel: "gpt-5.6-terra-2026-08-01"))

        XCTAssertEqual(price.model, "gpt-5.6-terra")
    }

    func testBuiltinModelIdentifiersAreUnique() {
        let modelIDs = BuiltinPrices.all.map(\.model)
        XCTAssertEqual(Set(modelIDs).count, modelIDs.count)
    }
}
