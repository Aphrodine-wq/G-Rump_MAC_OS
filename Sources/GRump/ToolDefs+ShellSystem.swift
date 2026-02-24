import Foundation

// MARK: - Shell, System, Clipboard, Screen Tool Definitions
// Extracted from ToolDefinitions.swift for maintainability.

extension ToolDefinitions {

    // MARK: - Shell & Environment

    static let getEnv: [String: Any] = [
        "type": "function",
        "function": [
            "name": "get_env",
            "description": "Read environment variable(s). Pass name for one variable, or omit to get all (filtered to common dev vars). Use to check PATH, HOME, LANG, or project-specific vars.",
            "parameters": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Optional. Variable name (e.g. PATH, HOME). If omitted, returns a summary of common env vars."]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let getCwd: [String: Any] = [
        "type": "function",
        "function": [
            "name": "get_cwd",
            "description": "Get the current working directory (project root). Use to verify paths or when paths must be resolved relative to the project.",
            "parameters": ["type": "object", "properties": [], "required": [] as [String]] as [String: Any]
        ] as [String: Any]
    ]

    static let listEnv: [String: Any] = [
        "type": "function",
        "function": [
            "name": "list_env",
            "description": "List all environment variables as key=value pairs. Use to inspect PATH, LANG, project env, or debug environment issues.",
            "parameters": [
                "type": "object",
                "properties": [
                    "prefix": ["type": "string", "description": "Optional. Only list vars whose names start with this prefix (e.g. 'PATH', 'NODE')."]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let listProcesses: [String: Any] = [
        "type": "function",
        "function": [
            "name": "list_processes",
            "description": "List running processes. Optional filter by name substring (e.g. 'node', 'python'). Returns PID, command, and optionally CPU/memory. Useful to see what's running before starting servers or debugging.",
            "parameters": [
                "type": "object",
                "properties": [
                    "filter": ["type": "string", "description": "Optional. Substring to filter process names (e.g. 'node', 'xcode')."],
                    "limit": ["type": "integer", "description": "Max processes to return (default: 50)"]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let diskUsage: [String: Any] = [
        "type": "function",
        "function": [
            "name": "disk_usage",
            "description": "Get disk usage for a path or the project directory. Returns total, used, free space in human-readable form. Useful to check space before large operations.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Optional. Path to check (directory or file). Defaults to working directory."]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let runCommand: [String: Any] = [
        "type": "function",
        "function": [
            "name": "run_command",
            "description": "Execute a shell command (via zsh) and return stdout, stderr, and exit code. Use for builds, tests, git operations, package management, and any CLI task. Default timeout is 60 seconds.",
            "parameters": [
                "type": "object",
                "properties": [
                    "command": [
                        "type": "string",
                        "description": "The shell command to execute"
                    ],
                    "cwd": [
                        "type": "string",
                        "description": "Working directory for the command (defaults to project working directory if set)"
                    ],
                    "timeout": [
                        "type": "integer",
                        "description": "Timeout in seconds (default: 60)"
                    ]
                ],
                "required": ["command"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let runBackground: [String: Any] = [
        "type": "function",
        "function": [
            "name": "run_background",
            "description": "Run a command in the background. Returns immediately with PID. Use kill_process to stop.",
            "parameters": [
                "type": "object",
                "properties": [
                    "command": ["type": "string", "description": "The shell command to run"],
                    "cwd": ["type": "string", "description": "Working directory (optional)"]
                ],
                "required": ["command"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let killProcess: [String: Any] = [
        "type": "function",
        "function": [
            "name": "kill_process",
            "description": "Kill a process by PID. Sends SIGTERM by default; use signal 9 for SIGKILL.",
            "parameters": [
                "type": "object",
                "properties": [
                    "pid": ["type": "integer", "description": "Process ID to kill"],
                    "signal": ["type": "integer", "description": "Signal number (default 15=SIGTERM, 9=SIGKILL)"]
                ],
                "required": ["pid"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let which: [String: Any] = [
        "type": "function",
        "function": [
            "name": "which",
            "description": "Find the path of an executable in PATH.",
            "parameters": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Executable name (e.g. node, python)"]
                ],
                "required": ["name"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - System (macOS)

    static let systemRun: [String: Any] = [
        "type": "function",
        "function": [
            "name": "system_run",
            "description": "Execute a shell command with system-level exec approvals. Use for running binaries outside the project (e.g. system tools, Homebrew). Subject to user allowlist and approval prompts. Prefer run_command for project-scoped builds and scripts.",
            "parameters": [
                "type": "object",
                "properties": [
                    "command": [
                        "type": "string",
                        "description": "The shell command to execute"
                    ],
                    "cwd": [
                        "type": "string",
                        "description": "Working directory (optional)"
                    ],
                    "timeout_seconds": [
                        "type": "integer",
                        "description": "Timeout in seconds (default: 60)"
                    ]
                ],
                "required": ["command"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let systemNotify: [String: Any] = [
        "type": "function",
        "function": [
            "name": "system_notify",
            "description": "Show a native system notification to the user. Use for alerts, completion notices, or reminders.",
            "parameters": [
                "type": "object",
                "properties": [
                    "title": [
                        "type": "string",
                        "description": "Notification title"
                    ],
                    "body": [
                        "type": "string",
                        "description": "Notification body text"
                    ],
                    "subtitle": [
                        "type": "string",
                        "description": "Optional subtitle"
                    ]
                ],
                "required": ["title", "body"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - Clipboard & Open (macOS)

    static let clipboardRead: [String: Any] = [
        "type": "function",
        "function": [
            "name": "clipboard_read",
            "description": "Read the current string content from the system clipboard.",
            "parameters": [
                "type": "object",
                "properties": [],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let clipboardWrite: [String: Any] = [
        "type": "function",
        "function": [
            "name": "clipboard_write",
            "description": "Write a string to the system clipboard.",
            "parameters": [
                "type": "object",
                "properties": [
                    "text": [
                        "type": "string",
                        "description": "The text to copy to the clipboard"
                    ]
                ],
                "required": ["text"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let openURL: [String: Any] = [
        "type": "function",
        "function": [
            "name": "open_url",
            "description": "Open a URL in the default browser or application (e.g. https://, file://, mailto:).",
            "parameters": [
                "type": "object",
                "properties": [
                    "url": [
                        "type": "string",
                        "description": "The URL to open"
                    ]
                ],
                "required": ["url"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let openApp: [String: Any] = [
        "type": "function",
        "function": [
            "name": "open_app",
            "description": "Open an application by name or bundle identifier (macOS).",
            "parameters": [
                "type": "object",
                "properties": [
                    "name_or_bundle_id": [
                        "type": "string",
                        "description": "Application name (e.g. Safari, Xcode) or bundle id (e.g. com.apple.Safari)"
                    ]
                ],
                "required": ["name_or_bundle_id"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - Screen & Camera (macOS)

    static let screenSnapshot: [String: Any] = [
        "type": "function",
        "function": [
            "name": "screen_snapshot",
            "description": "Capture a single screenshot of the screen. Returns the path to the saved PNG file. Requires Screen Recording permission on macOS.",
            "parameters": [
                "type": "object",
                "properties": [],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let screenRecord: [String: Any] = [
        "type": "function",
        "function": [
            "name": "screen_record",
            "description": "Start a short screen recording (macOS). Saves to a temp file and returns the path. Requires Screen Recording permission. Duration in seconds (max 60).",
            "parameters": [
                "type": "object",
                "properties": [
                    "duration_seconds": [
                        "type": "integer",
                        "description": "Recording duration in seconds (default: 5, max 60)"
                    ]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let cameraSnap: [String: Any] = [
        "type": "function",
        "function": [
            "name": "camera_snap",
            "description": "Capture a single still image from the camera (macOS). Returns path to the saved image. Requires Camera permission.",
            "parameters": [
                "type": "object",
                "properties": [],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let windowList: [String: Any] = [
        "type": "function",
        "function": [
            "name": "window_list",
            "description": "List visible windows (macOS). Requires Accessibility permission. Returns app names and window titles.",
            "parameters": [
                "type": "object",
                "properties": [],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let windowSnapshot: [String: Any] = [
        "type": "function",
        "function": [
            "name": "window_snapshot",
            "description": "Capture an accessibility snapshot of the frontmost window or a named app (macOS). Requires Accessibility permission. Returns a text description of the UI hierarchy.",
            "parameters": [
                "type": "object",
                "properties": [
                    "app_name": [
                        "type": "string",
                        "description": "Optional: target app by name (e.g. Safari). If omitted, uses frontmost window."
                    ]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - System Info & Network

    static let getSystemInfo: [String: Any] = [
        "type": "function",
        "function": [
            "name": "get_system_info",
            "description": "Get system information (OS, architecture, hostname).",
            "parameters": [
                "type": "object",
                "properties": [],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let listNetworkInterfaces: [String: Any] = [
        "type": "function",
        "function": [
            "name": "list_network_interfaces",
            "description": "List network interfaces and their status.",
            "parameters": [
                "type": "object",
                "properties": [],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]
}
