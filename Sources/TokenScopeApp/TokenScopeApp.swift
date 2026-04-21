import SwiftUI
import TokenScopeCore

@main
struct TokenScopeApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup("TokenScope") {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 1000, minHeight: 640)
                .task {
                    store.loadCached()
                    await store.loadAll()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
