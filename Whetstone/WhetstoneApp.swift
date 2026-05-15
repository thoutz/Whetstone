import SwiftUI

@main
struct WhetstoneApp: App {

    @StateObject private var auth: AuthManager
    @StateObject private var agentModeStore: AgentModeStore
    @StateObject private var store: ConversationStore

    init() {
        let authMgr = AuthManager()
        let modeStore = AgentModeStore()
        _auth = StateObject(wrappedValue: authMgr)
        _agentModeStore = StateObject(wrappedValue: modeStore)
        _store = StateObject(wrappedValue: ConversationStore(agentModeStore: modeStore, auth: authMgr))
    }

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
            .environmentObject(agentModeStore)
            .task(id: auth.isAuthenticated) {
                await store.applyAuthenticatedTransition(isAuthenticated: auth.isAuthenticated)
                if auth.isAuthenticated {
                    await auth.refreshEntitlementFromSession()
                }
            }
            .task(id: auth.isAdvancedUser) {
                agentModeStore.revertToStandardIfNotEntitled(isAdvancedUser: auth.isAdvancedUser)
            }
        }
    }
}
