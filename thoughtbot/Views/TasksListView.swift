import SwiftUI
import Combine

struct TasksListView: View {
    @Binding var selectedCategory: Category
    @StateObject private var dataStore = DataStore.shared
    @State private var showRecorder = false
    @State private var highlightedId: String?
    @State private var scrollToId: String?

    private var tasks: [TaskItem] {
        dataStore.tasks(for: selectedCategory)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if dataStore.isLoadingTasks && tasks.isEmpty {
                    ProgressView("Loading tasks...")
                } else if let error = dataStore.tasksError, tasks.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(error)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            Task { await dataStore.forceRefreshTasks(for: selectedCategory) }
                        }
                    }
                } else if tasks.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checklist")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No tasks yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Tap the mic to capture a task")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(tasks) { task in
                                TaskRow(task: task, isHighlighted: highlightedId == task.id, onStatusChange: { newStatus in
                                    await updateTaskStatus(taskId: task.id, status: newStatus)
                                })
                                .id(task.id)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        Task {
                                            await deleteTask(task: task)
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .refreshable {
                            await dataStore.forceRefreshTasks(for: selectedCategory)
                        }
                        .onChange(of: scrollToId) { _, newId in
                            if let id = newId {
                                withAnimation {
                                    proxy.scrollTo(id, anchor: .top)
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    scrollToId = nil
                                }
                            }
                        }
                    }
                }

                // Floating record button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: { showRecorder = true }) {
                            Image(systemName: "mic.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        // Instant toggle - data already cached
                        selectedCategory = selectedCategory == .personal ? .business : .personal
                    }) {
                        Image(systemName: selectedCategory == .personal ? "house.fill" : "building.2.fill")
                            .foregroundColor(.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    ProcessingIndicator {
                        // Navigate to most recent task
                        if let firstTask = tasks.first {
                            scrollToId = firstTask.id
                            highlightedId = firstTask.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation {
                                    highlightedId = nil
                                }
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showRecorder) {
                CaptureView()
                    .presentationDetents([.medium])
            }
        }
        .task {
            // Initial load if cache is empty/stale
            await dataStore.refreshTasksIfNeeded(for: selectedCategory)
        }
        .onChange(of: selectedCategory) { _, newCategory in
            // Refresh if needed when category changes
            Task {
                await dataStore.refreshTasksIfNeeded(for: newCategory)
            }
        }
        .onReceive(dataStore.$personalTasks.merge(with: dataStore.$businessTasks)) { _ in
            // Highlight newest task when data updates
            if let firstTask = tasks.first, highlightedId == nil {
                // Only auto-highlight if we just got new data from a capture
                if CaptureQueue.shared.isProcessing == false && CaptureQueue.shared.queuedCount == 0 {
                    // Check if this is a recent task (within last 5 seconds)
                    if firstTask.createdAt.timeIntervalSinceNow > -5 {
                        scrollToId = firstTask.id
                        highlightedId = firstTask.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                highlightedId = nil
                            }
                        }
                    }
                }
            }
        }
    }

    private func updateTaskStatus(taskId: String, status: TaskStatus) async {
        do {
            let updatedTask = try await APIClient.shared.updateTaskStatus(taskId: taskId, status: status)
            dataStore.updateTaskLocally(updatedTask)
        } catch {
            print("Error updating task: \(error)")
            await dataStore.forceRefreshTasks(for: selectedCategory)
        }
    }

    private func deleteTask(task: TaskItem) async {
        do {
            try await APIClient.shared.deleteTask(id: task.id)
            withAnimation {
                dataStore.removeTaskLocally(id: task.id, category: task.category ?? selectedCategory)
            }
        } catch {
            print("Error deleting task: \(error)")
            await dataStore.forceRefreshTasks(for: selectedCategory)
        }
    }
}

struct TaskRow: View {
    let task: TaskItem
    var isHighlighted: Bool = false
    let onStatusChange: (TaskStatus) async -> Void

    @State private var isExpanded = false
    @State private var isUpdating = false

    private var isDone: Bool {
        task.status == .done || task.status == .cancelled
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Checkbox
            Button(action: {
                Task {
                    isUpdating = true
                    let newStatus: TaskStatus = isDone ? .open : .done
                    await onStatusChange(newStatus)
                    isUpdating = false
                }
            }) {
                ZStack {
                    if isUpdating {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundColor(isDone ? .green : .secondary)
                    }
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(isUpdating)

            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Main title with mention count badge
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.body)
                        .fontWeight(.semibold)
                        .strikethrough(isDone)
                        .foregroundColor(isDone ? .secondary : .primary)

                    // Mention count badge (only show if > 1)
                    if let count = task.mentionCount, count > 1 {
                        Text("x\(count)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }

                // Collapsible transcript
                if let transcript = task.transcript, !transcript.isEmpty, transcript != task.title {
                    Button(action: { withAnimation { isExpanded.toggle() } }) {
                        HStack(spacing: 4) {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                            Text(isExpanded ? "Hide transcript" : "Show transcript")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        Text(transcript)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }

                // Due date and timestamp
                HStack(spacing: 8) {
                    if !isDone {
                        Label(formatDueDate(task.dueDate), systemImage: "calendar")
                            .font(.caption2)
                            .foregroundColor(isOverdue(task.dueDate) ? .red : .secondary)
                    }

                    Text(task.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .opacity(0.7)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, isHighlighted ? 8 : 0)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHighlighted ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.3), value: isHighlighted)
        .opacity(isDone ? 0.6 : 1.0)
    }

    private func formatDueDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }

    private func isOverdue(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dueDay = calendar.startOfDay(for: date)
        return dueDay < today
    }
}

#Preview {
    TasksListView(selectedCategory: .constant(.personal))
}
