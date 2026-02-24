# G-Rump Architecture Summary

Short reference for contributors on key architecture decisions.

## Onboarding (pre-app)

Onboarding runs **before** the main app. It never appears inside the Chat Interface.

- **Gate:** `AppRootView` checks `HasCompletedOnboarding` (UserDefaults). If `false`, it shows only `OnboardingView` (full-screen). Sidebar and chat are not shown until onboarding is finished.
- **Flow:** Splash → (if not completed) OnboardingView (3 slides, "Finish onboarding" / "Open Settings") → on finish, `HasCompletedOnboarding = true` → main app (`ContentView` with sidebar + chat).
- **Existing users:** If the user already has an API key (e.g. after upgrade), `AppRootView.onAppear` sets `HasCompletedOnboarding = true` so they are not blocked.
- **Files:** `AppRootView.swift` (gate + shared `ChatViewModel`), `OnboardingView.swift` (3-slide flow).

## Settings (tabbed)

Settings are split into **tabs** instead of a single long scroll.

- **Tabs:** Account (API Key), Appearance (Theme + Accent), Model, Project (Working Directory), Behavior (System Prompt), Tools (active tools list), About.
- **UI:** `SettingsView` uses `NavigationSplitView`: sidebar list of tabs, detail shows the selected section. Same bindings and behavior as before; only the layout is tabbed.
- **Opening to a tab:** Callers can pass `initialTab: SettingsTab?` (e.g. `.model`) so the sheet opens on that tab (e.g. from the chat toolbar model badge).
- **File:** `SettingsView.swift`; `SettingsTab` enum is internal so callers can reference it.

## 250fps target (high-frequency loop + smooth display)

The app targets a **250Hz internal update loop** and smooth display output (60/120Hz limited by the display).

- **Loop:** `FrameLoopService` runs a 250Hz timer (every 4ms) on the main thread when the app is active. It does minimal work per tick (increment tick count). Start/stop is tied to scene phase in `AppRootView`.
- **Display:** Actual frame presentation is still bounded by the display refresh rate (60 or 120Hz ProMotion). The 250Hz loop is for driving time-based state and keeping the app responsive; views can observe `frameLoop.tick` if needed.
- **FPS overlay:** Optional overlay (enable with UserDefaults `ShowFPSOverlay = true`) shows the measured loop rate in Hz.
- **Performance:** Heavy work is avoided in view bodies (e.g. markdown parsing in `MarkdownTextView` is cached and only runs when text changes). Message and conversation lists use `LazyVStack`; streaming row uses `.drawingGroup()` to reduce redraw cost.
- **Files:** `FrameLoopService.swift`, `FPSOverlayView.swift`; `AppRootView` and `GRumpApp` wire the loop and environment.

## Keyboard shortcuts

- **⌘N** New Chat  
- **⌘,** Settings  
- **⌘.** Stop generation  
- **⌘L** Focus message input  
- **⌘E** Export current conversation as Markdown  

Shortcuts work from both sidebar and detail. Listed in Help → Keyboard Shortcuts and in tooltips (e.g. sidebar Settings button).
