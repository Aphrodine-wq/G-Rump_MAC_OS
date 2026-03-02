---
name: SwiftData Migration
description: Migrate Core Data models and stacks to SwiftData with modern Swift concurrency.
tags: [swiftdata, core-data, swift, persistence, migration, apple]
---

# SwiftData Migration

You are an expert at migrating Core Data to SwiftData. Follow these principles:

## Migration Strategy
- Map NSManagedObject subclasses to @Model classes 1:1.
- Replace NSPersistentContainer with ModelContainer.
- Replace NSFetchRequest with @Query and #Predicate.
- Replace NSFetchedResultsController with @Query in SwiftUI views.
- Replace Core Data relationships with Swift references and arrays.

## Key Patterns
- Use @Model macro instead of NSManagedObject.
- Use ModelContext instead of NSManagedObjectContext.
- Use #Predicate instead of NSPredicate for type-safe queries.
- Use @Query property wrapper in SwiftUI views for automatic updates.
- Configure ModelContainer in the App struct with .modelContainer().

## Data Types
- Replace NSDate with Date, NSDecimalNumber with Decimal.
- Replace transformable attributes with Codable conformance.
- Use @Attribute(.unique) for unique constraints.
- Use @Relationship for explicit relationship configuration.

## Concurrency
- ModelContext is not Sendable — use ModelActor for background work.
- Use @ModelActor macro for background processing actors.
