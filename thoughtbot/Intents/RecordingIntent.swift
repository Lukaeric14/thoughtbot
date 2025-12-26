//
//  RecordingIntent.swift
//  thoughtbot
//
//  Created by Luka Eric on 15/12/2025.
//

import AppIntents
import AVFoundation

// Shared state for recording across app and intents
@MainActor
class RecordingManager: ObservableObject {
    static let shared = RecordingManager()

    @Published var isRecording = false
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?

    private init() {}

    func toggleRecording() async -> String {
        if isRecording {
            return await stopRecording()
        } else {
            return await startRecording()
        }
    }

    func startRecording() async -> String {
        guard !isRecording else { return "Already recording" }

        // Request permission
        let hasPermission = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        guard hasPermission else { return "Microphone permission denied" }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Use .record category for background recording from shortcuts
            try audioSession.setCategory(.record, mode: .default, options: [])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let audioFilename = documentsPath.appendingPathComponent("\(UUID().uuidString).m4a")
            recordingURL = audioFilename

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.record()
            isRecording = true

            return "Recording started"
        } catch {
            return "Failed to start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording() async -> String {
        guard isRecording else { return "Not recording" }

        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard let url = recordingURL else { return "No recording found" }
        recordingURL = nil

        // Queue the upload (will complete even if app goes to background)
        await CaptureQueue.shared.enqueue(audioURL: url)

        return "Recording saved! Uploading..."
    }
}

// App Intent for Shortcuts and Action Button
struct ToggleRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Recording"
    static var description = IntentDescription("Start or stop voice recording")

    // Must open app for audio recording to work
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await RecordingManager.shared.toggleRecording()
        return .result(dialog: "\(result)")
    }
}

struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Recording"
    static var description = IntentDescription("Start voice recording")

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await RecordingManager.shared.startRecording()
        return .result(dialog: "\(result)")
    }
}

struct StopRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Recording"
    static var description = IntentDescription("Stop voice recording and upload")

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await RecordingManager.shared.stopRecording()
        return .result(dialog: "\(result)")
    }
}

// Register shortcuts with the app
struct ThoughtbotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleRecordingIntent(),
            phrases: [
                "Toggle recording in \(.applicationName)",
                "Record thought with \(.applicationName)",
                "Capture thought in \(.applicationName)"
            ],
            shortTitle: "Toggle Recording",
            systemImageName: "mic.fill"
        )
    }
}
