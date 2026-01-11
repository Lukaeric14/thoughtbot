import SwiftUI
import AppKit

// Custom NSWindow that can become key (required for borderless windows to accept keyboard input)
class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

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

@MainActor
class RecordingWindow: NSObject {
    private var window: NSWindow?
    private var recorder: MacAudioRecorder?
    private var hostingView: NSHostingView<WidgetView>?
    private var trackingView: TrackingView?
    private var viewModel = WidgetViewModel()

    // Hover state management to prevent flickering
    private var lastHoverEnterTime: Date = .distantPast
    private let hoverEnterDebounceInterval: TimeInterval = 0.3
    private var isAnimatingHover = false

    // Mouse tracking to move widget between screens
    private var mouseTrackingTimer: Timer?
    private var lastScreenId: String?

    // Notch safe area - content should be positioned below this
    private let notchHeight: CGFloat = 37

    // Size constants - NotchNook style (4 states)
    // Heights INCLUDE notch area - content will be padded down
    // 1. Idle: Small notch-like rectangle (extends into notch)
    private let idleWidth: CGFloat = 200
    private let idleHeight: CGFloat = 50  // 37 notch + 13 visible content
    // 2. Semi-expanded: Wider pill for recording/listening
    private let semiExpandedWidth: CGFloat = 340
    private let semiExpandedHeight: CGFloat = 77  // 37 notch + 40 content
    // 3. Fully expanded: Large dropdown panel
    private let expandedWidth: CGFloat = 420
    private let expandedHeight: CGFloat = 377  // 37 notch + 340 content
    // 4. Typing: Medium pill with input
    private let typingWidth: CGFloat = 320
    private let typingHeight: CGFloat = 81  // 37 notch + 44 content

    override init() {
        super.init()
        recorder = MacAudioRecorder()
        setupWindow()
    }

