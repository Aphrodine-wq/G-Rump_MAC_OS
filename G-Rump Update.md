# G-Rump Update: Evolution Plan

**Date:** February 28, 2026

---

## Where G-Rump Stands Right Now

G-Rump is a native macOS/iOS AI coding agent. 100K lines of Swift. 150+ tools. 6 AI providers. 6 agent modes including parallel multi-agent orchestration. 50+ MCP server integrations. ExecApprovals security. Soul/Skill system. Adaptive 60-120Hz streaming. One external dependency (Sparkle).

That's a serious foundation. But right now it lives in the same lane as Cursor, Windsurf, and Claude Code — the "AI coding agent" category. That lane is getting crowded fast.

---

## The Market Proof: Why Staying a Coding Agent Isn't Enough

The numbers tell the story of where the opportunity is — and where it isn't.

### The coding agent lane is already won (and consolidating)

Cursor hit $500M ARR and a $9B valuation in May 2025. GitHub Copilot holds 40% market share with 20M+ users. Seven companies crossed $100M ARR in this space. OpenAI bought Windsurf for $3B. The coding AI market is ~$4B and the top 3 players own 70%+ of it.

Competing head-to-head here means fighting Cursor's $900M in funding, GitHub's distribution, and OpenAI's resources. That's not where G-Rump wins.

### The ambient AI layer is wide open (and the incumbents just died)

Rewind AI was the only real ambient computing product on Mac. Meta acquired them in December 2025, shut down the Rewind app on December 19th, and killed the Limitless pendant. The product is gone. Amazon did the same thing — acquired Bee (another ambient AI startup) and absorbed it.

That means the "always-on AI that understands your context" space on Mac has zero independent players right now. The two companies that were building it got absorbed by Meta and Amazon, who will turn them into closed ecosystem plays. There is no standalone ambient AI product on macOS today.

### Apple Intelligence failed to fill the gap

Apple Intelligence launched to widespread criticism. Users report little to no value from it. It's limited to newer hardware only (even a $999 iPhone 15 Plus doesn't qualify). It only works in US English. Meta blocked it from Facebook, WhatsApp, and Instagram entirely. Users describe it as "goofy and generally useless." Apple's approach of extreme caution means Siri remains objectively behind every competitor on actual capability.

The Mac user who wants real AI integrated into their workflow has no good option right now.

### The AI agent market is exploding beyond coding

The broader AI agent market is projected to grow from $7.84B (2025) to $52.62B by 2030 — a 46.3% CAGR. 80% of companies have moved past pilots into full-scale deployment. But critically, privacy and on-device processing is the #1 factor enterprises weigh when choosing vendors. Small Language Models running locally are becoming the standard for sensitive industries. 2026 is the year of hybrid architectures — local processing with selective cloud escalation.

G-Rump already supports on-device CoreML and local Ollama. This is where the market is heading.

### Native macOS apps have a real performance advantage

Electron apps (Cursor, VS Code, most competitors) use significantly more memory and battery than native Swift apps. Mac users consistently express frustration with Electron-based AI tools. G-Rump's pure SwiftUI architecture with CVDisplayLink-synced frame loops is a measurable advantage that Electron competitors literally cannot replicate without rewriting their entire stack.

---

## What G-Rump Should Become

G-Rump should evolve from a coding agent into an **ambient AI workspace** — an always-on, context-aware AI layer that runs natively on macOS, understands everything you're working on across your machine, and acts proactively rather than waiting for prompts.

Not a chatbot with extra features. Not a Siri replacement. A persistent AI environment that wraps around your existing workflow and makes every app smarter.

The difference from the previous vision document: this isn't about building a new product. This is about evolving G-Rump specifically, using what's already built, in a focused sequence of concrete changes.

---

## How to Build It: The Exact Steps

### Update 1: Persistent Memory (Weeks 1-4)

**The problem it solves:** Every G-Rump conversation starts from zero. The user re-explains their project, their preferences, their codebase structure every time.

**What to build:**

File: `MemoryStore.swift` (new, ~400 lines)
- Actor-based persistent memory using sqlite-vec (SQLite extension for vector search)
- Store conversation summaries, user preferences, project context, tool usage patterns
- On-device embedding generation via CoreML (use a small model like all-MiniLM-L6-v2 converted to .mlmodel)
- Three memory tiers: Session (current conversation), Project (per-workspace), Global (cross-project)

File: `ChatViewModel+Memory.swift` (new extension, ~200 lines)
- Hook into `sendMessage()` to inject relevant memory into system prompt
- After each conversation turn, extract and store key facts asynchronously
- Memory retrieval: vector similarity search + recency weighting

