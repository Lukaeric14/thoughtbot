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

    // MARK: - Persistent Cache Keys
    private let personalTasksKey = "MacDataStore.personalTasks"
    private let businessTasksKey = "MacDataStore.businessTasks"
    private let personalThoughtsKey = "MacDataStore.personalThoughts"
    private let businessThoughtsKey = "MacDataStore.businessThoughts"

    private init() {
        loadFromDisk()
    }

    // MARK: - Disk Persistence

    private func loadFromDisk() {
        let decoder = JSONDecoder()

        if let data = UserDefaults.standard.data(forKey: personalTasksKey),
           let tasks = try? decoder.decode([TaskItem].self, from: data) {
            personalTasks = tasks
        }
        if let data = UserDefaults.standard.data(forKey: businessTasksKey),
           let tasks = try? decoder.decode([TaskItem].self, from: data) {
            businessTasks = tasks
        }
        if let data = UserDefaults.standard.data(forKey: personalThoughtsKey),
           let thoughts = try? decoder.decode([ThoughtItem].self, from: data) {
            personalThoughts = thoughts
        }
        if let data = UserDefaults.standard.data(forKey: businessThoughtsKey),
           let thoughts = try? decoder.decode([ThoughtItem].self, from: data) {
            businessThoughts = thoughts
        }
    }

    private func saveToDisk() {
        let encoder = JSONEncoder()

        if let data = try? encoder.encode(personalTasks) {
            UserDefaults.standard.set(data, forKey: personalTasksKey)
        }
        if let data = try? encoder.encode(businessTasks) {
            UserDefaults.standard.set(data, forKey: businessTasksKey)
        }
        if let data = try? encoder.encode(personalThoughts) {
            UserDefaults.standard.set(data, forKey: personalThoughtsKey)
        }
        if let data = try? encoder.encode(businessThoughts) {
            UserDefaults.standard.set(data, forKey: businessThoughtsKey)
        }
    }

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
        saveToDisk()
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
        saveToDisk()
    }

    /// Remove a task locally
    func removeTaskLocally(id: String, category: String) {
        switch category {
        case "business":
            businessTasks.removeAll { $0.id == id }
        default:
            personalTasks.removeAll { $0.id == id }
        }
        saveToDisk()
    }

    /// Remove a thought locally
    func removeThoughtLocally(id: String, category: String) {
        switch category {
        case "business":
            businessThoughts.removeAll { $0.id == id }
        default:
            personalThoughts.removeAll { $0.id == id }
        }
        saveToDisk()
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
            saveToDisk()
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
            saveToDisk()
        } catch {
            print("Error loading thoughts for \(category): \(error)")
        }
    }
}