    private func setupWindow() {
        let swiftUIView = WidgetView(
            viewModel: viewModel,
            onSubmit: { [weak self] in self?.submitTypedText() },
            onCancel: { [weak self] in self?.cancelTyping() }
        )
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

        let window = KeyableWindow(
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

        // Position window (will be hidden in idle state)
        positionWindow(state: .idle, animate: false)

        // Window starts hidden (idle state), orderFront so it's ready when needed
        window.orderFrontRegardless()

        // Start tracking mouse to move idle widget between screens
        startMouseTracking()
    }

    private func startMouseTracking() {
        // Check mouse position periodically to move idle window between screens
        mouseTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateIdleWindowScreen()
            }
        }
    }

    private func updateIdleWindowScreen() {
        // Only move the window when in idle state (not recording, not expanded, etc.)
        guard viewModel.widgetState == .idle && !viewModel.isHovering else { return }

        let mouseLocation = NSEvent.mouseLocation
        guard let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) else { return }

        // Check if we're on a different screen
        let screenId = mouseScreen.localizedName
        if screenId != lastScreenId {
            lastScreenId = screenId
            // Instantly reposition to new screen (no animation)
            positionWindow(state: .idle, animate: false)
        }
    }

    private func handleMouseEntered() {
        // Allow hover to expand from any state except recording, typing, or already expanded
        let cannotExpand = viewModel.widgetState == .recording ||
                          viewModel.widgetState == .typing ||
                          viewModel.widgetState == .expanded ||
                          viewModel.isHovering
        guard !cannotExpand else { return }
        guard !isAnimatingHover else { return }

        // Debounce rapid hover entries to prevent flickering
        let now = Date()
        guard now.timeIntervalSince(lastHoverEnterTime) >= hoverEnterDebounceInterval else { return }
        lastHoverEnterTime = now
        isAnimatingHover = true

        // Expand to show full dropdown
        viewModel.isHovering = true
        positionWindow(state: .expanded, animate: true)
        viewModel.fetchData()

        // Reset animation flag after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.isAnimatingHover = false
        }
    }

    private func handleMouseExited() {
        // Handle mouse exit when expanded via hover
        guard viewModel.isHovering else { return }

        // Check if mouse is actually outside the window frame
        guard let window = window else { return }
        let mouseLocation = NSEvent.mouseLocation
        let windowFrame = window.frame

        // Add a small margin to prevent edge flickering
        let expandedFrame = windowFrame.insetBy(dx: -3, dy: -3)
        if expandedFrame.contains(mouseLocation) {
            return // Mouse is still inside, ignore this exit event
        }

        // Don't exit during animation - but schedule a recheck
        if isAnimatingHover {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // Recheck if mouse is still outside after animation
                if self.viewModel.isHovering {
                    self.handleMouseExited()
                }
            }
            return
        }

        isAnimatingHover = true

        // Collapse back to previous state
        viewModel.isHovering = false

        // Determine what state to return to
        if viewModel.isProcessing {
            // Return to processing pill
            viewModel.widgetState = viewModel.processingCount > 0 ? .processing : .idle
            positionWindow(state: viewModel.widgetState, animate: true)
        } else {
            // Return to hidden idle
            viewModel.widgetState = .idle
            positionWindow(state: .idle, animate: true)
        }

        // Reset animation flag after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.isAnimatingHover = false
        }
    }

    private func positionWindow(state: WidgetState, animate: Bool) {
        guard let window = window else { return }

        // Use the screen where the mouse cursor currently is
        let mouseLocation = NSEvent.mouseLocation
        let screen: NSScreen
        if let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            screen = mouseScreen
        } else if let primary = NSScreen.screens.first {
            screen = primary
        } else {
            return
        }

        // Check if we're changing screens - if so, don't animate (instant jump)
        let currentWindowScreen = window.screen
        let isChangingScreens = currentWindowScreen != nil && currentWindowScreen != screen
        let shouldAnimate = animate && !isChangingScreens

        // In idle state (not hovering, not processing), make window nearly invisible
        // but still able to receive hover events
        let shouldBeInvisible = state == .idle && !viewModel.isHovering && !viewModel.isProcessing
        let targetAlpha: CGFloat = shouldBeInvisible ? 0.01 : 1.0

        if shouldAnimate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                window.animator().alphaValue = targetAlpha
            }
        } else {
            window.alphaValue = targetAlpha
        }

        let fullFrame = screen.frame
        let width: CGFloat
        let height: CGFloat

        switch state {
        case .idle:
            if viewModel.isHovering {
                // Fully expanded dropdown
                width = expandedWidth
                height = expandedHeight
            } else if viewModel.isProcessing {
                // Show semi-expanded when processing in background
                width = semiExpandedWidth
                height = semiExpandedHeight
            } else {
                // Hidden (handled above, but fallback)
                width = idleWidth
                height = idleHeight
            }
        case .recording, .processing, .noted, .error:
            // Semi-expanded pill
            width = semiExpandedWidth
            height = semiExpandedHeight
        case .expanded:
            // Fully expanded dropdown
            width = expandedWidth
            height = expandedHeight
        case .typing:
            // Medium pill with input
            width = typingWidth
            height = typingHeight
        }

        // Position at top center, touching the bezel (no gap)
        let x = fullFrame.midX - width / 2
        // Window touches the very top of the screen - merges with notch
        let y = fullFrame.maxY - height

        let newFrame = NSRect(x: x, y: y, width: width, height: height)

        if shouldAnimate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(newFrame, display: true)
            }
        } else {
            window.setFrame(newFrame, display: true)
        }

        // Update mouse tracking - allow mouse events for typing and hovering
        window.ignoresMouseEvents = state == .recording || state == .processing || state == .noted || state == .error
    }

    func toggleExpanded() {
        if viewModel.widgetState == .expanded || viewModel.isHovering {
            // Collapse: fade to nearly invisible (still accepts hover)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                self.window?.animator().alphaValue = 0.01
            } completionHandler: {
                self.viewModel.widgetState = .idle
                self.viewModel.isHovering = false
                self.positionWindow(state: .idle, animate: false)
                // Window stays hidden in idle
            }
        } else if viewModel.widgetState == .idle {
            // Expand: show window with expanded content
            self.viewModel.widgetState = .expanded
            self.viewModel.isHovering = true
            self.positionWindow(state: .expanded, animate: false)
            self.viewModel.fetchData()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                self.window?.animator().alphaValue = 1
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

        // Show and grow window
        window.alphaValue = 1
        positionWindow(state: .recording, animate: true)
        window.orderFrontRegardless()

        print("RecordingWindow.show() - calling recorder?.startRecording()")
        recorder?.startRecording()
    }

    func stopAndSend() {
        guard let recorder = recorder else {
            print("stopAndSend: no recorder")
            return
        }

        print("stopAndSend: setting processing state, processingCount will be \(viewModel.processingCount + 1)")
        viewModel.widgetState = .processing
        viewModel.processingCount += 1

        // Ensure window is visible for processing
        window?.alphaValue = 1
        positionWindow(state: .processing, animate: true)

        if let audioURL = recorder.stopRecording() {
            print("stopAndSend: got audio URL, starting upload")
            Task {
                do {
                    print("stopAndSend: uploading...")
                    let response = try await MacAPIClient.shared.uploadCapture(audioURL: audioURL)
                    print("stopAndSend: upload complete, capture ID: \(response.id)")
                    try? FileManager.default.removeItem(at: audioURL)

                    // Poll for classification, then fetch data and navigate
                    await self.waitForCaptureAndNavigate(captureId: response.id)

                } catch {
                    print("Upload error: \(error)")
                    viewModel.processingCount = max(0, viewModel.processingCount - 1)
                    await self.showErrorState()
                }
            }
        } else {
            print("stopAndSend: no audio URL from recorder")
            viewModel.processingCount = max(0, viewModel.processingCount - 1)
            showErrorState()
        }
    }

    private func waitForCaptureAndNavigate(captureId: String) async {
        print("Waiting for capture: \(captureId), isProcessing: \(viewModel.isProcessing)")

        var captureResult: MacCaptureResult = .unknown
        var captureCategory: String? = nil

        // Try SSE first (single connection, instant notification)
        do {
            print("Using SSE for capture: \(captureId)")
            let status = try await MacAPIClient.shared.streamCaptureStatus(id: captureId)
            if let classification = status.classification {
                print("SSE received classification: \(classification), category: \(status.category ?? "nil")")
                captureResult = MacCaptureResult(from: classification)
                captureCategory = status.category
            }
        } catch {
            print("SSE failed, falling back to polling: \(error)")

            // Fallback to polling with exponential backoff
            let maxTotalTime: TimeInterval = 30.0
            let initialInterval: UInt64 = 500_000_000  // 500ms
            let maxInterval: UInt64 = 4_000_000_000    // 4s cap

            var currentInterval = initialInterval
            var totalElapsed: TimeInterval = 0
            var attempt = 0

            while totalElapsed < maxTotalTime {
                do {
                    let status = try await MacAPIClient.shared.fetchCaptureStatus(id: captureId)
                    if let classification = status.classification {
                        print("Classification found after \(attempt) attempts (\(String(format: "%.1f", totalElapsed))s): \(classification), category: \(status.category ?? "nil")")
                        captureResult = MacCaptureResult(from: classification)
                        captureCategory = status.category
                        break
                    }
                } catch {
                    print("Poll error: \(error)")
                }

                try? await Task.sleep(nanoseconds: currentInterval)
                totalElapsed += Double(currentInterval) / 1_000_000_000.0
                attempt += 1

                // Exponential backoff with cap
                currentInterval = min(currentInterval * 2, maxInterval)
            }
        }

        // Switch to the category where the item was created
        let category = captureCategory ?? viewModel.selectedCategory
        if category != viewModel.selectedCategory {
            print("Switching category from \(viewModel.selectedCategory) to \(category)")
            viewModel.selectedCategory = category
        }

        // Force refresh cache for the correct category (uses existing DataStore)
        do {
            await MacDataStore.shared.forceRefresh(for: category)
            let thoughts = MacDataStore.shared.thoughts(for: category)
            let tasks = MacDataStore.shared.tasks(for: category)

            print("Refreshed cache: \(thoughts.count) thoughts, \(tasks.count) tasks. Result: \(captureResult)")
            viewModel.processingCount = max(0, viewModel.processingCount - 1)

            // Check if this was an error (nothing heard)
            if captureResult == .error {
                print("Nothing heard - showing error state")
                viewModel.widgetState = .error
                positionWindow(state: .error, animate: true)

                // After 2 seconds, transition to idle
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.viewModel.widgetState = .idle
                    self.positionWindow(state: .idle, animate: true)
                }
                return
            }

            // Show "Noted" success state briefly
            viewModel.widgetState = .noted
            positionWindow(state: .noted, animate: true)

            // After 1.5 seconds, transition to idle
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.viewModel.widgetState = .idle
                self.positionWindow(state: .idle, animate: true)
            }

            // Navigate to correct tab and highlight new item
            switch captureResult {
            case .thought:
                withAnimation {
                    viewModel.selectedTab = 0
                }
                if let newThought = thoughts.first {
                    print("Highlighting thought: \(newThought.id)")
                    viewModel.highlightedThoughtId = newThought.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation {
                            self.viewModel.highlightedThoughtId = nil
                        }
                    }
                }
            case .task:
                withAnimation {
                    viewModel.selectedTab = 1
                }
                if let newTask = tasks.first {
                    print("Highlighting task: \(newTask.id) - \(newTask.title)")
                    viewModel.highlightedTaskId = newTask.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation {
                            self.viewModel.highlightedTaskId = nil
                        }
                    }
                }
            case .unknown:
                print("Unknown classification, highlighting first thought if any")
                if let newThought = thoughts.first {
                    viewModel.highlightedThoughtId = newThought.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation {
                            self.viewModel.highlightedThoughtId = nil
                        }
                    }
                }
            case .error:
                // Already handled above with early return, but Swift requires exhaustive switch
                break
            }
        } catch {
            print("Fetch error after capture: \(error)")
            viewModel.processingCount = max(0, viewModel.processingCount - 1)
            // Still show "Noted" even on error (the capture was still processed)
            viewModel.widgetState = .noted
            positionWindow(state: .noted, animate: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.viewModel.widgetState = .idle
                self.positionWindow(state: .idle, animate: true)
            }
        }
    }

    func showErrorState() {
        viewModel.widgetState = .error
        positionWindow(state: .error, animate: true)

        // After 2 seconds, transition to idle
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.viewModel.widgetState = .idle
            self.positionWindow(state: .idle, animate: true)
        }
    }

    func showIdle() {
        viewModel.widgetState = .idle
        viewModel.isHovering = false
        guard let window = window else { return }
        // positionWindow handles visibility (hidden unless processing)
        positionWindow(state: .idle, animate: true)
        window.orderFrontRegardless()
    }

    func showTyping() {
        guard let window = window else {
            print("RecordingWindow.showTyping() - window is nil")
            return
        }

        print("RecordingWindow.showTyping() - activating typing mode")

        viewModel.typingText = ""
        viewModel.widgetState = .typing
        viewModel.isHovering = false

        // Show window and position
        window.alphaValue = 1
        positionWindow(state: .typing, animate: true)
        window.orderFrontRegardless()

        // Make window key to receive keyboard input
        window.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func submitTypedText() {
        let text = viewModel.typingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            cancelTyping()
            return
        }

        print("submitTypedText: submitting '\(text)', processingCount will be \(viewModel.processingCount + 1)")
        viewModel.widgetState = .processing
        viewModel.processingCount += 1
        viewModel.typingText = ""

        // Reset AppDelegate typing state
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.resetTypingState()
        }

        // Ensure window is visible and resize to processing state
        window?.alphaValue = 1
        positionWindow(state: .processing, animate: true)

        Task {
            do {
                print("submitTypedText: uploading text...")
                let response = try await MacAPIClient.shared.uploadTextCapture(
                    text: text,
                    category: viewModel.selectedCategory
                )
                print("submitTypedText: upload complete, capture ID: \(response.id)")

                // Poll for classification, then fetch data and navigate
                await self.waitForCaptureAndNavigate(captureId: response.id)

            } catch {
                print("Text upload error: \(error)")
                viewModel.processingCount = max(0, viewModel.processingCount - 1)
                viewModel.widgetState = .idle
                positionWindow(state: .idle, animate: true)
            }
        }
    }

    func cancelTyping() {
        print("RecordingWindow.cancelTyping()")
        viewModel.typingText = ""
        viewModel.widgetState = .idle

        // Reset AppDelegate typing state
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.resetTypingState()
        }

        positionWindow(state: .idle, animate: true)
    }
}

