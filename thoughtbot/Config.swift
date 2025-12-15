import Foundation

enum Config {
    // Railway backend URL
    static let apiBaseURL = "https://postgres-production-46d5.up.railway.app"

    static var capturesURL: URL {
        URL(string: "\(apiBaseURL)/api/captures")!
    }

    static var thoughtsURL: URL {
        URL(string: "\(apiBaseURL)/api/thoughts")!
    }

    static var tasksURL: URL {
        URL(string: "\(apiBaseURL)/api/tasks")!
    }

    // Audio recording settings
    static let audioSampleRate: Double = 44100.0
    static let audioBitRate = 128000
    static let audioChannels = 1

    // Queue settings
    static let maxRetryAttempts = 5
    static let retryDelaySeconds: Double = 30.0
}
