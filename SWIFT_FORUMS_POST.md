# [Show & Tell] G-Rump — A Native macOS AI Coding Agent Built Entirely in Swift

I've been building **G-Rump**, a native macOS AI coding agent — think Cursor or Windsurf, but built from scratch in pure Swift with zero external dependencies. I wanted to share it with the Swift community since it leans heavily on Apple frameworks and I'd love feedback.

## What is it?

G-Rump is an AI-powered coding assistant that runs as a native macOS app. It has a full IDE-like interface with a sidebar, chat panel, and 17 specialized panels (file navigator, git, tests, terminal, profiling, localization, etc.). You chat with it, and it can read/write files, run shell commands, search the web, manage git, deploy to cloud, and more — 100+ tool definitions total.

## Why Swift?

I wanted to prove that a full AI agent platform could be built natively on Apple's stack — no Electron, no Node.js runtime, no React Native. The result is an app that launches instantly, uses ~80MB of RAM idle, and integrates with macOS at a level that web-based tools simply can't.

## Apple Frameworks Used (32)

This project touches nearly every major Apple framework:

| Category | Frameworks |
|---|---|
| **UI** | SwiftUI, AppKit, UIKit, CoreGraphics, QuartzCore, PDFKit, ImageIO |
| **AI/ML** | CoreML, NaturalLanguage, Vision, Speech |
| **System Integration** | CoreSpotlight, AppIntents, UserNotifications, ActivityKit, ScreenCaptureKit |
| **Security** | Security, CryptoKit, LocalAuthentication |
| **Data** | SwiftData, Foundation, Combine, UniformTypeIdentifiers |
| **Contacts & Calendar** | Contacts, EventKit |
| **Spatial** | ARKit, RealityKit (visionOS stubs) |
| **Media** | AVFoundation, CoreImage |
| **Diagnostics** | OSLog, os.signpost |

## Key Technical Highlights

### Deep Apple Integration

- **Spotlight** — Conversations are indexed via `CoreSpotlight` so you can search your AI chat history from anywhere
- **Siri Shortcuts** — `AppIntents` exposes "Ask G-Rump", "New Chat", and "Run Agent Task" to Shortcuts.app and Siri
- **Handoff** — Start a conversation on your Mac, continue on another device
- **Live Activities** — Long-running agent tasks show progress on the Lock Screen and Dynamic Island (iOS)
- **Secure Enclave** — API keys stored via `LocalAuthentication` + Keychain, not plaintext
- **CoreML** — On-device inference with downloadable quantized models from HuggingFace
- **NaturalLanguage** — Semantic memory search using `NLEmbedding` for RAG (retrieval-augmented generation)
- **Focus Filters** — Integrates with Focus modes to auto-configure agent behavior

### Architecture

- **Zero external dependencies** — `Package.swift` has an empty `dependencies: []` array. Everything is Apple frameworks + hand-rolled networking.
- **MCP Protocol** — Supports 58 pre-configured Model Context Protocol servers for extensibility
- **Multi-provider AI** — Anthropic, OpenAI, Ollama, OpenRouter, and on-device CoreML — all via a unified streaming interface
- **Skills system** — 40+ bundled `SKILL.md` files (SwiftUI patterns, async/await, Kubernetes, code review) plus custom per-project skills
- **SOUL.md** — Global and per-project AI personality configuration
- **Agent modes** — Chat, Plan, Build, Debate, Spec, Parallel — each tailors the system prompt and tool selection
- **Unified `os.Logger`** — All logging goes through Apple's unified logging system with 10 subsystem categories, zero `print()` statements
- **Strict concurrency** — `StrictConcurrency=targeted` with zero warnings

### IDE Features

- 17 built-in panels: File Navigator, Git, Tests, Assets, Localization, Profiling, Logs, Terminal, App Store Tools, Apple Docs, and more
- LSP integration via SourceKit-LSP for live diagnostics
- Themes: Light, Dark, and fun themes matching Cursor, ChatGPT, Claude, Gemini, and Kiro
- Zen Mode, Activity Bar, customizable layout, full keyboard shortcuts
- 250Hz internal update loop for buttery-smooth streaming

## Stats

- ~25,000 lines of Swift across 80+ files
- 100+ tool definitions with real executors
- 40+ bundled skills
- 10 test files with ~40 tests
- Builds in ~10 seconds on M-series Macs
- macOS 14+ / iOS 17+ / visionOS ready

## What I Learned

1. **SwiftUI is production-ready for complex apps** — but you need `LazyVStack`, `drawingGroup()`, and careful state management for performance with large message lists.
2. **`os.Logger` is dramatically better than `print()`** — structured logging with categories, persistence, and Console.app filtering. Every Apple app should use it.
3. **`AppIntents` is underrated** — exposing actions to Siri/Shortcuts took ~50 lines of code and makes the app feel deeply integrated.
4. **`NLEmbedding` is free on-device vector search** — no need for external vector databases for small-to-medium RAG workloads.
5. **SPM works for large apps** — but you'll want `#if` flags to handle SwiftData macro expansion differences between `swift build` and Xcode.

## Try It / Source

GitHub: **[link to your repo]**

Built solo. Feedback welcome — especially on SwiftUI performance patterns, concurrency approaches, or Apple framework usage I might be missing.

---

*Built with Swift 5.9, targeting macOS 14+ / iOS 17+. Zero external dependencies.*
