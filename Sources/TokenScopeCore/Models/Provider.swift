import Foundation

public enum Provider: String, Codable, CaseIterable, Sendable, Hashable {
    case claudeCode = "claude_code"
    case codex = "codex"
    case openCode = "opencode"
    case glmPlan = "glm_plan"
    case openAIAPI = "openai_api"
    case anthropicAPI = "anthropic_api"
    case glmAPI = "glm_api"

    public var isSubscriptionPlan: Bool {
        switch self {
        case .claudeCode, .codex, .openCode, .glmPlan: return true
        case .openAIAPI, .anthropicAPI, .glmAPI: return false
        }
    }

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .openCode: return "OpenCode"
        case .glmPlan: return "GLM Coding Plan"
        case .openAIAPI: return "OpenAI API"
        case .anthropicAPI: return "Anthropic API"
        case .glmAPI: return "GLM API"
        }
    }
}

public struct Account: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let provider: Provider
    public let identifier: String
    public let displayName: String

    public init(id: String, provider: Provider, identifier: String, displayName: String) {
        self.id = id
        self.provider = provider
        self.identifier = identifier
        self.displayName = displayName
    }
}
