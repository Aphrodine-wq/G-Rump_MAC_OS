import XCTest
@testable import GRump

#if os(macOS)

final class ExecApprovalsTests: XCTestCase {

    // MARK: - ExecSecurityLevel

    func testSecurityLevelAllCases() {
        let cases = ExecSecurityLevel.allCases
        XCTAssertEqual(cases.count, 4)
        XCTAssertTrue(cases.contains(.deny))
        XCTAssertTrue(cases.contains(.ask))
        XCTAssertTrue(cases.contains(.allowlist))
        XCTAssertTrue(cases.contains(.allow))
    }

    func testSecurityLevelRawValues() {
        XCTAssertEqual(ExecSecurityLevel.deny.rawValue, "deny")
        XCTAssertEqual(ExecSecurityLevel.ask.rawValue, "ask")
        XCTAssertEqual(ExecSecurityLevel.allowlist.rawValue, "allowlist")
        XCTAssertEqual(ExecSecurityLevel.allow.rawValue, "allow")
    }

    func testSecurityLevelCodable() throws {
        for level in ExecSecurityLevel.allCases {
            let data = try JSONEncoder().encode(level)
            let decoded = try JSONDecoder().decode(ExecSecurityLevel.self, from: data)
            XCTAssertEqual(decoded, level)
        }
    }

    // MARK: - ExecAllowlistEntry

    func testAllowlistEntryIdMatchesPattern() {
        let entry = ExecAllowlistEntry(pattern: "/usr/bin/swift", source: "user")
        XCTAssertEqual(entry.id, "/usr/bin/swift")
        XCTAssertEqual(entry.source, "user")
    }

    func testAllowlistEntryCodable() throws {
        let entry = ExecAllowlistEntry(pattern: "/opt/homebrew/bin/*", source: "always-allow")
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ExecAllowlistEntry.self, from: data)
        XCTAssertEqual(decoded.pattern, entry.pattern)
        XCTAssertEqual(decoded.source, entry.source)
    }

    // MARK: - ExecApprovalsConfig

    func testDefaultConfig() {
        let config = ExecApprovalsConfig.default
        XCTAssertEqual(config.version, ExecApprovalsConfig.currentVersion)
        XCTAssertEqual(config.security, .deny)
        XCTAssertTrue(config.askOnMiss)
        XCTAssertTrue(config.allowlist.isEmpty)
    }

    func testConfigCodableRoundTrip() throws {
        var config = ExecApprovalsConfig.default
        config.security = .allowlist
        config.askOnMiss = false
        config.allowlist = [
            ExecAllowlistEntry(pattern: "/usr/bin/swift", source: "user"),
            ExecAllowlistEntry(pattern: "/opt/homebrew/bin/*", source: "always-allow"),
        ]

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ExecApprovalsConfig.self, from: data)
        XCTAssertEqual(decoded.security, .allowlist)
        XCTAssertFalse(decoded.askOnMiss)
        XCTAssertEqual(decoded.allowlist.count, 2)
        XCTAssertEqual(decoded.allowlist[0].pattern, "/usr/bin/swift")
    }

    // MARK: - Path Matching

    func testExactPathMatch() {
        XCTAssertTrue(ExecApprovalsStorage.path("/usr/bin/swift", matchesPattern: "/usr/bin/swift"))
    }

    func testExactPathNoMatch() {
        XCTAssertFalse(ExecApprovalsStorage.path("/usr/bin/swift", matchesPattern: "/usr/bin/python"))
    }

    func testGlobWildcardAtEnd() {
        XCTAssertTrue(ExecApprovalsStorage.path("/opt/homebrew/bin/swift", matchesPattern: "/opt/homebrew/bin/*"))
    }

    func testGlobWildcardNoMatch() {
        XCTAssertFalse(ExecApprovalsStorage.path("/usr/bin/swift", matchesPattern: "/opt/homebrew/bin/*"))
    }

    func testGlobWildcardInMiddle() {
        XCTAssertTrue(ExecApprovalsStorage.path("/usr/local/bin/swift", matchesPattern: "/usr/*/bin/swift"))
    }

    func testEmptyPattern() {
        XCTAssertFalse(ExecApprovalsStorage.path("/usr/bin/swift", matchesPattern: ""))
    }

    func testEmptyPath() {
        XCTAssertFalse(ExecApprovalsStorage.path("", matchesPattern: "/usr/bin/swift"))
    }

    func testIdenticalPaths() {
        let path = "/Applications/Xcode.app/Contents/Developer/usr/bin/swift"
        XCTAssertTrue(ExecApprovalsStorage.path(path, matchesPattern: path))
    }

    func testDoubleWildcard() {
        // Pattern like /usr/* should match anything under /usr/
        XCTAssertTrue(ExecApprovalsStorage.path("/usr/bin/swift", matchesPattern: "/usr/*"))
    }

    // MARK: - Storage Load/Save

    func testStorageFileURL() {
        let url = ExecApprovalsStorage.fileURL
        XCTAssertTrue(url.path.contains("GRump"))
        XCTAssertTrue(url.path.hasSuffix("exec-approvals.json"))
    }

    func testStorageLoadReturnsDefaultWhenNoFile() {
        // If file doesn't exist, should return default config
        let config = ExecApprovalsStorage.load()
        XCTAssertEqual(config.version, ExecApprovalsConfig.currentVersion)
        // Note: in test environment, the actual file may or may not exist
    }
}

#endif
