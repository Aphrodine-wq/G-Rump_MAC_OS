# Distribution

G-Rump is distributed as a signed and notarized DMG outside the Mac App Store.

## Why Not the Mac App Store

- **Sandbox incompatible** — G-Rump runs shell commands, spawns LSP/Ollama processes, accesses arbitrary project directories
- **Apple's 30% cut** — Stripe billing is already integrated
- **Review delays** — AI agent with shell execution would face extra scrutiny
- **Industry norm** — Cursor, Windsurf, Warp, Zed all distribute directly

## Build Pipeline

### Debug Build
```bash
make run
```

### Release Build
```bash
make app    # Builds .app bundle
make dmg    # Builds .app + .dmg
```

### Signing
The app is signed with a Developer ID certificate for distribution outside the App Store.

### Notarization
```bash
make notarize
```
Submits the app to Apple's notarization service. Required for Gatekeeper to allow the app to run.

## Auto-Updates (Sparkle)

G-Rump uses the [Sparkle](https://sparkle-project.org/) framework for auto-updates:
- Integrated as a Swift Package dependency
- `SparkleUpdateService` manages update checks
- Appcast XML hosted on the distribution domain
- Users are prompted to update when a new version is available

Configure update preferences in **Settings → Updates**.

## DMG Contents

The DMG contains:
- `G-Rump.app` — The application bundle
- Symlink to `/Applications` for drag-to-install

## Entitlements

Key entitlements in `GRump.entitlements`:
- `com.apple.security.app-sandbox` = `false` (disabled for full system access)
- Network access, file access, camera access enabled

## Key Files

| File | Purpose |
|---|---|
| `Makefile` | Build, package, sign, notarize commands |
| `GRump.entitlements` | App entitlements |
| `project.yml` | Xcode project configuration |
| `Package.swift` | Swift package with Sparkle dependency |
| `DISTRIBUTION.md` | Detailed distribution guide |
