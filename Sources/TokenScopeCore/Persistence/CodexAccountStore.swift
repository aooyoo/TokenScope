import Foundation

public enum CodexManagedAccountStoreError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
}

public protocol CodexManagedAccountStoring: Sendable {
    func loadAccounts() throws -> CodexManagedAccountSet
    func storeAccounts(_ accounts: CodexManagedAccountSet) throws
    func ensureFileExists() throws -> URL
}

public struct FileCodexManagedAccountStore: CodexManagedAccountStoring, @unchecked Sendable {
    public static let currentVersion = 1

    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL = Self.defaultURL(), fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func loadAccounts() throws -> CodexManagedAccountSet {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return Self.emptyAccountSet()
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let accounts = try decoder.decode(CodexManagedAccountSet.self, from: data)
        guard accounts.version == Self.currentVersion else {
            throw CodexManagedAccountStoreError.unsupportedVersion(accounts.version)
        }
        return CodexManagedAccountSet(version: Self.currentVersion, accounts: accounts.accounts)
    }

    public func storeAccounts(_ accounts: CodexManagedAccountSet) throws {
        let normalized = CodexManagedAccountSet(version: Self.currentVersion, accounts: accounts.accounts)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(normalized)
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try data.write(to: fileURL, options: [.atomic])
        try applySecurePermissionsIfNeeded()
    }

    public func ensureFileExists() throws -> URL {
        if fileManager.fileExists(atPath: fileURL.path) { return fileURL }
        try storeAccounts(Self.emptyAccountSet())
        return fileURL
    }

    private func applySecurePermissionsIfNeeded() throws {
        #if os(macOS)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: Int16(0o600))], ofItemAtPath: fileURL.path)
        #endif
    }

    private static func emptyAccountSet() -> CodexManagedAccountSet {
        CodexManagedAccountSet(version: Self.currentVersion, accounts: [])
    }

    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("TokenScope", isDirectory: true)
            .appendingPathComponent("codex-accounts.json")
    }
}
