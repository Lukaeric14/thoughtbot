import Foundation

enum TaskStatus: String, Codable {
    case open
    case done
    case cancelled
}

struct TaskItem: Codable, Identifiable {
    let id: String
    let createdAt: Date
    let title: String
    let canonicalTitle: String?
    let dueDate: Date
    var status: TaskStatus
    let category: Category?
    let mentionCount: Int?
    let lastUpdatedAt: Date
    let captureId: String?
    let transcript: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case title
        case canonicalTitle = "canonical_title"
        case dueDate = "due_date"
        case status
        case category
        case mentionCount = "mention_count"
        case lastUpdatedAt = "last_updated_at"
        case captureId = "capture_id"
        case transcript
    }
}
