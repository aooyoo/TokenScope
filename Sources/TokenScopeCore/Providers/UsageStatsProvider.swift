import Foundation

public protocol UsageStatsProvider: Sendable {
    var provider: Provider { get }
    func fetchSnapshot() async throws -> ProviderUsageSnapshot
}
