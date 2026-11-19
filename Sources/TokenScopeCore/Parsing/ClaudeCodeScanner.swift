import Foundation

public struct ClaudeCodeScanner: Sendable {
    public let root: URL
    public let desktopRoots: [URL]
    public let parser: ClaudeCodeParser

    public init(root: URL? = nil, desktopRoots: [URL]? = nil, parser: ClaudeCodeParser = ClaudeCodeParser()) {
        if let root { self.root = root } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.root = home.appendingPathComponent(".claude/projects", isDirectory: true)
        }
        // Explicit roots remain isolated for imports and tests.
        self.desktopRoots = desktopRoots ?? (root == nil ? Self.defaultDesktopRoots : [])
        self.parser = parser
    }

    public static var defaultDesktopRoots: [URL] {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return ["Claude", "Claude-3p"].flatMap { app in
            ["local-agent-mode-sessions", "claude-code-sessions"].map { store in
                support.appendingPathComponent(app, isDirectory: true)
                    .appendingPathComponent(store, isDirectory: true)
            }
        }
    }

    public func scan() -> [ClaudeCodeParseResult] {
        let chatIDs = desktopChatSessionIDs()
        var byID: [String: ClaudeCodeParseResult] = [:]
        for parsed in scanProjects(at: root) {
            let result = resolvingChatID(parsed, aliases: chatIDs)
            byID[result.session.id] = result
        }
        var visitedRoots: Set<String> = []
        for desktopRoot in desktopRoots {
            let resolved = desktopRoot.resolvingSymlinksInPath().standardizedFileURL
            guard visitedRoots.insert(resolved.path).inserted else { continue }
            for parsed in scanDesktop(at: resolved) {
                let result = resolvingChatID(parsed, aliases: chatIDs)
                if let existing = byID[result.session.id] {
                    let existingPriority = sourcePriority(existing.session.sourceFile)
                    let incomingPriority = sourcePriority(result.session.sourceFile)
                    if existingPriority > incomingPriority { continue }
                    if existingPriority == incomingPriority,
                       existing.session.totalUsage.totalTokens >= result.session.totalUsage.totalTokens { continue }
                }
                byID[result.session.id] = result
            }
        }
        return byID.values.sorted { $0.session.startedAt > $1.session.startedAt }
    }

    private func scanProjects(at root: URL) -> [ClaudeCodeParseResult] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }

        var results: [ClaudeCodeParseResult] = []
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            do {
                let res = try parser.parse(fileURL: url)
                results.append(res)
            } catch {
                continue
            }
        }
        return results
    }

    private func scanDesktop(at root: URL) -> [ClaudeCodeParseResult] {
        let fm = FileManager.default
        let desktopParser = ClaudeDesktopParser()
        var results: [ClaudeCodeParseResult] = []
        var pending: [(url: URL, depth: Int)] = [(root, 0)]
        while let (directory, depth) = pending.popLast() {
            if directory.lastPathComponent == "usage-ledger" {
                results.append(contentsOf: ClaudeDesktopChatLedgerParser().parse(directory: directory))
                continue
            }
            let audit = directory.appendingPathComponent("audit.jsonl")
            let projects = directory.appendingPathComponent(".claude/projects", isDirectory: true)
            let hasAudit = fm.fileExists(atPath: audit.path)
            let hasProjects = fm.fileExists(atPath: projects.path)
            if hasAudit || hasProjects {
                if let result = try? desktopParser.parse(fileURL: audit), !result.usageRecords.isEmpty {
                    // SDK totals include the embedded transcript and subagents.
                    results.append(result)
                } else {
                    results.append(contentsOf: scanProjects(at: projects))
                }
                continue
            }
            // Stores have account/org/session levels. Do not recurse through
            // workspace outputs, plugins, caches, or mounted user folders.
            guard depth < 3 else { continue }
            let children = (try? fm.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for child in children.sorted(by: { $0.path < $1.path }) {
                guard !["skills-plugin", "cowork_plugins", "node_modules", "rpm", "memory"].contains(child.lastPathComponent),
                      let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory == true, values.isSymbolicLink != true
                else { continue }
                pending.append((child, depth + 1))
            }
        }
        return results
    }

    private func sourcePriority(_ file: URL) -> Int {
        if file.lastPathComponent == "audit.jsonl" { return 2 }
        if file.pathExtension == "ndjson", file.deletingLastPathComponent().lastPathComponent == "usage-ledger" { return 1 }
        return 0
    }

    private func desktopChatSessionIDs() -> [String: String] {
        var aliases: [String: String] = [:]
        let fm = FileManager.default
        for root in desktopRoots {
            var pending: [(URL, Int)] = [(root, 0)]
            while let (directory, depth) = pending.popLast() {
                let children = (try? fm.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                for file in children {
                    if file.pathExtension == "json",
                       let data = try? Data(contentsOf: file),
                       let metadata = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       metadata["sessionType"] as? String == "chat",
                       let localID = metadata["sessionId"] as? String, !localID.isEmpty,
                       let cliID = metadata["cliSessionId"] as? String, !cliID.isEmpty {
                        aliases[cliID] = localID
                    }
                    guard depth < 2,
                          !["skills-plugin", "cowork_plugins", "node_modules", "rpm", "memory"].contains(file.lastPathComponent),
                          let values = try? file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                          values.isDirectory == true, values.isSymbolicLink != true else { continue }
                    pending.append((file, depth + 1))
                }
            }
        }
        return aliases
    }

    private func resolvingChatID(_ result: ClaudeCodeParseResult, aliases: [String: String]) -> ClaudeCodeParseResult {
        let session = result.session
        guard let id = aliases[session.id], id != session.id else { return result }
        // Desktop IDs also appear in the retained Chat ledger. Keep them
        // stable when the transcript and metadata are later deleted.
        let resolved = SessionRecord(
            id: id, provider: session.provider, accountId: session.accountId, projectPath: session.projectPath,
            sourceFile: session.sourceFile, startedAt: session.startedAt, endedAt: session.endedAt,
            modelsUsed: session.modelsUsed, totalUsage: session.totalUsage, messageCount: session.messageCount
        )
        let records = result.usageRecords.map {
            UsageRecord(sessionId: id, messageIndex: $0.messageIndex, provider: $0.provider,
                        accountId: $0.accountId, model: $0.model, timestamp: $0.timestamp, usage: $0.usage)
        }
        return ClaudeCodeParseResult(session: resolved, usageRecords: records)
    }
}