File: `MemoryPanel.swift` (new panel view, ~150 lines)
- Add to the existing 17+ panel system
- Shows what G-Rump remembers about the current project
- User can edit, pin, or delete memory items

**What you're modifying in the existing codebase:**
- `ChatViewModel.swift` — add `memoryStore` property to the 4 existing `@StateObject` singletons
- `ChatViewModel+Streaming.swift` — add memory retrieval call before `runAgentLoop()`
- `PanelRegistry` (or equivalent) — register the new MemoryPanel

**Why this works first:** Memory is the foundation everything else builds on. Without it, proactive features have no context to act on. With it, G-Rump immediately feels smarter than every competitor because it remembers.

---

### Update 2: Menu Bar Presence (Weeks 5-8)

**The problem it solves:** G-Rump only exists when you open the app. It should always be there, ready.

**What to build:**

File: `MenuBarAgent.swift` (new, ~300 lines)
- macOS `NSStatusItem` menu bar app (lightweight, separate from main window)
- Shows current context awareness: active project, recent activity, pending suggestions
- Quick actions: ask a question, run a command, open full G-Rump
- Global keyboard shortcut to activate (like Spotlight: `⌘⇧G` or similar)

File: `QuickChatPopover.swift` (new, ~200 lines)
- A small floating panel that appears from the menu bar
- Supports quick Q&A without opening the full app
- Shares the same `ChatViewModel` and memory as the main app

File: `AmbientMonitor.swift` (new, ~250 lines)
- Extends the existing `AmbientCodeAwarenessService` beyond code files
- Watches: active app (via `NSWorkspace.shared.frontmostApplication`), clipboard changes, file system events in the workspace
- Feeds context into the memory store continuously
- All processing on-device, nothing leaves the machine

**What you're modifying:**
- `GRumpApp.swift` — add `MenuBarAgent` initialization alongside the existing `@StateObject` singletons
- `AppDelegate.swift` — register the `NSStatusItem` in the app delegate lifecycle
- `AmbientCodeAwarenessService` — extend to accept non-code file types and app context

**Why this works second:** Once memory exists, the menu bar agent has something to display. It becomes the always-present entry point that makes G-Rump feel like part of the OS rather than just another app.

---

### Update 3: Proactive Suggestions (Weeks 9-12)

**The problem it solves:** Every AI tool today waits for you to type something. G-Rump should surface relevant actions before you think to ask.

**What to build:**

File: `ProactiveEngine.swift` (new, ~400 lines)
- Event-driven suggestion system
- Monitors: file changes (FSEvents), git status, calendar events (EventKit), time-based triggers
- Priority queue: each suggestion has an urgency score (0-100) and a staleness timer
- User preference learning: track which suggestions get accepted vs. dismissed, adjust weights

File: `SuggestionTypes.swift` (new, ~100 lines)
- Enum of proactive suggestion types, starting with:
  - `uncommittedChanges` — you haven't committed in X hours, here's a summary of what changed
  - `meetingPrep` — meeting starts in 15 minutes, here's what you need to know
  - `testFailure` — tests failed after your last edit, here's the relevant error
  - `dependencyAlert` — a package you use has a known vulnerability
  - `contextSwitch` — you switched projects, here's where you left off last time
  - `codeReview` — PR assigned to you, here's a quick summary

