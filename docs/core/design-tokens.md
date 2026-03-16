# Design Tokens

G-Rump uses a centralized design token system defined in `DesignTokens.swift` for consistent UI styling.

## Typography

All text uses the `Typography` enum with pre-defined font styles:

| Token | Size | Weight | Usage |
|---|---|---|---|
| `heading1` | 24pt | Bold | Page titles |
| `heading2` | 20pt | Semibold | Section headers |
| `heading3` | 17pt | Semibold | Card titles |
| `body` | 14pt | Regular | Body text |
| `bodySemibold` | 14pt | Semibold | Emphasized body |
| `bodySmall` | 13pt | Regular | Secondary text |
| `bodySmallSemibold` | 13pt | Semibold | Labels |
| `bodySmallMedium` | 13pt | Medium | Interactive labels |
| `bodyMedium` | 14pt | Medium | Medium emphasis |
| `captionSemibold` | 12pt | Semibold | Section labels |
| `captionSmall` | 11pt | Regular | Captions |
| `captionSmallSemibold` | 11pt | Semibold | Bold captions |
| `captionSmallMedium` | 11pt | Medium | Medium captions |
| `codeSmall` | 11pt | Monospaced | Inline code |
| `micro` | 10pt | Medium | Badges, tags |

## Spacing

The `Spacing` enum provides consistent spacing values:

| Token | Value | Usage |
|---|---|---|
| `xs` | 2pt | Tight inline spacing |
| `sm` | 4pt | Small gaps |
| `md` | 6pt | Default element spacing |
| `lg` | 8pt | Card padding |
| `xl` | 10pt | Section spacing |
| `xxl` | 12pt | Large section gaps |
| `huge` | 16pt | Major layout spacing |

## Corner Radii

The `Radius` enum:

| Token | Value | Usage |
|---|---|---|
| `sm` | 4pt | Small elements (badges) |
| `md` | 6pt | Inputs, small cards |
| `standard` | 8pt | Default cards |
| `lg` | 10pt | Large cards |
| `xl` | 14pt | Input bars |
| `xxl` | 16pt | Hero cards |

## Borders

The `Border` enum:

| Token | Value | Usage |
|---|---|---|
| `hairline` | 0.5pt | Subtle dividers |
| `thin` | 1pt | Standard borders |
| `medium` | 1.5pt | Emphasized borders |

## Animations

The `Anim` enum:

| Token | Value | Usage |
|---|---|---|
| `quick` | 0.15s | Hover states |
| `standard` | 0.25s | Default transitions |
| `slow` | 0.4s | Large layout changes |

## Usage Pattern

```swift
Text("Hello")
    .font(Typography.bodySemibold)
    .foregroundColor(themeManager.palette.textPrimary)
    .padding(Spacing.lg)
    .background(themeManager.palette.bgCard)
    .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: Radius.standard, style: .continuous)
            .stroke(themeManager.palette.borderSubtle, lineWidth: Border.thin)
    )
```
