import Foundation

enum AppConstants {
    static let appName = "CustomWhisper"
    static let defaultModelVersion = "v3"

    // MARK: - Meeting transcription

    /// Meeting-file transcription + local LLM correction settings.
    enum Meeting {
        /// Default LM Studio OpenAI-compatible base URL (no trailing slash).
        static let defaultLMStudioBaseURL = "http://localhost:1234/v1"
        /// Default correction model id (overridable in Settings).
        static let defaultCorrectionModel = "qwen/qwen3.6-35b-a3b"

        /// Batch size (characters) used for LM Studio correction when the model's
        /// context window can't be auto-detected. Conservative on purpose: safe for a
        /// ~4k-token window even with a reasoning model that echoes a large `<think>` block.
        static let defaultCorrectionMaxChars = 1_800

        /// Audio containers we accept for import (decoded via ffmpeg).
        static let acceptedExtensions = ["ogg", "opus", "mp3", "m4a", "wav", "flac", "aac", "caf"]

        // Rough temp-footprint estimates used by the ffprobe preflight.
        /// 16 kHz mono s16 WAV ≈ 32 KB/s ≈ 115 MB/hour.
        static let estimatedWavBytesPerSecond: Int = 32_000
        /// FluidAudio's on-disk raw Float32 stream ≈ 64 KB/s ≈ 230 MB/hour.
        static let estimatedRawFloatBytesPerSecond: Int = 64_000
        /// Extra free-space safety margin required beyond the estimate.
        static let freeSpaceSafetyMarginBytes: Int = 200 * 1_024 * 1_024
    }

    /// UserDefaults keys shared across the app.
    enum DefaultsKey {
        static let lmStudioBaseURL = "lmStudioBaseURL"
        static let correctionModel = "correctionModel"
        static let autoCorrectAfterTranscription = "autoCorrectAfterTranscription"
        static let meetingOutputFolder = "meetingOutputFolder"
        /// Manual override for correction batch size (chars). 0 / unset = auto-detect.
        static let correctionMaxCharsOverride = "correctionMaxCharsOverride"
    }

    enum ModelVersion: String, CaseIterable, Identifiable {
        case v2 = "v2"
        case v3 = "v3"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .v2: return "Parakeet v2 (English only)"
            case .v3: return "Parakeet v3 (25 languages)"
            }
        }

        var description: String {
            switch self {
            case .v2: return "English-only model with highest recall. Best for English dictation."
            case .v3: return "Multilingual model supporting 25 European languages with auto-detection."
            }
        }
    }
}
