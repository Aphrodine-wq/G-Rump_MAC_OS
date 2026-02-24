# G-Rump Maintainability Guidelines

This document provides guidelines for maintaining code quality and structure as the G-Rump codebase evolves.

## File Size Guidelines

- **Target**: Keep individual Swift files under 1,000 lines when possible
- **Maximum**: Avoid files exceeding 2,000 lines without strong justification
- **Hotspots**: Monitor these files regularly for growth:
  - `ContentView.swift` - Main UI coordinator
  - `ChatViewModel.swift` - Core view model
  - `SettingsView.swift` - Settings UI
  - Tool definition and execution files

## Module Boundaries

### Core Responsibilities
- **Models.swift**: All data models and `GRumpDefaults` constants (canonical source)
- **ChatViewModel.swift**: Core view model logic, state management
- **ContentView.swift**: Main view coordination and layout
- **ToolDefinitions.swift**: Tool definitions only (no execution logic)
- **ChatViewModel+ToolExecution.swift**: Tool dispatch and parallel execution

### Extension Files
- Use `+` extensions for focused functionality (e.g., `ChatViewModel+Streaming.swift`)
- Keep execution methods in domain-specific files (`ToolExec+FileOps.swift`)
- One primary responsibility per extension file

## Naming Conventions

### Constants
- All default constants live in `GRumpDefaults` enum in `Models.swift`
- Do not duplicate default values elsewhere - reference from `GRumpDefaults`
- Use descriptive names: `defaultSystemPrompt`, not `prompt`

### Methods
- Tool executors: `execute<ToolName>` (e.g., `executeReadFile`)
- Use camelCase for method names derived from snake_case tool names
- Private helpers use descriptive verbs: `resolvePath`, `validateArguments`

### Files
- Use `+` for extensions: `ChatViewModel+ToolExecution.swift`
- Group related functionality: `ToolExec+FileOps.swift`, `ToolDefs+FileOps.swift`
- Views organized by hierarchy in `Views/` subdirectories

## Testing Requirements

### Critical Path Coverage
- All tool names must have corresponding executor methods
- Test critical paths: tool dispatch, path resolution, model defaults
- Add regression tests when fixing bugs or refactoring

### Test Organization
- One test file per major area: `ToolDispatchTests.swift`, `RegressionTests.swift`
- Include setup/teardown for complex test scenarios
- Use `@MainActor` for UI-related tests

## Refactoring Safety

### Before Refactoring
1. Run `swift build` and `swift test` to establish baseline
2. Add regression tests for the area being refactored
3. Identify all dependencies and import relationships

### During Refactoring
1. Make small, incremental changes
2. Run `swift build` after each significant change
3. Preserve existing behavior - no functional changes

### After Refactoring
1. Run full test suite: `swift test`
2. Verify build succeeds: `swift build`
3. Test critical user workflows manually

## Code Organization Principles

### Single Responsibility
- Each file should have one clear primary purpose
- Avoid mixing UI, business logic, and data models in single files
- Use extensions to separate concerns within classes

### Dependencies
- Minimize circular dependencies
- Prefer protocol-based abstractions for complex interactions
- Keep import statements focused and minimal

### Documentation
- Add comments for complex business logic
- Document non-obvious design decisions
- Keep `GRumpDefaults` comments updated as constants change

## Monitoring

### Regular Checks
- Watch file sizes in hotspots (weekly during active development)
- Run tool dispatch tests after any tool definition changes
- Verify build succeeds after major refactoring

### Red Flags
- Files growing beyond 2,000 lines
- Duplicate constants or default values
- Missing executor methods for defined tools
- Build warnings or errors in main branch

## Process for Adding New Tools

1. Define tool in appropriate `ToolDefs+*.swift` file
2. Add executor method in corresponding `ToolExec+*.swift` file  
3. Update `ToolDispatchTests.swift` with new tool name
4. Run tests to verify dispatch coverage
5. Test tool functionality manually

## Process for Major Refactoring

1. Create plan document in `.windsurf/plans/`
2. Add regression tests first
3. Implement changes incrementally
4. Verify build and tests at each step
5. Update documentation as needed

Following these guidelines helps maintain code quality and prevents technical debt as the project grows.
