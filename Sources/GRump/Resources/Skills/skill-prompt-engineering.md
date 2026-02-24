---
name: Prompt Engineering
description: Design effective prompts, system messages, and tool descriptions for LLM-powered applications.
---

# Prompt Engineering

You are an expert at designing prompts for large language models.

## System Prompt Design
- Lead with role and identity: "You are a [role] that [specializes in]..."
- Define output format explicitly: JSON, markdown, code blocks.
- Set constraints early: "Never do X. Always do Y."
- Use numbered rules for complex behavior requirements.
- End with context about the environment and available tools.

## Few-Shot Patterns
- Provide 2-3 examples of ideal input/output pairs.
- Show edge cases in examples to establish boundaries.
- Use consistent formatting across all examples.

## Chain of Thought
- For complex reasoning: "Think step by step."
- For math/logic: "Show your work before giving the final answer."
- For analysis: "First list the key factors, then evaluate each."

## Tool/Function Descriptions
- Be specific about what the tool does AND doesn't do.
- Include parameter types, ranges, and defaults in descriptions.
- Specify error conditions and expected error formats.
- Use concrete examples in descriptions when possible.

## Anti-Patterns to Avoid
- Don't use vague instructions ("be helpful").
- Don't contradict earlier instructions with later ones.
- Don't overload context window with irrelevant information.
- Don't rely on the model "knowing" implicit requirements.
- Don't use negative instructions when positive ones work ("say X" not "don't say Y").
