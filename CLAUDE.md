# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

G-Rump is an AI coding agent macOS/iOS app written in Swift (SwiftUI) with a Node.js backend. It provides chat-based AI assistance with local file system, shell, and system control tools, using OpenRouter for model access.

## Build & Run Commands

### Swift (frontend)

```bash
make build            # Debug build (uses all CPU cores)
make build-release    # Optimized release build
make run              # Build debug + run
make clean            # Remove .build and dist
swift test            # Run tests (requires full Xcode SDK)
```

The build uses Swift Package Manager. Dependencies resolve automatically on first build. The local `.build` directory is used (not `~/Library`) to avoid permission issues.

### Backend (Node.js)

```bash
cd backend && npm install   # Install dependencies
cd backend && npm start     # Run on http://localhost:3042
cd backend && npm run dev   # Watch mode
```

Backend lint check: `node --check backend/server.js backend/proxy.js backend/auth.js backend/db.js`

### Packaging

```bash
make app              # .app bundle in dist/
make dmg              # .app + .dmg
make package          # Signed .dmg (needs DEVELOPER_ID env)
make notarize         # Full distribution (needs DEVELOPER_ID, APPLE_ID, TEAM_ID, APP_PASSWORD)
```

## Architecture

### Swift App Structure (`Sources/GRump/`)

**Entry point**: `GRumpApp.swift` → `AppRootView.swift` (onboarding gate) → `ContentView.swift` (main chat UI with sidebar)

**ChatViewModel** is the central state manager, split into extensions by responsibility:
- `ChatViewModel+Streaming.swift` — OpenRouter streaming responses
- `ChatViewModel+ToolExecution.swift` — Tool dispatch, parallel execution, retry logic
- `ChatViewModel+AgentModes.swift` — Plan, Build, Debate, Spec, Parallel modes
- `ChatViewModel+Persistence.swift` — Conversation save/load
- `ChatViewModel+Memory.swift` — Activity tracking, memory store

**Key services**:
- `OpenRouterService` — Chat completion streaming (direct or via backend proxy)
- `MultiProviderAIService` — Multi-model support with tier-based access
- `AmbientCodeAwarenessService` — Project file context injection
- `LSPService` — Language Server Protocol integration
- `FrameLoopService` — 250Hz internal loop for responsive UI (display-limited to 60/120Hz)
- `ExecApprovals` — Security approval workflow for system commands

**Data models** (`Models.swift`): `Message`, `ToolCall`, `Conversation`, `MessageThread`, `MessageBranch`. Supports linear, threaded, and branched conversation views.

**Agent modes**: `standard`, `plan`, `fullStack`, `argue`, `spec`, `parallel`

### Backend Structure (`backend/`)

Express server with 4 core modules:
- `server.js` — Entry point, middleware, routes
- `auth.js` — Google Sign-In (IdToken → JWT), user creation
- `db.js` — SQLite (users, credits, tiers: Free/Pro/Team)
- `proxy.js` — OpenRouter proxying with credit deduction

### Tests (`Tests/GRumpTests/`)

Three test files: `ModelsTests.swift`, `OpenRouterServiceTests.swift`, `MemoryStoreTests.swift`. Run a single test with `swift test --filter GRumpTests.ModelsTests` or a specific method with `swift test --filter GRumpTests.ModelsTests/testMessageCreation`.

## Key Conventions

- **Concurrency**: `@MainActor` on ChatViewModel, async/await throughout, `AsyncThrowingStream` for streaming, task groups for parallel tool execution. Strict concurrency is `targeted` (not `complete`).
- **SwiftUI state**: `@EnvironmentObject` for app-wide sharing, `@Published` for reactive props, `@AppStorage` for UserDefaults persistence. Keychain for sensitive data (API keys).
- **Performance**: `LazyVStack` for lists, `.drawingGroup()` on streaming rows, cached markdown parsing. FPS overlay via `ShowFPSOverlay` UserDefaults key.
- **Platform**: `#if os(macOS)` / `#else` guards for platform-specific code. macOS 14+ / iOS 17+.
- **No sandbox**: App entitlements disable sandbox (required for shell execution and file tools).

## Project Config

Per-project settings live in `.grump/config.json` or `grump.json` at the project root. `.grump/context.md` is auto-injected into the system prompt when present. Exec approval rules at `~/Library/Application Support/GRump/exec-approvals.json`.
