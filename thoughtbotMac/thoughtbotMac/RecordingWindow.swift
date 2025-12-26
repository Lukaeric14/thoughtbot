import SwiftUI
import AppKit

// Custom tracking view for mouse enter/exit events
class TrackingView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        // Remove existing tracking areas
        for area in trackingAreas {
            removeTrackingArea(area)
        }

        // Add new tracking area
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }
}

class RecordingWindow: NSObject {
    private var window: NSWindow?
    private var recorder: MacAudioRecorder?
    private var hostingView: NSHostingView<WidgetView>?
    private var trackingView: TrackingView?
    private var viewModel = WidgetViewModel()

    // Size constants
    private let idleWidth: CGFloat = 12
    private let idleHeight: CGFloat = 48
    private let activeWidth: CGFloat = 16
    private let activeHeight: CGFloat = 56
    private let expandedWidth: CGFloat = 300
    private let expandedHeight: CGFloat = 480

    override init() {
        super.init()
        recorder = MacAudioRecorder()
        setupWindow()
    }

    private func setupWindow() {
        let swiftUIView = WidgetView(viewModel: viewModel)
        hostingView = NSHostingView(rootView: swiftUIView)

        // Create tracking view as container
        let tracking = TrackingView()
        tracking.wantsLayer = true
        tracking.layer?.backgroundColor = .clear

        trackingView = tracking

        // Add hosting view as subview
        if let hosting = hostingView {
            hosting.translatesAutoresizingMaskIntoConstraints = false
            tracking.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.topAnchor.constraint(equalTo: tracking.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: tracking.bottomAnchor),
                hosting.leadingAnchor.constraint(equalTo: tracking.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: tracking.trailingAnchor)
            ])
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: idleWidth, height: idleHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = tracking
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .screenSaver
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        self.window = window

        // Setup hover callbacks
        tracking.onMouseEntered = { [weak self] in
            self?.handleMouseEntered()
        }
        tracking.onMouseExited = { [weak self] in
            self?.handleMouseExited()
        }

        // Position on right side of screen
        positionWindow(state: .idle, animate: false)

