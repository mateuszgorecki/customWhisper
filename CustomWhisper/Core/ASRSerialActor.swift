import Foundation
import FluidAudio

/// Serializes ALL access to FluidAudio's `AsrManager`.
///
/// `AsrManager` is a mutable, non-`Sendable` `final class`: `transcribe` mutates decoder
/// state and resets per-source state. If live dictation and meeting-file transcription
/// touched it concurrently they would corrupt each other's decode. This actor is the single
/// gate both flows go through, so they run mutually exclusively.
actor ASRSerialActor {

    private var asrManager: AsrManager?
    private var loadedModels: AsrModels?
    private(set) var loadedVersion: String?

    var isLoaded: Bool { asrManager != nil }

    /// Download (if needed) and load the model for the given version. No-op if already loaded.
    func loadModel(version: AppConstants.ModelVersion) async throws {
        if loadedVersion == version.rawValue, asrManager != nil {
            return
        }

        let asrVersion: AsrModelVersion = version == .v2 ? .v2 : .v3
        let models = try await AsrModels.downloadAndLoad(version: asrVersion)

        let manager = AsrManager(config: .default)
        try await manager.initialize(models: models)

        asrManager = manager
        loadedModels = models
        loadedVersion = version.rawValue
    }

    /// Transcribe in-memory PCM samples (live dictation path).
    func transcribe(samples: [Float]) async throws -> ASRResult {
        guard let manager = asrManager else {
            throw TranscriptionError.modelNotLoaded
        }
        return try await manager.transcribe(samples, source: .microphone)
    }

    /// Transcribe an audio file, streamed from disk by FluidAudio (meeting path).
    func transcribe(url: URL) async throws -> ASRResult {
        guard let manager = asrManager else {
            throw TranscriptionError.modelNotLoaded
        }
        return try await manager.transcribe(url, source: .system)
    }

    func cleanup() {
        asrManager?.cleanup()
        asrManager = nil
        loadedModels = nil
        loadedVersion = nil
    }
}
