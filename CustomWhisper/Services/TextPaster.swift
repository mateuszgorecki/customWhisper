import AppKit
import CoreGraphics

/// Pastes text into the active application using the "clipboard sandwich" technique:
/// save clipboard -> set text -> simulate Cmd+V -> restore clipboard.
enum TextPaster {

    // MARK: - Public API

    /// Paste the given text into the frontmost application.
    @MainActor
    static func paste(_ text: String) async throws {
        guard !text.isEmpty else { return }

        guard Permissions.isAccessibilityGranted else {
            throw PasteError.accessibilityNotGranted
        }

        let pasteboard = NSPasteboard.general
        let savedContents = savePasteboard(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        try await Task.sleep(for: .milliseconds(50))

        simulatePaste()

        try await Task.sleep(for: .milliseconds(100))

        restorePasteboard(pasteboard, contents: savedContents)
    }

    /// Check if accessibility permission is available.
    static var isAvailable: Bool {
        Permissions.isAccessibilityGranted
    }

    // MARK: - Clipboard Helpers

    private static func savePasteboard(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        var savedItems: [NSPasteboardItem] = []

        for item in pasteboard.pasteboardItems ?? [] {
            let savedItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    savedItem.setData(data, forType: type)
                }
            }
            savedItems.append(savedItem)
        }

        return savedItems
    }

    private static func restorePasteboard(_ pasteboard: NSPasteboard, contents: [NSPasteboardItem]) {
        pasteboard.clearContents()
        if !contents.isEmpty {
            pasteboard.writeObjects(contents)
        }
    }

    // MARK: - Keystroke Simulation

    private static func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)   // 0x09 = 'V'
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

// MARK: - Errors

enum PasteError: LocalizedError {
    case accessibilityNotGranted

    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "Accessibility permission is required to paste text. Please enable it in System Settings > Privacy & Security > Accessibility."
        }
    }
}
