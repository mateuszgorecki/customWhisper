import AVFoundation
import Observation

/// Records microphone audio at 16 kHz mono Float32, the format expected by FluidAudio's Parakeet model.
@Observable
final class AudioRecorder {

    // MARK: - Published State

    private(set) var isRecording = false
    private(set) var elapsedTime: TimeInterval = 0
    private(set) var audioLevel: Float = 0

    // MARK: - Private

    private var audioEngine: AVAudioEngine?
    private var samples: [Float] = []
    private var recordingStartTime: Date?
    private var levelTimer: Timer?

    private let targetSampleRate: Double = 16_000
    private let bufferSize: AVAudioFrameCount = 4096

    // MARK: - Recording Control

    /// Start recording from the default input device at 16 kHz mono Float32.
    func startRecording() throws {
        guard !isRecording else { return }

        samples.removeAll()
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw RecordingError.noInputDevice
        }

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!

        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        guard let converter else {
            throw RecordingError.converterCreationFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.processBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        engine.prepare()
        try engine.start()

        audioEngine = engine
        isRecording = true
        recordingStartTime = Date()
        elapsedTime = 0

        startLevelTimer()
    }

    /// Stop recording and return the accumulated PCM samples.
    func stopRecording() -> [Float] {
        guard isRecording else { return [] }

        stopEngine()

        let result = samples
        samples.removeAll()
        return result
    }

    /// Cancel recording without returning samples.
    func cancelRecording() {
        guard isRecording else { return }
        stopEngine()
        samples.removeAll()
    }

    // MARK: - Private Helpers

    private func stopEngine() {
        levelTimer?.invalidate()
        levelTimer = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        isRecording = false
        audioLevel = 0
    }

    private func processBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) {
        let frameCapacity: AVAudioFrameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * (targetSampleRate / buffer.format.sampleRate)
        )
        guard frameCapacity > 0 else { return }

        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
            return
        }

        var error: NSError?
        var hasData = true

        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            if hasData {
                hasData = false
                outStatus.pointee = .haveData
                return buffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }

        if let error {
            print("Audio conversion error: \(error.localizedDescription)")
            return
        }

        guard let channelData = convertedBuffer.floatChannelData else { return }
        let frameLength = Int(convertedBuffer.frameLength)
        let pointer = channelData.pointee

        let newSamples = Array(UnsafeBufferPointer(start: pointer, count: frameLength))
        samples.append(contentsOf: newSamples)

        let rms = newSamples.reduce(Float(0)) { $0 + $1 * $1 } / max(Float(frameLength), 1)
        let level = sqrt(rms)
        DispatchQueue.main.async { [weak self] in
            self?.audioLevel = level
        }
    }

    private func startLevelTimer() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            self.elapsedTime = Date().timeIntervalSince(start)
        }
    }
}

// MARK: - Errors

enum RecordingError: LocalizedError {
    case noInputDevice
    case converterCreationFailed

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No audio input device found. Please check your microphone."
        case .converterCreationFailed:
            return "Failed to create audio format converter."
        }
    }
}
