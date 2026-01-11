import SwiftUI

struct CaptureView: View {
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var queue = CaptureQueue.shared

    @State private var showPermissionDenied = false
    @State private var displayState: RecordingState = .idle

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background - dark when recording/processing
                backgroundColor
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.3), value: displayState)

                VStack(spacing: 0) {
                    Spacer()

                    // Recording button with pixel indicator
                    PixelRecordButton(
                        state: displayState,
                        onTap: handleTap
                    )
                    .frame(width: min(geometry.size.width * 0.45, 180),
                           height: min(geometry.size.width * 0.45, 180))

                    // Status area
                    VStack(spacing: 8) {
                        // Timer (only during recording)
                        if displayState == .recording {
                            Text(formatTime(recorder.recordingTime))
                                .font(.system(.title2, design: .monospaced))
                                .foregroundColor(statusTextColor)
                                .transition(.opacity)
                        }

                        // Status text
                        Text(statusText)
                            .font(.system(.body, weight: .medium))
                            .foregroundColor(statusTextColor.opacity(0.7))
                    }
                    .frame(height: 60)
                    .padding(.top, 24)
                    .animation(.easeInOut(duration: 0.2), value: displayState)

                    Spacer()

                    // Queue indicator (subtle)
                    if queue.queuedCount > 0 && displayState == .idle {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle")
                                .font(.caption)
                            Text("\(queue.queuedCount) pending")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .alert("Microphone Access Required", isPresented: $showPermissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enable microphone access in Settings to record voice captures.")
        }
        .onChange(of: recorder.state) { _, newState in
            withAnimation(.easeInOut(duration: 0.2)) {
                displayState = newState
            }
        }
        .onReceive(queue.captureCompleted) { result in
            handleCaptureCompleted(result: result)
        }
    }

    private var backgroundColor: Color {
        switch displayState {
        case .idle:
            return Color(.systemBackground)
        case .recording, .processing, .noted, .error:
            return Color.black.opacity(0.95)
        }
    }

    private var statusTextColor: Color {
        switch displayState {
        case .idle:
            return Color(.label)
        case .recording, .processing, .noted, .error:
            return Color.white
        }
    }

    private var statusText: String {
        switch displayState {
        case .idle:
            return "Tap to record"
        case .recording:
            return "Listening..."
        case .processing:
            return "Processing..."
        case .noted:
            return "Noted"
        case .error:
            return "Nothing heard"
        }
    }

    private func handleTap() {
        Task {
            switch displayState {
            case .idle:
                let started = try? await recorder.startRecording()
                if started == false {
                    showPermissionDenied = true
                }
            case .recording:
                if let audioURL = recorder.stopRecording() {
                    // Show processing state
                    withAnimation {
                        displayState = .processing
                    }
                    queue.enqueue(audioURL: audioURL)
                }
            case .processing, .noted, .error:
                // Ignore taps during these states
                break
            }
        }
    }

    private func handleCaptureCompleted(result: CaptureResult) {
        // Show success or error state
        withAnimation(.easeInOut(duration: 0.2)) {
            if result == .error {
                displayState = .error
                // Haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
            } else {
                displayState = .noted
                // Haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        }

        // Auto-dismiss after delay
        let dismissDelay: Double = result == .error ? 2.0 : 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
            withAnimation(.easeInOut(duration: 0.3)) {
                displayState = .idle
            }
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

// MARK: - Pixel Record Button
struct PixelRecordButton: View {
    let state: RecordingState
    let onTap: () -> Void

    @State private var isPressed = false

    // Pixel grid sizing
    private let pixelSize: CGFloat = 20
    private let pixelSpacing: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack {
                // Outer glow/shadow
                Circle()
                    .fill(glowColor.opacity(0.15))
                    .blur(radius: 20)
                    .scaleEffect(state == .recording ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.5), value: state)

                // Main button circle
                Circle()
                    .fill(buttonBackgroundColor)
                    .shadow(color: glowColor.opacity(0.4), radius: state == .idle ? 8 : 15)

                // Pixel indicator (centered)
                pixelIndicator
                    .frame(width: size * 0.4, height: size * 0.4)
            }
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .onTapGesture {
                // Haptic on tap
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                onTap()
            }
            .onLongPressGesture(minimumDuration: 0.01, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
        }
    }

    @ViewBuilder
    private var pixelIndicator: some View {
        switch state {
        case .idle:
            MicrophonePixelIndicator(pixelSize: pixelSize, spacing: pixelSpacing)
        case .recording:
            WavePixelIndicator(pixelSize: pixelSize, spacing: pixelSpacing)
        case .processing:
            BreathePixelIndicator(pixelSize: pixelSize, spacing: pixelSpacing)
        case .noted:
            ArrowUpPixelIndicator(pixelSize: pixelSize, spacing: pixelSpacing)
        case .error:
            ErrorPixelIndicator(pixelSize: pixelSize, spacing: pixelSpacing)
        }
    }

    private var buttonBackgroundColor: Color {
        switch state {
        case .idle:
            return Color(.systemGray6)
        case .recording, .processing, .noted, .error:
            return Color.black.opacity(0.8)
        }
    }

    private var glowColor: Color {
        switch state {
        case .idle:
            return PixelColors.idle
        case .recording:
            return PixelColors.recording
        case .processing:
            return PixelColors.processing
        case .noted:
            return PixelColors.success
        case .error:
            return PixelColors.error
        }
    }
}

#Preview {
    CaptureView()
}
