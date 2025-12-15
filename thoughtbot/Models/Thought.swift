import Foundation

struct Thought: Codable, Identifiable {
    let id: String
    let createdAt: Date
    let text: String
    let canonicalText: String?
    let captureId: String?
    let transcript: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case text
        case canonicalText = "canonical_text"
        case captureId = "capture_id"
        case transcript
    }
}
