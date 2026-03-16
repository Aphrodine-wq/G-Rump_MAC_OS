# Notifications

G-Rump integrates with macOS notifications, Focus Filters, and App Intents.

## System Notifications

The `system_notify` tool sends notifications to macOS Notification Center. Configure in **Settings → Notifications**:

| Setting | Default | Description |
|---|---|---|
| Allow system notifications | ON | Enable/disable all notifications |
| Sound for notifications | ON | Play sound with notifications |
| Show menu bar extra | OFF | Show G-Rump icon in menu bar |

## Focus Filters

`FocusFilterService` integrates with macOS Focus modes:
- Detects when a Focus (Do Not Disturb, Work, etc.) is active
- Suppresses non-critical notifications during Focus
- Shows Focus status indicator in **Settings → Notifications**

When Focus is active, the agent reduces notification frequency and batches non-urgent alerts.

## App Intents

G-Rump registers App Intents for Shortcuts and Siri integration:
- Start a new conversation
- Ask a question
- Run a workflow preset

## Notification Types

| Type | When | Priority |
|---|---|---|
| **Agent Complete** | Long-running build/plan finishes | High |
| **Error** | Tool execution failure | High |
| **Update Available** | New version via Sparkle | Medium |
| **Tip** | Usage tips and suggestions | Low |

## Key Files

| File | Purpose |
|---|---|
| `NotificationService.swift` | Notification management |
| `FocusFilterService.swift` | Focus mode integration |
| `AppIntents.swift` | Shortcuts and Siri intents |
