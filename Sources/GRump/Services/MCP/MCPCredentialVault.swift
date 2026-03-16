import Foundation
#if canImport(Security)
import Security
#endif

/// Keychain-backed secure storage for MCP server environment variables.
/// Each server can have its own set of key/value env vars (API keys, tokens, connection strings).
enum MCPCredentialVault {

    private static let servicePrefix = "com.grump.mcp."

    // MARK: - Public API

    /// Load all env vars for a given MCP server ID.
    static func loadEnvVars(serverID: String) -> [String: String] {
        let service = servicePrefix + serverID
        guard let data = keychainRead(service: service, account: "envVars") else { return [:] }
        guard let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    /// Save env vars for a given MCP server ID (replaces existing).
    static func saveEnvVars(serverID: String, envVars: [String: String]) {
        let service = servicePrefix + serverID
        guard let data = try? JSONEncoder().encode(envVars) else { return }
        keychainWrite(service: service, account: "envVars", data: data)
    }

    /// Delete all env vars for a server.
    static func deleteEnvVars(serverID: String) {
        let service = servicePrefix + serverID
        keychainDelete(service: service, account: "envVars")
    }

    /// Get a single env var value.
    static func getValue(serverID: String, key: String) -> String? {
        loadEnvVars(serverID: serverID)[key]
    }

    /// Set a single env var value (merges with existing).
    static func setValue(serverID: String, key: String, value: String) {
        var vars = loadEnvVars(serverID: serverID)
        vars[key] = value
        saveEnvVars(serverID: serverID, envVars: vars)
    }

    /// Remove a single env var.
    static func removeValue(serverID: String, key: String) {
        var vars = loadEnvVars(serverID: serverID)
        vars.removeValue(forKey: key)
        saveEnvVars(serverID: serverID, envVars: vars)
    }

    /// Build a complete process environment by merging vault env vars with current process env.
    static func processEnvironment(for serverID: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let vaultVars = loadEnvVars(serverID: serverID)
        for (key, value) in vaultVars {
            env[key] = value
        }
        return env
    }

    /// Known env var hints for common MCP servers.
    static func envVarHints(for serverID: String) -> [(key: String, description: String)] {
        switch serverID {
        case "github":
            return [("GITHUB_PERSONAL_ACCESS_TOKEN", "GitHub personal access token with repo scope")]
        case "brave-search":
            return [("BRAVE_API_KEY", "Brave Search API key from search.brave.com")]
        case "slack":
            return [("SLACK_BOT_TOKEN", "Slack bot token (xoxb-...)"),
                    ("SLACK_TEAM_ID", "Slack workspace team ID")]
        case "postgres":
            return [("POSTGRES_CONNECTION_STRING", "PostgreSQL connection URI (postgres://user:pass@host:5432/db)")]
        case "gdrive":
            return [("GOOGLE_APPLICATION_CREDENTIALS", "Path to Google service account JSON")]
        case "sentry":
            return [("SENTRY_AUTH_TOKEN", "Sentry authentication token"),
                    ("SENTRY_ORG", "Sentry organization slug")]
        case "aws":
            return [("AWS_ACCESS_KEY_ID", "AWS access key ID"),
                    ("AWS_SECRET_ACCESS_KEY", "AWS secret access key"),
                    ("AWS_REGION", "AWS region (e.g. us-east-1)")]
        case "gcp":
            return [("GOOGLE_APPLICATION_CREDENTIALS", "Path to GCP service account JSON"),
                    ("GCP_PROJECT_ID", "Google Cloud project ID")]
        case "azure":
            return [("AZURE_SUBSCRIPTION_ID", "Azure subscription ID"),
                    ("AZURE_TENANT_ID", "Azure tenant ID"),
                    ("AZURE_CLIENT_ID", "Azure client/app ID"),
                    ("AZURE_CLIENT_SECRET", "Azure client secret")]
        case "stripe":
            return [("STRIPE_API_KEY", "Stripe secret API key (sk_...)")]
        case "shopify":
            return [("SHOPIFY_ACCESS_TOKEN", "Shopify Admin API access token"),
                    ("SHOPIFY_STORE_URL", "Shopify store URL (store.myshopify.com)")]
        case "hubspot":
            return [("HUBSPOT_ACCESS_TOKEN", "HubSpot private app access token")]
        case "discord":
            return [("DISCORD_BOT_TOKEN", "Discord bot token")]
        case "telegram":
            return [("TELEGRAM_BOT_TOKEN", "Telegram bot token from @BotFather")]
        case "twilio":
            return [("TWILIO_ACCOUNT_SID", "Twilio account SID"),
                    ("TWILIO_AUTH_TOKEN", "Twilio auth token")]
        case "datadog":
            return [("DD_API_KEY", "Datadog API key"),
                    ("DD_APP_KEY", "Datadog application key")]
        case "mongodb":
            return [("MONGODB_URI", "MongoDB connection URI")]
        case "redis":
            return [("REDIS_URL", "Redis connection URL (redis://...)")]
        case "elasticsearch":
            return [("ELASTICSEARCH_URL", "Elasticsearch endpoint URL"),
                    ("ELASTICSEARCH_API_KEY", "Elasticsearch API key")]
        case "bigquery":
            return [("GOOGLE_APPLICATION_CREDENTIALS", "Path to service account JSON"),
                    ("BIGQUERY_PROJECT_ID", "BigQuery project ID")]
        case "snowflake":
            return [("SNOWFLAKE_ACCOUNT", "Snowflake account identifier"),
                    ("SNOWFLAKE_USERNAME", "Snowflake username"),
                    ("SNOWFLAKE_PASSWORD", "Snowflake password")]
        case "airtable":
            return [("AIRTABLE_API_KEY", "Airtable personal access token")]
        case "linear":
            return [("LINEAR_API_KEY", "Linear API key")]
        case "notion":
            return [("NOTION_API_KEY", "Notion integration token")]
        case "jira":
            return [("JIRA_URL", "Jira instance URL"),
                    ("JIRA_EMAIL", "Jira account email"),
                    ("JIRA_API_TOKEN", "Jira API token")]
        case "figma":
            return [("FIGMA_ACCESS_TOKEN", "Figma personal access token")]
        case "vercel":
            return [("VERCEL_TOKEN", "Vercel personal access token")]
        case "supabase":
            return [("SUPABASE_URL", "Supabase project URL"),
                    ("SUPABASE_SERVICE_ROLE_KEY", "Supabase service role key")]
        case "cloudflare":
            return [("CLOUDFLARE_API_TOKEN", "Cloudflare API token"),
                    ("CLOUDFLARE_ACCOUNT_ID", "Cloudflare account ID")]
        case "todoist":
            return [("TODOIST_API_TOKEN", "Todoist API token")]
        case "zapier":
            return [("ZAPIER_NLA_API_KEY", "Zapier Natural Language Actions API key")]
        case "gitlab":
            return [("GITLAB_TOKEN", "GitLab personal access token"),
                    ("GITLAB_URL", "GitLab instance URL (default: gitlab.com)")]
        case "semgrep":
            return [("SEMGREP_APP_TOKEN", "Semgrep App token")]
        case "sourcegraph":
            return [("SRC_ACCESS_TOKEN", "Sourcegraph access token"),
                    ("SRC_ENDPOINT", "Sourcegraph instance URL")]
        case "terraform":
            return [("TFE_TOKEN", "Terraform Cloud/Enterprise API token")]
        case "intercom":
            return [("INTERCOM_ACCESS_TOKEN", "Intercom access token")]
        case "email":
            return [("IMAP_HOST", "IMAP server hostname"),
                    ("IMAP_PORT", "IMAP port (default: 993)"),
                    ("IMAP_USER", "IMAP username/email"),
                    ("IMAP_PASS", "IMAP password or app password")]
        case "asana":
            return [("ASANA_ACCESS_TOKEN", "Asana personal access token")]
        case "confluence":
            return [("CONFLUENCE_URL", "Confluence instance URL"),
                    ("CONFLUENCE_EMAIL", "Confluence account email"),
                    ("CONFLUENCE_API_TOKEN", "Confluence API token")]
        case "zendesk":
            return [("ZENDESK_SUBDOMAIN", "Zendesk subdomain"),
                    ("ZENDESK_EMAIL", "Zendesk agent email"),
                    ("ZENDESK_API_TOKEN", "Zendesk API token")]
        default:
            return []
        }
    }

    // MARK: - Keychain Helpers

    private static func keychainWrite(service: String, account: String, data: Data) {
        keychainDelete(service: service, account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func keychainRead(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func keychainDelete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
