JOBS := $(shell sysctl -n hw.ncpu)

.PHONY: run build build-debug build-release clean reset app dmg sign notarize package help

# ── Development ───────────────────────────────────────

run: build-debug ## Build debug and run
	.build/debug/GRump

build: build-debug ## Alias for build-debug

build-debug: ## Fast debug build (no optimizations)
	swift build -j $(JOBS)

build-release: ## Optimized release build
	swift build -c release -j $(JOBS)

clean: ## Remove all build artifacts
	rm -rf .build dist

# ── Packaging ─────────────────────────────────────────

app: ## Build release + create .app bundle in dist/
	./scripts/package.sh

dmg: ## Build release + create .app + .dmg in dist/
	./scripts/package.sh --dmg

sign: ## Build + sign .app (requires DEVELOPER_ID env var)
	./scripts/package.sh --sign

package: ## Build + sign + .dmg (requires DEVELOPER_ID)
	./scripts/package.sh --sign --dmg

notarize: ## Build + sign + .dmg + notarize (requires DEVELOPER_ID, APPLE_ID, TEAM_ID, APP_PASSWORD)
	./scripts/package.sh --sign --dmg --notarize

# ── Utilities ────────────────────────────────────────

reset: ## Reset app state (wipe UserDefaults, caches, data) for fresh-boot testing
	@echo "Resetting G-Rump app state..."
	defaults delete com.grump.app 2>/dev/null || true
	rm -rf "$$HOME/.grump"
	rm -rf "$$HOME/Library/Application Support/GRump"
	@echo "✓ App state reset. Next launch will show onboarding."

# ── Help ──────────────────────────────────────────────

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
