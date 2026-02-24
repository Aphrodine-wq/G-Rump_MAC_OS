import Foundation

// MARK: - Git, DevOps, Browser, Cloud, Code Intelligence Tool Definitions
// Extracted from ToolDefinitions.swift for maintainability.

extension ToolDefinitions {

    // MARK: - Web

    static let webSearch: [String: Any] = [
        "type": "function",
        "function": [
            "name": "web_search",
            "description": "Search the web for information. Returns titles, snippets, and URLs. Use for documentation lookups, error troubleshooting, finding API references, and current information.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "The search query (be specific for better results)"
                    ]
                ],
                "required": ["query"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let readURL: [String: Any] = [
        "type": "function",
        "function": [
            "name": "read_url",
            "description": "Fetch and read a web page. HTML is stripped to plain text for readability. Use after web_search to read specific results, or for documentation pages.",
            "parameters": [
                "type": "object",
                "properties": [
                    "url": [
                        "type": "string",
                        "description": "The URL to fetch"
                    ]
                ],
                "required": ["url"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let fetchJson: [String: Any] = [
        "type": "function",
        "function": [
            "name": "fetch_json",
            "description": "Fetch a URL and parse the response as JSON. Returns the parsed structure as text.",
            "parameters": [
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "The URL to fetch"]
                ],
                "required": ["url"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let downloadFile: [String: Any] = [
        "type": "function",
        "function": [
            "name": "download_file",
            "description": "Download a file from a URL and save it to a local path.",
            "parameters": [
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "URL to download"],
                    "path": ["type": "string", "description": "Local path to save the file"]
                ],
                "required": ["url", "path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - Code Intelligence & Build

    static let runBuild: [String: Any] = [
        "type": "function",
        "function": [
            "name": "run_build",
            "description": "Run the project's build. Infers command from package.json (npm run build), Package.swift (swift build), Cargo.toml (cargo build), Makefile (make), or pass a custom command. Use after editing code to verify it compiles.",
            "parameters": [
                "type": "object",
                "properties": [
                    "command": ["type": "string", "description": "Optional. Override build command (e.g. 'npm run build', 'xcodebuild'). If omitted, inferred from project files."]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let runLinter: [String: Any] = [
        "type": "function",
        "function": [
            "name": "run_linter",
            "description": "Run the project's linter or formatter. Tries eslint, swiftlint, ruff, clippy, etc. from project config, or use optional command override. Use to check code quality after edits.",
            "parameters": [
                "type": "object",
                "properties": [
                    "command": ["type": "string", "description": "Optional. Override linter command (e.g. 'eslint .', 'swiftlint')."],
                    "path": ["type": "string", "description": "Optional. Path or file to lint (default: project root)."]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let runFormat: [String: Any] = [
        "type": "function",
        "function": [
            "name": "run_format",
            "description": "Run the project's code formatter (prettier, swiftformat, black, rustfmt, etc.).",
            "parameters": [
                "type": "object",
                "properties": [
                    "command": ["type": "string", "description": "Optional. Override format command."],
                    "path": ["type": "string", "description": "Optional. Path or file to format."]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let getPackageDeps: [String: Any] = [
        "type": "function",
        "function": [
            "name": "get_package_deps",
            "description": "List project dependencies from package.json, Package.swift, requirements.txt, Cargo.toml, etc.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Project root path (optional)"]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let npmInstall: [String: Any] = [
        "type": "function",
        "function": [
            "name": "npm_install",
            "description": "Run npm install to add or update dependencies. Use package to add a specific package.",
            "parameters": [
                "type": "object",
                "properties": [
                    "package": ["type": "string", "description": "Optional. Package name to add (e.g. lodash)."],
                    "dev": ["type": "boolean", "description": "Add as devDependency (default false)"]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let pipInstall: [String: Any] = [
        "type": "function",
        "function": [
            "name": "pip_install",
            "description": "Run pip install to add Python packages.",
            "parameters": [
                "type": "object",
                "properties": [
                    "package": ["type": "string", "description": "Package to install (e.g. requests). Omit to install from requirements.txt."]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let cargoAdd: [String: Any] = [
        "type": "function",
        "function": [
            "name": "cargo_add",
            "description": "Add a Rust dependency with cargo add.",
            "parameters": [
                "type": "object",
                "properties": [
                    "package": ["type": "string", "description": "Crate name to add"],
                    "dev": ["type": "boolean", "description": "Add as dev-dependency (default false)"]
                ],
                "required": ["package"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let viewCodeOutline: [String: Any] = [
        "type": "function",
        "function": [
            "name": "view_code_outline",
            "description": "View the structural outline of a source code file — functions, classes, structs, imports, etc. Language-aware patterns for Swift, Python, JavaScript/TypeScript, Rust, Go, and Java.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": [
                        "type": "string",
                        "description": "Path to the source code file"
                    ]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - Git & Tests

    static let gitStatus: [String: Any] = [
        "type": "function",
        "function": [
            "name": "git_status",
            "description": "Run git status and optionally git diff --stat in the working directory. Use to see what files changed, branch, and staged/unstaged state before or after edits.",
            "parameters": [
                "type": "object",
                "properties": [
                    "include_diff_stat": [
                        "type": "boolean",
                        "description": "If true, also run git diff --stat to show changed line counts. Default true."
                    ]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let runTests: [String: Any] = [
        "type": "function",
        "function": [
            "name": "run_tests",
            "description": "Run the project's test suite. Detects test command from package.json (npm test), Package.swift (swift test), pyproject.toml (pytest), Cargo.toml (cargo test), or use an optional command override.",
            "parameters": [
                "type": "object",
                "properties": [
                    "command": [
                        "type": "string",
                        "description": "Optional. Override the test command (e.g. 'npm test', 'cargo test', 'pytest'). If omitted, the command is inferred from project files."
                    ]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - Git (extended)

    static let gitLog: [String: Any] = [
        "type": "function",
        "function": [
            "name": "git_log",
            "description": "Show git commit log. Optional limit and path filter. Use to see recent history or who changed a file.",
            "parameters": [
                "type": "object",
                "properties": [
                    "limit": ["type": "integer", "description": "Max commits to show (default: 20)"],
                    "path": ["type": "string", "description": "Optional. Limit log to this file or path."],
                    "oneline": ["type": "boolean", "description": "Short one-line format (default: true)"]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let gitDiff: [String: Any] = [
        "type": "function",
        "function": [
            "name": "git_diff",
            "description": "Show git diff. Optional: staged only, or between refs, or for a specific path. Use to see exact changes before/after edits.",
            "parameters": [
                "type": "object",
                "properties": [
                    "staged": ["type": "boolean", "description": "Show staged changes only (default: false)"],
                    "path": ["type": "string", "description": "Optional. Limit diff to this file or path."],
                    "ref": ["type": "string", "description": "Optional. Compare against ref (e.g. HEAD~1, main)."]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let gitBranch: [String: Any] = [
        "type": "function",
        "function": [
            "name": "git_branch",
            "description": "List git branches. Shows current branch and optionally all remotes. Use to see branch structure and current branch.",
            "parameters": [
                "type": "object",
                "properties": [
                    "all": ["type": "boolean", "description": "Include remote branches (default: false)"]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let gitShow: [String: Any] = [
        "type": "function",
        "function": [
            "name": "git_show",
            "description": "Show a file at a given git ref (commit, branch, or tag). Use to see previous version of a file or compare.",
            "parameters": [
                "type": "object",
                "properties": [
                    "ref": ["type": "string", "description": "Commit, branch, or tag (e.g. HEAD, main, abc123)"],
                    "path": ["type": "string", "description": "Path to the file in the repo"]
                ],
                "required": ["ref", "path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let gitAdd: [String: Any] = [
        "type": "function",
        "function": [
            "name": "git_add",
            "description": "Stage files for commit.",
            "parameters": [
                "type": "object",
                "properties": [
                    "paths": ["type": "array", "items": ["type": "string"], "description": "Paths to stage. Use . for all."]
                ],
                "required": ["paths"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let gitCommit: [String: Any] = [
        "type": "function",
        "function": [
            "name": "git_commit",
            "description": "Create a commit with staged changes.",
            "parameters": [
                "type": "object",
                "properties": [
                    "message": ["type": "string", "description": "Commit message"]
                ],
                "required": ["message"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let gitStash: [String: Any] = [
        "type": "function",
        "function": [
            "name": "git_stash",
            "description": "Stash or pop changes. Use action: push to stash, pop to restore.",
            "parameters": [
                "type": "object",
                "properties": [
                    "action": ["type": "string", "description": "push or pop"],
                    "message": ["type": "string", "description": "Optional message for stash push"]
                ],
                "required": ["action"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let gitCheckout: [String: Any] = [
        "type": "function",
        "function": [
            "name": "git_checkout",
            "description": "Checkout a branch or restore files.",
            "parameters": [
                "type": "object",
                "properties": [
                    "target": ["type": "string", "description": "Branch name, or -- for paths"],
                    "paths": ["type": "array", "items": ["type": "string"], "description": "Optional. Paths to restore (use with target: --)"]
                ],
                "required": ["target"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let gitPush: [String: Any] = [
        "type": "function",
        "function": [
            "name": "git_push",
            "description": "Push commits to remote.",
            "parameters": [
                "type": "object",
                "properties": [
                    "remote": ["type": "string", "description": "Remote name (default origin)"],
                    "branch": ["type": "string", "description": "Branch to push (default current)"]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let gitPull: [String: Any] = [
        "type": "function",
        "function": [
            "name": "git_pull",
            "description": "Pull from remote.",
            "parameters": [
                "type": "object",
                "properties": [
                    "remote": ["type": "string", "description": "Remote name (default origin)"]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let gitRemote: [String: Any] = [
        "type": "function",
        "function": [
            "name": "git_remote",
            "description": "List or show git remotes.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Repo path (default: working directory)"]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let gitTag: [String: Any] = [
        "type": "function",
        "function": [
            "name": "git_tag",
            "description": "List git tags.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Repo path"]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let gitReset: [String: Any] = [
        "type": "function",
        "function": [
            "name": "git_reset",
            "description": "Reset git working tree. Use soft/mixed/hard.",
            "parameters": [
                "type": "object",
                "properties": [
                    "mode": ["type": "string", "description": "soft, mixed, or hard"],
                    "target": ["type": "string", "description": "Commit or HEAD~1"]
                ],
                "required": ["mode"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - Database

    static let sqliteQuery: [String: Any] = [
        "type": "function",
        "function": [
            "name": "sqlite_query",
            "description": "Execute a SQL query on an SQLite database file. Returns results as CSV. Use SELECT queries only; for schema inspection use sqlite_schema or sqlite_tables.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to the .db or .sqlite file"],
                    "query": ["type": "string", "description": "SQL SELECT query to execute"]
                ],
                "required": ["path", "query"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let sqliteSchema: [String: Any] = [
        "type": "function",
        "function": [
            "name": "sqlite_schema",
            "description": "Get the schema (CREATE TABLE statements) of an SQLite database. Optionally filter by table name.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to the .db or .sqlite file"],
                    "table": ["type": "string", "description": "Optional: filter to a specific table"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let sqliteTables: [String: Any] = [
        "type": "function",
        "function": [
            "name": "sqlite_tables",
            "description": "List all tables in an SQLite database. Returns table names.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to the .db or .sqlite file"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - Image

    static let imageInfo: [String: Any] = [
        "type": "function",
        "function": [
            "name": "image_info",
            "description": "Get metadata for an image file: dimensions, format, file size. Supports PNG, JPEG, GIF, HEIC, WebP, etc.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to the image file"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let imageResize: [String: Any] = [
        "type": "function",
        "function": [
            "name": "image_resize",
            "description": "Resize an image. Creates a new file or overwrites. Specify max width or height to scale proportionally, or both for exact dimensions. macOS only.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to the image file"],
                    "output_path": ["type": "string", "description": "Output path (default: overwrites input)"],
                    "max_width": ["type": "integer", "description": "Max width in pixels (scale proportionally)"],
                    "max_height": ["type": "integer", "description": "Max height in pixels (scale proportionally)"],
                    "width": ["type": "integer", "description": "Exact width (with height for exact resize)"],
                    "height": ["type": "integer", "description": "Exact height (with width for exact resize)"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let imageConvert: [String: Any] = [
        "type": "function",
        "function": [
            "name": "image_convert",
            "description": "Convert an image to another format (e.g. PNG to JPEG, HEIC to PNG). macOS only.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to the source image"],
                    "output_path": ["type": "string", "description": "Output path with desired extension (e.g. .jpg, .png)"],
                    "quality": ["type": "number", "description": "JPEG quality 0-1 (default 0.9)"]
                ],
                "required": ["path", "output_path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - API & DevOps

    static let httpRequest: [String: Any] = [
        "type": "function",
        "function": [
            "name": "http_request",
            "description": "Make an HTTP request (GET, POST, PUT, PATCH, DELETE). Returns response body and status code. Use for REST APIs.",
            "parameters": [
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "The URL to request"],
                    "method": ["type": "string", "description": "HTTP method: GET, POST, PUT, PATCH, DELETE (default: GET)"],
                    "headers": ["type": "object", "description": "Optional headers as key-value object"],
                    "body": ["type": "string", "description": "Optional request body (for POST/PUT/PATCH)"]
                ],
                "required": ["url"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let readEnvFile: [String: Any] = [
        "type": "function",
        "function": [
            "name": "read_env_file",
            "description": "Read a .env file and return key-value pairs. Handles KEY=value format.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to .env file (default: .env in working directory)"]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let writeEnvFile: [String: Any] = [
        "type": "function",
        "function": [
            "name": "write_env_file",
            "description": "Write or update a .env file. Merges with existing or creates new. Keys are uppercased.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to .env file"],
                    "vars": ["type": "object", "description": "Key-value pairs to write"]
                ],
                "required": ["path", "vars"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let dockerPs: [String: Any] = [
        "type": "function",
        "function": [
            "name": "docker_ps",
            "description": "List Docker containers. Equivalent to docker ps -a. Requires Docker.",
            "parameters": [
                "type": "object",
                "properties": [
                    "all": ["type": "boolean", "description": "Show all containers including stopped (default: true)"]
                ],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let dockerImages: [String: Any] = [
        "type": "function",
        "function": [
            "name": "docker_images",
            "description": "List Docker images. Equivalent to docker images. Requires Docker.",
            "parameters": [
                "type": "object",
                "properties": [],
                "required": [] as [String]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - Docker & Kubernetes

    static let dockerRun: [String: Any] = [
        "type": "function",
        "function": [
            "name": "docker_run",
            "description": "Run a Docker container from an image. Returns container ID and output.",
            "parameters": [
                "type": "object",
                "properties": [
                    "image": ["type": "string", "description": "Docker image name (e.g. nginx:latest)"],
                    "command": ["type": "string", "description": "Optional command to run inside the container"],
                    "ports": ["type": "string", "description": "Port mapping (e.g. 8080:80)"],
                    "detach": ["type": "boolean", "description": "Run in background (default true)"],
                    "env": ["type": "object", "description": "Environment variables as key-value pairs"],
                    "name": ["type": "string", "description": "Container name"]
                ],
                "required": ["image"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let dockerBuild: [String: Any] = [
        "type": "function",
        "function": [
            "name": "docker_build",
            "description": "Build a Docker image from a Dockerfile.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to the build context (directory with Dockerfile)"],
                    "tag": ["type": "string", "description": "Tag for the built image (e.g. myapp:latest)"],
                    "dockerfile": ["type": "string", "description": "Path to Dockerfile (if not in context root)"]
                ],
                "required": ["path", "tag"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let dockerLogs: [String: Any] = [
        "type": "function",
        "function": [
            "name": "docker_logs",
            "description": "Get logs from a running or stopped Docker container.",
            "parameters": [
                "type": "object",
                "properties": [
                    "container": ["type": "string", "description": "Container ID or name"],
                    "tail": ["type": "integer", "description": "Number of lines from the end (default 100)"],
                    "follow": ["type": "boolean", "description": "Stream logs (default false)"]
                ],
                "required": ["container"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let dockerComposeUp: [String: Any] = [
        "type": "function",
        "function": [
            "name": "docker_compose_up",
            "description": "Start services defined in docker-compose.yml.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to docker-compose.yml directory"],
                    "detach": ["type": "boolean", "description": "Run in background (default true)"],
                    "build": ["type": "boolean", "description": "Build images before starting"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let dockerComposeDown: [String: Any] = [
        "type": "function",
        "function": [
            "name": "docker_compose_down",
            "description": "Stop and remove docker-compose services.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to docker-compose.yml directory"],
                    "volumes": ["type": "boolean", "description": "Also remove volumes"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let kubectlGet: [String: Any] = [
        "type": "function",
        "function": [
            "name": "kubectl_get",
            "description": "Get Kubernetes resources (pods, services, deployments, etc.).",
            "parameters": [
                "type": "object",
                "properties": [
                    "resource": ["type": "string", "description": "Resource type (pods, services, deployments, nodes, etc.)"],
                    "namespace": ["type": "string", "description": "Kubernetes namespace (default: default)"],
                    "name": ["type": "string", "description": "Specific resource name (optional)"],
                    "output": ["type": "string", "description": "Output format: wide, json, yaml (default: wide)"]
                ],
                "required": ["resource"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let kubectlApply: [String: Any] = [
        "type": "function",
        "function": [
            "name": "kubectl_apply",
            "description": "Apply a Kubernetes manifest file or directory.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to manifest file or directory"],
                    "namespace": ["type": "string", "description": "Target namespace"],
                    "dry_run": ["type": "boolean", "description": "Dry run without applying"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - Browser Automation

    static let browserOpen: [String: Any] = [
        "type": "function",
        "function": [
            "name": "browser_open",
            "description": "Open a URL in the default web browser.",
            "parameters": [
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "URL to open"]
                ],
                "required": ["url"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let browserScreenshot: [String: Any] = [
        "type": "function",
        "function": [
            "name": "browser_screenshot",
            "description": "Capture a screenshot of a webpage using a headless browser. Returns the image path.",
            "parameters": [
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "URL to screenshot"],
                    "width": ["type": "integer", "description": "Viewport width in pixels (default 1280)"],
                    "height": ["type": "integer", "description": "Viewport height in pixels (default 800)"],
                    "output_path": ["type": "string", "description": "Path to save the screenshot"]
                ],
                "required": ["url"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let browserEvaluate: [String: Any] = [
        "type": "function",
        "function": [
            "name": "browser_evaluate",
            "description": "Load a URL and evaluate JavaScript in a headless browser context. Returns the JS evaluation result.",
            "parameters": [
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "URL to load"],
                    "script": ["type": "string", "description": "JavaScript code to evaluate"],
                    "wait_ms": ["type": "integer", "description": "Wait time after page load before evaluating (ms, default 1000)"]
                ],
                "required": ["url", "script"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - AI & Embeddings

    static let generateEmbeddings: [String: Any] = [
        "type": "function",
        "function": [
            "name": "generate_embeddings",
            "description": "Generate vector embeddings for text using a language model. Useful for semantic search.",
            "parameters": [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "Text to embed"],
                    "model": ["type": "string", "description": "Embedding model (default: text-embedding-3-small)"]
                ],
                "required": ["text"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let semanticSearch: [String: Any] = [
        "type": "function",
        "function": [
            "name": "semantic_search",
            "description": "Search files by meaning using embeddings. Finds semantically similar code or text across a directory.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Natural language search query"],
                    "directory": ["type": "string", "description": "Directory to search in"],
                    "extensions": ["type": "string", "description": "File extensions to include (comma-separated, e.g. '.ts,.js')"],
                    "top_k": ["type": "integer", "description": "Number of results to return (default 10)"]
                ],
                "required": ["query", "directory"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let summarizeText: [String: Any] = [
        "type": "function",
        "function": [
            "name": "summarize_text",
            "description": "Summarize a long text or file contents into a concise summary.",
            "parameters": [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "Text to summarize (or file path)"],
                    "max_length": ["type": "integer", "description": "Maximum summary length in words (default 200)"],
                    "style": ["type": "string", "description": "Summary style: brief, detailed, bullet_points"]
                ],
                "required": ["text"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - Cloud Deployment

    static let vercelDeploy: [String: Any] = [
        "type": "function",
        "function": [
            "name": "vercel_deploy",
            "description": "Deploy a project to Vercel using the Vercel CLI.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Project directory to deploy"],
                    "production": ["type": "boolean", "description": "Deploy to production (default false = preview)"],
                    "env": ["type": "object", "description": "Environment variables to set"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let vercelLogs: [String: Any] = [
        "type": "function",
        "function": [
            "name": "vercel_logs",
            "description": "Get deployment logs from Vercel.",
            "parameters": [
                "type": "object",
                "properties": [
                    "deployment_url": ["type": "string", "description": "Deployment URL or ID"],
                    "follow": ["type": "boolean", "description": "Stream logs in real-time"]
                ],
                "required": ["deployment_url"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let netlifyDeploy: [String: Any] = [
        "type": "function",
        "function": [
            "name": "netlify_deploy",
            "description": "Deploy a site to Netlify using the Netlify CLI.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Directory to deploy (e.g. ./dist)"],
                    "production": ["type": "boolean", "description": "Deploy to production (default false = draft)"],
                    "site_id": ["type": "string", "description": "Netlify site ID (uses linked site if omitted)"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let flyDeploy: [String: Any] = [
        "type": "function",
        "function": [
            "name": "fly_deploy",
            "description": "Deploy an application to Fly.io.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Project directory with fly.toml"],
                    "region": ["type": "string", "description": "Fly.io region (e.g. iad, lhr)"],
                    "image": ["type": "string", "description": "Docker image to deploy (if not building)"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - Code Intelligence

    static let astParse: [String: Any] = [
        "type": "function",
        "function": [
            "name": "ast_parse",
            "description": "Parse a source file into an abstract syntax tree and return its symbol outline (classes, functions, properties, imports). Supports Swift, TypeScript/JavaScript, Python, Go, and Rust. Returns a structured JSON tree of symbols with their types, line numbers, and nesting.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Path to the source file to parse"],
                    "language": ["type": "string", "description": "Language hint (swift, typescript, python, go, rust). Auto-detected from extension if omitted."],
                    "depth": ["type": "integer", "description": "Maximum nesting depth to return (default: all levels)"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let findReferences: [String: Any] = [
        "type": "function",
        "function": [
            "name": "find_references",
            "description": "Find all references to a symbol (function, class, variable, type) across the project. Uses ripgrep-based search with language-aware pattern matching. Returns file paths, line numbers, and surrounding context for each reference.",
            "parameters": [
                "type": "object",
                "properties": [
                    "symbol": ["type": "string", "description": "The symbol name to search for (e.g., 'sendMessage', 'ChatViewModel', 'UserModel')"],
                    "path": ["type": "string", "description": "Directory or file to search within (defaults to working directory)"],
                    "language": ["type": "string", "description": "Filter to specific language files (swift, typescript, python, etc.)"],
                    "include_definitions": ["type": "boolean", "description": "Include the definition site in results (default: true)"]
                ],
                "required": ["symbol"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let typeCheck: [String: Any] = [
        "type": "function",
        "function": [
            "name": "type_check",
            "description": "Run the language's type checker or compiler in check mode and return diagnostics (errors, warnings). Supports: swift build (Swift), tsc --noEmit (TypeScript), mypy (Python), go vet (Go), cargo check (Rust). Returns structured diagnostics with file, line, severity, and message.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Project directory or specific file to type-check"],
                    "language": ["type": "string", "description": "Language (swift, typescript, python, go, rust). Auto-detected if omitted."],
                    "strict": ["type": "boolean", "description": "Enable strict mode where available (default: false)"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let dependencyGraph: [String: Any] = [
        "type": "function",
        "function": [
            "name": "dependency_graph",
            "description": "Build and return the dependency graph of a project. Shows which files/modules import which others. Supports Package.swift, package.json, requirements.txt, Cargo.toml, go.mod. Returns a JSON adjacency list of module dependencies.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Project root directory"],
                    "format": ["type": "string", "description": "Output format: 'json' (adjacency list), 'tree' (text tree), or 'dot' (graphviz). Default: json"],
                    "depth": ["type": "integer", "description": "Maximum depth of transitive dependencies to include (default: 2)"]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    static let codeComplexity: [String: Any] = [
        "type": "function",
        "function": [
            "name": "code_complexity",
            "description": "Calculate cyclomatic complexity and other code metrics for functions in a file or directory. Reports complexity score, lines of code, nesting depth, and parameter count per function. Flags functions exceeding threshold as needing refactoring.",
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "File or directory to analyze"],
                    "threshold": ["type": "integer", "description": "Complexity threshold above which functions are flagged (default: 10)"],
                    "language": ["type": "string", "description": "Language filter (swift, typescript, python, etc.). Auto-detected if omitted."]
                ],
                "required": ["path"]
            ] as [String: Any]
        ] as [String: Any]
    ]
}
