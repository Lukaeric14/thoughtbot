import SwiftUI

struct CaptureView: View {
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var queue = CaptureQueue.shared

    @State private var showPermissionDenied = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack {
                    Spacer()

                    // Recording button
                    RecordButton(
                        state: recorder.state,
                        onTap: handleTap
                    )
                    .frame(width: min(geometry.size.width * 0.4, 160),
                           height: min(geometry.size.width * 0.4, 160))

                    // Recording time indicator
                    if recorder.state == .recording {
                        Text(formatTime(recorder.recordingTime))
                            .font(.system(.title3, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.top, 20)
                    } else {
                        Text(" ")
                            .font(.system(.title3, design: .monospaced))
                            .padding(.top, 20)
                    }

                    Spacer()

                    // Queue indicator (subtle)
                    if queue.queuedCount > 0 {
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
    }

    private func handleTap() {
        Task {
            if recorder.state == .idle {
                let started = try? await recorder.startRecording()
                if started == false {
                    showPermissionDenied = true
                }
            } else if recorder.state == .recording {
                if let audioURL = recorder.stopRecording() {
                    queue.enqueue(audioURL: audioURL)
                }
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let tenths = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

struct RecordButton: View {
    let state: RecordingState
    let onTap: () -> Void

    @State private var isPressed = false
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack {
                // Pulse animation when recording
                if state == .recording {
                    Circle()
                        .fill(Color.red.opacity(0.3))
                        .scaleEffect(pulseScale)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                                pulseScale = 1.2
                            }
                        }
                        .onDisappear {
                            pulseScale = 1.0
                        }
                }

                // Main button
                Circle()
                    .fill(buttonColor)
                    .shadow(color: buttonColor.opacity(0.4), radius: state == .recording ? 15 : 5)

                // Icon
                Image(systemName: iconName)
                    .font(.system(size: size * 0.35, weight: .semibold))
                    .foregroundColor(.white)
            }
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .onTapGesture {
                onTap()
            }
            .onLongPressGesture(minimumDuration: 0.01, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
        }
    }

    private var buttonColor: Color {
        switch state {
        case .idle:
            return Color(.systemGray)
        case .recording:
            return Color.red
        case .processing:
            return Color.orange
        }
    }

    private var iconName: String {
        switch state {
        case .idle:
            return "mic.fill"
        case .recording:
            return "stop.fill"
        case .processing:
            return "ellipsis"
        }
    }
}

#Preview {
    CaptureView()
}