// MARK: - Widget State
enum WidgetState {
    case idle
    case recording
    case processing
    case noted      // Success state shown briefly after processing
    case error      // Error state shown briefly after failure
    case expanded
    case typing
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
@MainActor
class WidgetViewModel: ObservableObject {
    @Published var widgetState: WidgetState = .idle
    @Published var isHovering = false
    @Published var selectedTab = 0
    @Published var processingCount = 0
    @Published var highlightedThoughtId: String?
    @Published var highlightedTaskId: String?
    @Published var typingText: String = ""

    // Error state for subtle feedback
    @Published var errorItemId: String?

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
        // Ensure selectedCategory is valid (default to "personal" if invalid)
        if selectedCategory != "personal" && selectedCategory != "business" {
            selectedCategory = "personal"
        }

        // Prefetch all data on init
        Task {
            await dataStore.prefetchAll()
        }
    }

    func showError(itemId: String) {
        errorItemId = itemId

        // Auto-clear error after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            withAnimation {
                if self?.errorItemId == itemId {
                    self?.errorItemId = nil
                }
            }
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
        // Store for potential restoration
        let deletedThought = dataStore.thoughts(for: selectedCategory).first { $0.id == id }

        // Optimistic delete - notify view to update
        withAnimation {
            dataStore.removeThoughtLocally(id: id, category: selectedCategory)
            objectWillChange.send()
        }

