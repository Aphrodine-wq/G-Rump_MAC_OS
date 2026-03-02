# AI Providers

G-Rump supports multiple AI providers with automatic routing and fallback.

## Supported Providers

| Provider | Type | Models |
|---|---|---|
| **Anthropic** | Cloud | Claude 3.5 Sonnet, Claude 3 Opus, Claude 3 Haiku |
| **OpenAI** | Cloud | GPT-4o, GPT-4 Turbo, GPT-3.5 Turbo |
| **OpenRouter** | Cloud | 100+ models from multiple providers |
| **Ollama** | Local | Any GGUF model (Llama, Mistral, CodeLlama, etc.) |
| **CoreML (On-Device)** | Local | Apple Neural Engine optimized models |

## Configuration

API keys are stored in macOS Keychain via `KeychainService`. Configure in **Settings → Providers**.

### OpenRouter (Default)
```
API Key: sk-or-v1-...
Base URL: https://openrouter.ai/api/v1
```

### Ollama (Local)
```
Base URL: http://localhost:11434
No API key required
```

### CoreML (On-Device)
Download models in **Settings → Providers → On-Device**. Models run on Apple Neural Engine with zero network usage.

## Model Router

`ModelRouter` selects the optimal model based on:
- Task complexity (simple → small model, complex → large model)
- User preference (per-conversation or global default)
- Cost controls (`OpenClawCostControl`)
- Workflow preset overrides

## Streaming

All providers stream responses token-by-token. Streaming animation styles:
- **Smooth** — Animated token appearance
- **Typewriter** — Character-by-character
- **Instant** — Full blocks appear at once

Configure in **Settings → AI & Model → Streaming**.

## Privacy

- **Local Only Mode** — Restricts to Ollama and CoreML only
- **Privacy Badge** — Shows shield icon when running fully local
- Configure in **Settings → Privacy & On-Device**
