import Foundation

/// Represents the current state of the dictation pipeline.
enum AppState: Equatable {
    case idle
    case recording
    case processing
    case error(String)

    var isRecording: Bool { self == .recording }
    var isProcessing: Bool { self == .processing }
    var isIdle: Bool { self == .idle }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .idle: return "Ready"
        case .recording: return "Recording..."
        case .processing: return "Transcribing..."
        case .error(let message): return "Error: \(message)"
        }
    }
}