        Task {
            do {
                try await MacAPIClient.shared.deleteThought(id: id)
                // Success - item already removed
            } catch {
                print("Delete thought error: \(error)")
                // Failure - restore item and show error
                await MainActor.run {
                    if let thought = deletedThought {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            dataStore.restoreThought(thought, category: selectedCategory)
                            objectWillChange.send()
                        }
                        showError(itemId: id)
                    }
                }
            }
        }
    }

    func deleteTask(id: String) {
        // Store for potential restoration
        let deletedTask = dataStore.tasks(for: selectedCategory).first { $0.id == id }

        // Optimistic delete - notify view to update
        withAnimation {
            dataStore.removeTaskLocally(id: id, category: selectedCategory)
            objectWillChange.send()
        }

        Task {
            do {
                try await MacAPIClient.shared.deleteTask(id: id)
                // Success - item already removed
            } catch {
                print("Delete task error: \(error)")
                // Failure - restore item and show error
                await MainActor.run {
                    if let task = deletedTask {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            dataStore.restoreTask(task, category: selectedCategory)
                            objectWillChange.send()
                        }
                        showError(itemId: id)
                    }
                }
            }
        }
    }

    func completeTask(id: String) {
        // Optimistic removal from open tasks list
        withAnimation {
            dataStore.removeTaskLocally(id: id, category: selectedCategory)
            objectWillChange.send()
        }

        Task {
            do {
                try await MacAPIClient.shared.updateTask(id: id, status: "done")
                // Success - task completed
            } catch {
                print("Complete task error: \(error)")
                // Failure - refresh to restore
                await dataStore.forceRefresh(for: selectedCategory)
                await MainActor.run {
                    objectWillChange.send()
                    showError(itemId: id)
                }
            }
        }
    }
}

// MARK: - Notch Safe Area Constant
// Content should be positioned below this height to avoid the physical notch
private let notchSafeAreaHeight: CGFloat = 37

// MARK: - Notch Tab Shape (concave fillet top corners)
// Creates a notch shape like Dynamic Island / MacBook notch
// Has "ears" at top that are wider, transitioning to narrower body via concave curves
// The concave curves bulge OUTWARD toward the top corners
struct NotchTabShape: Shape {
    var cornerRadius: CGFloat = 18   // Bottom corners (convex/normal rounded)
    var concaveRadius: CGFloat = 12  // Size of concave fillet curves

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let w = rect.width
        let h = rect.height
        let cr = cornerRadius    // bottom corners
        let r = concaveRadius    // concave fillet radius

        // Shape visualization:
        //
        // (0,0)__________________(w,0)   <- top edge (full width ears)
        //  |                        |    <- ears extend down
        //  |   ╮                ╭   |    <- concave curves (bulge OUTWARD)
        //      |                |        <- narrower body
        //      |                |
        //       ╲______________╱         <- rounded bottom corners
        //
        // Ears are at x=0 to x=r (left) and x=w-r to x=w (right)
        // Body is from x=r to x=w-r
        // Concave curves connect ears to body, bulging toward top corners

        // Start at top-left corner (where left arc meets top)
        path.move(to: CGPoint(x: 0, y: 0))

        // Top edge (full width)
        path.addLine(to: CGPoint(x: w, y: 0))

        // Right concave fillet: from (w, 0) curving to (w - r, r)
        // Center at (w, r) - curves start immediately from top
        path.addArc(
            center: CGPoint(x: w, y: r),
            radius: r,
            startAngle: .degrees(-90),  // above center = (w, 0)
            endAngle: .degrees(180),    // left of center = (w - r, r)
            clockwise: true             // short arc, bulges outward
        )
        // Now at (w - r, r)

        // Body right edge going down
        path.addLine(to: CGPoint(x: w - r, y: h - cr))

        // Bottom-right convex corner
        path.addArc(
            center: CGPoint(x: w - r - cr, y: h - cr),
            radius: cr,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        // Now at (w - r - cr, h)

        // Bottom edge
        path.addLine(to: CGPoint(x: r + cr, y: h))

        // Bottom-left convex corner
        path.addArc(
            center: CGPoint(x: r + cr, y: h - cr),
            radius: cr,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        // Now at (r, h - cr)

        // Body left edge going up
        path.addLine(to: CGPoint(x: r, y: r))

        // Left concave fillet: from (r, r) curving to (0, 0)
        // Center at (0, r) - curves end at top
        path.addArc(
            center: CGPoint(x: 0, y: r),
            radius: r,
            startAngle: .degrees(0),    // right of center = (r, r)
            endAngle: .degrees(-90),    // above center = (0, 0)
            clockwise: true             // short arc, bulges outward
        )
        // Now at (0, 0) - back to start

        path.closeSubpath()
        return path
    }
}

// MARK: - Main Widget View
struct WidgetView: View {
    @ObservedObject var viewModel: WidgetViewModel
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?

    var body: some View {
        // No animation on content - window frame handles the animation
        if viewModel.widgetState == .typing {
            TypingInputView(viewModel: viewModel, onSubmit: onSubmit, onCancel: onCancel)
        } else if viewModel.showExpanded {
            ExpandedDropdownView(viewModel: viewModel)
        } else if viewModel.widgetState == .idle && viewModel.isProcessing {
            // Background processing - show processing pill
            NotchPillView(viewModel: viewModel, forceProcessing: true)
        } else {
            NotchPillView(viewModel: viewModel)
        }
    }
}

// MARK: - Typing Input View (NotchNook style)
struct TypingInputView: View {
    @ObservedObject var viewModel: WidgetViewModel
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    @FocusState private var isFocused: Bool

    private let cornerRadius: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            // Notch safe area spacer
            Spacer()
                .frame(height: notchSafeAreaHeight)

