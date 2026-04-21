import SwiftUI
import AppKit
import TokenScopeCore

struct SettingsView: View {
    private let home = FileManager.default.homeDirectoryForCurrentUser

    private var claudeDataDir: URL {
        home.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    private var codexDataDir: URL {
        home.appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    private var openCodeDataDir: URL {
        home.appendingPathComponent(".local/share/opencode/storage", isDirectory: true)
    }

    private var localCacheDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("TokenScope", isDirectory: true)
    }

    var body: some View {
        Form {
            Section("About") {
                LabeledContent("Version", value: TokenScopeCore.version)
            }

            Section("Directories") {
                SettingsPathRow(title: "Claude Code data dir", url: claudeDataDir)
                SettingsPathRow(title: "Codex data dir", url: codexDataDir)
                SettingsPathRow(title: "OpenCode data dir", url: openCodeDataDir)
                SettingsPathRow(title: "Local cache dir", url: localCacheDir)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}

private struct SettingsPathRow: View {
    let title: String
    let url: URL

    var body: some View {
        LabeledContent(title) {
            Button(url.path) {
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.link)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(url.path)
        }
    }
}
