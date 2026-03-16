# SOUL.md

SOUL.md defines the AI agent's personality, tone, and behavioral guidelines.

## How It Works

The SOUL.md content is prepended to the system prompt for every conversation. It shapes how the agent communicates — formal vs casual, verbose vs terse, proactive vs cautious.

## Locations

| Scope | File | Priority |
|---|---|---|
| **Global** | `~/.grump/SOUL.md` | Applied to all projects |
| **Project** | `.grump/SOUL.md` or `SOUL.md` in project root | Overrides global for this project |

Project SOUL.md takes precedence over global when both exist.

## Templates

Built-in templates available in **Settings → Workspace → Soul**:

- **Default** — Balanced, professional, concise
- **Mentor** — Patient, educational, explains reasoning
- **Senior Engineer** — Direct, opinionated, best-practices focused
- **Creative** — Exploratory, suggests alternatives, thinks broadly
- **Minimal** — Ultra-terse, code-only, minimal explanation

## Example SOUL.md

```markdown
# Soul

You are a senior Swift developer working on a macOS application.

## Communication Style
- Be direct and concise
- Show code, not prose
- Use SwiftUI best practices (iOS 17+)
- Prefer value types and protocol-oriented design

## Constraints
- Never use force unwrapping
- Always handle errors explicitly
- Use structured concurrency (async/await)
```

## Configuration

Edit in **Settings → Workspace → Soul** or directly in the file system.
