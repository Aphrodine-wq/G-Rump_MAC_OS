---
name: Code Migration
description: Migrate between frameworks, languages, or versions.
---

# Code Migration Skill

When migrating code:

1. Audit the current codebase: map all dependencies, APIs, and integration points
2. Create a migration plan with phases: prepare, migrate, validate, cleanup
3. Set up both old and new systems running in parallel when possible
4. Migrate incrementally (strangler fig pattern) rather than big-bang rewrites
5. Write adapter layers to maintain backward compatibility during transition
6. Update all tests to pass on the new framework/version before switching
7. Handle breaking API changes with deprecation notices and version bumps
8. Update CI/CD pipelines, build configs, and deployment scripts
9. Document all changed patterns, removed features, and new conventions

Verify the migration with comprehensive testing: unit, integration, and end-to-end.
