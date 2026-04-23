import Foundation

public struct CodexManagedAccount: Codable, Identifiable, Sendable, Hashable {
    public let id: UUID
    public let email: String
    public let providerAccountID: String?
    public let managedHomePath: String
    public let createdAt: Date
    public let updatedAt: Date
    public let lastAuthenticatedAt: Date?

    public init(
        id: UUID,
        email: String,
        providerAccountID: String? = nil,
        managedHomePath: String,
        createdAt: Date,
        updatedAt: Date,
        lastAuthenticatedAt: Date?
    ) {
        self.id = id
        self.email = Self.normalizeEmail(email)
        self.providerAccountID = Self.normalizeProviderAccountID(providerAccountID)
        self.managedHomePath = managedHomePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastAuthenticatedAt = lastAuthenticatedAt
    }

    public static func normalizeEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func normalizeProviderAccountID(_ providerAccountID: String?) -> String? {
        guard let trimmed = providerAccountID?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed.lowercased()
    }
}

public struct CodexManagedAccountSet: Codable, Sendable {
    public let version: Int
    public let accounts: [CodexManagedAccount]

    public init(version: Int, accounts: [CodexManagedAccount]) {
        self.version = version
        self.accounts = Self.sanitized(accounts)
    }

    public func account(id: UUID) -> CodexManagedAccount? {
        accounts.first { $0.id == id }
    }

    public func account(email: String, providerAccountID: String? = nil) -> CodexManagedAccount? {
        let normalizedEmail = CodexManagedAccount.normalizeEmail(email)
        if let normalizedProviderAccountID = CodexManagedAccount.normalizeProviderAccountID(providerAccountID),
           let exact = accounts.first(where: { $0.providerAccountID == normalizedProviderAccountID }) {
            return exact
        }
        if providerAccountID != nil {
            return accounts.first { $0.email == normalizedEmail && $0.providerAccountID == nil }
        }
        return accounts.first { $0.email == normalizedEmail }
    }

    private static func sanitized(_ accounts: [CodexManagedAccount]) -> [CodexManagedAccount] {
        var seenIDs: Set<UUID> = []
        var seenProviderAccountIDs: Set<String> = []
        var seenLegacyEmails: Set<String> = []
        var sanitized: [CodexManagedAccount] = []

        for account in accounts {
            guard seenIDs.insert(account.id).inserted else { continue }
            if let providerAccountID = account.providerAccountID {
                guard seenProviderAccountIDs.insert(providerAccountID).inserted else { continue }
            } else {
                guard seenLegacyEmails.insert(account.email).inserted else { continue }
            }
            sanitized.append(account)
        }

        return sanitized.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.email < rhs.email
        }
    }
}

public enum CodexActiveSource: Codable, Equatable, Sendable, Hashable {
    case liveSystem
    case managedAccount(id: UUID)

    private enum CodingKeys: String, CodingKey {
        case kind
        case accountID
    }

    private enum Kind: String, Codable {
        case liveSystem
        case managedAccount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .liveSystem:
            self = .liveSystem
        case .managedAccount:
            self = .managedAccount(id: try container.decode(UUID.self, forKey: .accountID))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .liveSystem:
            try container.encode(Kind.liveSystem, forKey: .kind)
        case let .managedAccount(id):
            try container.encode(Kind.managedAccount, forKey: .kind)
            try container.encode(id, forKey: .accountID)
        }
    }
}
