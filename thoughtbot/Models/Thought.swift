import Foundation

enum Category: String, Codable {
    case personal
    case business
}

struct Thought: Codable, Identifiable {
    let id: String
    let createdAt: Date
    let text: String
    let canonicalText: String?
    let category: Category?
    let mentionCount: Int?
    let captureId: String?
    let transcript: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case text
        case canonicalText = "canonical_text"
        case category
        case mentionCount = "mention_count"
        case captureId = "capture_id"
        case transcript
    }
}
