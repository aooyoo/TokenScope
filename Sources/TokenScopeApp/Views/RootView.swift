import SwiftUI
import TokenScopeCore

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard, sessions, pricing, backup, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .sessions: return "Sessions"
        case .pricing: return "Pricing"
        case .backup: return "Backup"
        case .settings: return "Settings"
        }
    }
    var systemImage: String {
        switch self {
        case .dashboard: return "chart.bar.xaxis"
        case .sessions: return "list.bullet.rectangle"
        case .pricing: return "dollarsign.circle"
        case .backup: return "externaldrive.badge.timemachine"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var selection: SidebarItem? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.systemImage).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            switch selection ?? .dashboard {
            case .dashboard: DashboardView()
            case .sessions: SessionsView()
            case .pricing: PricingView()
            case .backup: BackupView()
            case .settings: SettingsView()
            }
        }
    }
}
