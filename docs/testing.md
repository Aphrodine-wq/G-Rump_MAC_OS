# Testing

G-Rump includes a test suite and test exploration tools.

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

# Run specific test
swift test --filter TestClassName

# Run with verbose output
swift test --verbose
```

### From Makefile
```bash
make test
```

## Test Structure

Tests follow Swift Testing conventions:
```swift
import Testing

@Test func exampleTest() {
    let result = myFunction()
    #expect(result == expected)
}
```

## CI Pipeline

The project can be tested in CI using:
```yaml
steps:
  - name: Build
    run: swift build
  - name: Test
    run: swift test
```

## Key Files

| File | Purpose |
|---|---|
| `Tests/` | Test directory |
| `TestExplorerView.swift` | Test panel UI |
| `Package.swift` | Test target configuration |