        // Show with idle state
        window.orderFrontRegardless()
    }

    private func handleMouseEntered() {
        guard viewModel.widgetState == .idle else { return }

        // Fade out, resize, then fade in with new content
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            self.window?.animator().alphaValue = 0
        } completionHandler: {
            self.viewModel.isHovering = true
            self.positionWindow(state: .expanded, animate: false)
            self.viewModel.fetchData()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                self.window?.animator().alphaValue = 1
            }
        }
    }

    private func handleMouseExited() {
        guard viewModel.widgetState != .expanded else { return }

        if viewModel.widgetState == .idle {
            // Fade out, resize, then fade in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                self.window?.animator().alphaValue = 0
            } completionHandler: {
                self.viewModel.isHovering = false
                self.positionWindow(state: .idle, animate: false)

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    self.window?.animator().alphaValue = 1
                }
            }
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
            // Collapse: fade out, resize, fade in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                self.window?.animator().alphaValue = 0
            } completionHandler: {
                self.viewModel.widgetState = .idle
                self.viewModel.isHovering = false
                self.positionWindow(state: .idle, animate: false)

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    self.window?.animator().alphaValue = 1
                }
            }
        } else if viewModel.widgetState == .idle {
            // Expand: fade out, resize, fade in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                self.window?.animator().alphaValue = 0
            } completionHandler: {
                self.viewModel.widgetState = .expanded
                self.positionWindow(state: .expanded, animate: false)
                self.viewModel.fetchData()

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    self.window?.animator().alphaValue = 1
                }
            }
        }
    }

    func show() {
        guard let window = window else {
            print("RecordingWindow.show() - window is nil")
            return
        }

        print("RecordingWindow.show() - starting recording, current state: \(viewModel.widgetState)")

        // Start recording
        viewModel.widgetState = .recording
        viewModel.isHovering = false

        // Grow window
        positionWindow(state: .recording, animate: true)
        window.orderFrontRegardless()

        print("RecordingWindow.show() - calling recorder?.startRecording()")
        recorder?.startRecording()
    }

    func stopAndSend() {
        guard let recorder = recorder else { return }

        viewModel.widgetState = .processing
        viewModel.processingCount += 1

        if let audioURL = recorder.stopRecording() {
            Task {
                do {
                    let response = try await MacAPIClient.shared.uploadCapture(audioURL: audioURL)
                    try? FileManager.default.removeItem(at: audioURL)

                    // Poll for classification, then fetch data and navigate
                    await self.waitForCaptureAndNavigate(captureId: response.id)

                } catch {
                    print("Upload error: \(error)")
                    await MainActor.run {
                        self.viewModel.processingCount = max(0, self.viewModel.processingCount - 1)
                        self.viewModel.widgetState = .idle
                        self.positionWindow(state: .idle, animate: true)
                    }
                }
            }
        } else {
            viewModel.processingCount = max(0, viewModel.processingCount - 1)
            viewModel.widgetState = .idle
            positionWindow(state: .idle, animate: true)
        }
    }

    private func waitForCaptureAndNavigate(captureId: String) async {
        // Poll for classification (max 30 seconds at 500ms intervals)
        let maxAttempts = 60
        let pollInterval: UInt64 = 500_000_000  // 500ms

        var captureResult: MacCaptureResult = .unknown

        for _ in 0..<maxAttempts {
            do {
                let status = try await MacAPIClient.shared.fetchCaptureStatus(id: captureId)
                if let classification = status.classification {
                    captureResult = MacCaptureResult(from: classification)
                    break
                }
            } catch {
                // Continue polling on error
            }
            try? await Task.sleep(nanoseconds: pollInterval)
        }

        // Fetch fresh data
        do {
            let category = viewModel.selectedCategory
            let thoughts = try await MacAPIClient.shared.fetchThoughts(category: category)
            let tasks = try await MacAPIClient.shared.fetchTasks(category: category)

            await MainActor.run {
                self.viewModel.updateDataAfterCapture(thoughts: thoughts, tasks: tasks)
                self.viewModel.processingCount = max(0, self.viewModel.processingCount - 1)
                self.viewModel.widgetState = .idle
                self.positionWindow(state: .idle, animate: true)

                // Navigate to correct tab and highlight new item
                switch captureResult {
                case .thought:
                    withAnimation {
                        self.viewModel.selectedTab = 0
                    }
                    if let newThought = thoughts.first {
                        self.viewModel.highlightedThoughtId = newThought.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation {
                                self.viewModel.highlightedThoughtId = nil
                            }
                        }
                    }
                case .task:
                    withAnimation {
                        self.viewModel.selectedTab = 1
                    }
                    if let newTask = tasks.first {
                        self.viewModel.highlightedTaskId = newTask.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation {
                                self.viewModel.highlightedTaskId = nil
                            }
                        }
                    }
                case .unknown:
                    // Stay on current tab, highlight newest item in either list
                    if let newThought = thoughts.first {
                        self.viewModel.highlightedThoughtId = newThought.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation {
                                self.viewModel.highlightedThoughtId = nil
                            }
                        }
                    }
                }
            }
        } catch {
            print("Fetch error after capture: \(error)")
            await MainActor.run {
                self.viewModel.processingCount = max(0, self.viewModel.processingCount - 1)
                self.viewModel.widgetState = .idle
                self.positionWindow(state: .idle, animate: true)
            }
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
    let mention_count: Int?
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
    let mention_count: Int?
    let last_updated_at: String
    let capture_id: String?
    let transcript: String?
}

// MARK: - View Model
class WidgetViewModel: ObservableObject {
    @Published var widgetState: WidgetState = .idle
    @Published var isHovering = false
    @Published var selectedTab = 0
    @Published var processingCount = 0
    @Published var highlightedThoughtId: String?
    @Published var highlightedTaskId: String?

    // Persisted category
    @AppStorage("macSelectedCategory") var selectedCategory: String = "personal"

    // Use DataStore for data
    private let dataStore = MacDataStore.shared

