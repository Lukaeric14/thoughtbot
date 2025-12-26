import Foundation
import AVFoundation

class MacAudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var hasPermission = false

    override init() {
        super.init()
        requestMicrophonePermission()
    }

    private func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            hasPermission = true
            print("Microphone permission: authorized")
        case .notDetermined:
            print("Microphone permission: requesting...")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.hasPermission = granted
                    print("Microphone permission: \(granted ? "granted" : "denied")")
                }
            }
        case .denied, .restricted:
            hasPermission = false
            print("Microphone permission: denied or restricted")
        @unknown default:
            hasPermission = false
        }
    }

    func startRecording() {
        guard hasPermission else {
            print("Cannot record: no microphone permission")
            requestMicrophonePermission()
            return
        }

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

        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            let started = audioRecorder?.record() ?? false
            print("Recording started: \(started)")
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    func stopRecording() -> URL? {
        audioRecorder?.stop()
        audioRecorder = nil

        let url = recordingURL
        recordingURL = nil

        if let url = url {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            print("Recording stopped. File size: \(fileSize) bytes")
        }

        return url
    }
}
