---
name: Async/Await Conversion
description: Convert Combine pipelines and callback-based code to modern Swift async/await.
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
