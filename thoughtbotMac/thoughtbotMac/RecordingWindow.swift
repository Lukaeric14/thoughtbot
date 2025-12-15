import SwiftUI
import AppKit

class RecordingWindow: NSObject {
    private var window: NSWindow?
    private var recorder: MacAudioRecorder?
    private var hostingView: NSHostingView<WidgetView>?
    private var viewModel = WidgetViewModel()
    private var trackingArea: NSTrackingArea?

    // Size constants
    private let idleWidth: CGFloat = 12
    private let idleHeight: CGFloat = 48
    private let activeWidth: CGFloat = 16
    private let activeHeight: CGFloat = 56
    private let expandedWidth: CGFloat = 280
    private let expandedHeight: CGFloat = 360

    override init() {
        super.init()
        recorder = MacAudioRecorder()
        setupWindow()
    }

    private func setupWindow() {
        let contentView = WidgetView(viewModel: viewModel)
        hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: idleWidth, height: idleHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .screenSaver
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        self.window = window

        // Position on right side of screen
        positionWindow(state: .idle, animate: false)

        // Show with idle state
        window.orderFrontRegardless()

        // Setup hover tracking
        setupHoverTracking()
    }

    private func setupHoverTracking() {
        guard let window = window, let contentView = window.contentView else { return }

        // Remove existing tracking area
        if let existing = trackingArea {
            contentView.removeTrackingArea(existing)
        }

        // Create new tracking area
        trackingArea = NSTrackingArea(
            rect: contentView.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )

        contentView.addTrackingArea(trackingArea!)

        // Enable mouse events when not recording
        window.ignoresMouseEvents = viewModel.widgetState == .recording || viewModel.widgetState == .processing
    }

    override func mouseEntered(with event: NSEvent) {
        guard viewModel.widgetState == .idle else { return }
        viewModel.isHovering = true
        positionWindow(state: .expanded, animate: true)
        viewModel.fetchData()
    }

    override func mouseExited(with event: NSEvent) {
        guard viewModel.widgetState != .expanded else { return }
        viewModel.isHovering = false
        if viewModel.widgetState == .idle {
            positionWindow(state: .idle, animate: true)
        }
    }

    private func positionWindow(state: WidgetState, animate: Bool) {
        guard let window = window, let screen = NSScreen.main else { return }

        let screenFrame = screen.frame
        let width: CGFloat
        let height: CGFloat

        switch state {
        case .idle:
            width = viewModel.isHovering ? expandedWidth : idleWidth
            height = viewModel.isHovering ? expandedHeight : idleHeight
        case .recording, .processing:
            width = activeWidth
            height = activeHeight
        case .expanded:
            width = expandedWidth
            height = expandedHeight
        }

        // Position on right edge, vertically centered
        let x = screenFrame.maxX - width - 12
        let y = screenFrame.midY - height / 2

        let newFrame = NSRect(x: x, y: y, width: width, height: height)

        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(newFrame, display: true)
            }
        } else {
            window.setFrame(newFrame, display: true)
        }

        // Update mouse tracking
        window.ignoresMouseEvents = state == .recording || state == .processing
    }

    func toggleExpanded() {
        if viewModel.widgetState == .expanded {
            viewModel.widgetState = .idle
            viewModel.isHovering = false
            positionWindow(state: .idle, animate: true)
        } else if viewModel.widgetState == .idle {
            viewModel.widgetState = .expanded
            positionWindow(state: .expanded, animate: true)
            viewModel.fetchData()
        }
    }

    func show() {
        guard let window = window else { return }

        // Start recording
        viewModel.widgetState = .recording
        viewModel.isHovering = false

        // Grow window
        positionWindow(state: .recording, animate: true)
        window.orderFrontRegardless()

        recorder?.startRecording()
    }

    func stopAndSend() {
        guard let recorder = recorder else { return }

        viewModel.widgetState = .processing

        if let audioURL = recorder.stopRecording() {
            Task {
                do {
                    _ = try await MacAPIClient.shared.uploadCapture(audioURL: audioURL)
                    try? FileManager.default.removeItem(at: audioURL)
                } catch {
                    print("Upload error: \(error)")
                }

                await MainActor.run {
                    self.viewModel.widgetState = .idle
                    self.positionWindow(state: .idle, animate: true)
                }
            }
        } else {
            viewModel.widgetState = .idle
            positionWindow(state: .idle, animate: true)
        }
    }

    func showIdle() {
        viewModel.widgetState = .idle
        guard let window = window else { return }
        positionWindow(state: .idle, animate: true)
        window.orderFrontRegardless()
    }
}

