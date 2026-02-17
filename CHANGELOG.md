# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
