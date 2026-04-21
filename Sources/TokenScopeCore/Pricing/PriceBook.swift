import Foundation

public final class PriceBook: @unchecked Sendable {
    private var builtin: [String: ModelPrice]
    private var userOverrides: [String: ModelPrice]
    private let storageURL: URL?

    public init(
        builtin: [ModelPrice] = BuiltinPrices.all,
        userOverrides: [ModelPrice] = [],
        storageURL: URL? = PriceBook.defaultStorageURL
    ) {
        self.builtin = Dictionary(uniqueKeysWithValues: builtin.map { ($0.model, $0) })
        self.userOverrides = Dictionary(uniqueKeysWithValues: userOverrides.map { ($0.model, $0) })
        self.storageURL = storageURL
        if userOverrides.isEmpty {
            loadFromDisk()
        }
    }

    public static var defaultStorageURL: URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base
            .appendingPathComponent("TokenScope", isDirectory: true)
            .appendingPathComponent("user_prices.json")
    }

    public func price(forModel model: String) -> ModelPrice? {
        if let override = userOverrides[model] { return override }
        if let exact = builtin[model] { return exact }
        let candidates = builtin.values.filter { model.hasPrefix($0.model) }
        return candidates.max(by: { $0.model.count < $1.model.count })
    }

    @discardableResult
    public func upsert(_ price: ModelPrice) -> ModelPrice {
        let stored = ModelPrice(
            provider: price.provider,
            model: price.model,
            inputPerMillion: price.inputPerMillion,
            outputPerMillion: price.outputPerMillion,
            cacheReadPerMillion: price.cacheReadPerMillion,
            cacheCreationPerMillion: price.cacheCreationPerMillion,
            currency: price.currency,
            source: .user
        )
        userOverrides[stored.model] = stored
        saveToDisk()
        return stored
    }

    public func remove(modelName: String) {
        userOverrides.removeValue(forKey: modelName)
        saveToDisk()
    }

    public func resetUserOverrides() {
        userOverrides.removeAll()
        saveToDisk()
    }

    public func isUserOverride(model: String) -> Bool {
        userOverrides[model] != nil
    }

    public func cost(for usage: TokenUsage, model: String) -> Double {
        price(forModel: model)?.cost(for: usage) ?? 0
    }

    public func listAll() -> [ModelPrice] {
        var merged = builtin
        for (k, v) in userOverrides { merged[k] = v }
        return merged.values.sorted { lhs, rhs in
            if lhs.provider != rhs.provider {
                return lhs.provider.rawValue < rhs.provider.rawValue
            }
            return lhs.model < rhs.model
        }
    }

    public func listUserOverrides() -> [ModelPrice] {
        userOverrides.values.sorted { $0.model < $1.model }
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard let url = storageURL,
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([ModelPrice].self, from: data)
        else { return }
        for p in items {
            userOverrides[p.model] = ModelPrice(
                provider: p.provider,
                model: p.model,
                inputPerMillion: p.inputPerMillion,
                outputPerMillion: p.outputPerMillion,
                cacheReadPerMillion: p.cacheReadPerMillion,
                cacheCreationPerMillion: p.cacheCreationPerMillion,
                currency: p.currency,
                source: .user
            )
        }
    }

    private func saveToDisk() {
        guard let url = storageURL else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let items = Array(userOverrides.values)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(items) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
