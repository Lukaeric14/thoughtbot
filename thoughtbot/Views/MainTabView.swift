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
    @State private var recordingTime: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Pulsing recording indicator
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: 140, height: 140)
                    .scaleEffect(pulseScale)

                Circle()
                    .fill(Color.red)
                    .frame(width: 120, height: 120)
                    .shadow(color: .red.opacity(0.4), radius: 15)

                Image(systemName: "stop.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(.white)
            }
            .onTapGesture {
                stopRecording()
            }

            // Recording time
            Text(formatTime(recordingTime))
                .font(.system(.title2, design: .monospaced))
                .foregroundColor(.secondary)

            Text("Tap to stop recording")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    @State private var pulseScale: CGFloat = 1.0

    private func startTimer() {
        recordingTime = 0
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            pulseScale = 1.15
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingTime += 0.1
        }
    }

    private func stopRecording() {
        timer?.invalidate()
        Task {
            _ = await recordingManager.stopRecording()
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let tenths = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

#Preview {
    MainTabView()
}
