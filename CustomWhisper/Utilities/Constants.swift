import Foundation

enum AppConstants {
    static let appName = "CustomWhisper"
    static let defaultModelVersion = "v3"

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
