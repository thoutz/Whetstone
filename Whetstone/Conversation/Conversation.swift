import Foundation

struct Conversation: Identifiable {
    var id = UUID()
    var title: String = "New conversation"
    var messages: [ChatMessage] = []
    var apiHistory: [Message] = []
    var totalTokensUsed: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var isEmpty: Bool { messages.isEmpty }

    var timeGroup: String {
        let cal = Calendar.current
        let now = Date()
        if cal.isDateInToday(updatedAt)     { return "Today" }
        if cal.isDateInYesterday(updatedAt)  { return "Yesterday" }
        if let d = cal.dateComponents([.day], from: updatedAt, to: now).day {
            if d <= 7  { return "Previous 7 Days" }
            if d <= 30 { return "Previous 30 Days" }
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: updatedAt)
    }
}
