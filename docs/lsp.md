# LSP Integration

G-Rump integrates with SourceKit-LSP for live Swift diagnostics and code intelligence.

## Features

- **Live diagnostics** — Error and warning counts displayed in the chat top bar
- **Error badges** — Red (errors) and orange (warnings) indicators
- **Symbol graph** — `SymbolGraphService` extracts symbol information for context-aware AI responses

## How It Works

`LSPService` manages a SourceKit-LSP subprocess:
1. Starts LSP when a Swift project is opened
2. Sends `textDocument/didOpen` and `textDocument/didChange` notifications
3. Receives `textDocument/publishDiagnostics` with errors/warnings
4. Updates `errorCount` and `warningCount` published properties
5. UI reacts via SwiftUI bindings in `ChatTopBarView`

## Symbol Graph Service

`SymbolGraphService` uses `swift-symbolgraph-extract` to generate symbol graphs for Swift modules. This data is used by `ChatViewModel` to provide richer context to the AI about:
- Available types and protocols
- Method signatures
- Inheritance hierarchies
- Module dependencies

## Configuration

LSP starts automatically when a valid Swift project is detected in the working directory. No manual configuration required.

## Key Files

| File | Purpose |
|---|---|
| `LSPService.swift` | LSP subprocess management |
| `SymbolGraphService.swift` | Symbol graph extraction |
| `ChatTopBarView.swift` | Diagnostic badges UI |
