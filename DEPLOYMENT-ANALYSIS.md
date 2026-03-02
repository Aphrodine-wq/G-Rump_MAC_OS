# G-Rump Deployment Analysis

**Date:** March 2, 2026
**Scope:** Full product audit — macOS app, Node.js backend, website, security, testing, and distribution
**Verdict:** The product has strong architectural foundations but has 23 critical blockers, 31 high-priority items, and 28 polish items that must be addressed across six domains before a public launch.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Critical Blockers — Ship Stoppers](#2-critical-blockers--ship-stoppers)
3. [Security & Privacy](#3-security--privacy)
4. [Backend Deployment](#4-backend-deployment)
5. [App Quality & Completeness](#5-app-quality--completeness)
6. [Distribution & Packaging](#6-distribution--packaging)
7. [Website & Marketing](#7-website--marketing)
8. [Test Coverage & CI/CD](#8-test-coverage--cicd)
9. [Prioritized Action Plan](#9-prioritized-action-plan)

---

## 1. Executive Summary

### What Is Strong

- **Architecture**: The Swift app is well-structured with clean separation of concerns — ChatViewModel extensions, tool definition/execution split across domain files, actor-based MCP connection management, and a layered persistence system.
- **Tool ecosystem**: 100+ tools with proper JSON schema definitions, parallel execution with retry logic, and the exec approval security framework.
- **Backend fundamentals**: JWT auth, Helmet headers, rate limiting, GDPR export/delete endpoints, Stripe webhook signature verification, and graceful shutdown.
- **Website**: A production-grade Next.js 16 marketing site exists with 21 documentation pages, pricing tiers, blog, changelog, and full SEO metadata.
- **Design system**: 26 theme palettes, consistent spacing/typography tokens, spring animation presets.
- **Test suite breadth**: 834 test methods across 53 Swift test files covering tool definitions, streaming protocol, data models, persistence, MCP config, exec approvals, and model routing.

### What Is Broken

| Domain | Readiness | Key Issue |
|--------|-----------|-----------|
| Security | 4/10 | MCP server on port 18790 has zero authentication and binds to all interfaces; `run_command` bypasses the exec approval system entirely |
| Backend | 6/10 | Credit deduction race condition; DB initialization broken on Vercel cold starts; missing Stripe webhook handlers for renewals |
| App Quality | 6/10 | WritingToolsService returns hardcoded stubs; two settings (code font, line spacing) are stored but never applied; auth/sign-in is non-functional |
| Distribution | 5/10 | Sparkle auto-update is code-present but completely unconfigured; Info.plist has unfilled Google OAuth placeholder; version numbers are inconsistent across 3 files |
| Website | 5/10 | No privacy policy or terms of service pages; all social links are `href="#"`; OG image and logo assets are missing; contact form is non-functional |
| Testing | 5/10 | Zero tests for streaming pipeline, parallel tool execution, Stripe webhooks, credit deduction, backend auth middleware, or MCP subprocess lifecycle |

### Distribution Path

The app is **permanently ineligible for the Mac App Store** due to its unsandboxed entitlements (`app-sandbox = false`, `allow-unsigned-executable-memory`, `disable-library-validation`). This is architecturally correct — shell execution, LSP spawning, and file tools require it. Distribution must be via **Developer ID + notarization + direct download** (DMG from website).

---

## 2. Critical Blockers — Ship Stoppers

These 23 items must be resolved before any public release. They represent security vulnerabilities, broken user-facing features, legal requirements, and data integrity risks.

### Security (4 blockers)

**S1. MCP server on port 18790 has zero authentication**
`MCPServerHost.swift` binds a TCP listener with `NWParameters.tcp` and no auth gate. Any local process — including malware, browser-based XSS leveraging localhost, or other apps — can connect and invoke `read_file` (reads `~/.ssh/id_rsa`), `write_file` (arbitrary file writes), `get_env` (leaks `OPENROUTER_API_KEY`, `AWS_SECRET_ACCESS_KEY`), and `clipboard_read/write`. The listener binds to `0.0.0.0` (all interfaces), meaning other machines on the same LAN can access it.

**Fix:** Generate a random token at server start. Require it in every request. Bind the listener explicitly to `127.0.0.1`. Add path traversal protection restricting file tools to a workspace root.

**S2. `run_command` bypasses the exec approval system entirely**
`ChatViewModel+ToolExecution.swift` line 117: `run_command` calls `runShellCommand()` directly, skipping `executeSystemRun()` completely. The exec approval UI (allowlist, deny/ask/allow levels, user prompt) only applies to `system_run`. The AI's primary shell execution tool has zero approval checks regardless of the user's configured security level.

**Fix:** Route `run_command` through the same approval pipeline as `system_run`, or extract the approval logic into a shared function.

**S3. Shell command construction uses string interpolation instead of argument arrays**
`ToolExec+ShellSystem.swift` constructs shell commands by interpolating AI-supplied strings into `/bin/zsh -c` commands. While single-quote escaping is applied in most cases, the structural pattern is fragile. `executeListProcesses`, `executeWhich`, `executeDiskUsage`, and `executeSpotlightSearch` all use this pattern.

**Fix:** Use `Process()` with argument arrays for all tool helpers, removing shell interpolation entirely.

**S4. Backend credit deduction has a race condition**
`proxy.js` line 110-118: The deduct function reads the balance, computes a new value in application code, then writes it back. Two concurrent requests both read `balance = 100`, both compute `newBalance = 100 - X`, and one write is silently lost. Users can over-spend their credit balance.

**Fix:** Use an atomic SQL update: `UPDATE users SET credits_balance = MAX(0, credits_balance - ?) WHERE id = ? AND credits_balance > 0`.

### Legal (3 blockers)

**L1. No privacy policy page exists anywhere**
The website footer links to `href="#"` for Privacy Policy, Terms of Service, and License. No `/privacy` or `/terms` page exists. A privacy policy is required by: Apple's Developer Program License Agreement (direct distribution), Stripe's Merchant Agreement, GDPR, CCPA, and Google Sign-In's Terms.

**L2. No terms of service page exists**
Same as above. Required for any paid product and for the Google Sign-In integration.

**L3. `grump.app` vs `g-rump.com` domain conflict**
The LICENSE file references `https://grump.app` and `legal@grump.app`. The entire codebase (app, backend, website) uses `www.g-rump.com`. These must be reconciled.

### App Quality (5 blockers)

**A1. WritingToolsService returns hardcoded stub text**
The core `generateText(prompt:context:)` function returns `"[AI suggestion based on: ...]"` — a literal placeholder string. This backs `generateCommitMessage`, `generateDocumentation`, `generateComments`, `improveText`, `generateReleaseNotes`, and `generateAPIDocumentation`. The "Writing Tools" button in message actions is visible to all users and produces this stub output.

**A2. Code font setting is stored but never applied**
`@AppStorage("CodeFont")` is written in Settings but never read by `CodeBlockView`, `MarkdownTextView`, or any typography code. Choosing "Fira Code" or "JetBrains Mono" does nothing. Neither font is bundled.

**A3. Line spacing setting is stored but never applied**
`@AppStorage("LineSpacing")` is written in Settings but `MarkdownTextView` hardcodes `.lineSpacing(3)` and `.lineSpacing(2)`. The setting is deceptive.

**A4. Authentication / sign-in is non-functional**
Both the onboarding (step 0) and account settings display "Sign in is coming soon." The Google Sign-In backend exists but the macOS app integration is incomplete. Users who expect to create an account hit a dead end.

**A5. Git Shortcuts popover runs `git commit` with no `-m` argument**
`StatusBarView.swift`'s GitShortcutsPopover runs `git commit` which spawns a process that hangs waiting for an editor. The git output pipe is also never read — output is completely discarded.

### Distribution (4 blockers)

**D1. Sparkle auto-update is completely unconfigured**
`SparkleUpdateService.swift` is correct code. But `Info.plist` has no `SUFeedURL` and no `SUPublicEDKey`. No `appcast.xml` exists anywhere. Sparkle initializes silently, `canCheckForUpdates` is always `false`, and the "Check for Updates" menu item does nothing. Without auto-update, users must manually re-download every new version.

**D2. Info.plist contains a literal placeholder**
`CFBundleURLSchemes` contains `com.googleusercontent.apps.YOUR_CLIENT_ID` — a literal string that will be registered as a URL scheme. This must be replaced with the real reversed client ID or removed entirely.

**D3. Version numbers are inconsistent across 3 files**
`Info.plist` says `2.0.0`, `project.yml` says `1.0.0`, `create-release.sh` is hardcoded to `v1.0.0`. The bundle will report `2.0.0` (from Info.plist) but GitHub releases would be tagged `v1.0.0`.

**D4. No CI release pipeline**
The CI `release` job runs `make app` (ad-hoc signed, immediately discarded). No signing, no notarization, no artifact upload, no GitHub Release creation. Every release requires a manual `make notarize` from a developer machine.

### Backend (4 blockers)

**B1. Database initialization is broken on Vercel cold starts**
The `ensureDb()` middleware that calls `initDatabase()` is registered AFTER all route definitions in `server.js`. Express runs middleware in registration order, so routes are matched and executed before `initDatabase()` runs. On a fresh Vercel deployment with a new Turso database, tables may not exist when the first request hits.

**Fix:** Move `ensureDb()` to run before route registration, or call `initDatabase()` at module load time.

**B2. `invoice.payment_succeeded` webhook is not handled**
Subscription renewals fire `invoice.payment_succeeded`. The code handles `invoice.payment_failed` but not success. After the first billing cycle, `subscription_period_end` goes stale and the user's subscription state becomes incorrect.

**B3. Price ID fallback values are invalid Stripe IDs**
`stripe.js` line 15-21: `starter_monthly: process.env.STRIPE_PRICE_STARTER || 'price_starter_monthly'`. The fallback `'price_starter_monthly'` is not a real Stripe price ID. If environment variables are missing, the checkout flow silently sends an invalid ID to Stripe.

**Fix:** Throw on startup if Stripe is configured but price IDs are missing.

**B4. No global Express error handler**
There is no `app.use((err, req, res, next) => {...})` at the bottom of `server.js`. Express's default error handler may leak stack traces in some cases.

### Website (3 blockers)

**W1. OG image and icon assets are missing**
`layout.tsx` references `og-image.png` (1200x630), `manifest.json` references `icon-192.png` and `icon-512.png`, and the JSON-LD schema references `logo.png`. None of these files exist in `public/`. All social sharing previews and PWA install will be broken.

**W2. Website is not deployed**
The Next.js website at `RE/website/` has no deployment configuration, no Vercel project, and no DNS resolution for `www.g-rump.com`. The backend has `vercel.json` but the website does not.

**W3. JSON-LD claims fabricated social proof**
`layout.tsx` lines 141-146 contain `aggregateRating: { ratingValue: "4.9", ratingCount: "2400" }`. This is fabricated structured data that violates Google's structured data guidelines and could result in manual action penalties in search results.

---

## 3. Security & Privacy

### Attack Surface Map

| Exposure | Binding | Auth | Encryption | Risk |
|----------|---------|------|------------|------|
| MCP Server (18790) | `0.0.0.0` (all interfaces) | None | None (plain TCP) | **Critical** |
| OpenClaw WebSocket | Outbound to `ws://127.0.0.1:18789` | Node ID only | None (`ws://`) | High |
| Backend API (3042) | Configurable | JWT Bearer | HTTPS in prod | Low-Medium |
| `run_command` | N/A (internal) | None — bypasses approval | N/A | **Critical** |

### Credential Storage

**Good:**
- API keys stored in macOS Keychain under service `"GRump"`. No hardcoded secrets in source. Test files use placeholder strings.
- Backend JWT production enforcement requires `JWT_SECRET` >= 32 chars when `NODE_ENV=production`.
- MCP credential vault uses Keychain for environment variable injection.

**Needs improvement:**
- **Keychain items have no `kSecAttrAccessible` set.** Without it, any process running as the same user can query the Keychain by service name and extract API keys (because the app is unsandboxed).
- **No `kSecAttrAccessGroup` isolation.** Any process with the same team ID can read the entries.
- **JWT has no revocation mechanism.** A stolen token is valid for 7 days with no refresh endpoint and no way to invalidate it server-side.
- **JWT secret fallback in non-production:** `auth.js` line 17 uses `'dev-only-change-in-production'` as fallback if `JWT_SECRET` is unset and `NODE_ENV` is not `production`. If someone deploys without `NODE_ENV=production` (a very common mistake), they get a deterministic, publicly visible secret.

### Privacy Manifest — App Store Readiness

The current `PrivacyInfo.xcprivacy` declares crash data, performance data, file timestamps, UserDefaults, disk space, and system boot time.

**Missing required entries:**
1. **NSPasteboard access** — The app reads/writes `NSPasteboard.general` directly and via AI tools. Clipboard access is a required-reason API on macOS 14+. Omission will cause rejection.
2. **AmbientMonitor clipboard polling** — Reads clipboard every 2 seconds when enabled. Even though `clipboardMonitorEnabled` defaults `false`, the capability exists in the binary.
3. **User content sent to third-party AI providers** — Chat messages are sent to OpenRouter/Anthropic/OpenAI. Not declared as `NSPrivacyCollectedDataTypeUserContent`.
4. **App name / window title tracking** — `AmbientMonitor` tracks active app names and window titles. `appTrackingEnabled` and `windowTitleTrackingEnabled` both default `true`.
5. **Screen capture** — `executeScreenSnapshot` uses `SCScreenshotManager`. Not declared.

### GDPR / Privacy Compliance Gaps

**Good:**
- `GET /api/me/export` provides data export
- `DELETE /api/me` cascades deletes
- 90-day retention policy on usage logs

**Gaps:**
- No consent mechanism at onboarding before sending data to cloud AI providers (GDPR Article 7)
- No privacy policy link at onboarding
- `appTrackingEnabled` defaults `true` — behavioral data collection should be opt-in, not opt-out
- No cookie banner / tracking disclosure for the backend

### OpenClaw WebSocket Risks

The OpenClaw service connects outbound to `ws://127.0.0.1:18789` (plain WebSocket, not encrypted). The gateway URL is user-configurable. If set to a remote host, conversation content and credentials traverse the wire unencrypted. The session acceptance flow has no cryptographic verification that messages come from a trusted gateway versus a spoofed local service.

**Fix:** Enforce `wss://` for non-localhost URLs. Add session signing.

---

## 4. Backend Deployment

### Platform: Vercel + Turso

The backend is configured for Vercel serverless (`vercel.json` routes all traffic through `api/index.js` which re-exports Express). Database is Turso (libsql over network). This architecture works but has specific issues:

### Critical Issues

**1. DB initialization ordering bug (see B1 above)**

**2. Rate limiter uses in-memory store**
`express-rate-limit` defaults to an in-memory store. On Vercel, each cold start gets a fresh process — rate limits reset on every invocation, effectively providing no rate limiting at all.

**Fix:** Use `rate-limit-redis` or Vercel KV-backed store.

**3. `pruneOldUsageLogs` setInterval never runs on Vercel**
The `setInterval` that prunes 90-day-old usage logs starts in the module but Vercel tears down the process after each request. The prune never executes.

**Fix:** Add a Vercel Cron job or GitHub Actions scheduled workflow.

**4. `maxDuration: 60` may be insufficient for streaming**
Long AI completions can run 60+ seconds. Vercel's Pro plan allows 300s. Increase to at least 120-300s.

### Authentication Issues

**5. JWT expiry is 7 days with no refresh mechanism**
Users must fully re-authenticate with Google every week. For a native macOS app, this is a disruptive pop-up.

**Fix:** Issue short-lived access tokens (1h) + long-lived refresh tokens, or add a sliding-window extension endpoint.

**6. `avatarUrl` not validated**
`PATCH /api/me` accepts any string up to 2048 chars as `avatarUrl`. No URL validation or scheme restriction. If rendered in a web context, this is a stored XSS vector.

**Fix:** Validate with `new URL(avatarUrl)` and restrict to `https://` scheme.

### Database Issues

**7. Migrations are not tracked**
PRAGMA-based column checks run on every cold start. No migration version table exists. Rollback is impossible.

**8. Foreign keys are not enforced**
SQLite does not enforce foreign keys by default. `PRAGMA foreign_keys = ON` is never set. Child row cleanup in `DELETE /api/me` is manual and fragile.

**9. No index on `usage_log(created_at)`**
The prune and usage queries filter on `created_at` but only `user_id` is indexed. At scale, these queries do full table scans.

### Stripe / Billing Issues

**10. `customer.subscription.paused` not handled**
If Stripe pauses a subscription (smart retries, manual pause), no event handler updates the user's tier. They keep paid access indefinitely.

**11. Trial handling is incomplete**
`trial_end` column exists but is never written to. When a trial ends and converts to paid, no timestamp is recorded.

**12. No idempotency keys on Stripe API calls**
Network timeout retries could create duplicate customers or checkout sessions.

### Missing Production Hardening

**13. No structured logging** — All logging is `console.log`. No request ID correlation, no log aggregator integration.

**14. No error tracking** — No Sentry, Honeybadger, or equivalent. Unhandled rejections go to `console.error` with no alerting.

**15. No compression middleware** — JSON API responses are uncompressed.

**16. Health check leaks configuration info** — The public (unauthenticated) health endpoint exposes whether Stripe and OpenRouter keys are configured.

**17. No API versioning except on chat proxy** — `/api/v1/chat/completions` is versioned but `/api/me`, `/api/billing/...` are not. Response shape changes break all deployed clients.

**18. Model tier classification is fragile** — `proxy.js` line 24 uses `model.includes(':free')` and `model.includes('claude-opus')` string checks. New high-cost models not in the hardcoded list silently fall to `'fast'` tier pricing.

---

## 5. App Quality & Completeness

### Feature Completeness

| Feature | Status | Notes |
|---------|--------|-------|
| Chat + streaming | Working | Well-tested streaming protocol layer |
| 100+ tools | Working | Comprehensive definition/execution split |
| Agent modes | Working | standard, plan, fullStack, argue, spec, parallel |
| MCP client | Working | Actor-based connection manager, 3 transports |
| Skills system | Working | Three scopes, relevance scoring, combo skills |
| Soul / personality | Working | Global + project override |
| Themes | Working | 26 palettes, migration handled |
| Settings | Partially working | Code font and line spacing settings are non-functional |
| Onboarding | Partially working | Auth step is placeholder |
| Writing Tools | **Broken** | Returns hardcoded stub strings |
| Auto-update | **Non-functional** | Sparkle code exists but no appcast or keys configured |
| Sign-in / account | **Non-functional** | "Coming soon" message in both onboarding and settings |
| Git shortcuts | **Broken** | `git commit` hangs, output pipe never read |
| Connection monitoring | Partially working | Started only in ChatTopBarView; not consulted before streaming |
| Notification approvals | **Broken** | `approvalId` extracted but discarded; wrong approval can be resolved |

### Error Handling & Resilience

**Good:**
- `StreamErrorView` preserves partial content above error card with retry/dismiss
- ConnectionMonitor detects degraded/disconnected states with descriptive messages
- Tool execution has exponential backoff retry (200ms/500ms/1s, 2 retries)

**Gaps:**
- **655 occurrences of `try?`** across 114 files — the majority are appropriate but several in tool execution and git operations silently swallow meaningful errors
- Two explicit empty `catch {}` blocks: `ToolExec+GitDevOps.swift:543` and `ToolExec+ShellSystem.swift:310`
- `ConnectionMonitor.canStream` is never checked before `startStreaming()` — users can send messages while offline and get opaque URLSession errors instead of a clear "You are offline" warning
- `ConnectionMonitor.start()` is only called from `ChatTopBarView.onAppear` — if the top bar is hidden (Zen mode), the monitor never starts
- No offline message queuing for retry when connectivity returns
- No VoiceOver announcement when `StreamErrorView` appears

### Accessibility

**Good:**
- `.accessibilityLabel` on ~35+ interactive elements across ContentView, ChatInputView, MessageViews, OnboardingView
- `@Environment(\.accessibilityReduceMotion)` read in SplashScreenView and ContentView
- 82 `.help()` tooltip locations across 37 files
- AccessibilityAuditView developer tool exists

**Critical gap:**
- **Dynamic Type is not supported.** All `Typography.*` static properties use `Font.system(size: N)` with hardcoded pixel sizes. They do not use `.body`, `.headline`, `.caption` from the system type scale. No `@ScaledMetric` or `@Environment(\.sizeCategory)` usage in the main app (only in developer tools). Users who set "Larger Text" in system Accessibility settings will see no change in G-Rump.

**Other gaps:**
- `StreamErrorView` does not check `reduceMotion` — animation should be `.opacity` only when active
- No VoiceOver announcements on splash completion, stream error appearance, or onboarding step progression
- Message list (`LazyVStack` in `MessageListView`) does not announce row counts or positions to VoiceOver
- `StatusBarView` connection status dot has no `.accessibilityLabel`
- Some theme combinations (e.g., Kiro: textMuted on purple) may fail WCAG AA contrast

### Other Quality Issues

- `StatusBarView` connection indicator only checks `platformUser != nil`, not `ConnectionMonitor.shared` — shows green ("Connected") while offline as long as a user is cached
- `SpotlightIndexer.indexConversation` uses synchronous `CSSearchableIndex` API on the main thread
- `NotificationService.pendingApprovalId` is `@Published` but never set anywhere
- `checkWritingToolsAvailability()` returns `true` for macOS 14+ but Apple's Writing Tools framework requires macOS 15+ / iOS 18+
- `UNNotificationSound.defaultCritical` requires special entitlement on iOS — app only requests `.provisional`, not `.criticalAlert`

---

## 6. Distribution & Packaging

### Current Pipeline

```
make build-release  →  scripts/package.sh  →  .app bundle  →  DMG  →  codesign  →  notarytool  →  staple
```

This works end-to-end for manual releases from a developer machine.

### What Is Complete

- `GRump.entitlements` correctly configured for direct distribution (unsandboxed, hardened runtime)
- `package.sh` handles ad-hoc, Developer ID, and unsigned signing modes
- Full notarization workflow: submit, wait, log retrieval on failure, staple to both DMG and .app
- `spctl --assess` verification post-staple
- `.gitignore` excludes signing material (`.p12`, `.pem`, `.key`)

### What Is Broken

**Sparkle auto-update (code present, functionally dead):**
- `SparkleUpdateService.swift` is correct Sparkle 2.x integration with `SPUStandardUpdaterController`
- `GRumpApp.swift` instantiates it, adds "Check for Updates" menu item
- BUT: No `SUFeedURL` in Info.plist → Sparkle never checks
- No `SUPublicEDKey` in Info.plist → Sparkle refuses to install any update even if found
- No `appcast.xml` exists anywhere
- Settings "Check for updates on launch" toggle opens `https://www.g-rump.com/releases` in a browser instead of calling `sparkleService.checkForUpdates()`
- `DISTRIBUTION.md` says "Future: Sparkle framework" but code is already integrated

**Version management:**
- Three separate files define the version number, all with different values
- No automated version bump mechanism
- `create-release.sh` is hardcoded to `v1.0.0` and `Aphrodine-wq/G-Rump_MAC_OS` — cannot be reused

**CI release pipeline:**
- The `release` CI job builds ad-hoc only (no signing, no notarization)
- No `upload-artifact` step — build output is immediately discarded
- No GitHub Release creation
- Single-arch `swift build -c release` in CI but `package.sh` builds universal — redundant double-build

**Other:**
- `DEVELOPMENT_TEAM` is an empty string in `project.yml` — xcodegen builds will be unsigned
- `--deep` flag on `codesign` is deprecated — should use per-component signing
- `project.yml` references `xcodeVersion: "15.0"` but CI uses Xcode 16.2

### Required Actions for Auto-Update

1. Generate EdDSA keypair using Sparkle's `generate_keys` CLI tool
2. Add `SUFeedURL` and `SUPublicEDKey` to `Info.plist`
3. Create and host `appcast.xml` at the SUFeedURL
4. Sign each release DMG with `sign_update` from Sparkle's toolchain
5. Fix the Settings toggle to call `sparkleService.checkForUpdates()`
6. Store the EdDSA private key securely (CI secret or secure local storage — never in the repo)

---

## 7. Website & Marketing

### What Exists

A full Next.js 16 marketing site exists at `RE/website/` with:
- **Pages:** Home (hero, features, stats, testimonials, comparison, newsletter CTA), Features, Pricing (Free/Starter/Pro/Team tiers), About, Contact, Changelog, Blog (3 posts), Security, Releases, Billing success/cancel
- **Documentation:** 21 pages covering quick start, tools, panels, agent modes, skills, soul, MCP, project config, workflow presets, exec approvals, permissions, themes, shortcuts, packaging
- **Tech stack:** React 19, Tailwind CSS v4, Framer Motion, TypeScript
- **SEO:** Full OpenGraph tags, Twitter cards, JSON-LD structured data, `sitemap.ts` with 40+ URLs, `robots.ts`
- **Domain:** `https://www.g-rump.com` hardcoded throughout app and backend

### What Is Missing

**Hard blockers:**

| Item | Details |
|------|---------|
| Privacy Policy page | Footer links to `href="#"`. Required by Apple, Stripe, GDPR, CCPA, Google Sign-In |
| Terms of Service page | Footer links to `href="#"`. Required for paid products |
| OG image (1200x630) | Referenced in `layout.tsx`, does not exist in `public/` — all social shares broken |
| PWA icons (192, 512) | Referenced in `manifest.json`, do not exist — PWA install broken |
| Logo PNG | Referenced in JSON-LD schema, does not exist |
| Favicon + apple-touch-icon | Only placeholder exists |
| Website deployment | No Vercel project, no DNS for `www.g-rump.com` |
| Download links | "Download for Mac" CTAs have no actual href |

**Functional gaps:**

| Item | Details |
|------|---------|
| Contact form | `onSubmit` calls `setSubmitted(true)` — no backend integration |
| Social accounts | Twitter/X and Discord links all `href="#"` — no verified accounts |
| Fabricated aggregate rating | JSON-LD claims 4.9/5 with 2400 ratings — violates Google guidelines |
| Testimonials | Homepage testimonials section needs real user quotes |
| Blog content | 3 seed posts, changelog has template-looking content |

**App Store listing (for discoverability, even though distribution is direct):**

| Item | Details |
|------|---------|
| Screenshots | `screenshots/` directory is empty — 5 PNGs were deleted |
| App Store description copy | Does not exist |
| Keywords list | Does not exist |
| Promotional text | Does not exist |
| App preview video | Does not exist |

---

## 8. Test Coverage & CI/CD

### By the Numbers

| Metric | Value |
|--------|-------|
| Swift test files | 53 |
| Swift test methods | ~834 |
| Backend test file | 1 (`backend.test.js`) |
| Backend test assertions | ~44 |
| UI test files | 0 |
| Integration test files | 0 |
| Snapshot tests | 0 |
| Performance benchmarks | 0 |
| Skipped/disabled tests | 0 (all active) |

### Well-Tested Critical Paths

- **Tool infrastructure** (strongest area): All 100+ tool definitions validated for structure, every defined tool has a matching execution handler, parameter validation across a dozen tool types, pure-function tool execution (time, UUID, base64, cron)
- **Streaming protocol layer**: `StreamChunk`, `StreamDelta`, `ToolCallDelta` JSON decoding against real payloads, `StreamMetrics` lifecycle (start/record/end/reset, TPS, TTFT)
- **Data models**: Codable round-trips, equality, thread/branch creation, title truncation edge cases
- **Persistence**: SwiftData model conversions, view mode preservation, tool call serialization
- **MCP config**: Transport type Codable, config enable/disable, preset validation, Keychain roundtrip with actual Keychain writes
- **Exec approvals**: Glob pattern matching, config Codable, storage paths
- **OpenRouter request builder**: Header validation, body validation, assistant tool_calls serialization (no network calls — all unit tests)
- **Backend DB layer**: Schema shape, constraints, unique indexes, CRUD, credit replenishment, usage logs, GDPR export/delete (real SQLite in `:memory:`)

### Missing Test Coverage — Critical Paths

| Missing Test | Business Risk |
|-------------|--------------|
| **Stripe webhook handlers** (subscription create/update/pause, credit purchase) | Financial: incorrect billing, lost revenue, tier misassignment |
| **OpenRouter proxy credit deduction** | Financial: race condition allows over-spending |
| **Backend auth middleware** (route protection, token expiry in HTTP context) | Security: auth bypass |
| **Streaming pipeline end-to-end** (SSE parsing, chunk accumulation, partial tool call JSON assembly) | Core functionality: broken chat |
| **Parallel tool execution** (task group semantics, result ordering, failure isolation) | Core functionality: tool execution failures |
| **MCP subprocess lifecycle** (process spawn/terminate, stdio message exchange) | Integration: MCP tools non-functional |
| **Agent mode prompt construction** | Core functionality: wrong system prompts per mode |
| **Backend `proxy.js`** (streaming proxy, credit deduction, rate limiting) | Financial + reliability |
| **Conversation persistence round-trip** (write to file, reload, verify fidelity) | Data loss |

### Test Quality Issues

Several test files contain assertions that verify nothing meaningful:

- `GRumpLoggerTests`: Every test is `XCTAssertNotNil(logger)` — logger instances are `static let` and cannot be nil by construction
- `GRumpLoggerTests.testLoggersCategoryCount`: `XCTAssertGreaterThanOrEqual(10, 10)` — a literal tautology
- `BrandColorsTests`: Tests verify `color.description != Color.clear.description` — fragile and platform-dependent
- `PerformanceAdvisorTests`: `_ = advisor.thermalState` with no assertion
- `InlineDiffCardTests`: `XCTAssertNotNil(card)` — the actual diff computation is not verified

### Backend Test Issues

- Uses `better-sqlite3` (synchronous) but production uses `@libsql/client` (async) — production wrapper code paths untested
- `better-sqlite3` is not in `package.json` devDependencies — tests fail on clean `npm install`
- No HTTP integration tests — auth middleware, route 401s, rate limiting never exercised
- No Stripe webhook tests (cannot import `stripe.js` due to package check)

### CI Pipeline Gaps

- SwiftLint is `|| true` if not installed — lint gate silently skipped if brew fails
- Force-unwrap check is informational only (no `exit 1`)
- No iOS simulator tests despite targeting iOS 17+
- No automated release artifact publishing
- No deployment pipeline for the backend
- `scripts/create-release.sh` and `scripts/deploy-backend.sh` exist but are never invoked by CI

---

## 9. Prioritized Action Plan

### Phase 1: Security Hardening (Week 1)

These items have the highest blast radius and must be fixed before any external user touches the product.

| # | Item | Files | Effort |
|---|------|-------|--------|
| 1 | Add authentication to MCP server + bind to 127.0.0.1 | `MCPServerHost.swift` | 1 day |
| 2 | Route `run_command` through exec approval pipeline | `ChatViewModel+ToolExecution.swift` | 0.5 day |
| 3 | Add path traversal protection to MCP file tools | `MCPServerHost.swift` | 0.5 day |
| 4 | Remove `get_env` from unauthenticated MCP dispatcher | `MCPServerHost.swift` | 0.5 day |
| 5 | Move shell helpers to `Process()` argument arrays | `ToolExec+ShellSystem.swift`, `ToolExec+AppleNative.swift` | 1 day |
| 6 | Fix credit deduction race with atomic SQL | `backend/proxy.js` | 0.5 day |
| 7 | Fix DB initialization ordering for Vercel | `backend/server.js` | 0.5 day |
| 8 | Add global Express error handler | `backend/server.js` | 0.5 day |
| 9 | Add `kSecAttrAccessible` to Keychain storage | `KeychainStorage.swift` | 0.5 day |
| 10 | Enforce `wss://` for non-localhost OpenClaw URLs | `OpenClawService.swift` | 0.5 day |

### Phase 2: Legal & Compliance (Week 1-2)

Cannot launch without these.

| # | Item | Location | Effort |
|---|------|----------|--------|
| 11 | Write and publish Privacy Policy page | `RE/website/` | 1 day |
| 12 | Write and publish Terms of Service page | `RE/website/` | 1 day |
| 13 | Reconcile domain: choose `grump.app` or `g-rump.com` | LICENSE, entire codebase | 0.5 day |
| 14 | Add consent prompt at onboarding (before first AI call) | `OnboardingView.swift` | 0.5 day |
| 15 | Complete privacy manifest (NSPasteboard, UserContent, ambient tracking) | `PrivacyInfo.xcprivacy` | 0.5 day |
| 16 | Flip ambient monitoring defaults to opt-in | `AmbientMonitor.swift` | 0.5 day |
| 17 | Remove fabricated aggregate rating from JSON-LD | `RE/website/src/app/layout.tsx` | 0.5 day |

### Phase 3: Broken Features Fix (Week 2)

Fix features that are visibly broken to users.

| # | Item | Files | Effort |
|---|------|-------|--------|
| 18 | Implement WritingToolsService (connect to AI service or remove the button) | `WritingToolsService.swift`, `MessageViews.swift` | 1 day |
| 19 | Wire code font setting to CodeBlockView/MarkdownTextView | `DesignTokens.swift`, `CodeBlockView.swift`, `MarkdownTextView.swift` | 0.5 day |
| 20 | Wire line spacing setting to MarkdownTextView | `MarkdownTextView.swift` | 0.5 day |
| 21 | Fix git shortcuts (add `-m` flag, read pipe output) | `StatusBarView.swift` | 0.5 day |
| 22 | Fix notification approval handler to use specific approvalId | `ContentView.swift`, `NotificationService.swift` | 0.5 day |
| 23 | Move ConnectionMonitor.start() to app lifecycle level | `GRumpApp.swift` | 0.5 day |
| 24 | Gate streaming on ConnectionMonitor.canStream | `ChatViewModel+Streaming.swift` | 0.5 day |
| 25 | Fix WritingTools availability check (macOS 15+ / iOS 18+) | `WritingToolsService.swift` | 0.5 day |

### Phase 4: Distribution Pipeline (Week 2-3)

Enable automatic updates and streamlined releases.

| # | Item | Files | Effort |
|---|------|-------|--------|
| 26 | Generate Sparkle EdDSA keypair, add SUFeedURL + SUPublicEDKey to Info.plist | `Info.plist` | 0.5 day |
| 27 | Create and host appcast.xml | `RE/website/public/` or CDN | 0.5 day |
| 28 | Fix "Check for updates on launch" Settings toggle | `Settings+TabViews.swift` | 0.5 day |
| 29 | Replace Google OAuth placeholder in Info.plist | `Info.plist` | 0.5 day |
| 30 | Synchronize version number across Info.plist, project.yml, create-release.sh | All three files | 0.5 day |
| 31 | Parameterize create-release.sh | `scripts/create-release.sh` | 0.5 day |
| 32 | Add CI signing + notarization + artifact upload | `.github/workflows/ci.yml` | 1 day |

### Phase 5: Backend Hardening (Week 3)

Production reliability and billing correctness.

| # | Item | Files | Effort |
|---|------|-------|--------|
| 33 | Handle `invoice.payment_succeeded` webhook | `backend/stripe.js` | 0.5 day |
| 34 | Handle `customer.subscription.paused` webhook | `backend/stripe.js` | 0.5 day |
| 35 | Validate Stripe price IDs on startup (fail fast) | `backend/stripe.js` | 0.5 day |
| 36 | Add pre-request credit balance check before proxying | `backend/proxy.js` | 0.5 day |
| 37 | Validate `avatarUrl` as `https://` URL | `backend/server.js` | 0.5 day |
| 38 | Add versioned migration table | `backend/db.js` | 1 day |
| 39 | Enable `PRAGMA foreign_keys = ON` | `backend/db.js` | 0.5 day |
| 40 | Add index on `usage_log(created_at)` | `backend/db.js` | 0.5 day |
| 41 | Add Vercel Cron for 90-day log prune | `backend/vercel.json` or GitHub Actions | 0.5 day |
| 42 | Increase `maxDuration` to 300 for streaming | `backend/vercel.json` | 0.5 day |
| 43 | Add structured JSON logging with request IDs | `backend/server.js` | 1 day |
| 44 | Add Sentry or equivalent error tracking | `backend/server.js` | 0.5 day |
| 45 | Replace model tier string-includes with maintained allowlist | `backend/proxy.js` | 0.5 day |
| 46 | Add JWT refresh endpoint | `backend/auth.js`, `backend/server.js` | 1 day |
| 47 | Add Stripe idempotency keys | `backend/stripe.js` | 0.5 day |
| 48 | Add `rate-limit-redis` or Vercel KV store | `backend/server.js` | 0.5 day |

### Phase 6: Website Launch (Week 3-4)

| # | Item | Effort |
|---|------|--------|
| 49 | Create OG image, PWA icons, logo, favicon | 1 day |
| 50 | Deploy website to Vercel with DNS for g-rump.com | 0.5 day |
| 51 | Wire download button to actual DMG URL | 0.5 day |
| 52 | Implement contact form backend | 0.5 day |
| 53 | Create/verify Twitter and Discord accounts | 0.5 day |
| 54 | Replace placeholder testimonials with real quotes (or remove section) | 0.5 day |
| 55 | Take fresh product screenshots | 0.5 day |

### Phase 7: Test Coverage (Week 4-5)

| # | Item | Priority | Effort |
|---|------|----------|--------|
| 56 | Stripe webhook integration tests | Financial risk | 1 day |
| 57 | Credit deduction tests (including race condition) | Financial risk | 0.5 day |
| 58 | Backend auth middleware HTTP tests | Security | 0.5 day |
| 59 | Streaming pipeline integration test (mock SSE) | Core functionality | 1 day |
| 60 | Parallel tool execution tests | Core functionality | 1 day |
| 61 | MCP subprocess lifecycle tests | Integration | 0.5 day |
| 62 | Conversation persistence round-trip test | Data integrity | 0.5 day |
| 63 | Backend API route integration tests | Reliability | 1 day |
| 64 | Add `better-sqlite3` to devDependencies | CI fix | 0.1 day |

### Phase 8: Accessibility & Polish (Week 5-6)

| # | Item | Effort |
|---|------|--------|
| 65 | Dynamic Type: Refactor Typography tokens to respect `@Environment(\.sizeCategory)` | 2 days |
| 66 | Add VoiceOver announcements (splash, errors, onboarding steps) | 1 day |
| 67 | Fix StreamErrorView to skip animations when reduceMotion is active | 0.5 day |
| 68 | Add `.accessibilityLabel` to StatusBarView connection dot | 0.5 day |
| 69 | Audit theme palettes for WCAG AA contrast compliance | 0.5 day |
| 70 | Fix SpotlightIndexer to use async API off main thread | 0.5 day |

---

## Appendix A: Environment Variables Required for Deployment

### Backend (Vercel)

```
# Required
NODE_ENV=production
JWT_SECRET=<min 32 chars>
TURSO_DATABASE_URL=libsql://<your-db>.turso.io
TURSO_AUTH_TOKEN=<turso-token>
CORS_ORIGIN=https://www.g-rump.com
OPENROUTER_API_KEY=<key>

# Stripe (required if billing enabled)
STRIPE_SECRET_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
STRIPE_PRICE_STARTER=price_...
STRIPE_PRICE_PRO=price_...
STRIPE_PRICE_TEAM=price_...
STRIPE_PRICE_CREDITS_SMALL=price_...
STRIPE_PRICE_CREDITS_MEDIUM=price_...
STRIPE_PRICE_CREDITS_LARGE=price_...

# Google Auth
GOOGLE_CLIENT_ID=<client-id>.apps.googleusercontent.com
```

### macOS App Distribution

```
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
APPLE_ID=your@email.com
TEAM_ID=YOURTEAMID
APP_PASSWORD=xxxx-xxxx-xxxx-xxxx  # App-specific password from appleid.apple.com
```

## Appendix B: Files Referenced in This Analysis

| File | Section |
|------|---------|
| `Sources/GRump/MCPServerHost.swift` | S1, S3 |
| `Sources/GRump/ChatViewModel+ToolExecution.swift` | S2 |
| `Sources/GRump/ToolExec+ShellSystem.swift` | S3 |
| `backend/proxy.js` | S4, B4 |
| `backend/server.js` | B1, B4 |
| `backend/stripe.js` | B2, B3 |
| `backend/auth.js` | 3.Credentials |
| `Sources/GRump/WritingToolsService.swift` | A1 |
| `Sources/GRump/DesignTokens.swift` | A2, A3, 5.Accessibility |
| `Sources/GRump/StatusBarView.swift` | A5, 5.Quality |
| `Sources/GRump/Info.plist` | D2, D3, D1 |
| `Sources/GRump/Services/SparkleUpdateService.swift` | D1 |
| `Sources/GRump/GRumpApp.swift` | D1 |
| `scripts/package.sh` | 6.Distribution |
| `scripts/create-release.sh` | 6.Distribution |
| `.github/workflows/ci.yml` | D4, 8.CI |
| `GRump.entitlements` | 6.Distribution |
| `Sources/GRump/Resources/PrivacyInfo.xcprivacy` | 3.Privacy |
| `Sources/GRump/AmbientMonitor.swift` | 3.Privacy |
| `Sources/GRump/ConnectionMonitor.swift` | 5.Quality |
| `Sources/GRump/NotificationService.swift` | 5.Quality |
| `Sources/GRump/OnboardingView.swift` | 5.Quality |
| `Sources/GRump/ThemeManager.swift` | 5.Quality |
| `Sources/GRump/OpenClawService.swift` | 3.OpenClaw |
| `RE/website/` | 7.Website |
| `backend/vercel.json` | 4.Backend |