// MARK: - Widget State
enum WidgetState {
    case idle
    case recording
    case processing
    case expanded
}

// MARK: - Data Models
struct ThoughtItem: Codable, Identifiable {
    let id: String
    let created_at: String
    let text: String
    let canonical_text: String?
    let capture_id: String?
    let transcript: String?
}

struct TaskItem: Codable, Identifiable {
    let id: String
    let created_at: String
    let title: String
    let canonical_title: String?
    let due_date: String
    let status: String
    let last_updated_at: String
    let capture_id: String?
    let transcript: String?
}

// MARK: - View Model
class WidgetViewModel: ObservableObject {
    @Published var widgetState: WidgetState = .idle
    @Published var isHovering = false
    @Published var selectedTab = 0
    @Published var thoughts: [ThoughtItem] = []
    @Published var tasks: [TaskItem] = []
    @Published var isLoading = false

    var isRecording: Bool { widgetState == .recording }
    var isSending: Bool { widgetState == .processing }
    var showExpanded: Bool { widgetState == .expanded || isHovering }

    func fetchData() {
        guard !isLoading else { return }
        isLoading = true

        Task {
            do {
                async let fetchedThoughts = MacAPIClient.shared.fetchThoughts()
                async let fetchedTasks = MacAPIClient.shared.fetchTasks()

                let (t, tk) = try await (fetchedThoughts, fetchedTasks)

                await MainActor.run {
                    self.thoughts = t
                    self.tasks = tk
                    self.isLoading = false
                }
            } catch {
                print("Fetch error: \(error)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Main Widget View
struct WidgetView: View {
    @ObservedObject var viewModel: WidgetViewModel

    var body: some View {
        Group {
            if viewModel.showExpanded {
                ExpandedView(viewModel: viewModel)
            } else {
                StatusIndicatorView(viewModel: viewModel)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.showExpanded)
    }
}

// MARK: - Expanded View with Tabs
struct ExpandedView: View {
    @ObservedObject var viewModel: WidgetViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                TabButton(title: "Thoughts", isSelected: viewModel.selectedTab == 0) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedTab = 0
                    }
                }
                TabButton(title: "Tasks", isSelected: viewModel.selectedTab == 1) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedTab = 1
                    }
                }
                TabButton(title: "Actions", isSelected: viewModel.selectedTab == 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedTab = 2
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)

            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.top, 8)

            // Content
            if viewModel.isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                Spacer()
            } else {
                TabView(selection: $viewModel.selectedTab) {
                    ThoughtsListView(thoughts: viewModel.thoughts)
                        .tag(0)
                    TasksListView(tasks: viewModel.tasks)
                        .tag(1)
                    ActionsListView()
                        .tag(2)
                }
                .tabViewStyle(.automatic)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.white.opacity(0.2) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Thoughts List
struct ThoughtsListView: View {
    let thoughts: [ThoughtItem]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if thoughts.isEmpty {
                    EmptyStateView(icon: "lightbulb", message: "No thoughts yet")
                } else {
                    ForEach(thoughts.prefix(10)) { thought in
                        ThoughtRow(thought: thought)
                    }
                }
            }
            .padding(12)
        }
    }
}

struct ThoughtRow: View {
    let thought: ThoughtItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(thought.text)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .lineLimit(2)

            Text(formatRelativeTime(thought.created_at))
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
        )
    }
}

// MARK: - Tasks List
struct TasksListView: View {
    let tasks: [TaskItem]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if tasks.isEmpty {
                    EmptyStateView(icon: "checkmark.circle", message: "No tasks yet")
                } else {
                    ForEach(tasks.filter { $0.status == "open" }.prefix(10)) { task in
                        TaskRow(task: task)
                    }
                }
            }
            .padding(12)
        }
    }
}

struct TaskRow: View {
    let task: TaskItem

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .lineLimit(2)

