# Data Persistence

G-Rump uses multiple storage mechanisms for different data types.

## Storage Layers

| Data | Storage | Location |
|---|---|---|
| **Conversations** | SwiftData | App container |
| **Messages** | SwiftData | App container |
| **Settings** | UserDefaults | `~/Library/Preferences/` |
| **API Keys** | Keychain | macOS Keychain |
| **Exec Approvals** | JSON file | `~/Library/Application Support/GRump/` |
| **Skills** | Markdown files | `~/.grump/skills/` or `.grump/skills/` |
| **Project Config** | JSON file | `.grump/config.json` |
| **SOUL.md** | Markdown file | `~/.grump/SOUL.md` or `.grump/SOUL.md` |
| **Project Memory** | `MemoryStore` | App container |

## SwiftData Models

Primary models:
- **Conversation** — Title, creation date, messages, mode, model
- **Message** — Role, content, timestamp, tool calls, reactions

## Export / Import

**Settings → Data** provides:
- **Export** — Save all conversations as JSON or individual as Markdown
- **Import** — Load conversations from JSON backup
- **Reset** — Clear all data (with confirmation)

## JSON Fallback

For data that doesn't fit SwiftData (exec approvals, workflow presets), plain JSON files are used with atomic writes for crash safety.

## Project Memory

`MemoryStore` and `SemanticMemoryStore` maintain per-project context that persists across conversations:
- Key facts about the project
- Common patterns and conventions
- User corrections and preferences

Manage in **Settings → Project Memory**.

## Key Files

| File | Purpose |
|---|---|
| `Conversation.swift` | SwiftData conversation model |
| `Message.swift` | SwiftData message model |
| `ExecApprovalsStorage.swift` | JSON exec approvals |
| `MemoryStore.swift` | Project memory |
| `SemanticMemoryStore.swift` | Semantic search over memories |