File: `SuggestionBannerView.swift` (new, ~100 lines)
- Subtle notification-style banner in the menu bar agent and main app
- Three actions per suggestion: Accept (execute), Snooze (remind later), Dismiss (don't show again)

**What you're modifying:**
- `MenuBarAgent.swift` — display pending suggestions with badge count
- `ChatViewModel+Streaming.swift` — when a suggestion is accepted, route it into the normal agent loop
- `MemoryStore.swift` — store suggestion acceptance/dismissal patterns for learning

**Why this works third:** Memory + presence + proactive suggestions = G-Rump starts feeling like it's thinking about your work even when you're not talking to it. This is the inflection point where it stops being "a coding tool" and becomes "my AI workspace."

---

### Update 4: Channel Connections (Weeks 13-20)

**The problem it solves:** Your work context is split across email, Slack, GitHub, calendar, and files. G-Rump should understand all of it.

**What to build:**

File: `ChannelAdapter.swift` (new protocol, ~50 lines)
```
protocol ChannelAdapter {
    var id: String { get }
    var displayName: String { get }
    func connect(credentials: ChannelCredentials) async throws
    func fetchRecent(limit: Int) async throws -> [ChannelMessage]
    func search(query: String) async throws -> [ChannelMessage]
    func send(message: OutgoingMessage) async throws
}
```

Start with 3 adapters (one per file, ~200 lines each):
- `GitHubAdapter.swift` — PRs, issues, notifications via GitHub API (you already have git tools, extend them)
- `CalendarAdapter.swift` — Apple EventKit (you already have `calendar_events` in the tool system, promote it)
- `SlackAdapter.swift` — Slack Web API via OAuth, read channels and DMs

File: `ChannelManager.swift` (new, ~200 lines)
- Manages adapter lifecycle, credential storage (Keychain — you already use this), polling intervals
- Normalizes all channel messages into a common `ChannelMessage` format
- Feeds into the memory store for cross-channel context

File: `ChannelPanel.swift` (new panel view, ~200 lines)
- Unified view of recent activity across all connected channels
- AI-generated summaries of what happened since you last looked
- Clickable items that open the source (GitHub PR, Slack thread, calendar event)

**What you're modifying:**
- `MemoryStore.swift` — add channel message indexing
- `ProactiveEngine.swift` — add channel-triggered suggestions (new PR assigned, meeting conflict detected, Slack mention in a thread you follow)
- `SettingsView` — add channel connection configuration

**Why this works fourth:** Channels give the memory store and proactive engine dramatically more context. Now G-Rump doesn't just know about your code — it knows about the conversation around the code, the deadlines, the people involved.

---

### Update 5: Agent Specialization (Weeks 21-28)

**The problem it solves:** One AI trying to do everything is mediocre at most things. Specialized agents can be excellent at their specific role.

**What to build:**

This is an evolution of G-Rump's existing parallel agent mode (`.parallel` in `AgentOrchestrator`), not a rewrite.

File: `AgentDefinition.swift` (new, ~100 lines)
- Extends the existing Soul system to support per-agent Souls
- Each agent gets: a Soul (personality/instructions), a tool whitelist (subset of the 150+), a memory partition

File: `AgentRegistry.swift` (new, ~150 lines)
- Registry of available agent types, starting with:
  - **Code Agent** — existing G-Rump capabilities (all code tools, LSP, git)
  - **Research Agent** — web search, URL reading, document analysis, summarization
  - **Ops Agent** — calendar management, channel monitoring, file organization, scheduling

File: `AgentOrchestrator+Persistent.swift` (new extension, ~300 lines)
- Extends the existing `AgentOrchestrator` to support long-running agents (not just per-task)
- Agents can run background tasks (e.g., Ops Agent monitors channels every 5 minutes)
- Inter-agent messaging via the existing message format — agents can hand off tasks to each other
- Uses Swift Distributed Actors for thread-safe inter-agent communication

**What you're modifying:**
- `ChatViewModel+Streaming.swift` — route user requests to the appropriate agent based on intent detection
- `AgentOrchestrator` — add persistent agent lifecycle management alongside existing per-task orchestration
- `Soul` system — extend to load agent-specific soul files from a `souls/` directory

**Why this works fifth:** By this point, G-Rump has memory, presence, proactive intelligence, and channel connections. Splitting the workload across specialized agents makes each capability sharper. The Code Agent handles your PR review while the Ops Agent preps your meeting notes simultaneously.

---

## Proof This Would Be Better: Direct Competitor Comparison

| Capability | Cursor ($9B) | Claude Code | Apple Intelligence | Rewind (dead) | G-Rump (today) | G-Rump (updated) |
|---|---|---|---|---|---|---|
| Native macOS | No (Electron) | No (terminal) | Yes (shallow) | Yes | Yes | Yes |
| Always-on presence | No | No | Yes (Siri) | Yes | No | Yes |
| Persistent memory | No | Limited | No | Yes (recording) | No | Yes (semantic) |
| Proactive suggestions | No | No | Basic | No | No | Yes |
| Multi-channel context | No | No | Limited | No | No | Yes |
| Multi-agent orchestration | No | No | No | No | Yes (per-task) | Yes (persistent) |
| 150+ native tools | No | ~20 | No | No | Yes | Yes |
| On-device AI processing | No | No | Yes | No | Yes (CoreML, Ollama) | Yes |
| Code intelligence (LSP) | Yes | Yes | No | No | Yes | Yes |
| MCP extensibility | No | Yes | No | No | Yes (50+) | Yes (50+) |
| Privacy-first architecture | No | No | Yes | Partial | Yes | Yes |
| Self-evolving skills | No | No | No | No | Basic (static) | Yes (generative) |

G-Rump updated fills the only column with "Yes" across every row. No other product does that. Not Cursor at $9B. Not Apple with infinite resources.

### Why each competitor can't replicate this easily:

**Cursor** would have to rewrite their entire Electron frontend in Swift to get native macOS integration, Spotlight access, Keychain storage, and CVDisplayLink frame sync. That's a multi-year effort that would break their cross-platform story. Their business model depends on being on Windows + Mac + Linux.

**Claude Code** is a terminal tool. Adding a native GUI, menu bar presence, and ambient monitoring would mean building an entirely separate product. Anthropic is focused on the API and web interface, not desktop apps.

**Apple Intelligence** is constrained by Apple's extreme caution, hardware restrictions, and refusal to let third-party AI models run with system-level access. They'll never ship a code agent or multi-model orchestration.

**Rewind/Limitless** is dead as an independent product. Meta will turn it into a Meta ecosystem play, not an open macOS tool.

**OpenClaw** has the channel architecture but no native app, no code intelligence, no multi-agent orchestration, and no ambient awareness. It's a gateway server, not a desktop experience.

---

## What This Gets You in Business Terms

### Addressable market shift

Staying as a coding agent: competing in a $4B market where 3 players own 70%.
Evolving into an ambient AI workspace: competing in the $52B AI agent market (2030 projection) with no established Mac-native competitor.

### Revenue model evolution

Current: credit-based billing for AI API calls (commodity, race to zero).
Updated: subscription for the ambient workspace layer (sticky, high retention). The AI calls become a feature of the workspace, not the product itself.

### Pricing power

Cursor charges $20/mo for a code editor with AI. An ambient AI workspace that handles code + communications + scheduling + proactive intelligence across your entire Mac is worth $30-50/mo easily. Enterprise teams managing developers would pay $75-100/seat for a tool that reduces context-switching overhead.

### Competitive timing

The ambient AI space on Mac is empty RIGHT NOW because Rewind got acquired in December 2025. The window to establish G-Rump as the default won't stay open forever. Meta and Amazon are building their versions internally. Apple will eventually improve Apple Intelligence. But none of them will ship a privacy-first, multi-model, multi-agent, native Mac workspace in 2026. G-Rump can.

---

## The 28-Week Timeline

| Week | Update | Deliverable | User-Facing Change |
|------|--------|-------------|-------------------|
| 1-4 | Persistent Memory | `MemoryStore`, `MemoryPanel`, memory injection | G-Rump remembers you between sessions |
| 5-8 | Menu Bar Presence | `MenuBarAgent`, `QuickChatPopover`, `AmbientMonitor` | G-Rump is always available from the menu bar |
| 9-12 | Proactive Suggestions | `ProactiveEngine`, `SuggestionTypes`, `SuggestionBanner` | G-Rump suggests actions before you ask |
| 13-20 | Channel Connections | `ChannelAdapter` protocol, GitHub/Calendar/Slack adapters, `ChannelPanel` | G-Rump understands your work across apps |
| 21-28 | Agent Specialization | `AgentDefinition`, `AgentRegistry`, persistent orchestration | G-Rump runs specialized agents in parallel |

Each update ships as a usable G-Rump release. No update depends on a future update to be valuable. Users get immediate benefit at every step.

---

## What NOT to Build

Things that sound appealing but would distract from the core evolution:

- **Windows/Linux support** — the entire advantage is native macOS integration. Cross-platform would destroy that.
- **A web interface** — defeats the ambient, on-device purpose. Keep the iOS companion minimal.
- **Custom AI models** — use existing providers through the multi-provider architecture. Training models is a money pit.
- **Hardware** — Rewind tried a pendant and it got them acqui-hired. Stay software.
- **A social/community layer** — skill sharing later, but don't build a social network. Stay focused.

---

## Summary

G-Rump is already the most capable native macOS AI agent in existence. The update path is clear: add persistent memory, become always-present, get proactive, connect channels, and specialize agents. Five updates, 28 weeks, all building on the existing 100K-line codebase.

The timing is perfect. The ambient AI space on Mac is empty. The market is growing at 46% CAGR. Users want native, private, on-device AI that actually works. Nobody else can build this because nobody else has the native Swift foundation, the 150+ tool system, the multi-agent orchestrator, and the MCP extensibility that G-Rump already has.

This isn't speculation. The competitors are Electron-bound, terminal-bound, cloud-bound, or dead. G-Rump is the only product positioned to fill this gap.
