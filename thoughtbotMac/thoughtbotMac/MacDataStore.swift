import Foundation
import Combine

@MainActor
class MacDataStore: ObservableObject {
    static let shared = MacDataStore()

    // MARK: - Published Data
    @Published private(set) var personalTasks: [TaskItem] = []
    @Published private(set) var businessTasks: [TaskItem] = []
    @Published private(set) var personalThoughts: [ThoughtItem] = []
    @Published private(set) var businessThoughts: [ThoughtItem] = []

    @Published private(set) var isLoading: Bool = false

    // MARK: - Cache Management
    private var lastTasksFetch: [String: Date] = [:]
    private var lastThoughtsFetch: [String: Date] = [:]
    private let cacheTimeout: TimeInterval = 30 // seconds

    private init() {}

    // MARK: - Public API

    /// Get tasks for a category
    func tasks(for category: String) -> [TaskItem] {
        switch category {
        case "business":
            return businessTasks
        default:
            return personalTasks
        }
    }

    /// Get thoughts for a category
    func thoughts(for category: String) -> [ThoughtItem] {
        switch category {
        case "business":
            return businessThoughts
        default:
            return personalThoughts
        }
    }

    /// Prefetch both categories on app launch
    func prefetchAll() async {
        isLoading = true

        async let personalTasksFetch: () = refreshTasks(for: "personal", force: false)
        async let businessTasksFetch: () = refreshTasks(for: "business", force: false)
        async let personalThoughtsFetch: () = refreshThoughts(for: "personal", force: false)
        async let businessThoughtsFetch: () = refreshThoughts(for: "business", force: false)

        _ = await (personalTasksFetch, businessTasksFetch, personalThoughtsFetch, businessThoughtsFetch)

        isLoading = false
    }

    /// Refresh if cache is stale
    func refreshIfNeeded(for category: String) async {
        async let t: () = refreshTasks(for: category, force: false)
        async let th: () = refreshThoughts(for: category, force: false)
        _ = await (t, th)
    }

    /// Force refresh for a category
    func forceRefresh(for category: String) async {
        isLoading = true
        async let t: () = refreshTasks(for: category, force: true)
        async let th: () = refreshThoughts(for: category, force: true)
        _ = await (t, th)
        isLoading = false
    }

    /// Force refresh all data
    func forceRefreshAll() async {
        isLoading = true
        async let t1: () = refreshTasks(for: "personal", force: true)
        async let t2: () = refreshTasks(for: "business", force: true)
        async let th1: () = refreshThoughts(for: "personal", force: true)
        async let th2: () = refreshThoughts(for: "business", force: true)
        _ = await (t1, t2, th1, th2)
        isLoading = false
    }

    /// Update tasks directly (used after capture polling)
    func updateTasks(_ tasks: [TaskItem], for category: String) {
        switch category {
        case "business":
            businessTasks = tasks
        default:
            personalTasks = tasks
        }
        lastTasksFetch[category] = Date()
    }

    /// Update thoughts directly (used after capture polling)
    func updateThoughts(_ thoughts: [ThoughtItem], for category: String) {
        switch category {
        case "business":
            businessThoughts = thoughts
        default:
            personalThoughts = thoughts
        }
        lastThoughtsFetch[category] = Date()
    }

    /// Remove a task locally
    func removeTaskLocally(id: String, category: String) {
        switch category {
        case "business":
            businessTasks.removeAll { $0.id == id }
        default:
            personalTasks.removeAll { $0.id == id }
        }
    }

    /// Remove a thought locally
    func removeThoughtLocally(id: String, category: String) {
        switch category {
        case "business":
            businessThoughts.removeAll { $0.id == id }
        default:
            personalThoughts.removeAll { $0.id == id }
        }
    }

    // MARK: - Private Methods

    private func shouldRefreshTasks(for category: String) -> Bool {
        guard let lastFetch = lastTasksFetch[category] else { return true }
        return Date().timeIntervalSince(lastFetch) > cacheTimeout
    }

    private func shouldRefreshThoughts(for category: String) -> Bool {
        guard let lastFetch = lastThoughtsFetch[category] else { return true }
        return Date().timeIntervalSince(lastFetch) > cacheTimeout
    }

    private func refreshTasks(for category: String, force: Bool) async {
        guard force || shouldRefreshTasks(for: category) else { return }

        do {
            let fetchedTasks = try await MacAPIClient.shared.fetchTasks(category: category)

            switch category {
            case "business":
                businessTasks = fetchedTasks
            default:
                personalTasks = fetchedTasks
            }

            lastTasksFetch[category] = Date()
        } catch {
            print("Error loading tasks for \(category): \(error)")
        }
    }

    private func refreshThoughts(for category: String, force: Bool) async {
        guard force || shouldRefreshThoughts(for: category) else { return }

        do {
            let fetchedThoughts = try await MacAPIClient.shared.fetchThoughts(category: category)

            switch category {
            case "business":
                businessThoughts = fetchedThoughts
            default:
                personalThoughts = fetchedThoughts
            }

            lastThoughtsFetch[category] = Date()
        } catch {
            print("Error loading thoughts for \(category): \(error)")
        }
    }
}
