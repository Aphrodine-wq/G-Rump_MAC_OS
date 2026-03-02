# Layout

G-Rump's layout is highly customizable with multiple panels and modes.

## Layout Structure

```
┌──────────┬─────────────────────┬──────────┬───┐
│ Sidebar  │     Chat Area       │  Right   │ R │
│ (convos) │                     │  Panel   │ I │
│          │  ┌───────────────┐  │          │ S │
│          │  │ Messages      │  │ (17 tabs)│   │
│          │  │               │  │          │   │
│          │  │               │  │          │   │
│          │  └───────────────┘  │          │   │
│          │  ┌───────────────┐  │          │   │
│          │  │ Input Bar     │  │          │   │
│          │  └───────────────┘  │          │   │
└──────────┴─────────────────────┴──────────┴───┘
                                              ^
                                        Right Icon
                                        Sidebar (RIS)
```

## Components

| Component | File | Description |
|---|---|---|
| **Conversation Sidebar** | `ConversationSidebar.swift` | Left sidebar with conversation list |
| **Chat Area** | `ChatAreaView.swift` | Message list + input bar |
| **Right Panel** | `RightPanelManager.swift` | Panel content for 17 tabs |
| **Right Icon Sidebar** | `RightPanelSidebar.swift` | Vertical icon buttons |
| **Layout Customizer** | `LayoutCustomizerView.swift` | `⌘⇧L` overlay for layout options |

## Zen Mode

Hides all panels and sidebars, showing only the chat area. Toggle via Layout Customizer or keyboard shortcut.

## Activity Bar

The right icon sidebar can be shown/hidden. When hidden, panels are accessed via the menu or shortcuts.

## Density

Two density levels affect spacing throughout the app:
- **Comfortable** — Default, spacious layout (scale 1.0)
- **Compact** — Tighter spacing (scale 0.92)

Configure in **Settings → Appearance → Density**.

## Content Size

Three text scale levels:
- **Small** — 0.92x
- **Medium** — 1.0x (default)
- **Large** — 1.12x

Configure in **Settings → Appearance → Content Size**.
