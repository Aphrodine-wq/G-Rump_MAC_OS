# Agent Modes

G-Rump supports 5 agent modes, each tailoring the AI's behavior for different workflows.

## Modes

### Chat
Default conversational mode. The agent answers questions, explains code, and provides suggestions. Tool usage is moderate — reads files on request, runs searches.

### Plan
The agent creates a structured plan before acting. Outputs a numbered checklist of steps, asks for confirmation, then executes. Best for complex multi-file changes.

### Build
Aggressive execution mode. The agent reads, writes, and runs commands autonomously to implement features end-to-end. Minimal confirmation — uses all available tools. Best for greenfield features.

### Debate
The agent presents multiple approaches with pros/cons before recommending one. Encourages discussion. Best for architectural decisions and design reviews.

### Spec
The agent writes a detailed specification document (requirements, API design, data models, edge cases) without implementing. Best for planning before coding.

## Mode Selection

Mode is selected via the mode selector row in the chat area (below the input bar). The current mode persists per conversation.

## Workflow Presets

Presets combine a mode with a model, system prompt, and optional tool subset. Configure in **Settings → AI & Model → Workflow Presets**.

Built-in presets:
- **Refactor** — Build mode + focused tool subset
- **Debug** — Chat mode + diagnostic tools
- **Read-only** — Chat mode + read-only tools (no writes)
- **Extended Run** — Build mode + 150 max agent steps
