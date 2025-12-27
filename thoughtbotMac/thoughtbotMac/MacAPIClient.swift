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

struct SSECaptureResult: Codable {
    let classification: String
    let category: String
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
    func fetchThoughts(category: String? = nil, slim: Bool = true) async throws -> [ThoughtItem] {
        guard var components = URLComponents(string: "\(baseURL)/api/thoughts") else {
            throw MacAPIError.invalidURL
        }
        var queryItems: [URLQueryItem] = []
        if let category = category {
            queryItems.append(URLQueryItem(name: "category", value: category))
        }
        if slim {
            queryItems.append(URLQueryItem(name: "slim", value: "true"))
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw MacAPIError.invalidURL
        }

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
    func fetchTasks(category: String? = nil, slim: Bool = true) async throws -> [TaskItem] {
        guard var components = URLComponents(string: "\(baseURL)/api/tasks") else {
            throw MacAPIError.invalidURL
        }
        var queryItems: [URLQueryItem] = []
        if let category = category {
            queryItems.append(URLQueryItem(name: "category", value: category))
        }
        if slim {
            queryItems.append(URLQueryItem(name: "slim", value: "true"))
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw MacAPIError.invalidURL
        }

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
        guard let url = URL(string: "\(baseURL)/api/captures/\(id)") else {
            throw MacAPIError.invalidURL
        }

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

    // MARK: - Stream Capture Status (SSE)
    // Uses Server-Sent Events for efficient real-time updates
    // Falls back to polling if SSE fails
    func streamCaptureStatus(id: String) async throws -> MacCaptureStatus {
        guard let url = URL(string: "\(baseURL)/api/captures/\(id)/stream") else {
            throw MacAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60 // Longer timeout for SSE
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MacAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw MacAPIError.serverError(httpResponse.statusCode)
        }

        // Response could be JSON (if already complete) or SSE data
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""

        if contentType.contains("application/json") {
            // Already complete, parse as JSON
            return try JSONDecoder().decode(MacCaptureStatus.self, from: data)
        }

        // Parse SSE data format: "data: {...}\n\n"
        guard let text = String(data: data, encoding: .utf8) else {
            throw MacAPIError.invalidResponse
        }

        // Extract JSON from SSE format
        let lines = text.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                if let jsonData = jsonString.data(using: .utf8) {
                    let sseResult = try JSONDecoder().decode(SSECaptureResult.self, from: jsonData)
                    return MacCaptureStatus(
                        id: id,
                        classification: sseResult.classification,
                        raw_llm_output: "{\"category\":\"\(sseResult.category)\"}"
                    )
                }
            }
        }

        throw MacAPIError.invalidResponse
    }

    // MARK: - Upload Capture
    func uploadCapture(audioURL: URL) async throws -> MacCaptureResponse {
        let boundary = UUID().uuidString
        guard let url = URL(string: "\(baseURL)/api/captures") else {
            throw MacAPIError.invalidURL
        }

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
        guard let url = URL(string: "\(baseURL)/api/thoughts/\(id)") else {
            throw MacAPIError.invalidURL
        }

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

    // MARK: - Upload Text Capture
    func uploadTextCapture(text: String, category: String? = nil) async throws -> MacCaptureResponse {
        guard let url = URL(string: "\(baseURL)/api/captures/text") else {
            throw MacAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var body: [String: Any] = ["text": text]
        if let category = category {
            body["category"] = category
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MacAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw MacAPIError.serverError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(MacCaptureResponse.self, from: data)
    }

    // MARK: - Delete Task
    func deleteTask(id: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/tasks/\(id)") else {
            throw MacAPIError.invalidURL
        }

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
