import Foundation

public enum BuiltinPrices {
    public static let all: [ModelPrice] = [
        // Anthropic Claude — public list prices, USD per 1M tokens
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
            inputPerMillion: 0.875, outputPerMillion: 7.0,
            cacheReadPerMillion: 0.175, cacheCreationPerMillion: 0.0
        ),
        ModelPrice(
            provider: .openAIAPI, model: "gpt-5.2-codex",
            inputPerMillion: 0.875, outputPerMillion: 7.0,
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
    ]

    public static var byModelPrefix: [(prefix: String, price: ModelPrice)] {
        all.map { ($0.model, $0) }
    }
}
