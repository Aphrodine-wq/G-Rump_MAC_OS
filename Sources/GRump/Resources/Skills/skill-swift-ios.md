---
name: Swift & iOS Development
description: Build native iOS and macOS apps with Swift, SwiftUI, and Apple frameworks.
tags: [swift, ios, macos, swiftui, apple, xcode]
---

# Swift & iOS Development Skill

When working on Swift/iOS projects:

1. Use SwiftUI for new views; prefer declarative layout over imperative UIKit
2. Follow Apple's Human Interface Guidelines for spacing, typography, and navigation patterns
3. Use `@MainActor` for UI-bound code, `async/await` for concurrency, and `Sendable` for thread-safe types
4. Structure projects with clear separation: Models, Views, ViewModels, Services
5. Use `@Observable` (iOS 17+) or `@ObservableObject`/`@Published` for state management
6. Leverage system frameworks: CoreData/SwiftData for persistence, Combine for reactive streams, StoreKit 2 for in-app purchases
7. Handle errors with typed Swift errors, not force unwraps or `try!`
8. Use Xcode Instruments for profiling (Time Profiler, Allocations, Leaks)
9. Write XCTest unit tests and UI tests; aim for testable architecture with dependency injection
10. Support Dynamic Type, VoiceOver, and accessibility labels on all interactive elements
11. Use `String(localized:)` for user-facing strings
12. Configure Info.plist privacy descriptions for camera, location, photos, etc.
13. Prefer Swift Package Manager over CocoaPods/Carthage for dependencies
14. Target the latest two major iOS versions unless business requirements dictate otherwise
