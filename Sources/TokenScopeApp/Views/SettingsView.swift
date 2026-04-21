import SwiftUI
import TokenScopeCore

struct SettingsView: View {
    var body: some View {
        Form {
            Section("About") {
                LabeledContent("Version", value: TokenScopeCore.version)
                LabeledContent("Claude data dir", value: "~/.claude/projects")
                LabeledContent("Codex data dir", value: "~/.codex/sessions")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}
