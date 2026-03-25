import AVFoundation
import AppKit

class AudioRecorder: NSObject {
    private var audioRecorder: AVAudioRecorder?
    private(set) var isRecording = false
    private(set) var lastRecordingURL: URL?
    private(set) var recordingStartTime: Date?
    private var maxDurationTimer: Timer?

    /// Maximum recording duration in seconds
    static let maxDuration: TimeInterval = 180 // 3 minutes

    /// Called when recording auto-stops at max duration
    var onMaxDurationReached: (() -> Void)?

    private var recordingDirectory: URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("NimbusGlide", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    func startRecording() {
        guard !isRecording else { return }

        let url = recordingDirectory.appendingPathComponent("recording_\(Date().timeIntervalSince1970).wav")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()
            isRecording = true
            lastRecordingURL = url
            recordingStartTime = Date()
            playStartSound()

            // Auto-stop after max duration
            maxDurationTimer = Timer.scheduledTimer(withTimeInterval: Self.maxDuration, repeats: false) { [weak self] _ in
                guard let self, self.isRecording else { return }
                print("[NimbusGlide] Max recording duration reached (3 min)")
                self.onMaxDurationReached?()
            }

            print("[NimbusGlide] Recording started: \(url.lastPathComponent)")
        } catch {
            print("[NimbusGlide] Failed to start recording: \(error.localizedDescription)")
        }
    }

    func stopRecording() -> URL? {
        guard isRecording, let recorder = audioRecorder else { return nil }

        recorder.stop()
        isRecording = false
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
        playStopSound()
        print("[NimbusGlide] Recording stopped: \(lastRecordingURL?.lastPathComponent ?? "unknown")")
        return lastRecordingURL
    }

    func cleanup() {
        if let url = lastRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Removes any stale .wav files left behind by a previous crash.
    func cleanupStaleRecordings() {
        let dir = recordingDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "wav" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func playStartSound() {
        NSSound(named: .init("Tink"))?.play()
    }

    private func playStopSound() {
        NSSound(named: .init("Pop"))?.play()
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("[NimbusGlide] Recording finished unsuccessfully")
        }
    }
}
