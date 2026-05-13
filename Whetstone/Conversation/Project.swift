import Foundation

struct Project: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var createdAt: Date = Date()
}
