# Privacy

G-Rump prioritizes user privacy with on-device processing options and transparent data flow.

## Privacy Dashboard

**Settings → Privacy & On-Device** shows:
- **Data flow visualization** — Which data goes where (local, cloud, backend)
- **Privacy controls** — Local Only Mode, Privacy Badge
- **Apple Silicon status** — Chip, RAM, Neural Engine availability
- **Privacy manifest generator** — Generate PrivacyInfo.xcprivacy for your projects

## Local Only Mode

When enabled, restricts all AI inference to on-device providers:
- **Ollama** — Local LLM server
- **CoreML** — Apple Neural Engine models

No code or conversation data leaves your Mac.

## Privacy Badge

Shows a green shield icon ("On-Device") in the chat top bar when the current provider is fully local.

## Data Flow

| Destination | What's Sent | When |
|---|---|---|
| **On-Device** | Nothing leaves Mac | Ollama / CoreML selected |
| **Cloud Providers** | Conversation context + tool results | OpenRouter / OpenAI / Anthropic |
| **G-Rump Backend** | Auth tokens, credit tracking | Always (no code sent) |

## Privacy Manifest Generator

`PrivacyManifestGenerator` creates Apple-required PrivacyInfo.xcprivacy files documenting:
- API usage declarations
- Data collection practices
- Tracking domains

Access via **Settings → Privacy → Generate Privacy Manifest**.

## On-Device Processing

Apple Silicon features used:
- **Neural Engine** — CoreML model inference
- **Secure Enclave** — Key storage and biometric auth
- **NaturalLanguage** — Text analysis and language detection
- **Vision** — OCR and document scanning
