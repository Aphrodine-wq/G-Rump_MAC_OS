# Themes

G-Rump supports 25+ themes organized into three categories.

## Theme Categories

| Category | Themes |
|---|---|
| **Light** | Lavender, Mint, Ocean, Forest, Rose, Cream, Sunset, Sand, Peach, Light |
| **Dark** | Berry, Dusk, Coffee, Dracula, Midnight, Sepia, Slate, Aurora, Ember, Dark |
| **Fun** | ChatGPT, Claude (Anthropic), Gemini, Kiro, Perplexity |

## Key Files

- **`ThemeManager.swift`** — `AppTheme` enum, `ThemePalette` struct, `ThemeManager` class
- **`DesignTokens.swift`** — Typography, Spacing, Radius, Border, Anim constants

## How Themes Work

### AppTheme Enum
Each theme is a case in `AppTheme: String, CaseIterable`. Properties:
- `displayName` — Human-readable name
- `icon` — SF Symbol name
- `colorScheme` — `.light`, `.dark`, or `nil` (system)

### ThemePalette
`ThemePalette` provides all colors for a given theme + accent combination:

| Token | Purpose |
|---|---|
| `bgDark` | Main background |
| `bgCard` | Card/container background |
| `bgSidebar` | Sidebar background |
| `bgInput` | Text input fields |
| `bgElevated` | Elevated surfaces (popovers, menus) |
| `borderCrisp` | Visible borders |
| `borderSubtle` | Subtle dividers |
| `effectiveAccent` | Primary accent color |
| `effectiveAccentDarkVariant` | Darker accent for pressed states |
| `effectiveAccentLightVariant` | Lighter accent for labels on dark bg |
| `textPrimary` | Primary text |
| `textSecondary` | Secondary/label text |
| `textMuted` | Placeholder/disabled text |

### ThemeManager
`ThemeManager` is an `ObservableObject` singleton injected as `@EnvironmentObject`. It persists selections via `UserDefaults`:
- `theme` → `"AppTheme"`
- `accentColor` → `"AccentColor"`
- `density` → `"AppDensity"`
- `contentSize` → `"AppContentSize"`

## Accent Colors

7 accent colors: Purple, Blue, Green, Orange, Pink, Teal, Amber. Each has `.color`, `.darkVariant`, and `.lightVariant`. Fun themes override the accent with their brand color.

## Adding a New Theme

1. Add a `case` to `AppTheme`
2. Add `displayName`, `icon`, `colorScheme`
3. Add the case to the appropriate static array (`lightThemes`, `darkThemes`, or `funThemes`)
4. Add color values to every `ThemePalette` switch: `bgDark`, `bgCard`, `bgSidebar`, `bgInput`, `bgElevated`, `borderCrisp`, `borderSubtle`, `effectiveAccent`, `effectiveAccentDarkVariant`, `effectiveAccentLightVariant`, `textPrimary`, `textSecondary`, `textMuted`

## UI Selection

Theme picker is in **Settings → Appearance**. Themes are displayed as a horizontal scroll of cards grouped by category.
