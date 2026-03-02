# Accessibility

G-Rump includes built-in accessibility features and an audit panel for projects.

## Accessibility Audit Panel

The **Accessibility** panel (right sidebar) provides:
- Automated accessibility audit for SwiftUI views
- VoiceOver label coverage analysis
- Dynamic Type compliance checking
- Color contrast ratio validation
- Actionable fix suggestions

## Built-in Accessibility

### VoiceOver
All interactive elements have `accessibilityLabel` modifiers:
- Send button → "Send message"
- Stop button → "Stop generation"
- Reaction buttons → "Thumbs up", "Thumbs down"
- Panel tabs → Panel name
- Settings controls → Descriptive labels

### Dynamic Type
- Typography system (`DesignTokens.swift`) uses relative font sizes
- Content Size setting (Small/Medium/Large) applies a scale factor
- Layout adapts to larger text without clipping

### Keyboard Navigation
- Full keyboard navigation support
- All actions accessible via keyboard shortcuts
- Focus indicators on interactive elements
- Tab order follows visual layout

### Color & Contrast
- All themes maintain WCAG AA contrast ratios for text
- Status indicators use both color and shape (dot + text label)
- Interactive elements have sufficient contrast in all themes

## Accessibility Labels in Code

Pattern used throughout:
```swift
Button(action: onSend) {
    Image(systemName: "arrow.up")
}
.accessibilityLabel("Send message")
```

## Key Files

| File | Purpose |
|---|---|
| `AccessibilityAuditView.swift` | Audit panel UI |
| `DesignTokens.swift` | Typography with relative sizing |
| `ThemeManager.swift` | Theme contrast compliance |
