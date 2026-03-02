---
name: Async/Await Conversion
description: Convert Combine pipelines and callback-based code to modern Swift async/await.
tags: [swift, concurrency, async-await, combine, migration]
---

# Async/Await Conversion

You are an expert at converting legacy async patterns to modern Swift concurrency.

## Combine → async/await
- Replace Publishers.Future with async functions.
- Replace sink/store with await calls.
- Replace PassthroughSubject for events with AsyncStream.
- Replace CurrentValueSubject with @Published properties or actors.
- Replace combineLatest/merge with TaskGroup or async let.
- Replace flatMap chains with sequential await calls.

## Callbacks → async/await
- Wrap completion handlers with withCheckedContinuation or withCheckedThrowingContinuation.
- Convert delegate patterns to AsyncStream.
- Replace DispatchQueue.async with Task { }.
- Replace DispatchGroup with TaskGroup.
- Replace semaphores with actors.

## Best Practices
- Use structured concurrency (TaskGroup, async let) over unstructured (Task { }).
- Mark actors with @MainActor for UI work, not DispatchQueue.main.
- Use Task.detached only when you explicitly need to escape the current actor.
- Prefer throwing async functions over Result types.
- Use AsyncSequence for streaming data patterns.
- Always handle cancellation with Task.isCancelled or Task.checkCancellation().

## Anti-Patterns
- Using Task { @MainActor in } when the enclosing type should just be @MainActor
- Bridging every Combine publisher — keep Combine for SwiftUI bindings where @Published is needed
- Using continuations without resuming exactly once (crashes or hangs)
- Ignoring Sendable warnings — they indicate real data race risks
- Creating detached tasks to avoid actor isolation (hides concurrency bugs)

## Verification
- No compiler warnings about Sendable conformance or actor isolation
- All continuations resume exactly once in every code path (including error paths)
- Background work uses appropriate actors, not DispatchQueue.global()
- Cancellation is handled gracefully — no orphaned network requests or file handles

## Examples
- **Callback→async**: `func fetch(completion: @escaping (Result<Data, Error>) -> Void)` → `func fetch() async throws -> Data` using `withCheckedThrowingContinuation`
- **Combine→async**: `publisher.sink { value in }` → `for await value in publisher.values { }`
- **Delegate→AsyncStream**: `AsyncStream<CLLocation> { continuation in locationManager.delegate = StreamDelegate(continuation) }`