    var thoughts: [ThoughtItem] { dataStore.thoughts(for: selectedCategory) }
    var tasks: [TaskItem] { dataStore.tasks(for: selectedCategory) }
    var isLoading: Bool { dataStore.isLoading }

    var isRecording: Bool { widgetState == .recording }
    var isSending: Bool { widgetState == .processing }
    var showExpanded: Bool { widgetState == .expanded || isHovering }
    var isProcessing: Bool { processingCount > 0 || widgetState == .processing }

    init() {
        // Prefetch all data on init
        Task {
            await dataStore.prefetchAll()
        }
    }

    func toggleCategory() {
        // Instant toggle - data already cached
        selectedCategory = selectedCategory == "personal" ? "business" : "personal"
        // Refresh if cache is stale (async, won't block UI)
        Task {
            await dataStore.refreshIfNeeded(for: selectedCategory)
        }
    }

    func fetchData() {
        Task {
            await dataStore.refreshIfNeeded(for: selectedCategory)
        }
    }

    func forceRefresh() async {
        await dataStore.forceRefresh(for: selectedCategory)
    }

    func updateDataAfterCapture(thoughts: [ThoughtItem], tasks: [TaskItem]) {
        dataStore.updateThoughts(thoughts, for: selectedCategory)
        dataStore.updateTasks(tasks, for: selectedCategory)
    }

    func deleteThought(id: String) {
        Task {
            do {
                try await MacAPIClient.shared.deleteThought(id: id)
                await MainActor.run {
                    withAnimation {
                        dataStore.removeThoughtLocally(id: id, category: selectedCategory)
                    }
                }
            } catch {
                print("Delete thought error: \(error)")
            }
        }
    }

    func deleteTask(id: String) {
        Task {
            do {
                try await MacAPIClient.shared.deleteTask(id: id)
                await MainActor.run {
                    withAnimation {
                        dataStore.removeTaskLocally(id: id, category: selectedCategory)
                    }
                }
            } catch {
                print("Delete task error: \(error)")
            }
        }
    }
}

// MARK: - Main Widget View
struct WidgetView: View {
    @ObservedObject var viewModel: WidgetViewModel

    var body: some View {
        // No animation on content - window frame handles the animation
        if viewModel.showExpanded {
            ExpandedView(viewModel: viewModel)
        } else {
            StatusIndicatorView(viewModel: viewModel)
        }
    }
}

