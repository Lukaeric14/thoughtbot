import Foundation

struct CaptureResponse: Codable {
    let id: String
    let status: String
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
