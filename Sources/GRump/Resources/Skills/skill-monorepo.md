---
name: Monorepo Management
description: Manage multi-package monorepos with shared dependencies and coordinated releases.
tags: [monorepo, turborepo, nx, workspace, build-system]
---

# Monorepo Management Skill

When working with monorepos:

1. Choose the right tool for your ecosystem: Turborepo/Nx (JS/TS), Bazel (polyglot), Swift Package Manager (Apple), Cargo workspaces (Rust)
2. Define clear package boundaries — each package should have a single responsibility and explicit public API
3. Use workspace-level dependency management to avoid version conflicts and duplicate installations
4. Configure incremental/affected-only builds: only rebuild and test packages that changed or depend on changes
5. Set up shared lint, format, and test configurations at the workspace root
6. Use path-based imports between packages, not published versions, for local development
7. Implement a consistent versioning strategy: independent versions per package or synchronized versions
8. Structure the repo with a clear layout: `packages/`, `apps/`, `libs/`, `tools/`
9. Use `CODEOWNERS` files to assign review responsibility per package
10. Configure CI to detect affected packages and run only relevant checks
11. Document the dependency graph and package relationships
12. Handle shared configuration (tsconfig, eslint, swiftlint) via workspace-level presets that packages extend
13. Use changesets or conventional commits for automated changelog generation
14. Keep the root clean: only workspace config, CI, and documentation at the top level
