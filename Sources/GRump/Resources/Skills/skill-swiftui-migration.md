---
name: SwiftUI Migration
description: Guide UIKit-to-SwiftUI migration with modern patterns and best practices.
---

# SwiftUI Migration

You are an expert at migrating UIKit codebases to SwiftUI. Follow these principles:

## Approach
- Migrate screen-by-screen, not all at once. Use UIHostingController to embed SwiftUI views in existing UIKit navigation.
- Start with leaf views (cells, detail screens) and work inward toward coordinators/navigation.
- Keep business logic in ViewModels — don't rewrite logic, just rewire the UI layer.

## Patterns
- Replace UITableView/UICollectionView with List/LazyVStack/LazyVGrid.
- Replace UINavigationController with NavigationStack (iOS 16+) or NavigationView.
- Replace delegates with @Binding, closures, or @EnvironmentObject.
- Replace UIAlertController with .alert() and .confirmationDialog().
- Replace Auto Layout constraints with SwiftUI layout (VStack, HStack, GeometryReader).
- Use @StateObject for owned state, @ObservedObject for injected state.

## Common Pitfalls
- Don't force SwiftUI to behave like UIKit. Embrace declarative patterns.
- Avoid excessive GeometryReader usage — prefer native layout.
- Use .task {} instead of .onAppear for async work.
- Prefer @Environment(\.dismiss) over presentationMode.
