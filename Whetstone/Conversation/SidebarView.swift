import SwiftUI

// MARK: - Root drawer wrapper (lives at the top of the view hierarchy)

struct DrawerContainer<Content: View>: View {
    @EnvironmentObject var store: ConversationStore
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .leading) {
            content

            if store.sidebarOpen {
                // Dim overlay
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                            store.sidebarOpen = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)

                // Sidebar panel
                SidebarView()
                    .frame(width: sidebarWidth)
                    .transition(.move(edge: .leading))
                    .zIndex(2)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: store.sidebarOpen)
        // Swipe right anywhere to open. Use simultaneousGesture so vertical pans favor the chat
        // ScrollView (keyboard dismiss on scroll, etc.); the drag still receives its onEnded.
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { v in
                    if !store.sidebarOpen && v.translation.width > 60
                        && abs(v.translation.height) < 100 {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                            store.sidebarOpen = true
                        }
                    } else if store.sidebarOpen && v.translation.width < -60 {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                            store.sidebarOpen = false
                        }
                    }
                }
        )
    }

    private var sidebarWidth: CGFloat {
        min(UIScreen.main.bounds.width * 0.82, 320)
    }
}

// MARK: - Sidebar panel content

struct SidebarView: View {
    @EnvironmentObject var store: ConversationStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(WhetstoneTheme.blade.opacity(0.15))
            conversationList
        }
        .background(Color(hex: "0b0e14"))
        .ignoresSafeArea(edges: .vertical)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("WHETSTONE")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .tracking(3)
                .foregroundStyle(WhetstoneTheme.blade.opacity(0.85))

            Spacer()

            Button {
                store.newConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 60)
        .padding(.bottom, 14)
    }

    // MARK: Conversation list

    private var conversationList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if store.conversations.filter({ !$0.isEmpty }).isEmpty {
                    emptyState
                } else {
                    ForEach(store.grouped, id: \.label) { group in
                        if !group.items.filter({ !$0.isEmpty }).isEmpty {
                            sectionHeader(group.label)
                            ForEach(group.items.filter { !$0.isEmpty }) { conv in
                                ConversationRow(conversation: conv)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 40)
        }
    }

    private func sectionHeader(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(Color.white.opacity(0.25))
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No conversations yet.")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

// MARK: - Conversation row

private struct ConversationRow: View {
    @EnvironmentObject var store: ConversationStore
    let conversation: Conversation

    private var isActive: Bool { store.activeId == conversation.id }

    var body: some View {
        Button {
            store.select(conversation.id)
        } label: {
            HStack(spacing: 10) {
                // Active indicator
                RoundedRectangle(cornerRadius: 1)
                    .fill(isActive ? WhetstoneTheme.blade : Color.clear)
                    .frame(width: 2, height: 18)

                Text(conversation.title)
                    .font(.system(size: 14))
                    .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isActive
                    ? WhetstoneTheme.blade.opacity(0.08)
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                store.delete(conversation.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
