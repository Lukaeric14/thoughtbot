import Foundation
import Network
import Combine

@MainActor
class CaptureQueue: ObservableObject {
    static let shared = CaptureQueue()

    @Published private(set) var queuedCount: Int = 0
    @Published private(set) var isProcessing: Bool = false

    // Publisher that fires when a capture is successfully processed with result type
    let captureCompleted = PassthroughSubject<CaptureResult, Never>()

    private var queue: [QueuedCapture] = []
    private let queueKey = "CaptureQueue"
    private let monitor = NWPathMonitor()
    private var isNetworkAvailable = true

    private init() {
        loadQueue()
        startNetworkMonitoring()
    }

    func enqueue(audioURL: URL) {
        let capture = QueuedCapture(audioURL: audioURL)
        queue.append(capture)
        queuedCount = queue.count
        saveQueue()

        Task {
            await processQueue()
        }
    }

    func processQueue() async {
        guard !isProcessing, isNetworkAvailable, !queue.isEmpty else { return }

        isProcessing = true

        while !queue.isEmpty && isNetworkAvailable {
            var capture = queue[0]

            do {
                let response = try await APIClient.shared.uploadCapture(audioURL: capture.audioURL)

                // Success - remove from queue and delete audio file
                queue.removeFirst()
                queuedCount = queue.count
                saveQueue()

                try? FileManager.default.removeItem(at: capture.audioURL)

                // Poll for capture classification (max 30s)
                let result = await pollForClassification(captureId: response.id)

                // Notify that a capture was successfully processed with result type
                captureCompleted.send(result)

            } catch {
                capture.retryCount += 1

                if capture.retryCount >= Config.maxRetryAttempts {
                    // Max retries reached - move to failed captures folder
                    moveToFailedCaptures(capture)
                    queue.removeFirst()
                } else {
                    // Update retry count and move to end of queue
                    queue[0] = capture
                }

                queuedCount = queue.count
                saveQueue()

                // Wait before retrying
                try? await Task.sleep(nanoseconds: UInt64(Config.retryDelaySeconds * 1_000_000_000))
            }
        }

        isProcessing = false
    }

    private func pollForClassification(captureId: String) async -> CaptureResult {
        let maxAttempts = 60  // 30 seconds at 500ms intervals
        let pollInterval: UInt64 = 500_000_000  // 500ms in nanoseconds

        for _ in 0..<maxAttempts {
            do {
                let status = try await APIClient.shared.fetchCaptureStatus(id: captureId)
                if let classification = status.classification {
                    return CaptureResult(from: classification)
                }
            } catch {
                // Continue polling on error
            }

            try? await Task.sleep(nanoseconds: pollInterval)
        }

        // Timeout - return unknown
        return .unknown
    }

    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasAvailable = self?.isNetworkAvailable ?? false
                self?.isNetworkAvailable = path.status == .satisfied

                // If network just became available, try processing queue
                if !wasAvailable && path.status == .satisfied {
                    await self?.processQueue()
                }
            }
        }

        let queue = DispatchQueue(label: "NetworkMonitor")
        monitor.start(queue: queue)
    }

    private func moveToFailedCaptures(_ capture: QueuedCapture) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let failedDir = documentsPath.appendingPathComponent("FailedCaptures")

        try? FileManager.default.createDirectory(at: failedDir, withIntermediateDirectories: true)

        let destination = failedDir.appendingPathComponent(capture.audioURL.lastPathComponent)
        try? FileManager.default.moveItem(at: capture.audioURL, to: destination)
    }

    private func saveQueue() {
        if let data = try? JSONEncoder().encode(queue) {
            UserDefaults.standard.set(data, forKey: queueKey)
        }
    }

    private func loadQueue() {
        if let data = UserDefaults.standard.data(forKey: queueKey),
           let savedQueue = try? JSONDecoder().decode([QueuedCapture].self, from: data) {
            queue = savedQueue
            queuedCount = queue.count
        }
    }
}
