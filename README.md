# CustomWhisper

**Local AI dictation for macOS -- press a shortcut, speak, get text.**

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%2FM2%2FM3%2FM4-orange)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-F05138)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

---

## What is CustomWhisper?

CustomWhisper is a native macOS dictation app that runs entirely on your machine. It uses NVIDIA's Parakeet TDT v3 model (via [FluidAudio](https://github.com/FluidInference/FluidAudio) CoreML) to transcribe your voice into text at blazing speed -- then automatically pastes the result wherever your cursor is.

No cloud APIs. No subscriptions. No data leaves your Mac.

---

## Features

- **Global keyboard shortcut** -- dictate from any app without switching windows
- **NVIDIA Parakeet TDT v3** via CoreML -- 25 European languages with automatic language detection
- **~190x real-time** on Apple Silicon (1 hour of audio transcribed in ~19 seconds)
- **Auto-paste** -- transcribed text appears at your cursor position instantly
- **Recording overlay** -- floating pill-shaped indicator with mic animation and elapsed time
- **Transcription history** -- searchable log of all past transcriptions
- **Configurable shortcuts** -- set any key combination you prefer
- **Model selection** -- choose between v3 (multilingual) or v2 (English-only, higher recall)
- **Launch at login** -- always ready when you need it
- **Runs on Apple Neural Engine** -- minimal CPU and battery impact

---

## Demo

<!-- Add screenshots or a GIF here -->
> Screenshots coming soon. The app features a clean settings panel, a floating recording overlay, and a searchable transcription history.

---

## Requirements

| Requirement | Details |
|---|---|
| **macOS** | 14.0+ (Sonoma) |
| **Chip** | Apple Silicon (M1, M2, M3, M4) |
| **Xcode** | 16+ (for building from source) |
| **Disk** | ~500 MB for model download on first launch |
| **Permissions** | Microphone access, Accessibility (for auto-paste) |

---

## Installation

### Build from Source

**Prerequisites:**

```bash
brew install xcodegen
```

**Steps:**

```bash
git clone https://github.com/yourusername/customwhisper.git
cd customwhisper
xcodegen generate
open CustomWhisper.xcodeproj
```

Then in Xcode: **Product > Run** (or `Cmd+R`).

On first launch the app will automatically download the Parakeet TDT v3 CoreML model (~500 MB) from HuggingFace. This only happens once -- the model is cached locally.

### Rebuild & Install without Xcode

You can rebuild and refresh the installed app with one command:

```bash
./scripts/rebuild_and_install.sh
```

The script regenerates the project, builds `Release`, replaces `/Applications/CustomWhisper.app`, and relaunches the app.

### Permissions

The app will prompt you to grant:

1. **Microphone** -- to record your voice
2. **Accessibility** -- to auto-paste text into other apps (System Settings > Privacy & Security > Accessibility)

---

## Usage

### Basic Dictation

1. Press **Cmd + Shift + Space** (default shortcut) from any app
2. A floating recording indicator appears near the top of your screen
3. Speak naturally -- the app records your voice
4. Press **Cmd + Shift + Space** again to stop
5. Your speech is transcribed and automatically pasted at the cursor position

### Cancel Recording

- Press **Escape** to cancel the current recording without transcribing

### Keyboard Shortcuts

| Action | Default Shortcut |
|---|---|
| Toggle recording (start/stop) | `Cmd + Shift + Space` |
| Cancel recording | `Escape` |

Shortcuts are fully customizable in the Settings tab.

### Settings

Open the main app window to access:

- **Model version** -- Parakeet v3 (25 languages) or v2 (English-only)
- **Keyboard shortcuts** -- click the recorder to set a new shortcut
- **Auto-paste** -- toggle whether text is pasted automatically or just copied to clipboard
- **Save history** -- toggle transcription logging
- **Launch at login** -- start CustomWhisper when you log in

---

## Architecture

CustomWhisper is a native Swift macOS app with no web views, no Electron, and no Python.

### Tech Stack

| Component | Technology |
|---|---|
| **Language** | Swift 5.9 |
| **UI** | SwiftUI |
| **ASR Model** | NVIDIA Parakeet TDT v3 via CoreML |
| **ML Framework** | [FluidAudio](https://github.com/FluidInference/FluidAudio) (CoreML, Apple Neural Engine) |
| **Shortcuts** | [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by sindresorhus |
| **Audio** | AVFoundation (AVAudioEngine) |
| **Persistence** | SwiftData |
| **Text Pasting** | CGEvent + NSPasteboard (clipboard sandwich) |
| **Launch at Login** | ServiceManagement (SMAppService) |

### How It Works

```
Shortcut pressed
  -> AVAudioEngine records at 16kHz mono Float32
  -> Floating overlay shows recording state
Shortcut pressed again
  -> Recording stops, samples passed to FluidAudio AsrManager
  -> Parakeet TDT v3 (CoreML) transcribes on Apple Neural Engine
  -> Text pasted via clipboard sandwich (save clipboard -> set text -> Cmd+V -> restore clipboard)
  -> Transcription saved to SwiftData history
```

### Project Structure

```
CustomWhisper/
  project.yml                    # XcodeGen project definition
  CustomWhisper/
    App.swift                    # App entry point, lifecycle
    Core/
      AppStateMachine.swift      # Central state coordinator
      AppState.swift             # State enum (idle/recording/processing/error)
    Services/
      AudioRecorder.swift        # AVAudioEngine recording
      TranscriptionService.swift # FluidAudio ASR wrapper
      TextPaster.swift           # Clipboard sandwich paste
    Models/
      TranscriptionRecord.swift  # SwiftData model
    Views/
      MainWindow.swift           # Tab-based main window
      SettingsView.swift         # Settings tab
      HistoryView.swift          # History tab
      RecordingOverlay.swift     # Floating NSPanel overlay
    Utilities/
      ShortcutDefinitions.swift  # Global shortcut names
      Permissions.swift          # Permission helpers
      Constants.swift            # App constants
  CustomWhisperTests/            # Unit tests
  CustomWhisperUITests/          # UI tests
```

---

## Roadmap

- [ ] Meeting mode with speaker diarization (FluidAudio already supports this)
- [ ] Text correction via local LLM (mlx-swift / llama.cpp)
- [ ] Real-time streaming transcription (show partial results as you speak)
- [ ] Push-to-talk mode (hold shortcut to record, release to stop)
- [ ] VibeVoice-ASR integration for 60-minute long-form audio
- [ ] Additional model support from HuggingFace

---

## Acknowledgments

- [FluidAudio](https://github.com/FluidInference/FluidAudio) by FluidInference -- CoreML models for ASR, diarization, and VAD
- [NVIDIA Parakeet](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) -- the underlying speech recognition model
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by sindresorhus -- global keyboard shortcut management
- Inspired by [Spokenly](https://spokenly.app), [Superwhisper](https://superwhisper.com), [OpenWhisper](https://github.com/richardwu/openwhisper), and [Epicenter Whispering](https://github.com/EpicenterHQ/epicenter)

---

## License

MIT License. See [LICENSE](LICENSE) for details.
