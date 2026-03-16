# Testing

G-Rump includes a comprehensive test suite with 81 test files covering all major areas.

## Test Explorer Panel

The **Tests** panel (right sidebar) provides:
- Test discovery for Swift packages and Xcode projects
- Run individual tests or full suites
- Pass/fail status indicators
- Test output and failure details

## Running Tests

### From the App
Click the play button next to any test or test suite in the Tests panel.

### From Terminal
```bash
# Run all tests
swift test

# Run all tests in parallel
swift test --parallel

# Run specific test
swift test --filter TestClassName

# Run with verbose output
swift test --verbose
```

### From Makefile
```bash
make test
```

## Test Coverage Areas

| Area | Files | What's Tested |
|---|---|---|
| Core Models | ChatModelsTests, ConversationTests | Message, Conversation, ToolCall codable round-trips, threading, branching |
| ViewModel | ChatViewModelTests, StreamingTests | State management, message handling, streaming pipeline |
| Thinking Parser | ThinkingParserTests | `<thinking>` block extraction from streaming text |
| Prompt Building | PromptBuildingTests | System prompt construction per agent mode, file extension detection |
| Export/Import | ExportImportTests | Markdown/JSON export, import validation, filename sanitization |
| Persistence | PersistenceRoundTripTests | Conversation save/load cycle, field fidelity |
| Tool Execution | ToolExecutionTests, ToolDefTests | Tool definitions, parameter validation, execution flow |
| Settings | SettingsTests | Preference storage, defaults, migration |
| Markdown | MarkdownParsingTests | Block parsing, code fences, headers, tables, inline formatting |
| Security | SecurityTests | Command validation, path traversal prevention |
| MCP | MCPTests | Protocol parsing, server lifecycle |
| AI Providers | AIProviderTests | Provider configuration, model selection |

## Test Structure

Tests follow Swift Testing conventions:
```swift
import XCTest
@testable import GRump

final class ExampleTests: XCTestCase {
    func testFeature() {
        let result = myFunction()
        XCTAssertEqual(result, expected)
    }
}
```

> **Note:** Many test classes require `@MainActor` annotation because `ChatViewModel` is `@MainActor`. Always add this when testing ViewModel methods.

## CI Pipeline

The project can be tested in CI using:
```yaml
steps:
  - name: Build
    run: swift build
  - name: Test
    run: swift test --parallel
```

## Key Files

| File | Purpose |
|---|---|
| `Tests/GRumpTests/` | Test directory (81 files) |
| `Package.swift` | Test target configuration |
| `Makefile` | `make test` shortcut |