// MARK: - Expanded View with Tabs
struct ExpandedView: View {
    @ObservedObject var viewModel: WidgetViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header with category toggle and tabs
            HStack(spacing: 8) {
                // Category toggle button (top left) - gray icon
                Button(action: { viewModel.toggleCategory() }) {
                    Image(systemName: viewModel.selectedCategory == "personal" ? "house.fill" : "building.2.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
                .help(viewModel.selectedCategory == "personal" ? "Switch to Business" : "Switch to Personal")

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

                Spacer()

                // Processing indicator in expanded view
                if viewModel.isProcessing {
                    ExpandedProcessingIndicator()
                }
            }
            .padding(.horizontal, 12)
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
                // Manual tab content (no TabView to avoid macOS styling issues)
                Group {
                    switch viewModel.selectedTab {
                    case 0:
                        ThoughtsListView(viewModel: viewModel)
                    case 1:
                        TasksListView(viewModel: viewModel)
                    case 2:
                        ActionsListView()
                    default:
                        ThoughtsListView(viewModel: viewModel)
                    }
                }
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
    @ObservedObject var viewModel: WidgetViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if viewModel.thoughts.isEmpty {
                    EmptyStateView(icon: "lightbulb", message: "No thoughts yet")
                } else {
                    ForEach(viewModel.thoughts.prefix(10)) { thought in
                        ThoughtRow(thought: thought, isHighlighted: viewModel.highlightedThoughtId == thought.id) {
                            viewModel.deleteThought(id: thought.id)
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}

struct ThoughtRow: View {
    let thought: ThoughtItem
    var isHighlighted: Bool = false
    var onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(thought.text)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    // Mention count badge (only show if > 1)
                    if let count = thought.mention_count, count > 1 {
                        Text("x\(count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }

                Text(formatRelativeTime(thought.created_at))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            // Delete button on hover
            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHighlighted ? Color.accentColor.opacity(0.3) : (isHovering ? Color.white.opacity(0.12) : Color.white.opacity(0.08)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHighlighted ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .animation(.easeInOut(duration: 0.3), value: isHighlighted)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Tasks List
struct TasksListView: View {
    @ObservedObject var viewModel: WidgetViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if viewModel.tasks.isEmpty {
                    EmptyStateView(icon: "checkmark.circle", message: "No tasks yet")
                } else {
                    ForEach(viewModel.tasks.filter { $0.status == "open" }.prefix(10)) { task in
                        TaskRow(task: task, isHighlighted: viewModel.highlightedTaskId == task.id) {
                            viewModel.deleteTask(id: task.id)
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}

struct TaskRow: View {
    let task: TaskItem
    var isHighlighted: Bool = false
    var onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    // Mention count badge (only show if > 1)
                    if let count = task.mention_count, count > 1 {
                        Text("x\(count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }

                Text(formatDueDate(task.due_date))
                    .font(.system(size: 10))
                    .foregroundColor(isOverdue(task.due_date) ? .red.opacity(0.8) : .white.opacity(0.5))
            }

            Spacer()

            // Delete button on hover
            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHighlighted ? Color.accentColor.opacity(0.3) : (isHovering ? Color.white.opacity(0.12) : Color.white.opacity(0.08)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHighlighted ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .animation(.easeInOut(duration: 0.3), value: isHighlighted)
        .onHover { hovering in
            isHovering = hovering
        }
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
    @State private var rotation: Double = 0

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
                if viewModel.isProcessing {
                    // Show processing indicator in idle with count
                    VStack(spacing: 2) {
                        // Spinning ring
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(Color.accentColor, lineWidth: 1.5)
                            .frame(width: 8, height: 8)
                            .rotationEffect(.degrees(rotation))
                            .onAppear {
                                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                    rotation = 360
                                }
                            }

                        if viewModel.processingCount > 0 {
                            Text("\(viewModel.processingCount)")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                } else {
                    IdleIndicator()
                }
            case .recording:
                RecordingIndicator()
            case .processing:
                MacProcessingIndicator()
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
struct MacProcessingIndicator: View {
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

// MARK: - Expanded Processing Indicator
struct ExpandedProcessingIndicator: View {
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 28, height: 28)

            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(Color.accentColor, lineWidth: 2)
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
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
    // Try multiple date formats
    let date: Date?

    // Try ISO 8601 with fractional seconds
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = isoFormatter.date(from: dateString) {
        date = d
    } else {
        // Try ISO 8601 without fractional seconds
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let d = isoFormatter.date(from: dateString) {
            date = d
        } else {
            // Try simple date format
            let simpleFormatter = DateFormatter()
            simpleFormatter.dateFormat = "yyyy-MM-dd"
            date = simpleFormatter.date(from: dateString)
        }
    }

    guard let date = date else { return dateString }

    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let dueDate = calendar.startOfDay(for: date)
    let days = calendar.dateComponents([.day], from: today, to: dueDate).day ?? 0

    if days == 0 { return "Today" }
    if days == 1 { return "Tomorrow" }
    if days == -1 { return "Yesterday" }
    if days < -1 { return "\(abs(days))d overdue" }
    if days > 1 && days <= 7 { return "In \(days) days" }

    let outputFormatter = DateFormatter()
    outputFormatter.dateStyle = .medium
    return outputFormatter.string(from: date)
}

func isOverdue(_ dateString: String) -> Bool {
    // Try multiple date formats
    let date: Date?

    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = isoFormatter.date(from: dateString) {
        date = d
    } else {
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let d = isoFormatter.date(from: dateString) {
            date = d
        } else {
            let simpleFormatter = DateFormatter()
            simpleFormatter.dateFormat = "yyyy-MM-dd"
            date = simpleFormatter.date(from: dateString)
        }
    }

    guard let date = date else { return false }

    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let dueDate = calendar.startOfDay(for: date)

    return dueDate < today
}
