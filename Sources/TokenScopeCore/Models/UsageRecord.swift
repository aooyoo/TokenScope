import Foundation

public struct UsageRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(sessionId)#\(messageIndex)" }
    public let sessionId: String
    public let messageIndex: Int
    public let provider: Provider
    public let accountId: String?
    public let model: String
    public let timestamp: Date
    public let usage: TokenUsage

    public init(
        sessionId: String,
        messageIndex: Int,
        provider: Provider,
        accountId: String?,
        model: String,
        timestamp: Date,
        usage: TokenUsage
    ) {
        self.sessionId = sessionId
        self.messageIndex = messageIndex
        self.provider = provider
        self.accountId = accountId
        self.model = model
        self.timestamp = timestamp
        self.usage = usage
    }
}
