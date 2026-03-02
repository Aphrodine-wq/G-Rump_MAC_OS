---
name: Test Generation
description: Auto-generate test suites from existing code.
tags: [testing, test-generation, automation, coverage, quality]
---

# Test Generation Skill

When generating tests:

1. Analyze the function/module signature, return types, and side effects
2. Generate unit tests covering: happy path, edge cases, error cases, boundary values
3. Use the project's existing test framework and conventions (Jest, pytest, XCTest, etc.)
4. Mock external dependencies (APIs, databases, file system) appropriately
5. Test both the interface contract and important implementation details
6. Include negative tests: invalid inputs, null values, empty collections, overflow
7. Generate integration tests for cross-module interactions
8. Add property-based tests for pure functions when appropriate
9. Ensure test names describe the behavior being verified, not the implementation

Follow the Arrange-Act-Assert pattern. Each test should test one behavior.
