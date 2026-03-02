# Onboarding

G-Rump has a first-run onboarding flow that guides new users through setup.

## Flow

1. **Welcome** — App introduction and overview
2. **Provider Setup** — Configure at least one AI provider (API key)
3. **Theme Selection** — Choose a theme and accent color
4. **Working Directory** — Optionally set a default project directory
5. **Complete** — Ready to use

## Gating

`AppRootView.swift` gates the main UI behind onboarding completion:
- Checks `@AppStorage("HasCompletedOnboarding")`
- Shows `OnboardingView` if false
- Shows `ContentView` once complete

## What's New

After app updates, a "What's New" view can be shown:
- `WhatsNewView.swift` displays release highlights
- Triggered by version comparison against `@AppStorage("LastSeenVersion")`
- Accessible anytime via **Help → What's New**

## Restart Onboarding

Users can restart the onboarding flow from **Settings → About → Restart Onboarding**.

## Key Files

| File | Purpose |
|---|---|
| `AppRootView.swift` | Onboarding gate |
| `OnboardingView.swift` | Onboarding flow UI |
| `WhatsNewView.swift` | Post-update highlights |
