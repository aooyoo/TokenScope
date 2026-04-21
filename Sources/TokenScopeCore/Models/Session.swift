import Foundation

public struct SessionMessage: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let role: String
    public let model: String?
    public let usage: TokenUsage
    public let timestamp: Date
    public let contentText: String?
    public let contentPreview: String?

    public init(
        id: String,
        role: String,
        model: String?,
        usage: TokenUsage,
        timestamp: Date,
        contentText: String? = nil,
        contentPreview: String? = nil
    ) {
        self.id = id
        self.role = role
        self.model = model
        self.usage = usage
        self.timestamp = timestamp
        self.contentText = contentText
        self.contentPreview = contentPreview
    }
}

public enum SessionDetailMode: String, Codable, Sendable, Hashable {
    case messages
    case usageOnly
}

public struct SessionDetail: Sendable, Identifiable {
    public var id: String { "\(session.provider.rawValue):\(session.id)" }
    public let session: SessionRecord
    public let mode: SessionDetailMode
    public let messages: [SessionMessage]
    public let usageRecords: [UsageRecord]
    public let notice: String?

    public init(
        session: SessionRecord,
        mode: SessionDetailMode,
        messages: [SessionMessage] = [],
        usageRecords: [UsageRecord] = [],
        notice: String? = nil
    ) {
        self.session = session
        self.mode = mode
        self.messages = messages
        self.usageRecords = usageRecords
        self.notice = notice
    }
}

public struct SessionRecord: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let provider: Provider
    public let accountId: String?
    public let projectPath: String?
    public let sourceFile: URL
    public let startedAt: Date
    public let endedAt: Date
    public let modelsUsed: [String]
    public let totalUsage: TokenUsage
    public let messageCount: Int

    public init(
        id: String,
        provider: Provider,
        accountId: String?,
        projectPath: String?,
        sourceFile: URL,
        startedAt: Date,
        endedAt: Date,
        modelsUsed: [String],
        totalUsage: TokenUsage,
        messageCount: Int
    ) {
        self.id = id
        self.provider = provider
        self.accountId = accountId
        self.projectPath = projectPath
        self.sourceFile = sourceFile
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.modelsUsed = modelsUsed
        self.totalUsage = totalUsage
        self.messageCount = messageCount
    }
}
