import SwiftUI
import AppKit

class RecordingWindow: NSObject {
    private var window: NSWindow?
    private var recorder: MacAudioRecorder?
    private var hostingView: NSHostingView<StatusIndicatorView>?
    private var viewModel = RecordingViewModel()

    override init() {
        super.init()
        recorder = MacAudioRecorder()
        setupWindow()
    }

    private func setupWindow() {
        let contentView = StatusIndicatorView(viewModel: viewModel)
        hostingView = NSHostingView(rootView: contentView)

        // Thin vertical bar dimensions
        let barWidth: CGFloat = 6
        let barHeight: CGFloat = 80

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: barWidth, height: barHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .floating
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = true

        self.window = window

        // Position on right side of screen
        positionWindow()

        // Show with idle state
        window.makeKeyAndOrderFront(nil)
    }

    private func positionWindow() {
        guard let window = window, let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame

        // Position on right edge, vertically centered
        let x = screenFrame.maxX - windowFrame.width - 8
        let y = screenFrame.midY - windowFrame.height / 2

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func show() {
        guard let window = window else { return }

        // Reposition in case screen changed
        positionWindow()
        window.makeKeyAndOrderFront(nil)

        // Start recording
        viewModel.state = .recording
        recorder?.startRecording()
    }

    func stopAndSend() {
        guard let recorder = recorder else { return }

        viewModel.state = .processing

        if let audioURL = recorder.stopRecording() {
            Task {
                do {
                    _ = try await MacAPIClient.shared.uploadCapture(audioURL: audioURL)
                    try? FileManager.default.removeItem(at: audioURL)
                } catch {
                    print("Upload error: \(error)")
                }

                await MainActor.run {
                    self.viewModel.state = .idle
                }
            }
        } else {
            viewModel.state = .idle
        }
    }

    func showIdle() {
        viewModel.state = .idle
        guard let window = window else { return }
        positionWindow()
        window.makeKeyAndOrderFront(nil)
    }
}

enum RecordingState {
    case idle
    case recording
    case processing
}

class RecordingViewModel: ObservableObject {
    @Published var state: RecordingState = .idle

    // Convenience computed properties
    var isRecording: Bool { state == .recording }
    var isSending: Bool { state == .processing }
}

struct StatusIndicatorView: View {
    @ObservedObject var viewModel: RecordingViewModel

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                switch viewModel.state {
                case .idle:
                    IdleIndicator()
                case .recording:
                    RecordingIndicator()
                case .processing:
                    ProcessingIndicator()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

// MARK: - Idle State
struct IdleIndicator: View {
    @State private var opacity: Double = 0.3

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(opacity))
            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: opacity)
            .onAppear {
                opacity = 0.15
            }
    }
}

// MARK: - Recording State (Sound Waves)
struct RecordingIndicator: View {
    let barCount = 5

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                SoundWaveBar(delay: Double(index) * 0.1)
            }
        }
        .padding(.vertical, 8)
    }
}

struct SoundWaveBar: View {
    let delay: Double
    @State private var scale: CGFloat = 0.3

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.white.opacity(0.9))
            .frame(height: 3)
            .scaleEffect(x: scale, y: 1)
            .animation(
                .easeInOut(duration: 0.4)
                .repeatForever(autoreverses: true)
                .delay(delay),
                value: scale
            )
            .onAppear {
                scale = 1.0
            }
    }
}

// MARK: - Processing State (Loading Dots)
struct ProcessingIndicator: View {
    let dotCount = 5

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<dotCount, id: \.self) { index in
                ProcessingDot(delay: Double(index) * 0.15)
            }
        }
        .padding(.vertical, 8)
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
                .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true)
                .delay(delay),
                value: opacity
            )
            .onAppear {
                opacity = 1.0
            }
    }
}