            // Content below notch
            HStack(spacing: 12) {
                // Pixel grid icon
                IdlePixelGrid()
                    .frame(width: 18, height: 18)

                // Text field
                TextField("Type a thought or task...", text: $viewModel.typingText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .focused($isFocused)
                    .onSubmit {
                        onSubmit?()
                    }
                    .onExitCommand {
                        onCancel?()
                    }

                Spacer()

                // Submit button
                if !viewModel.typingText.isEmpty {
                    Button(action: { onSubmit?() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Keyboard shortcut hint
                    Text("⌘K")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(NotchTabShape(cornerRadius: cornerRadius, concaveRadius: 12))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
    }
}

// MARK: - Expanded Dropdown View (NotchNook style)
struct ExpandedDropdownView: View {
    @ObservedObject var viewModel: WidgetViewModel

    private let cornerRadius: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            // Notch safe area spacer
            Spacer()
                .frame(height: notchSafeAreaHeight)

            // Header row (below notch)
            HStack(spacing: 12) {
                // Left: Pixel grid with count badge + name
                HStack(spacing: 10) {
                    ZStack(alignment: .topTrailing) {
                        if viewModel.isProcessing {
                            BreathePixelIndicator()
                                .frame(width: 18, height: 18)
                        } else {
                            IdlePixelGrid()
                                .frame(width: 18, height: 18)
                        }

                        // Count badge (only when processing multiple)
                        if viewModel.processingCount > 1 {
                            Text("\(viewModel.processingCount)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 12, height: 12)
                                .background(Circle().fill(Color.purple))
                                .offset(x: 4, y: -4)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }

                    Text("thoughtbot")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }

                Spacer()

                // Right: Category toggle (dual-icon)
                HStack(spacing: 2) {
                    // Personal button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.selectedCategory = "personal"
                        }
                    }) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 12))
                            .foregroundColor(viewModel.selectedCategory == "personal" ? .white : .white.opacity(0.3))
                            .frame(width: 28, height: 28)
                            .background(
                                viewModel.selectedCategory == "personal"
                                    ? Color.white.opacity(0.25)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    // Business button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.selectedCategory = "business"
                        }
                    }) {
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 12))
                            .foregroundColor(viewModel.selectedCategory == "business" ? .white : .white.opacity(0.3))
                            .frame(width: 28, height: 28)
                            .background(
                                viewModel.selectedCategory == "business"
                                    ? Color.white.opacity(0.25)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(2)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 10)

            // Tab bar - centered
            HStack(spacing: 8) {
                ExpandedTabButton(title: "Thoughts", isSelected: viewModel.selectedTab == 0) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedTab = 0
                    }
                }
                ExpandedTabButton(title: "Tasks", isSelected: viewModel.selectedTab == 1) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedTab = 1
                    }
                }
                ExpandedTabButton(title: "Actions", isSelected: viewModel.selectedTab == 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedTab = 2
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
                .padding(.horizontal, 16)

            // Content area
            if viewModel.isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                Spacer()
            } else {
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
        .background(Color.black)
        .clipShape(NotchTabShape(cornerRadius: cornerRadius, concaveRadius: 12))
    }
}

