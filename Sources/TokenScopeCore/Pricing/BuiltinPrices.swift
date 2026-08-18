import Foundation

public enum BuiltinPrices {
    public static let all: [ModelPrice] = [
        // Public list prices as of August 2026, USD per 1M tokens.
        // Anthropic Claude
        ModelPrice(
            provider: .anthropicAPI, model: "claude-fable-5",
            inputPerMillion: 10.0, outputPerMillion: 50.0,
            cacheReadPerMillion: 1.0, cacheCreationPerMillion: 12.5
        ),
        ModelPrice(
            provider: .anthropicAPI, model: "claude-mythos-5",
            inputPerMillion: 10.0, outputPerMillion: 50.0,
            cacheReadPerMillion: 1.0, cacheCreationPerMillion: 12.5
        ),
        ModelPrice(
            provider: .anthropicAPI, model: "claude-opus-4",
            inputPerMillion: 15.0, outputPerMillion: 75.0,
            cacheReadPerMillion: 1.5, cacheCreationPerMillion: 18.75
        ),
        ModelPrice(
            provider: .anthropicAPI, model: "claude-opus-4-5",
            inputPerMillion: 5.0, outputPerMillion: 25.0,
            cacheReadPerMillion: 0.5, cacheCreationPerMillion: 6.25
        ),
        ModelPrice(
            provider: .anthropicAPI, model: "claude-opus-4-6",
            inputPerMillion: 5.0, outputPerMillion: 25.0,
            cacheReadPerMillion: 0.5, cacheCreationPerMillion: 6.25
        ),
        ModelPrice(
            provider: .anthropicAPI, model: "claude-opus-4-7",
            inputPerMillion: 5.0, outputPerMillion: 25.0,
            cacheReadPerMillion: 0.5, cacheCreationPerMillion: 6.25
        ),
        ModelPrice(
            provider: .anthropicAPI, model: "claude-opus-4-8",
            inputPerMillion: 5.0, outputPerMillion: 25.0,
            cacheReadPerMillion: 0.5, cacheCreationPerMillion: 6.25
        ),
        ModelPrice(
            provider: .anthropicAPI, model: "claude-opus-5",
            inputPerMillion: 5.0, outputPerMillion: 25.0,
            cacheReadPerMillion: 0.5, cacheCreationPerMillion: 6.25
        ),
        ModelPrice(
            provider: .anthropicAPI, model: "claude-sonnet-4",
            inputPerMillion: 3.0, outputPerMillion: 15.0,
            cacheReadPerMillion: 0.3, cacheCreationPerMillion: 3.75
        ),
        ModelPrice(
            provider: .anthropicAPI, model: "claude-sonnet-4-5",
            inputPerMillion: 3.0, outputPerMillion: 15.0,
            cacheReadPerMillion: 0.3, cacheCreationPerMillion: 3.75
        ),
        ModelPrice(
            provider: .anthropicAPI, model: "claude-sonnet-4-6",
            inputPerMillion: 3.0, outputPerMillion: 15.0,
            cacheReadPerMillion: 0.3, cacheCreationPerMillion: 3.75
        ),
        ModelPrice(
            provider: .anthropicAPI, model: "claude-sonnet-5",
            inputPerMillion: 2.0, outputPerMillion: 10.0,
            cacheReadPerMillion: 0.2, cacheCreationPerMillion: 2.5
        ),
        ModelPrice(
            provider: .anthropicAPI, model: "claude-haiku-4-5",
            inputPerMillion: 1.0, outputPerMillion: 5.0,
            cacheReadPerMillion: 0.1, cacheCreationPerMillion: 1.25
        ),
        // OpenAI GPT-5 family
        ModelPrice(
            provider: .openAIAPI, model: "gpt-5",
            inputPerMillion: 1.25, outputPerMillion: 10.0,
            cacheReadPerMillion: 0.125, cacheCreationPerMillion: 0.0
        ),
        ModelPrice(
            provider: .openAIAPI, model: "gpt-5-codex",
            inputPerMillion: 1.25, outputPerMillion: 10.0,
            cacheReadPerMillion: 0.125, cacheCreationPerMillion: 0.0
        ),
        ModelPrice(
            provider: .openAIAPI, model: "gpt-5.2",
            inputPerMillion: 1.75, outputPerMillion: 14.0,
            cacheReadPerMillion: 0.175, cacheCreationPerMillion: 0.0
        ),
        ModelPrice(
            provider: .openAIAPI, model: "gpt-5.2-codex",
            inputPerMillion: 1.75, outputPerMillion: 14.0,
            cacheReadPerMillion: 0.175, cacheCreationPerMillion: 0.0
        ),
        ModelPrice(
            provider: .openAIAPI, model: "gpt-5.3",
            inputPerMillion: 1.75, outputPerMillion: 14.0,
            cacheReadPerMillion: 0.175, cacheCreationPerMillion: 0.0
        ),
        ModelPrice(
            provider: .openAIAPI, model: "gpt-5.3-codex",
            inputPerMillion: 1.75, outputPerMillion: 14.0,
            cacheReadPerMillion: 0.175, cacheCreationPerMillion: 0.0
        ),
        ModelPrice(
            provider: .openAIAPI, model: "gpt-5.4",
            inputPerMillion: 2.5, outputPerMillion: 15.0,
            cacheReadPerMillion: 0.25, cacheCreationPerMillion: 0.0
        ),
        ModelPrice(
            provider: .openAIAPI, model: "gpt-5.4-mini",
            inputPerMillion: 0.75, outputPerMillion: 4.5,
            cacheReadPerMillion: 0.075, cacheCreationPerMillion: 0.0
        ),
        ModelPrice(
            provider: .openAIAPI, model: "gpt-5.4-nano",
            inputPerMillion: 0.2, outputPerMillion: 1.25,
            cacheReadPerMillion: 0.02, cacheCreationPerMillion: 0.0
        ),
        ModelPrice(
            provider: .openAIAPI, model: "gpt-5.5",
            inputPerMillion: 5.0, outputPerMillion: 30.0,
            cacheReadPerMillion: 0.5, cacheCreationPerMillion: 0.0
        ),
        ModelPrice(
            provider: .openAIAPI, model: "gpt-5.6",
            inputPerMillion: 5.0, outputPerMillion: 30.0,
            cacheReadPerMillion: 0.5, cacheCreationPerMillion: 6.25
        ),
        ModelPrice(
            provider: .openAIAPI, model: "gpt-5.6-sol",
            inputPerMillion: 5.0, outputPerMillion: 30.0,
            cacheReadPerMillion: 0.5, cacheCreationPerMillion: 6.25
        ),
        ModelPrice(
            provider: .openAIAPI, model: "gpt-5.6-terra",
            inputPerMillion: 2.0, outputPerMillion: 12.0,
            cacheReadPerMillion: 0.2, cacheCreationPerMillion: 2.5
        ),
        ModelPrice(
            provider: .openAIAPI, model: "gpt-5.6-luna",
            inputPerMillion: 0.2, outputPerMillion: 1.2,
            cacheReadPerMillion: 0.02, cacheCreationPerMillion: 0.25
        ),
        // GLM
        ModelPrice(
            provider: .glmAPI, model: "glm-4.5",
            inputPerMillion: 0.6, outputPerMillion: 2.2,
            cacheReadPerMillion: 0.11, cacheCreationPerMillion: 0.0
        ),
        ModelPrice(
            provider: .glmAPI, model: "glm-4.6",
            inputPerMillion: 0.6, outputPerMillion: 2.2,
            cacheReadPerMillion: 0.11, cacheCreationPerMillion: 0.0
        ),
        ModelPrice(
            provider: .glmAPI, model: "glm-4.7",
            inputPerMillion: 0.6, outputPerMillion: 2.2,
            cacheReadPerMillion: 0.11, cacheCreationPerMillion: 0.0
        ),
        ModelPrice(
            provider: .glmAPI, model: "glm-5",
            inputPerMillion: 1.0, outputPerMillion: 3.2,
            cacheReadPerMillion: 0.2, cacheCreationPerMillion: 0.0
        ),
        ModelPrice(
            provider: .glmAPI, model: "glm-5-turbo",
            inputPerMillion: 1.2, outputPerMillion: 4.0,
            cacheReadPerMillion: 0.24, cacheCreationPerMillion: 0.0
        ),
        ModelPrice(
            provider: .glmAPI, model: "glm-5.1",
            inputPerMillion: 1.4, outputPerMillion: 4.4,
            cacheReadPerMillion: 0.26, cacheCreationPerMillion: 0.0
        ),
        ModelPrice(
            provider: .glmAPI, model: "glm-5.2",
            inputPerMillion: 1.4, outputPerMillion: 4.4,
            cacheReadPerMillion: 0.26, cacheCreationPerMillion: 0.0
        ),
        ModelPrice(
            provider: .glmAPI, model: "glm-5v-turbo",
            inputPerMillion: 1.2, outputPerMillion: 4.0,
            cacheReadPerMillion: 0.24, cacheCreationPerMillion: 0.0
        ),
        // Moonshot Kimi
        ModelPrice(
            provider: .moonshotAPI, model: "kimi-k2.6",
            inputPerMillion: 0.95, outputPerMillion: 4.0,
            cacheReadPerMillion: 0.16, cacheCreationPerMillion: 0.0
        ),
        ModelPrice(
            provider: .moonshotAPI, model: "kimi-k2.7-code",
            inputPerMillion: 0.95, outputPerMillion: 4.0,
            cacheReadPerMillion: 0.19, cacheCreationPerMillion: 0.0
        ),
        ModelPrice(
            provider: .moonshotAPI, model: "kimi-k2.7-code-highspeed",
            inputPerMillion: 1.9, outputPerMillion: 8.0,
            cacheReadPerMillion: 0.38, cacheCreationPerMillion: 0.0
        ),
        ModelPrice(
            provider: .moonshotAPI, model: "kimi-k3",
            inputPerMillion: 3.0, outputPerMillion: 15.0,
            cacheReadPerMillion: 0.3, cacheCreationPerMillion: 0.0
        ),
        // MiniMax
        ModelPrice(
            provider: .miniMaxAPI, model: "MiniMax-M3",
            inputPerMillion: 0.3, outputPerMillion: 1.2,
            cacheReadPerMillion: 0.06, cacheCreationPerMillion: 0.0
        ),
        // Tencent TokenHub
        ModelPrice(
            provider: .tencentTokenHub, model: "hy3",
            inputPerMillion: 0.132, outputPerMillion: 0.528,
            cacheReadPerMillion: 0.033, cacheCreationPerMillion: 0.0
        ),
    ]

    public static var byModelPrefix: [(prefix: String, price: ModelPrice)] {
        all.map { ($0.model, $0) }
    }
}
