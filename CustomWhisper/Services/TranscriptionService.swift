import Foundation
import Observation
import FluidAudio

/// Wraps FluidAudio's ASR engine to provide model management and transcription.
@Observable
final class TranscriptionService {

    // MARK: - Published State

    private(set) var isModelLoaded = false
    private(set) var isDownloading = false
    private(set) var downloadProgress: Double = 0
    private(set) var currentModelVersion: String?

    // MARK: - Private

    private var asrManager: AsrManager?
    private var loadedModels: AsrModels?

    // MARK: - Model Management

    /// Download (if needed) and load the ASR model for the given version.
    func loadModel(version: AppConstants.ModelVersion) async throws {
        if currentModelVersion == version.rawValue && isModelLoaded {
            return
        }

        isDownloading = true
        downloadProgress = 0

        do {
            let asrVersion: AsrModelVersion = version == .v2 ? .v2 : .v3
            let models = try await AsrModels.downloadAndLoad(version: asrVersion)

            let manager = AsrManager(config: .default)
            try await manager.initialize(models: models)

            asrManager = manager
            loadedModels = models
            currentModelVersion = version.rawValue
            isModelLoaded = true
            isDownloading = false
            downloadProgress = 1.0
        } catch {
            isDownloading = false
            isModelLoaded = false
            throw TranscriptionError.modelLoadFailed(error.localizedDescription)
        }
    }

    /// Transcribe an array of 16 kHz mono Float32 PCM samples.
    func transcribe(_ samples: [Float]) async throws -> TranscriptionResult {
        guard let manager = asrManager, isModelLoaded else {
            throw TranscriptionError.modelNotLoaded
        }

        guard !samples.isEmpty else {
            throw TranscriptionError.emptyAudio
        }

        let startTime = Date()

        let result = try await manager.transcribe(samples, source: .microphone)

        let processingTime = Date().timeIntervalSince(startTime)
        let audioDuration = Double(samples.count) / 16_000.0

        return TranscriptionResult(
            text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
            audioDuration: audioDuration,
            processingTime: processingTime,
            language: nil
        )
    }

    /// Clean up resources.
    func cleanup() {
        asrManager?.cleanup()
        asrManager = nil
        loadedModels = nil
        isModelLoaded = false
        currentModelVersion = nil
    }
}

// MARK: - Result Type

struct TranscriptionResult {
    let text: String
    let audioDuration: TimeInterval
    let processingTime: TimeInterval
    let language: String?

    var realTimeFactor: Double {
        guard processingTime > 0 else { return 0 }
        return audioDuration / processingTime
    }
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case emptyAudio
    case modelLoadFailed(String)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "No transcription model is loaded. Please download a model in Settings."
        case .emptyAudio:
            return "No audio to transcribe. The recording was empty."
        case .modelLoadFailed(let reason):
            return "Failed to load model: \(reason)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}
