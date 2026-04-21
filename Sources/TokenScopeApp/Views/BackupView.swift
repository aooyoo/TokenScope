import SwiftUI

struct BackupView: View {
    var body: some View {
        ContentUnavailableView(
            "Backup (coming in P2)",
            systemImage: "externaldrive.badge.timemachine",
            description: Text("Incremental backup of Claude Code and Codex sessions keyed by session id.")
        )
        .navigationTitle("Backup")
    }
}
