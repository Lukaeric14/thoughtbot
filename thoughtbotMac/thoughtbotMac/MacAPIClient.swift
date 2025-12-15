import Foundation

enum MacAPIError: Error {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case serverError(Int)
    case decodingError(Error)
}

struct MacCaptureResponse: Codable {
    let id: String
    let status: String
}

actor MacAPIClient {
    static let shared = MacAPIClient()

    // Same backend URL as iOS app
    private let baseURL = "https://backend-production-4605.up.railway.app"

    private init() {}

    // MARK: - Fetch Thoughts
    func fetchThoughts() async throws -> [ThoughtItem] {
        let url = URL(string: "\(baseURL)/api/thoughts")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MacAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw MacAPIError.serverError(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode([ThoughtItem].self, from: data)
        } catch {
            throw MacAPIError.decodingError(error)
        }
    }

    // MARK: - Fetch Tasks
    func fetchTasks() async throws -> [TaskItem] {
        let url = URL(string: "\(baseURL)/api/tasks")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MacAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw MacAPIError.serverError(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode([TaskItem].self, from: data)
        } catch {
            throw MacAPIError.decodingError(error)
        }
    }

    // MARK: - Upload Capture
    func uploadCapture(audioURL: URL) async throws -> MacCaptureResponse {
        let boundary = UUID().uuidString
        let url = URL(string: "\(baseURL)/api/captures")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let audioData = try Data(contentsOf: audioURL)
        let filename = audioURL.lastPathComponent

        var body = Data()

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MacAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw MacAPIError.serverError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(MacCaptureResponse.self, from: data)
    }
}