// MARK: - Expanded Tab Button
struct ExpandedTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.white.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Legacy Expanded View (kept for reference)
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
                        ThoughtRow(
                            thought: thought,
                            isHighlighted: viewModel.highlightedThoughtId == thought.id,
                            hasError: viewModel.errorItemId == thought.id
                        ) {
                            viewModel.deleteThought(id: thought.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
}

struct ThoughtRow: View {
    let thought: ThoughtItem
    var isHighlighted: Bool = false
    var hasError: Bool = false
    var onDelete: () -> Void

    @State private var isHovering = false
    @State private var shakeOffset: CGFloat = 0
    @State private var isDeleting = false

    private var backgroundColor: Color {
        if hasError { return Color.red.opacity(0.25) }
        if isDeleting { return Color.white.opacity(0.04) }
        if isHighlighted { return Color.accentColor.opacity(0.3) }
        if isHovering { return Color.white.opacity(0.12) }
        return Color.white.opacity(0.08)
    }

    private var borderColor: Color {
        if hasError { return Color.red.opacity(0.5) }
        if isHighlighted { return Color.accentColor }
        return Color.clear
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(thought.text)
                        .font(.system(size: 12))
                        .foregroundColor(isDeleting ? .white.opacity(0.3) : .white)
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
                    .foregroundColor(.white.opacity(isDeleting ? 0.2 : 0.5))
            }

            Spacer()

            // Delete button or spinner on hover
            if isHovering || isDeleting {
                if isDeleting {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                } else {
                    Button(action: {
                        isDeleting = true
                        onDelete()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .offset(x: shakeOffset)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .animation(.easeInOut(duration: 0.3), value: isHighlighted)
        .onHover { hovering in
            isHovering = hovering
        }
        .onChange(of: hasError) { _, isError in
            if isError {
                // Shake animation sequence
                withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
                    shakeOffset = 8
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
                        shakeOffset = -6
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
                        TaskRow(
                            task: task,
                            isHighlighted: viewModel.highlightedTaskId == task.id,
                            hasError: viewModel.errorItemId == task.id,
                            onComplete: {
                                viewModel.completeTask(id: task.id)
                            },
                            onDelete: {
                                viewModel.deleteTask(id: task.id)
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
}

struct TaskRow: View {
    let task: TaskItem
    var isHighlighted: Bool = false
    var hasError: Bool = false
    var onComplete: () -> Void
    var onDelete: () -> Void

    @State private var isHovering = false
    @State private var shakeOffset: CGFloat = 0
    @State private var isCompleting = false
    @State private var isDeleting = false

    private var backgroundColor: Color {
        if hasError { return Color.red.opacity(0.25) }
        if isDeleting { return Color.white.opacity(0.04) }
        if isHighlighted { return Color.accentColor.opacity(0.3) }
        if isHovering { return Color.white.opacity(0.12) }
        return Color.white.opacity(0.08)
    }

    private var borderColor: Color {
        if hasError { return Color.red.opacity(0.5) }
        if isHighlighted { return Color.accentColor }
        return Color.clear
    }

    var body: some View {
        HStack(spacing: 10) {
            // Tappable checkbox
            Button(action: {
                isCompleting = true
                onComplete()
            }) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 16, height: 16)

                    if isCompleting {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.system(size: 12))
                        .foregroundColor(isDeleting ? .white.opacity(0.3) : .white)
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
                    .foregroundColor(isDeleting ? .white.opacity(0.2) : (isOverdue(task.due_date) ? .red.opacity(0.8) : .white.opacity(0.5)))
            }

            Spacer()

            // Delete button or spinner on hover
            if isHovering || isDeleting {
                if isDeleting {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                } else {
                    Button(action: {
                        isDeleting = true
                        onDelete()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .offset(x: shakeOffset)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .animation(.easeInOut(duration: 0.3), value: isHighlighted)
        .onHover { hovering in
            isHovering = hovering
        }
        .onChange(of: hasError) { _, isError in
            if isError {
                // Shake animation sequence
                withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
                    shakeOffset = 8
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
                        shakeOffset = -6
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

// MARK: - Notch View (NotchNook style)
struct NotchPillView: View {
    @ObservedObject var viewModel: WidgetViewModel
    var forceProcessing: Bool = false

    // Corner radius that matches notch aesthetic
    private let cornerRadius: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            // Notch safe area spacer
            Spacer()
                .frame(height: notchSafeAreaHeight)

            // Content below notch
            Group {
                if forceProcessing {
                    // Background processing indicator
                    backgroundProcessingView
                } else {
                    switch viewModel.widgetState {
                    case .idle:
                        // Idle is hidden, but this is fallback
                        EmptyView()
                    case .recording:
                        // Semi-expanded with listening animation
                        recordingView
                    case .processing:
                        // Semi-expanded with processing animation
                        processingView
                    case .noted:
                        // Success state with green up arrow
                        notedView
                    case .error:
                        // Error state with red X
                        errorView
                    case .expanded, .typing:
                        // These are handled by other views
                        EmptyView()
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(NotchTabShape(cornerRadius: cornerRadius, concaveRadius: 12))
    }

    // MARK: - Background Processing View (shown when idle but processing)
    private var backgroundProcessingView: some View {
        HStack(spacing: 12) {
            BreathePixelIndicator()
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text("thoughtbot")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)

                Text("Processing...")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            if viewModel.processingCount > 1 {
                Text("\(viewModel.processingCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 36)
    }

    // MARK: - Recording View (semi-expanded)
    private var recordingView: some View {
        HStack(spacing: 12) {
            // Wave pixel grid animation on the left
            WavePixelIndicator()
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text("thoughtbot")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)

                Text("Listening...")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()
        }
        .padding(.horizontal, 36)
    }

    // MARK: - Processing View (semi-expanded)
    private var processingView: some View {
        HStack(spacing: 12) {
            OrbitPixelIndicator()
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text("thoughtbot")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)

                Text("Processing...")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            if viewModel.processingCount > 1 {
                Text("\(viewModel.processingCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 36)
    }

    // MARK: - Noted View (success state)
    private var notedView: some View {
        HStack(spacing: 12) {
            ArrowUpPixelIndicator()
                .frame(width: 22, height: 22)

            Text("Noted")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, 36)
    }

    // MARK: - Error View (failure state)
    private var errorView: some View {
        HStack(spacing: 12) {
            ErrorPixelIndicator()
                .frame(width: 22, height: 22)

            Text("Nothing heard")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.red.opacity(0.9))

            Spacer()
        }
        .padding(.horizontal, 36)
    }
}

// MARK: - Waveform Bar (for recording state)
struct WaveformBar: View {
    let index: Int
    @State private var height: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.white.opacity(0.6))
            .frame(width: 3, height: height)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.3)
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.08)
                ) {
                    height = CGFloat.random(in: 8...16)
                }
            }
    }
}

// MARK: - Idle Pixel Grid (static 3x3 with subtle glow)
struct IdlePixelGrid: View {
    private let dotColor = Color(red: 0.3, green: 0.7, blue: 0.9)  // Soft cyan

    var body: some View {
        let pixelStates: [[Double]] = [
            [0.6, 0.8, 0.6],
            [0.8, 1.0, 0.8],
            [0.6, 0.8, 0.6]
        ]
        let colors = (0..<3).map { _ in
            (0..<3).map { _ in dotColor }
        }

        PixelGridIndicator(pixelStates: pixelStates, colors: colors)
    }
}

// MARK: - Idle State
struct IdleIndicator: View {
    @State private var opacity: Double = 0.5

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(opacity))
            .frame(width: 24, height: 4)  // Horizontal pill
            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: opacity)
            .onAppear {
                opacity = 0.25
            }
    }
}

// MARK: - Pixel Grid Base Component
struct PixelGridIndicator: View {
    let pixelStates: [[Double]]  // 3x3 grid of "on" values (0-1)
    let colors: [[Color]]        // 3x3 grid of colors for ON state
    let pixelSize: CGFloat = 4
    let spacing: CGFloat = 1.5

    // Off dots are visible but dim
    private let offColor = Color.white.opacity(0.15)

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<3, id: \.self) { col in
                        let isOn = pixelStates[row][col] > 0.5
                        let intensity = pixelStates[row][col]

                        RoundedRectangle(cornerRadius: 1)
                            .fill(isOn ? colors[row][col] : offColor)
                            .frame(width: pixelSize, height: pixelSize)
                            .scaleEffect(isOn ? 1.0 + (intensity * 0.15) : 1.0)
                            .shadow(
                                color: isOn ? colors[row][col].opacity(0.8) : .clear,
                                radius: isOn ? 3 : 0
                            )
                    }
                }
            }
        }
    }
}

// MARK: - Recording State: Pulse Ripple (Listening)
// Center pixel pulses, then ripples outward like sound waves - warm magenta/pink
struct ListeningPixelIndicator: View {
    @State private var phase: Int = 0

    // Vibrant warm colors like Dot Matrix Animator
    private let pulseColor = Color(red: 1.0, green: 0.08, blue: 0.8)  // Hot pink/magenta

    // Animation phases - ripple from center outward
    private func opacityFor(row: Int, col: Int) -> Double {
        let ring = ringFor(row: row, col: col)
        let activeRing = phase % 3

        if ring == activeRing {
            return 1.0
        } else if ring == (activeRing + 2) % 3 {
            return 0.7  // Trailing ring
        }
        return 0.0
    }

    private func ringFor(row: Int, col: Int) -> Int {
        // Center = ring 0
        if row == 1 && col == 1 { return 0 }
        // Edges (cross pattern) = ring 1
        if (row == 0 && col == 1) || (row == 2 && col == 1) ||
           (row == 1 && col == 0) || (row == 1 && col == 2) { return 1 }
        // Corners = ring 2
        return 2
    }

    var body: some View {
        let pixelStates = (0..<3).map { row in
            (0..<3).map { col in opacityFor(row: row, col: col) }
        }
        let colors = (0..<3).map { _ in
            (0..<3).map { _ in pulseColor }
        }

        PixelGridIndicator(pixelStates: pixelStates, colors: colors)
            .onAppear {
                startAnimation()
            }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { _ in
            withAnimation(.easeOut(duration: 0.15)) {
                phase += 1
            }
        }
    }
}

// MARK: - Processing State 1: Clockwise Spinner
// Like the Dot Matrix Animator "Clockwise" preset - dots light up around the edge
struct OrbitPixelIndicator: View {
    @State private var frame: Int = 0

    // Cyan/teal color like the Dot Matrix Animator
    private let dotColor = Color(red: 0.2, green: 0.9, blue: 1.0)  // Bright cyan

    // Clockwise path around the edge (8 positions)
    // Frame 0: top-left, Frame 1: top-center, Frame 2: top-right, etc.
    private let clockwisePath: [(Int, Int)] = [
        (0, 0), (0, 1), (0, 2),  // Top row: left to right
        (1, 2),                   // Right middle
        (2, 2), (2, 1), (2, 0),  // Bottom row: right to left
        (1, 0)                    // Left middle
    ]

    private func isOn(row: Int, col: Int) -> Double {
        // Center is always off
        if row == 1 && col == 1 { return 0.0 }

        guard let idx = clockwisePath.firstIndex(where: { $0 == (row, col) }) else { return 0.0 }

        let currentFrame = frame % 8
        let distance = (idx - currentFrame + 8) % 8

        // Current dot and 2 trailing dots are lit (creates comet effect)
        switch distance {
        case 0: return 1.0      // Head (brightest)
        case 7: return 0.8      // Trail 1
        case 6: return 0.5      // Trail 2
        default: return 0.0
        }
    }

    var body: some View {
        let pixelStates = (0..<3).map { row in
            (0..<3).map { col in isOn(row: row, col: col) }
        }
        let colors = (0..<3).map { _ in
            (0..<3).map { _ in dotColor }
        }

        PixelGridIndicator(pixelStates: pixelStates, colors: colors)
            .onAppear {
                startAnimation()
            }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            withAnimation(.easeOut(duration: 0.08)) {
                frame += 1
            }
        }
    }
}

// MARK: - Processing State 2: Pulse (center-outward burst)
// Like the Dot Matrix Animator "Pulse" preset - center lights up, expands to cross, then corners
struct BreathePixelIndicator: View {
    @State private var frame: Int = 0

    // Purple/violet color for processing
    private let dotColor = Color(red: 0.7, green: 0.3, blue: 1.0)  // Bright purple

    // Pulse pattern frames (6 frames total):
    // Frame 0: Center only
    // Frame 1: Center + cross (edges)
    // Frame 2: All 9 dots
    // Frame 3: Cross + corners (no center)
    // Frame 4: Corners only
    // Frame 5: All off (pause)
    private func isOn(row: Int, col: Int) -> Double {
        let currentFrame = frame % 6
        let isCenter = row == 1 && col == 1
        let isEdge = (row == 0 && col == 1) || (row == 2 && col == 1) ||
                     (row == 1 && col == 0) || (row == 1 && col == 2)
        let isCorner = (row == 0 || row == 2) && (col == 0 || col == 2)

        switch currentFrame {
        case 0:  // Center only
            return isCenter ? 1.0 : 0.0
        case 1:  // Center + cross
            return (isCenter || isEdge) ? 1.0 : 0.0
        case 2:  // All dots
            return 1.0
        case 3:  // Cross + corners (fading center)
            if isCenter { return 0.3 }
            return (isEdge || isCorner) ? 1.0 : 0.0
        case 4:  // Corners only
            return isCorner ? 0.8 : 0.0
        case 5:  // Pause (all dim)
            return 0.0
        default:
            return 0.0
        }
    }

    var body: some View {
        let pixelStates = (0..<3).map { row in
            (0..<3).map { col in isOn(row: row, col: col) }
        }
        let colors = (0..<3).map { _ in
            (0..<3).map { _ in dotColor }
        }

        PixelGridIndicator(pixelStates: pixelStates, colors: colors)
            .onAppear {
                startAnimation()
            }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            withAnimation(.easeOut(duration: 0.12)) {
                frame += 1
            }
        }
    }
}

// MARK: - Wave Pixel Indicator (for listening/recording state)
// Diagonal wave from bottom-left to top-right corner, with trailing opacity
struct WavePixelIndicator: View {
    @State private var frame: Int = 0

    // Warm magenta/pink color for listening
    private let waveColor = Color(red: 1.0, green: 0.08, blue: 0.8)  // Hot pink/magenta

    // Diagonal index for each cell (sum of row + col, but inverted for bottom-left start)
    // Grid positions and their diagonal index (for wave from bottom-left to top-right):
    // (0,0)=2  (0,1)=3  (0,2)=4
    // (1,0)=1  (1,1)=2  (1,2)=3
    // (2,0)=0  (2,1)=1  (2,2)=2
    private func diagonalIndex(row: Int, col: Int) -> Int {
        return (2 - row) + col
    }

    // Wave animation: diagonal sweep with trailing glow
    // 7 frames total (5 diagonals + 2 pause frames)
    private func isOn(row: Int, col: Int) -> Double {
        let diagIdx = diagonalIndex(row: row, col: col)
        let phase = frame % 7

        // Calculate distance from current wave front
        let distance = diagIdx - phase

        switch distance {
        case 0:  // Wave front (brightest)
            return 1.0
        case -1:  // Just passed (trailing)
            return 0.6
        case -2:  // Further behind (fading)
            return 0.25
        case 1:  // About to hit (leading glow)
            return 0.3
        default:
            return 0.0
        }
    }

    var body: some View {
        let pixelStates = (0..<3).map { row in
            (0..<3).map { col in isOn(row: row, col: col) }
        }
        let colors = (0..<3).map { _ in
            (0..<3).map { _ in waveColor }
        }

        PixelGridIndicator(pixelStates: pixelStates, colors: colors)
            .onAppear {
                startAnimation()
            }
    }

    private func startAnimation() {
        // Slower animation - 250ms per frame
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                frame += 1
            }
        }
    }
}

// MARK: - Arrow Up Pixel Indicator (for success/noted state)
// Upward arrow animation - sweeps from bottom to top
// Arrow shape:
//   ●      <- top center (tip)
// ● ● ●   <- middle row (arrow head)
//   ●      <- bottom center (stem)
struct ArrowUpPixelIndicator: View {
    @State private var frame: Int = 0

    // Bright green for success
    private let arrowColor = Color(red: 0.3, green: 0.85, blue: 0.4)

    // Arrow pixels: center column + middle row wings
    private func isArrowPixel(row: Int, col: Int) -> Bool {
        return col == 1 || (row == 1 && (col == 0 || col == 2))
    }

    // Animation: arrow "rises" from bottom to top with trailing glow
    // 8 frames total
    private func isOn(row: Int, col: Int) -> Double {
        if !isArrowPixel(row: row, col: col) { return 0.0 }

        let phase = frame % 8

        switch phase {
        case 0:  // Bottom stem starts
            if row == 2 && col == 1 { return 1.0 }
            return 0.0
        case 1:  // Bottom bright, middle row starting
            if row == 2 && col == 1 { return 0.8 }
            if row == 1 { return 0.4 }
            return 0.0
        case 2:  // Middle row bright, bottom fading, top starting
            if row == 1 { return 1.0 }
            if row == 2 && col == 1 { return 0.4 }
            if row == 0 && col == 1 { return 0.3 }
            return 0.0
        case 3:  // Top bright, middle fading
            if row == 0 && col == 1 { return 1.0 }
            if row == 1 { return 0.6 }
            if row == 2 && col == 1 { return 0.2 }
            return 0.0
        case 4:  // Full arrow visible, top brightest
            if row == 0 && col == 1 { return 1.0 }
            if row == 1 { return 0.8 }
            if row == 2 && col == 1 { return 0.5 }
            return 0.0
        case 5:  // Full arrow pulse
            if row == 0 && col == 1 { return 0.9 }
            if row == 1 { return 0.9 }
            if row == 2 && col == 1 { return 0.7 }
            return 0.0
        case 6:  // Fading out from bottom
            if row == 0 && col == 1 { return 0.7 }
            if row == 1 { return 0.5 }
            if row == 2 && col == 1 { return 0.2 }
            return 0.0
        case 7:  // Almost off, pause
            if row == 0 && col == 1 { return 0.3 }
            if row == 1 && col == 1 { return 0.2 }
            return 0.0
        default:
            return 0.0
        }
    }

    var body: some View {
        let pixelStates = (0..<3).map { row in
            (0..<3).map { col in isOn(row: row, col: col) }
        }
        let colors = (0..<3).map { _ in
            (0..<3).map { _ in arrowColor }
        }

        PixelGridIndicator(pixelStates: pixelStates, colors: colors)
            .onAppear {
                startAnimation()
            }
    }

    private func startAnimation() {
        // ~200ms per frame for smooth upward motion
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            withAnimation(.easeOut(duration: 0.15)) {
                frame += 1
            }
        }
    }
}

// MARK: - Error Pixel Indicator (for error state)
// Red X pattern that pulses
// X shape:
// ●   ●   <- top corners
//   ●     <- center
// ●   ●   <- bottom corners
struct ErrorPixelIndicator: View {
    @State private var frame: Int = 0

    // Red for error
    private let errorColor = Color(red: 0.95, green: 0.3, blue: 0.3)

    // X pixels: diagonals
    private func isXPixel(row: Int, col: Int) -> Bool {
        return (row == col) || (row + col == 2)
    }

    // Animation: X pulses/flashes
    private func isOn(row: Int, col: Int) -> Double {
        if !isXPixel(row: row, col: col) { return 0.0 }

        let phase = frame % 6

        switch phase {
        case 0:  // Center starts
            if row == 1 && col == 1 { return 1.0 }
            return 0.3
        case 1:  // Center bright, corners growing
            if row == 1 && col == 1 { return 1.0 }
            return 0.6
        case 2:  // Full X visible
            return 1.0
        case 3:  // Full X pulse
            return 0.9
        case 4:  // Dimming
            return 0.7
        case 5:  // Pause dim
            return 0.5
        default:
            return 0.5
        }
    }

    var body: some View {
        let pixelStates = (0..<3).map { row in
            (0..<3).map { col in isOn(row: row, col: col) }
        }
        let colors = (0..<3).map { _ in
            (0..<3).map { _ in errorColor }
        }

        PixelGridIndicator(pixelStates: pixelStates, colors: colors)
            .onAppear {
                startAnimation()
            }
    }

    private func startAnimation() {
        // ~200ms per frame for pulsing
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                frame += 1
            }
        }
    }
}

// MARK: - Legacy Recording Indicator (kept for reference)
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

// MARK: - Legacy Processing Indicator (kept for reference)
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
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 28, height: 28)

            OrbitPixelIndicator()
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
