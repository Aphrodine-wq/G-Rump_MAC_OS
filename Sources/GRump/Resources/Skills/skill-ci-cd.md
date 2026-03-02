---
name: CI/CD Pipeline Design
description: Design and maintain continuous integration and deployment pipelines.
tags: [ci-cd, github-actions, automation, deployment, pipeline]
---

# CI/CD Pipeline Design Skill

When setting up or improving CI/CD:

1. Define stages clearly: lint → test → build → deploy (with approval gates for production)
2. Use matrix builds to test across OS versions, language versions, and architectures
3. Cache dependencies aggressively (SPM, npm, pip, cargo) to reduce build times
4. Run tests in parallel where possible; fail fast on critical checks
5. Use concurrency groups to cancel superseded runs on the same branch
6. Store secrets in the CI platform's secret manager — never hardcode tokens or keys
7. Pin action/image versions to SHA or major version tags for reproducibility
8. Set reasonable timeouts (5 min for lint, 15 min for tests, 30 min for release builds)
9. Generate and upload build artifacts (binaries, coverage reports, changelogs)
10. Use branch protection rules: require passing CI, code review, and up-to-date branches
11. Implement deployment strategies: blue-green, canary, or rolling for production
12. Add health checks and smoke tests post-deploy; auto-rollback on failure
13. Monitor CI metrics: build duration, flake rate, queue time
14. For Apple platforms: use `xcodebuild` or `swift build`, manage certificates with match/fastlane or manual provisioning
15. Document the pipeline in the repo README so contributors understand the flow
