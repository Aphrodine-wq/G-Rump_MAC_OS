---
name: Rapid Prototyping
description: Quickly scaffold MVPs and prototypes to validate ideas fast.
tags: [prototyping, mvp, scaffolding, validation, startup]
---

# Rapid Prototyping Skill

When building prototypes and MVPs:

1. Start with the core user flow — build only what's needed to validate the hypothesis
2. Use high-level frameworks that minimize boilerplate: SwiftUI, Next.js, Rails, FastAPI, Flutter
3. Prefer managed services over self-hosted: Supabase/Firebase for auth+DB, Vercel/Railway for hosting
4. Use existing UI component libraries (shadcn/ui, Chakra, Apple HIG templates) instead of custom design
5. Hard-code or mock what isn't critical yet — real integrations can come later
6. Deploy early and share: get the prototype in users' hands within days, not weeks
7. Use feature flags to ship incomplete features behind toggles
8. Keep the data model simple — normalize later, ship now
9. Write just enough tests to catch regressions on the critical path
10. Document decisions briefly so you can revisit or hand off the prototype
11. Use AI code generation to accelerate repetitive scaffolding (models, CRUD, forms)
12. Set a time box: if a prototype takes more than 1-2 weeks, scope is too large
13. Collect feedback with minimal tooling: a feedback button, a shared Slack channel, or a simple form
14. Plan the transition: identify what needs to be rewritten vs. what can evolve into production code
