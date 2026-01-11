import SwiftUI
import Combine

struct TasksListView: View {
    @Binding var selectedCategory: Category
    @StateObject private var dataStore = DataStore.shared
    @State private var showRecorder = false
    @State private var highlightedId: String?
    @State private var scrollToId: String?
    @State private var errorItemId: String?  // Track item with delete error

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
                            ForEach(tasks.filter { $0.status == .open }) { task in
                                TaskRow(
                                    task: task,
                                    isHighlighted: highlightedId == task.id,
                                    hasError: errorItemId == task.id,
                                    onComplete: {
                                        completeTask(task: task)
                                    }
                                )
                                .id(task.id)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteTask(task: task)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        completeTask(task: task)
                                    } label: {
                                        Label("Done", systemImage: "checkmark")
                                    }
                                    .tint(.green)
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
                    CategoryToggle(selectedCategory: $selectedCategory)
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

    private func completeTask(task: TaskItem) {
        let category = task.category ?? selectedCategory

        // Optimistic removal - remove immediately with animation
        withAnimation(.easeOut(duration: 0.25)) {
            dataStore.removeTaskLocally(id: task.id, category: category)
        }

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // API call in background
        Task {
            do {
                _ = try await APIClient.shared.updateTaskStatus(taskId: task.id, status: .done)
                // Success - task completed and removed from open list
            } catch {
                print("Error completing task: \(error)")
                // Failure - restore task with animation
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        dataStore.restoreTask(task, category: category)
                    }
                    showError(itemId: task.id)
                }
            }
        }
    }

    private func deleteTask(task: TaskItem) {
        let category = task.category ?? selectedCategory

        // Optimistic delete - remove immediately with animation
        withAnimation(.easeOut(duration: 0.25)) {
            dataStore.removeTaskLocally(id: task.id, category: category)
        }

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // API call in background
        Task {
            do {
                try await APIClient.shared.deleteTask(id: task.id)
                // Success - item already removed
            } catch {
                print("Error deleting task: \(error)")
                // Failure - restore item with animation
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        dataStore.restoreTask(task, category: category)
                    }
                    showError(itemId: task.id)
                }
            }
        }
    }

    private func showError(itemId: String) {
        errorItemId = itemId
        // Haptic feedback for error
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)

        // Auto-clear error after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                if errorItemId == itemId {
                    errorItemId = nil
                }
            }
        }
    }
}

struct TaskRow: View {
    let task: TaskItem
    var isHighlighted: Bool = false
    var hasError: Bool = false
    var onComplete: () -> Void

    @State private var isExpanded = false
    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Checkbox button
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Main title with mention count badge
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.body)
                        .fontWeight(.semibold)

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

                // Due date
                Label(formatDueDate(task.dueDate), systemImage: "calendar")
                    .font(.caption2)
                    .foregroundColor(isOverdue(task.dueDate) ? .red : .secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, isHighlighted || hasError ? 8 : 0)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .offset(x: shakeOffset)
        .animation(.easeInOut(duration: 0.3), value: isHighlighted)
        .onChange(of: hasError) { _, newValue in
            if newValue {
                // Shake animation
                withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
                    shakeOffset = 8
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
                        shakeOffset = -8
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
                        shakeOffset = 4
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.1, dampingFraction: 0.5)) {
                        shakeOffset = 0
                    }
                }
            }
        }
    }

    private var backgroundColor: Color {
        if hasError {
            return Color.red.opacity(0.15)
        } else if isHighlighted {
            return Color.accentColor.opacity(0.15)
        }
        return Color.clear
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
