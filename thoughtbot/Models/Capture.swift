import Foundation

struct CaptureResponse: Codable {
    let id: String
    let status: String
}

struct CaptureStatus: Codable {
    let id: String
    let classification: String?
}

enum CaptureResult {
    case thought
    case task
    case error      // Invalid/empty transcript (silence, "you", etc.)
    case unknown

    init(from classification: String?) {
        switch classification {
        case "thought":
            self = .thought
        case "task_create", "task_update":
            self = .task
        case "error":
            self = .error
        default:
            self = .unknown
        }
    }
}

struct QueuedCapture: Codable, Identifiable {
    let id: UUID
    let audioURL: URL
    let createdAt: Date
    var retryCount: Int

    init(audioURL: URL) {
        self.id = UUID()
        self.audioURL = audioURL
        self.createdAt = Date()
        self.retryCount = 0
    }
}
