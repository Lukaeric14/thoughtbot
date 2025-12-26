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

struct MacCaptureStatus: Codable {
    let id: String
    let classification: String?
    let raw_llm_output: String?

    var category: String? {
        guard let raw = raw_llm_output,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let category = json["category"] as? String else {
            return nil
        }
        return category
    }
}

enum MacCaptureResult {
    case thought
    case task
    case unknown

    init(from classification: String?) {
        switch classification {
        case "thought":
            self = .thought
        case "task_create", "task_update":
            self = .task
        default:
            self = .unknown
        }
    }
}

actor MacAPIClient {
    static let shared = MacAPIClient()

    // Same backend URL as iOS app
    private let baseURL = "https://backend-production-4605.up.railway.app"

    private init() {}

    // MARK: - Fetch Thoughts
    func fetchThoughts(category: String? = nil) async throws -> [ThoughtItem] {
        var urlString = "\(baseURL)/api/thoughts"
        if let category = category {
            urlString += "?category=\(category)"
        }
        let url = URL(string: urlString)!

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
    func fetchTasks(category: String? = nil) async throws -> [TaskItem] {
        var urlString = "\(baseURL)/api/tasks"
        if let category = category {
            urlString += "?category=\(category)"
        }
        let url = URL(string: urlString)!

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

    // MARK: - Fetch Capture Status
    func fetchCaptureStatus(id: String) async throws -> MacCaptureStatus {
        let url = URL(string: "\(baseURL)/api/captures/\(id)")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MacAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw MacAPIError.serverError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(MacCaptureStatus.self, from: data)
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

    // MARK: - Delete Thought
    func deleteThought(id: String) async throws {
        let url = URL(string: "\(baseURL)/api/thoughts/\(id)")!

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 30

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MacAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw MacAPIError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Delete Task
    func deleteTask(id: String) async throws {
        let url = URL(string: "\(baseURL)/api/tasks/\(id)")!

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 30

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MacAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw MacAPIError.serverError(httpResponse.statusCode)
        }
    }
}
