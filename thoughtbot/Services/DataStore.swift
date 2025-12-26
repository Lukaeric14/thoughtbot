import Foundation
import Combine

@MainActor
class DataStore: ObservableObject {
    static let shared = DataStore()

    // MARK: - Published Data
    @Published private(set) var personalTasks: [TaskItem] = []
    @Published private(set) var businessTasks: [TaskItem] = []
    @Published private(set) var personalThoughts: [Thought] = []
    @Published private(set) var businessThoughts: [Thought] = []

    @Published private(set) var isLoadingTasks: Bool = false
    @Published private(set) var isLoadingThoughts: Bool = false
    @Published private(set) var tasksError: String?
    @Published private(set) var thoughtsError: String?

    // MARK: - Cache Management
    private var lastTasksFetch: [Category: Date] = [:]
    private var lastThoughtsFetch: [Category: Date] = [:]
    private let cacheTimeout: TimeInterval = 30 // seconds

    // MARK: - Subscriptions
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Listen for capture completions to refresh data
        CaptureQueue.shared.captureCompleted
            .debounce(for: .seconds(1.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task {
                    await self?.forceRefreshAll()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    /// Get tasks for a category, using cache if valid
    func tasks(for category: Category) -> [TaskItem] {
        switch category {
        case .personal:
            return personalTasks
        case .business:
            return businessTasks
        }
    }

    /// Get thoughts for a category, using cache if valid
    func thoughts(for category: Category) -> [Thought] {
        switch category {
        case .personal:
            return personalThoughts
        case .business:
            return businessThoughts
        }
    }

    /// Prefetch both categories on app launch
    func prefetchAll() async {
        async let personalTasksFetch: () = refreshTasks(for: .personal, force: false)
        async let businessTasksFetch: () = refreshTasks(for: .business, force: false)
        async let personalThoughtsFetch: () = refreshThoughts(for: .personal, force: false)
        async let businessThoughtsFetch: () = refreshThoughts(for: .business, force: false)

        _ = await (personalTasksFetch, businessTasksFetch, personalThoughtsFetch, businessThoughtsFetch)
    }

    /// Refresh tasks for a category if cache is stale
    func refreshTasksIfNeeded(for category: Category) async {
        await refreshTasks(for: category, force: false)
    }

    /// Refresh thoughts for a category if cache is stale
    func refreshThoughtsIfNeeded(for category: Category) async {
        await refreshThoughts(for: category, force: false)
    }

    /// Force refresh tasks for a category (ignores cache)
    func forceRefreshTasks(for category: Category) async {
        await refreshTasks(for: category, force: true)
    }

    /// Force refresh thoughts for a category (ignores cache)
    func forceRefreshThoughts(for category: Category) async {
        await refreshThoughts(for: category, force: true)
    }

    /// Force refresh all data (both categories, both types)
    func forceRefreshAll() async {
        async let t1: () = refreshTasks(for: .personal, force: true)
        async let t2: () = refreshTasks(for: .business, force: true)
        async let th1: () = refreshThoughts(for: .personal, force: true)
        async let th2: () = refreshThoughts(for: .business, force: true)

        _ = await (t1, t2, th1, th2)
    }

    /// Update a task locally (optimistic update)
    func updateTaskLocally(_ task: TaskItem) {
        if task.category == .business {
            if let index = businessTasks.firstIndex(where: { $0.id == task.id }) {
                businessTasks[index] = task
            }
        } else {
            if let index = personalTasks.firstIndex(where: { $0.id == task.id }) {
                personalTasks[index] = task
            }
        }
    }

    /// Remove a task locally
    func removeTaskLocally(id: String, category: Category) {
        switch category {
        case .personal:
            personalTasks.removeAll { $0.id == id }
        case .business:
            businessTasks.removeAll { $0.id == id }
        }
    }

    /// Remove a thought locally
    func removeThoughtLocally(id: String, category: Category) {
        switch category {
        case .personal:
            personalThoughts.removeAll { $0.id == id }
        case .business:
            businessThoughts.removeAll { $0.id == id }
        }
    }

    // MARK: - Private Methods

    private func shouldRefreshTasks(for category: Category) -> Bool {
        guard let lastFetch = lastTasksFetch[category] else { return true }
        return Date().timeIntervalSince(lastFetch) > cacheTimeout
    }

    private func shouldRefreshThoughts(for category: Category) -> Bool {
        guard let lastFetch = lastThoughtsFetch[category] else { return true }
        return Date().timeIntervalSince(lastFetch) > cacheTimeout
    }

    private func refreshTasks(for category: Category, force: Bool) async {
        guard force || shouldRefreshTasks(for: category) else { return }

        isLoadingTasks = true
        tasksError = nil

        do {
            let fetchedTasks = try await APIClient.shared.fetchTasks(category: category)

            switch category {
            case .personal:
                personalTasks = fetchedTasks
            case .business:
                businessTasks = fetchedTasks
            }

            lastTasksFetch[category] = Date()
        } catch {
            tasksError = "Failed to load tasks"
            print("Error loading tasks for \(category): \(error)")
        }

        isLoadingTasks = false
    }

    private func refreshThoughts(for category: Category, force: Bool) async {
        guard force || shouldRefreshThoughts(for: category) else { return }

        isLoadingThoughts = true
        thoughtsError = nil

        do {
            let fetchedThoughts = try await APIClient.shared.fetchThoughts(category: category)

            switch category {
            case .personal:
                personalThoughts = fetchedThoughts
            case .business:
                businessThoughts = fetchedThoughts
            }

            lastThoughtsFetch[category] = Date()
        } catch {
            thoughtsError = "Failed to load thoughts"
            print("Error loading thoughts for \(category): \(error)")
        }

        isLoadingThoughts = false
    }
}
