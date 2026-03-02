import XCTest
@testable import GRump

final class MCPCredentialVaultTests: XCTestCase {

    // MARK: - envVarHints

    func testGitHubHints() {
        let hints = MCPCredentialVault.envVarHints(for: "github")
        XCTAssertFalse(hints.isEmpty)
        XCTAssertTrue(hints.contains(where: { $0.key == "GITHUB_PERSONAL_ACCESS_TOKEN" }))
    }

    func testBraveSearchHints() {
        let hints = MCPCredentialVault.envVarHints(for: "brave-search")
        XCTAssertFalse(hints.isEmpty)
        XCTAssertTrue(hints.contains(where: { $0.key == "BRAVE_API_KEY" }))
    }

    func testSlackHints() {
        let hints = MCPCredentialVault.envVarHints(for: "slack")
        XCTAssertEqual(hints.count, 2)
        XCTAssertTrue(hints.contains(where: { $0.key == "SLACK_BOT_TOKEN" }))
        XCTAssertTrue(hints.contains(where: { $0.key == "SLACK_TEAM_ID" }))
    }

    func testPostgresHints() {
        let hints = MCPCredentialVault.envVarHints(for: "postgres")
        XCTAssertFalse(hints.isEmpty)
        XCTAssertTrue(hints.contains(where: { $0.key == "POSTGRES_CONNECTION_STRING" }))
    }

    func testAWSHints() {
        let hints = MCPCredentialVault.envVarHints(for: "aws")
        XCTAssertEqual(hints.count, 3)
        let keys = hints.map(\.key)
        XCTAssertTrue(keys.contains("AWS_ACCESS_KEY_ID"))
        XCTAssertTrue(keys.contains("AWS_SECRET_ACCESS_KEY"))
        XCTAssertTrue(keys.contains("AWS_REGION"))
    }

    func testAzureHints() {
        let hints = MCPCredentialVault.envVarHints(for: "azure")
        XCTAssertEqual(hints.count, 4)
    }

    func testUnknownServerReturnsEmptyHints() {
        let hints = MCPCredentialVault.envVarHints(for: "totally-unknown-server")
        XCTAssertTrue(hints.isEmpty)
    }

    func testAllKnownServersHaveDescriptions() {
        let knownServers = [
            "github", "brave-search", "slack", "postgres", "gdrive",
            "sentry", "aws", "gcp", "azure", "stripe", "shopify",
            "hubspot", "discord", "telegram", "twilio", "datadog",
            "mongodb", "redis", "elasticsearch", "bigquery", "snowflake",
            "airtable", "linear", "notion", "jira", "figma", "vercel",
            "supabase", "cloudflare", "todoist", "zapier", "gitlab",
            "semgrep", "sourcegraph", "terraform", "intercom", "email",
            "asana", "confluence", "zendesk",
        ]
        for server in knownServers {
            let hints = MCPCredentialVault.envVarHints(for: server)
            XCTAssertFalse(hints.isEmpty, "Server '\(server)' should have env var hints")
            for hint in hints {
                XCTAssertFalse(hint.key.isEmpty, "Hint key for '\(server)' should not be empty")
                XCTAssertFalse(hint.description.isEmpty, "Hint description for '\(server)'/'\(hint.key)' should not be empty")
            }
        }
    }

    // MARK: - processEnvironment

    func testProcessEnvironmentIncludesSystemEnv() {
        let env = MCPCredentialVault.processEnvironment(for: "nonexistent-server-\(UUID().uuidString)")
        // Should at least contain PATH from system env
        XCTAssertNotNil(env["PATH"], "Should include system PATH")
    }

    // MARK: - Keychain roundtrip (save/load/delete)

    func testSaveAndLoadEnvVars() {
        let testID = "test-vault-\(UUID().uuidString)"
        let vars = ["API_KEY": "sk-test-123", "SECRET": "mysecret"]

        MCPCredentialVault.saveEnvVars(serverID: testID, envVars: vars)
        let loaded = MCPCredentialVault.loadEnvVars(serverID: testID)
        XCTAssertEqual(loaded["API_KEY"], "sk-test-123")
        XCTAssertEqual(loaded["SECRET"], "mysecret")

        // Clean up
        MCPCredentialVault.deleteEnvVars(serverID: testID)
    }

    func testDeleteEnvVars() {
        let testID = "test-vault-delete-\(UUID().uuidString)"
        MCPCredentialVault.saveEnvVars(serverID: testID, envVars: ["KEY": "val"])
        MCPCredentialVault.deleteEnvVars(serverID: testID)
        let loaded = MCPCredentialVault.loadEnvVars(serverID: testID)
        XCTAssertTrue(loaded.isEmpty)
    }

    func testGetValue() {
        let testID = "test-vault-get-\(UUID().uuidString)"
        MCPCredentialVault.saveEnvVars(serverID: testID, envVars: ["TOKEN": "abc123"])
        XCTAssertEqual(MCPCredentialVault.getValue(serverID: testID, key: "TOKEN"), "abc123")
        XCTAssertNil(MCPCredentialVault.getValue(serverID: testID, key: "NONEXISTENT"))

        // Clean up
        MCPCredentialVault.deleteEnvVars(serverID: testID)
    }

    func testSetValueMerges() {
        let testID = "test-vault-set-\(UUID().uuidString)"
        MCPCredentialVault.saveEnvVars(serverID: testID, envVars: ["A": "1"])
        MCPCredentialVault.setValue(serverID: testID, key: "B", value: "2")
        let loaded = MCPCredentialVault.loadEnvVars(serverID: testID)
        XCTAssertEqual(loaded["A"], "1")
        XCTAssertEqual(loaded["B"], "2")

        // Clean up
        MCPCredentialVault.deleteEnvVars(serverID: testID)
    }

    func testRemoveValue() {
        let testID = "test-vault-remove-\(UUID().uuidString)"
        MCPCredentialVault.saveEnvVars(serverID: testID, envVars: ["X": "1", "Y": "2"])
        MCPCredentialVault.removeValue(serverID: testID, key: "X")
        let loaded = MCPCredentialVault.loadEnvVars(serverID: testID)
        XCTAssertNil(loaded["X"])
        XCTAssertEqual(loaded["Y"], "2")

        // Clean up
        MCPCredentialVault.deleteEnvVars(serverID: testID)
    }

    func testLoadEnvVarsNonexistentServer() {
        let loaded = MCPCredentialVault.loadEnvVars(serverID: "nonexistent-\(UUID().uuidString)")
        XCTAssertTrue(loaded.isEmpty)
    }
}
