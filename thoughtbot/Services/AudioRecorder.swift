import Foundation
import AVFoundation
import UIKit

enum RecordingState {
    case idle
    case recording
    case processing
    case noted      // Success state - shown briefly after processing
    case error      // Error state - shown briefly after failure
}

@MainActor
class AudioRecorder: NSObject, ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var recordingTime: TimeInterval = 0

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var timer: Timer?

    override init() {
        super.init()
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startRecording() async throws -> Bool {
        guard state == .idle else { return false }

        let hasPermission = await requestPermission()
        guard hasPermission else { return false }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try audioSession.setActive(true)

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("\(UUID().uuidString).m4a")
        recordingURL = audioFilename

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: Config.audioSampleRate,
            AVNumberOfChannelsKey: Config.audioChannels,
            AVEncoderBitRateKey: Config.audioBitRate,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.record()

        state = .recording
        recordingTime = 0
        startTimer()

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        return true
    }

    func stopRecording() -> URL? {
        guard state == .recording else { return nil }

        stopTimer()
        audioRecorder?.stop()
        audioRecorder = nil

        state = .idle

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        let url = recordingURL
        recordingURL = nil
        return url
    }

    func cancelRecording() {
        guard state == .recording else { return }

        stopTimer()
        audioRecorder?.stop()
        audioRecorder = nil

        // Delete the partial recording
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil

        state = .idle

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordingTime += 0.1
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            Task { @MainActor in
                self.state = .idle
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.state = .idle
        }
    }
}
