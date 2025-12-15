import SwiftUI
import AppKit

class RecordingWindow: NSObject {
    private var window: NSWindow?
    private var recorder: MacAudioRecorder?
    private var hostingView: NSHostingView<RecordingView>?
    private var viewModel = RecordingViewModel()

    override init() {
        super.init()
        recorder = MacAudioRecorder()
        setupWindow()
    }

    private func setupWindow() {
        let contentView = RecordingView(viewModel: viewModel)
        hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .floating
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        self.window = window
    }

    func show() {
        guard let window = window else { return }

        // Position near mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        let screenFrame = NSScreen.main?.frame ?? .zero
        let windowFrame = window.frame

        var x = mouseLocation.x - windowFrame.width / 2
        var y = mouseLocation.y + 20

        // Keep on screen
        x = max(10, min(x, screenFrame.width - windowFrame.width - 10))
        y = max(windowFrame.height + 10, min(y, screenFrame.height - 10))

        window.setFrameOrigin(NSPoint(x: x, y: y - windowFrame.height))
        window.makeKeyAndOrderFront(nil)

        // Start recording
        viewModel.isRecording = true
        recorder?.startRecording()
    }

    func stopAndSend() {
        guard let recorder = recorder else { return }

        viewModel.isRecording = false
        viewModel.isSending = true

        if let audioURL = recorder.stopRecording() {
            Task {
                do {
                    _ = try await MacAPIClient.shared.uploadCapture(audioURL: audioURL)
                    try? FileManager.default.removeItem(at: audioURL)
                } catch {
                    print("Upload error: \(error)")
                }

                await MainActor.run {
                    self.viewModel.isSending = false
                    self.window?.orderOut(nil)
                }
            }
        } else {
            viewModel.isSending = false
            window?.orderOut(nil)
        }
    }
}

class RecordingViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var isSending = false
}

struct RecordingView: View {
    @ObservedObject var viewModel: RecordingViewModel

    var body: some View {
        HStack(spacing: 16) {
            // Pulsing indicator
            Circle()
                .fill(viewModel.isRecording ? Color.red : Color.gray)
                .frame(width: 16, height: 16)
                .scaleEffect(viewModel.isRecording ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: viewModel.isRecording)

            VStack(alignment: .leading, spacing: 4) {
                Text(statusText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)

                Text(subtitleText)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            if viewModel.isSending {
                ProgressView()
                    .scaleEffect(0.7)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var statusText: String {
        if viewModel.isSending {
            return "Sending..."
        } else if viewModel.isRecording {
            return "Recording"
        } else {
            return "Ready"
        }
    }

    private var subtitleText: String {
        if viewModel.isSending {
            return "Processing your thought"
        } else if viewModel.isRecording {
            return "Release Right Option to send"
        } else {
            return "Hold Right Option to speak"
        }
    }
}
