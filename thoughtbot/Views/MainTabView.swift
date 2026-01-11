import SwiftUI
import Combine

struct MainTabView: View {
    @State private var selectedTab = 0
    @AppStorage("selectedCategory") private var selectedCategoryRaw: String = Category.personal.rawValue
    @ObservedObject private var recordingManager = RecordingManager.shared
    @ObservedObject private var captureQueue = CaptureQueue.shared

    private var selectedCategory: Binding<Category> {
        Binding(
            get: { Category(rawValue: selectedCategoryRaw) ?? .personal },
            set: { selectedCategoryRaw = $0.rawValue }
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ThoughtsListView(selectedCategory: selectedCategory)
                .tabItem {
                    Label("Thoughts", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(0)

            TasksListView(selectedCategory: selectedCategory)
                .tabItem {
                    Label("Tasks", systemImage: "checklist")
                }
                .tag(1)

            ActionsView()
                .tabItem {
                    Label("Actions", systemImage: "bolt.fill")
                }
                .tag(2)
        }
        .sheet(isPresented: $recordingManager.isRecording) {
            ActionButtonRecordingView()
                .presentationDetents([.medium])
                .interactiveDismissDisabled()
        }
        .task {
            // Prefetch all data on app launch for instant category switching
            await DataStore.shared.prefetchAll()
        }
        .onReceive(captureQueue.captureCompleted) { result in
            // Auto-navigate to the correct tab based on capture result
            withAnimation {
                switch result {
                case .thought:
                    selectedTab = 0
                case .task:
                    selectedTab = 1
                case .error:
                    // Nothing heard - stay on current tab (haptic feedback could be added here)
                    break
                case .unknown:
                    break  // Stay on current tab
                }
            }
        }
    }
}

// Recording view shown when Action Button starts recording
struct ActionButtonRecordingView: View {
    @ObservedObject private var recordingManager = RecordingManager.shared
    @ObservedObject private var captureQueue = CaptureQueue.shared
    @State private var recordingTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var displayState: RecordingState = .recording

    var body: some View {
        ZStack {
            // Dark background
            Color.black.opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Pixel-based recording indicator
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(glowColor.opacity(0.15))
                        .frame(width: 180, height: 180)
                        .blur(radius: 20)

                    // Main button
                    Circle()
                        .fill(Color.black.opacity(0.8))
                        .frame(width: 140, height: 140)
                        .shadow(color: glowColor.opacity(0.4), radius: 15)

                    // Pixel indicator
                    pixelIndicator
                }
                .onTapGesture {
                    if displayState == .recording {
                        stopRecording()
                    }
                }

                // Status area
                VStack(spacing: 8) {
                    // Recording time (only during recording)
                    if displayState == .recording {
                        Text(formatTime(recordingTime))
                            .font(.system(.title2, design: .monospaced))
                            .foregroundColor(.white)
                    }

                    // Status text
                    Text(statusText)
                        .font(.system(.body, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()
            }
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
        .onReceive(captureQueue.captureCompleted) { result in
            handleCaptureCompleted(result: result)
        }
    }

    @ViewBuilder
    private var pixelIndicator: some View {
        switch displayState {
        case .recording:
            WavePixelIndicator(pixelSize: 20, spacing: 6)
        case .processing:
            BreathePixelIndicator(pixelSize: 20, spacing: 6)
        case .noted:
            ArrowUpPixelIndicator(pixelSize: 20, spacing: 6)
        case .error:
            ErrorPixelIndicator(pixelSize: 20, spacing: 6)
        case .idle:
            MicrophonePixelIndicator(pixelSize: 20, spacing: 6)
        }
    }

    private var glowColor: Color {
        switch displayState {
        case .recording:
            return PixelColors.recording
        case .processing:
            return PixelColors.processing
        case .noted:
            return PixelColors.success
        case .error:
            return PixelColors.error
        case .idle:
            return PixelColors.idle
        }
    }

    private var statusText: String {
        switch displayState {
        case .recording:
            return "Tap to stop"
        case .processing:
            return "Processing..."
        case .noted:
            return "Noted"
        case .error:
            return "Nothing heard"
        case .idle:
            return ""
        }
    }

    private func startTimer() {
        recordingTime = 0
        displayState = .recording
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingTime += 0.1
        }
    }

    private func stopRecording() {
        timer?.invalidate()

        // Show processing state
        withAnimation(.easeInOut(duration: 0.2)) {
            displayState = .processing
        }

        Task {
            _ = await recordingManager.stopRecording()
        }
    }

    private func handleCaptureCompleted(result: CaptureResult) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if result == .error {
                displayState = .error
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
            } else {
                displayState = .noted
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        }

        // Auto-dismiss the sheet after delay
        let dismissDelay: Double = result == .error ? 2.0 : 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
            recordingManager.isRecording = false
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

#Preview {
    MainTabView()
}
