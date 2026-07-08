# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-07-08

### Added
- Meeting transcription: import an audio file (.ogg, .opus, .mp3, .m4a, .wav, .flac, .aac, .caf) from a new "Meetings" tab and transcribe it locally with Parakeet. Files are decoded via ffmpeg, so Ogg/Opus recordings work.
- Optional local correction of a transcript with a model served by LM Studio (fixes spelling, punctuation, and mis-heard words without changing meaning); the corrected version is saved separately from the raw transcript.
- Transcripts can be exported to a chosen folder as `<name>.txt` (raw) and `<name>.corrected.txt` (corrected), and are always kept in the app's meeting history.
- Settings: output folder, LM Studio URL, correction model picker, and an "auto-correct after transcription" toggle.

### Changed
- All speech recognition now runs through a single serialized actor, so live dictation and meeting-file transcription can never run at the same time and corrupt each other.
- Pinned FluidAudio to 0.7.9 (newer releases fail to build under the current Swift toolchain).

## [0.3.2] - 2026-02-17

### Fixed
- Switched accessibility runtime verification to AX API probing so granted permission no longer appears as stale after re-authorization.

## [0.3.1] - 2026-02-17

### Fixed
- Corrected accessibility permission state handling so stale/not-granted/granted status and restart behavior stay in sync with actual System Settings changes.

## [0.3.0] - 2026-02-17

### Added
- Push-to-talk mode: hold the shortcut to record, release to stop

## [0.2.0] - 2026-02-17

### Fixed

- Accessibility permission check now uses a runtime CGEventTap probe instead of relying on the TCC database, which returns stale results after ad-hoc rebuilds
- Settings view shows a distinct "Stale" warning (orange) when the TCC entry is outdated, with a one-click "Reset & Re-grant" button to clear and re-authorize
- Permission polling replaced with on-activation refresh to avoid unnecessary kernel object churn

## [0.1.1] - 2026-02-17

### Fixed

- Escape key being consumed globally even when not recording, preventing it from working in other apps

## [0.1.0] - 2026-02-17

### Added

- Global keyboard shortcut for dictation from any app (default: Cmd+Shift+Space)
- NVIDIA Parakeet TDT v3 speech recognition via CoreML with automatic language detection (25 European languages)
- Auto-paste transcribed text at cursor position using clipboard sandwich technique
- Floating pill-shaped recording overlay with mic animation and elapsed time
- Searchable transcription history stored with SwiftData
- Settings panel with model selection (v3 multilingual / v2 English-only)
- Configurable keyboard shortcuts
- Launch at login via ServiceManagement
- Cancel recording with Escape key
- Rebuild and install script (`scripts/rebuild_and_install.sh`)
- GitHub Actions CI workflow for building the macOS app
- Unit tests and UI tests
