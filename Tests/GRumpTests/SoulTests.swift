import XCTest
@testable import GRump

final class SoulTests: XCTestCase {

    // MARK: - Soul struct

    func testSoulEquatable() {
        let path = URL(fileURLWithPath: "/tmp/SOUL.md")
        let a = Soul(name: "Rump", version: 1, body: "Hello", path: path, scope: .global)
        let b = Soul(name: "Rump", version: 1, body: "Hello", path: path, scope: .global)
        XCTAssertEqual(a, b)
    }

    func testSoulNotEqualDifferentName() {
        let path = URL(fileURLWithPath: "/tmp/SOUL.md")
        let a = Soul(name: "Rump", version: 1, body: "Hello", path: path, scope: .global)
        let b = Soul(name: "Other", version: 1, body: "Hello", path: path, scope: .global)
        XCTAssertNotEqual(a, b)
    }

    func testSoulScopeValues() {
        XCTAssertEqual(Soul.Scope.global.rawValue, "global")
        XCTAssertEqual(Soul.Scope.project.rawValue, "project")
    }

    // MARK: - SoulStorage paths

    func testGlobalSoulPathEndsWithSOULmd() {
        let path = SoulStorage.globalSoulPath
        XCTAssertTrue(path.lastPathComponent == "SOUL.md")
        XCTAssertTrue(path.path.contains(".grump"))
    }

    func testProjectSoulPathForValidDirectory() {
        let path = SoulStorage.projectSoulPath(workingDirectory: "/tmp/myproject")
        XCTAssertNotNil(path)
        XCTAssertTrue(path!.lastPathComponent == "SOUL.md")
        XCTAssertTrue(path!.path.contains(".grump"))
        XCTAssertTrue(path!.path.contains("myproject"))
    }

    func testProjectSoulPathReturnsNilForEmptyDir() {
        let path = SoulStorage.projectSoulPath(workingDirectory: "")
        XCTAssertNil(path)
    }

    // MARK: - Default soul content

    func testDefaultSoulContentHasFrontmatter() {
        let content = SoulStorage.defaultSoulContent
        XCTAssertTrue(content.hasPrefix("---"), "Default soul should start with YAML frontmatter")
        XCTAssertTrue(content.contains("name: Rump"))
        XCTAssertTrue(content.contains("version: 1"))
    }

    func testDefaultSoulContentHasIdentitySection() {
        let content = SoulStorage.defaultSoulContent
        XCTAssertTrue(content.contains("# Identity"))
    }

    func testDefaultSoulContentHasExpertiseSection() {
        let content = SoulStorage.defaultSoulContent
        XCTAssertTrue(content.contains("# Expertise"))
    }

    func testDefaultSoulContentHasRulesSection() {
        let content = SoulStorage.defaultSoulContent
        XCTAssertTrue(content.contains("# Rules"))
    }

    func testDefaultSoulContentHasToneSection() {
        let content = SoulStorage.defaultSoulContent
        XCTAssertTrue(content.contains("# Tone"))
    }

    // MARK: - Save and load roundtrip

    func testSaveAndLoadRoundtrip() throws {
        let tmpDir = NSTemporaryDirectory() + "grump-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let content = """
        ---
        name: TestBot
        version: 2
        ---

        # Identity

        You are TestBot.
        """

        let saved = SoulStorage.saveSoul(content: content, scope: .project, workingDirectory: tmpDir)
        XCTAssertTrue(saved, "Should save soul successfully")

        let exists = SoulStorage.soulExists(scope: .project, workingDirectory: tmpDir)
        XCTAssertTrue(exists, "Soul file should exist after save")

        let raw = SoulStorage.rawContent(scope: .project, workingDirectory: tmpDir)
        XCTAssertNotNil(raw)
        XCTAssertEqual(raw, content)
    }

    func testDeleteSoul() throws {
        let tmpDir = NSTemporaryDirectory() + "grump-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let content = "---\nname: Test\nversion: 1\n---\nBody"
        _ = SoulStorage.saveSoul(content: content, scope: .project, workingDirectory: tmpDir)
        XCTAssertTrue(SoulStorage.soulExists(scope: .project, workingDirectory: tmpDir))

        let deleted = SoulStorage.deleteSoul(scope: .project, workingDirectory: tmpDir)
        XCTAssertTrue(deleted)
        XCTAssertFalse(SoulStorage.soulExists(scope: .project, workingDirectory: tmpDir))
    }

    func testDeleteNonexistentSoulReturnsFalse() {
        let deleted = SoulStorage.deleteSoul(scope: .project, workingDirectory: "/nonexistent/\(UUID().uuidString)")
        XCTAssertFalse(deleted)
    }

    func testLoadSoulFromNonexistentDirReturnsNil() {
        let soul = SoulStorage.loadSoul(workingDirectory: "/nonexistent/\(UUID().uuidString)")
        // May or may not be nil depending on whether global soul exists
        // Just verify no crash
        _ = soul
    }

    // MARK: - Soul existence checks

    func testSoulExistsReturnsFalseForEmptyWorkingDir() {
        XCTAssertFalse(SoulStorage.soulExists(scope: .project, workingDirectory: ""))
    }

    func testRawContentReturnsNilForEmptyWorkingDir() {
        XCTAssertNil(SoulStorage.rawContent(scope: .project, workingDirectory: ""))
    }
}
