import SwiftUI
import AppKit
import TokenScopeCore

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var zaiAPIKey = ""
    @State private var zaiRegion: ZaiAPIRegion = .global
    @State private var codexLoginError: String?
    @State private var isAddingCodexAccount = false

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

            Section("Usage Providers") {
                SecureField("z.ai API Key", text: $zaiAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveZaiAPIKey)
                HStack {
                    Picker("z.ai Region", selection: $zaiRegion) {
                        ForEach(ZaiAPIRegion.allCases, id: \.self) { region in
                            Text(region.displayName).tag(region)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: zaiRegion) { _, newValue in
                        store.usageSettings.zaiRegion = newValue
                        Task { await store.refreshUsage(for: .zai) }
                    }
                    Button("Save") { saveZaiAPIKey() }
                }
                LabeledContent("Claude Code", value: providerStatusText(.claudeCode))
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Codex", value: providerStatusText(.codex))
                    HStack {
                        Picker("Codex Account", selection: codexAccountBinding) {
                            Text("System account").tag("live-system")
                            ForEach(store.usageSettings.codexAccounts, id: \.id) { account in
                                Text(account.email).tag(account.id.uuidString)
                            }
                        }
                        .pickerStyle(.menu)
                        Button(isAddingCodexAccount ? "Signing in…" : "Add Account") {
                            addCodexAccount()
                        }
                        .disabled(isAddingCodexAccount)
                    }
                    if let codexLoginError {
                        Text(codexLoginError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                LabeledContent("z.ai", value: store.usageSettings.hasZaiAPIKey() ? "Configured" : "Missing API key")
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
        .onAppear {
            zaiAPIKey = store.usageSettings.loadZaiAPIKey()
            zaiRegion = store.usageSettings.zaiRegion
        }
    }

    private var codexAccountBinding: Binding<String> {
        Binding(
            get: {
                switch store.usageSettings.codexActiveSource {
                case .liveSystem:
                    return "live-system"
                case let .managedAccount(id):
                    return id.uuidString
                }
            },
            set: { newValue in
                codexLoginError = nil
                Task {
                    if newValue == "live-system" {
                        await store.setCodexActiveAccount(id: nil)
                    } else if let uuid = UUID(uuidString: newValue) {
                        await store.setCodexActiveAccount(id: uuid)
                    }
                }
            }
        )
    }

    private func saveZaiAPIKey() {
        store.usageSettings.saveZaiAPIKey(zaiAPIKey)
        Task { await store.refreshUsage(for: .zai) }
    }

    private func addCodexAccount() {
        codexLoginError = nil
        isAddingCodexAccount = true
        Task {
            do {
                try await store.addCodexAccount()
            } catch {
                codexLoginError = error.localizedDescription
            }
            isAddingCodexAccount = false
        }
    }

    private func providerStatusText(_ provider: Provider) -> String {
        switch store.usageRefreshStates[provider] ?? .idle {
        case .idle:
            return store.providerUsageSnapshots[provider] == nil ? "Not refreshed" : "Cached"
        case .loading:
            return "Refreshing..."
        case .loaded:
            return "Ready"
        case .failed:
            return store.usageErrors[provider] ?? "Failed"
        }
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
