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

    @State private var renamingConversationId: UUID?
    @State private var renameDraft: String = ""
    @State private var projectPickerConversationId: UUID?
    @State private var showRenameSheet: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(WhetstoneTheme.blade.opacity(0.15))
            conversationList
        }
        .background(Color(hex: "0b0e14"))
        .ignoresSafeArea(edges: .vertical)
        .sheet(isPresented: Binding(
            get: { projectPickerConversationId != nil },
            set: { if !$0 { projectPickerConversationId = nil } }
        )) {
            if let id = projectPickerConversationId {
                ProjectPickerSheet(conversationId: id)
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showRenameSheet) {
            NavigationStack {
                Form {
                    Section {
                        TextField("Title", text: $renameDraft)
                            .textInputAutocapitalization(.sentences)
                    }
                }
                .navigationTitle("Rename")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showRenameSheet = false
                            renamingConversationId = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if let id = renamingConversationId {
                                store.renameConversation(id, to: renameDraft)
                            }
                            showRenameSheet = false
                            renamingConversationId = nil
                        }
                        .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
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
                    ForEach(store.sidebarSections, id: \.sectionId) { section in
                        if !section.items.isEmpty {
                            sectionHeader(section.label)
                            ForEach(section.items) { conv in
                                ConversationRow(
                                    conversation: conv,
                                    onRename: {
                                        renamingConversationId = conv.id
                                        renameDraft = conv.title
                                        showRenameSheet = true
                                    },
                                    onAddToProject: {
                                        projectPickerConversationId = conv.id
                                    }
                                )
                                .id("\(section.sectionId)-\(conv.id.uuidString)")
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
    let onRename: () -> Void
    let onAddToProject: () -> Void

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

                if conversation.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.35))
                }

                Spacer(minLength: 0)
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
        .contextMenu {
            Button {
                store.setPinned(conversation.id, pinned: !conversation.isPinned)
            } label: {
                Label(
                    conversation.isPinned ? "Unpin" : "Pin",
                    systemImage: conversation.isPinned ? "pin.slash" : "pin"
                )
            }
            Button(action: onRename) {
                Label("Rename", systemImage: "pencil")
            }
            Button(action: onAddToProject) {
                Label("Add to project", systemImage: "tray.and.arrow.down.fill")
            }
            Divider()
            Button(role: .destructive) {
                store.delete(conversation.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                store.delete(conversation.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Add to project sheet

private struct ProjectPickerSheet: View {
    @EnvironmentObject var store: ConversationStore
    let conversationId: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var newProjectName: String = ""
    @State private var showNewProjectAlert: Bool = false

    private var conversation: Conversation? {
        store.conversations.first { $0.id == conversationId }
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    store.assignToProject(conversationId, projectId: nil)
                    dismiss()
                } label: {
                    HStack {
                        Text("None")
                            .foregroundStyle(Color.primary)
                        Spacer()
                        if conversation?.projectId == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(WhetstoneTheme.blade)
                        }
                    }
                }
                ForEach(store.projects) { project in
                    Button {
                        store.assignToProject(conversationId, projectId: project.id)
                        dismiss()
                    } label: {
                        HStack {
                            Text(project.name)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            if conversation?.projectId == project.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(WhetstoneTheme.blade)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(hex: "0b0e14"))
            .navigationTitle("Add to project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newProjectName = ""
                        showNewProjectAlert = true
                    } label: {
                        Text("New Project")
                    }
                }
            }
            .alert("New project", isPresented: $showNewProjectAlert) {
                TextField("Name", text: $newProjectName)
                Button("Create") {
                    let trimmed = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let project = store.createProject(name: trimmed) {
                        store.assignToProject(conversationId, projectId: project.id)
                        dismiss()
                    }
                    newProjectName = ""
                }
                .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) {
                    newProjectName = ""
                }
            } message: {
                Text("Choose a name for this folder.")
            }
        }
    }
}
