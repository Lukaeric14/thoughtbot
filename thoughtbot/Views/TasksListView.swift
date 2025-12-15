import SwiftUI

struct TasksListView: View {
    @State private var tasks: [TaskItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showRecorder = false

    var body: some View {
        NavigationStack {
            ZStack {
                if isLoading && tasks.isEmpty {
                    ProgressView("Loading tasks...")
                } else if let error = errorMessage, tasks.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(error)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            Task { await loadTasks() }
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
                    List {
                        ForEach(tasks) { task in
                            TaskRow(task: task, onStatusChange: { newStatus in
                                await updateTaskStatus(taskId: task.id, status: newStatus)
                            })
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await loadTasks()
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
            .sheet(isPresented: $showRecorder) {
                CaptureView()
                    .presentationDetents([.medium])
                    .onDisappear {
                        Task {
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            await loadTasks()
                        }
                    }
            }
        }
        .task {
            await loadTasks()
        }
    }

    private func loadTasks() async {
        isLoading = true
        errorMessage = nil

        do {
            tasks = try await APIClient.shared.fetchTasks()
        } catch {
            errorMessage = "Failed to load tasks"
            print("Error loading tasks: \(error)")
        }

        isLoading = false
    }

    private func updateTaskStatus(taskId: String, status: TaskStatus) async {
        do {
            let updatedTask = try await APIClient.shared.updateTaskStatus(taskId: taskId, status: status)
            if let index = tasks.firstIndex(where: { $0.id == taskId }) {
                tasks[index] = updatedTask
            }
        } catch {
            print("Error updating task: \(error)")
            // Reload to get fresh state
            await loadTasks()
        }
    }
}

struct TaskRow: View {
    let task: TaskItem
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
                // Main title (embossed/bold, strikethrough if done)
                Text(task.title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .strikethrough(isDone)
                    .foregroundColor(isDone ? .secondary : .primary)

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
    TasksListView()
}
