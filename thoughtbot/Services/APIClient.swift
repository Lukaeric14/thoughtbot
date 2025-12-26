import Foundation

enum APIError: Error {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case serverError(Int)
    case decodingError(Error)
}

actor APIClient {
    static let shared = APIClient()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 with fractional seconds
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }

            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }

            // Try date-only format (YYYY-MM-DD)
            let dateOnlyFormatter = DateFormatter()
            dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
            if let date = dateOnlyFormatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
        }
        return decoder
    }()

    private init() {}

    // MARK: - Captures

    func uploadCapture(audioURL: URL) async throws -> CaptureResponse {
        let boundary = UUID().uuidString

        var request = URLRequest(url: Config.capturesURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let audioData = try Data(contentsOf: audioURL)
        let filename = audioURL.lastPathComponent

        var body = Data()

        // Add audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        let captureResponse = try JSONDecoder().decode(CaptureResponse.self, from: data)
        return captureResponse
    }

    // MARK: - Thoughts

    func fetchThoughts(category: Category? = nil) async throws -> [Thought] {
        var urlComponents = URLComponents(url: Config.thoughtsURL, resolvingAgainstBaseURL: false)!
        if let category = category {
            urlComponents.queryItems = [URLQueryItem(name: "category", value: category.rawValue)]
        }

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        do {
            return try decoder.decode([Thought].self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Tasks

    func fetchTasks(status: TaskStatus? = nil, category: Category? = nil) async throws -> [TaskItem] {
        var urlComponents = URLComponents(url: Config.tasksURL, resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = []

        if let status = status {
            queryItems.append(URLQueryItem(name: "status", value: status.rawValue))
        }
        if let category = category {
            queryItems.append(URLQueryItem(name: "category", value: category.rawValue))
        }

        if !queryItems.isEmpty {
            urlComponents.queryItems = queryItems
        }

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        do {
            return try decoder.decode([TaskItem].self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func updateTaskStatus(taskId: String, status: TaskStatus) async throws -> TaskItem {
        let url = Config.tasksURL.appendingPathComponent(taskId)

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = ["status": status.rawValue]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        do {
            return try decoder.decode(TaskItem.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Delete

    func deleteThought(id: String) async throws {
        let url = Config.thoughtsURL.appendingPathComponent(id)

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 30

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }
    }

    func deleteTask(id: String) async throws {
        let url = Config.tasksURL.appendingPathComponent(id)

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 30

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }
    }
}
