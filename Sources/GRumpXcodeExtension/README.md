# G-Rump Xcode Source Editor Extension

Deep Xcode integration — commands appear under **Editor > G-Rump** in Xcode's menu bar.

## Commands

| Command | What it does |
|---|---|
| **Explain Selection** | Sends selected code to G-Rump for a clear explanation |
| **Refactor Selection** | Refactors code using modern Swift patterns |
| **Add Documentation** | Generates Apple-style documentation comments |
| **Fix This** | Analyzes and fixes bugs or compiler errors |
| **Send to G-Rump Chat** | Opens the main app with the selected code in context |

## Setup (Xcode Project)

Source Editor Extensions must be built as app extension targets, which SPM doesn't support directly. To add this to your Xcode project:

1. **Open the Xcode project** (or create one from the SPM package via `File > New > Project from Package`)

2. **Add a new target**: `File > New > Target > Xcode Source Editor Extension`
   - Name: `GRumpXcodeExtension`
   - Bundle ID: `com.grump.app.xcode-extension`

3. **Replace the generated files** with the files in this directory:
   - `SourceEditorExtension.swift`
   - `SourceEditorCommands.swift`
   - `Info.plist`

4. **Add an App Group** to both the main app and the extension:
   - Group ID: `group.com.grump.shared`
   - This enables the extension to pass selected code to the main app

5. **Register a URL scheme** in the main app's Info.plist:
   - URL Scheme: `grump`
   - This allows the extension to open the main app via `grump://xcode-command`

6. **Build & Run** the extension scheme. Xcode will launch a debug instance of Xcode where the extension is active.

## How It Works

1. User selects code in Xcode and invokes a command from **Editor > G-Rump**
2. The extension writes the selected text + instruction to the shared App Group UserDefaults
3. The extension opens the main G-Rump app via the `grump://` URL scheme
4. G-Rump picks up the pending request and processes it with the configured AI model
5. Results appear in the G-Rump chat interface

## Future: In-Editor Results

Phase 2 will add inline result rendering — the extension will poll for the AI response and replace/annotate the selection directly in Xcode, without switching apps.
