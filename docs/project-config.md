# Project Configuration

G-Rump supports per-project configuration via `.grump/` directory in your project root.

## Config File

`.grump/config.json`:

```json
{
  "model": "anthropic/claude-3.7-sonnet",
  "systemPrompt": "Custom instructions for this project…",
  "toolAllowlist": ["read_file", "write_file", "grep_search", "system_run"],
  "projectFacts": ["Uses Swift 5.9", "SwiftLint enabled", "Targets macOS 14+"],
  "maxAgentSteps": 30,
  "contextFile": ".grump/context.md"
}
```

### Fields

| Field | Type | Description |
|---|---|---|
| `model` | string | Default model for this project |
| `systemPrompt` | string | Additional system prompt text |
| `toolAllowlist` | string[] | Restrict available tools to this list |
| `projectFacts` | string[] | Facts injected into every conversation |
| `maxAgentSteps` | number | Max tool calls per conversation turn |
| `contextFile` | string | Path to persistent context file |

## Context File

`.grump/context.md` — Markdown content injected into every conversation for this project. Use it for:
- Project architecture overview
- Coding conventions
- Important file locations
- Team-specific rules

## SOUL.md (Per-Project)

`.grump/SOUL.md` or `SOUL.md` in project root — Overrides the global SOUL.md personality for this project.

## Skills (Per-Project)

`.grump/skills/*.skill.md` — Project-specific skills loaded only when working in this directory.

## Working Directory

Set in **Settings → Workspace → Project** or via the file picker. The working directory determines which `.grump/` config is loaded.

## Workflow Presets

Presets can override project config temporarily. Configure in **Settings → AI & Model → Workflow Presets**.
