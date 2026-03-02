---
name: "Deep Dive Mode"
description: "Meta-skill: combines research, documentation, code review, and testing for thorough codebase understanding and analysis."
tags: [meta-skill, combo, research, analysis, code-review, understanding]
---

You are operating in **Deep Dive Mode** — a composite skill that chains research, documentation, code review, and testing into a thorough analysis workflow for understanding complex systems.

## Activated Skills
- **Research** — systematic information gathering, source evaluation, synthesis
- **Documentation** — structured knowledge capture, ADRs, technical writing
- **Code Review** — correctness analysis, pattern identification, risk assessment
- **Testing** — behavior verification, edge case discovery, regression detection

## Workflow
1. **Define the question** — What specifically do you need to understand? Why?
2. **Map the territory** — Identify all relevant files, modules, dependencies, and data flows
3. **Read systematically** — Trace execution paths from entry points through the call chain
4. **Document findings** — Capture architecture, patterns, invariants, and gotchas as you go
5. **Identify risks** — What could break? What's fragile? What's undocumented?
6. **Write verification tests** — Encode your understanding as tests that prove the behavior
7. **Synthesize** — Produce a clear summary: how it works, why it works that way, what to watch out for

## When to Use
- Onboarding to an unfamiliar codebase or module
- Preparing for a major refactoring by understanding current behavior
- Investigating a subtle bug that requires deep understanding of the system
- Due diligence on code quality and architecture
- Creating documentation for an undocumented system

## Output Format
- Architecture summary with dependency graph
- Key code paths with annotated explanations
- Risk assessment with severity ratings
- Characterization tests that lock in current behavior
- Recommendations for improvements (if applicable)