                Text(formatDueDate(task.due_date))
                    .font(.system(size: 10))
                    .foregroundColor(isOverdue(task.due_date) ? .red.opacity(0.8) : .white.opacity(0.5))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
        )
    }
}

// MARK: - Actions List
struct ActionsListView: View {
    var body: some View {
        VStack {
            Spacer()
            EmptyStateView(icon: "bolt", message: "Actions coming soon")
            Spacer()
        }
    }
}

// MARK: - Empty State
struct EmptyStateView: View {
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.3))
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.top, 40)
    }
}

// MARK: - Status Indicator (Collapsed)
struct StatusIndicatorView: View {
    @ObservedObject var viewModel: WidgetViewModel

    private var backgroundOpacity: Double {
        viewModel.widgetState == .idle ? 0.4 : 0.85
    }

    var body: some View {
        ZStack {
            // Dark capsule background - lighter when idle
            Capsule()
                .fill(Color.black.opacity(backgroundOpacity))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .animation(.easeInOut(duration: 0.3), value: viewModel.widgetState)

            // Content based on state
            switch viewModel.widgetState {
            case .idle:
                IdleIndicator()
            case .recording:
                RecordingIndicator()
            case .processing:
                ProcessingIndicator()
            case .expanded:
                EmptyView()
            }
        }
    }
}

// MARK: - Idle State
struct IdleIndicator: View {
    @State private var opacity: Double = 0.5

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(opacity))
            .frame(width: 3, height: 16)
            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: opacity)
            .onAppear {
                opacity = 0.25
            }
    }
}

// MARK: - Recording State (Sound Waves)
struct RecordingIndicator: View {
    let barCount = 5

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                SoundWaveBar(delay: Double(index) * 0.08)
            }
        }
    }
}

struct SoundWaveBar: View {
    let delay: Double
    @State private var width: CGFloat = 3

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.white)
            .frame(width: width, height: 3)
            .animation(
                .easeInOut(duration: 0.25)
                .repeatForever(autoreverses: true)
                .delay(delay),
                value: width
            )
            .onAppear {
                width = 8
            }
    }
}

// MARK: - Processing State (Loading Dots)
struct ProcessingIndicator: View {
    let dotCount = 5

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<dotCount, id: \.self) { index in
                ProcessingDot(delay: Double(index) * 0.1)
            }
        }
    }
}

struct ProcessingDot: View {
    let delay: Double
    @State private var opacity: Double = 0.3

    var body: some View {
        Circle()
            .fill(Color.white.opacity(opacity))
            .frame(width: 4, height: 4)
            .animation(
                .easeInOut(duration: 0.35)
                .repeatForever(autoreverses: true)
                .delay(delay),
                value: opacity
            )
            .onAppear {
                opacity = 1.0
            }
    }
}

// MARK: - Helper Functions
func formatRelativeTime(_ dateString: String) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    guard let date = formatter.date(from: dateString) else {
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }
        return formatDate(date)
    }
    return formatDate(date)
}

private func formatDate(_ date: Date) -> String {
    let now = Date()
    let diff = now.timeIntervalSince(date)
    let mins = Int(diff / 60)
    let hours = Int(diff / 3600)
    let days = Int(diff / 86400)

    if mins < 1 { return "just now" }
    if mins < 60 { return "\(mins)m ago" }
    if hours < 24 { return "\(hours)h ago" }
    if days < 7 { return "\(days)d ago" }

    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .short
    return dateFormatter.string(from: date)
}

func formatDueDate(_ dateString: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"

    guard let date = formatter.date(from: dateString) else { return dateString }

    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let dueDate = calendar.startOfDay(for: date)
    let days = calendar.dateComponents([.day], from: today, to: dueDate).day ?? 0

    if days == 0 { return "Today" }
    if days == 1 { return "Tomorrow" }
    if days == -1 { return "Yesterday" }
    if days < -1 { return "\(abs(days)) days overdue" }

    return formatter.string(from: date)
}

func isOverdue(_ dateString: String) -> Bool {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"

    guard let date = formatter.date(from: dateString) else { return false }

    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let dueDate = calendar.startOfDay(for: date)

    return dueDate < today
}
