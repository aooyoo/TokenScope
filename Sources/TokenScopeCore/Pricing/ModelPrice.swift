import Foundation

public struct ModelPrice: Codable, Sendable, Hashable, Identifiable {
    public enum Source: String, Codable, Sendable { case builtin, user }

    public var id: String { "\(provider.rawValue):\(model)" }
    public let provider: Provider
    public let model: String
    public let inputPerMillion: Double
    public let outputPerMillion: Double
    public let cacheReadPerMillion: Double
    public let cacheCreationPerMillion: Double
    public let currency: String
    public let source: Source

    public init(
        provider: Provider,
        model: String,
        inputPerMillion: Double,
        outputPerMillion: Double,
        cacheReadPerMillion: Double,
        cacheCreationPerMillion: Double,
        currency: String = "USD",
        source: Source = .builtin
    ) {
        self.provider = provider
        self.model = model
        self.inputPerMillion = inputPerMillion
        self.outputPerMillion = outputPerMillion
        self.cacheReadPerMillion = cacheReadPerMillion
        self.cacheCreationPerMillion = cacheCreationPerMillion
        self.currency = currency
        self.source = source
    }

    public func cost(for usage: TokenUsage) -> Double {
        let m = 1_000_000.0
        return Double(usage.inputTokens) * inputPerMillion / m
            + Double(usage.outputTokens) * outputPerMillion / m
            + Double(usage.cacheReadTokens) * cacheReadPerMillion / m
            + Double(usage.cacheCreationTokens) * cacheCreationPerMillion / m
    }
}
