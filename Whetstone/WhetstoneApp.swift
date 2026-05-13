import SwiftUI

@main
struct WhetstoneApp: App {
    @StateObject private var auth  = AuthManager()
    @StateObject private var store = ConversationStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isAuthenticated {
                    DrawerContainer {
                        ChatView()
                    }
                } else {
                    LoginView()
                }
            }
            .environmentObject(store)
            .environmentObject(auth)
            .task(id: auth.isAuthenticated) {
                await store.applyAuthenticatedTransition(isAuthenticated: auth.isAuthenticated)
            }
        }
    }
}
