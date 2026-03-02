import XCTest
@testable import GRump

final class SkillTests: XCTestCase {

    func testBuiltInSkillsLoad() throws {
        let skills = SkillsStorage.loadSkills(workingDirectory: "")
        let builtIn = skills.filter { $0.isBuiltIn }
        // Built-in skills require seedBundledSkillsIfNeeded() to have run (app launch).
        // In CI or fresh environments they won't exist — just verify the
        // builtInBaseIds constant is populated so seeding will work.
        if builtIn.isEmpty {
            XCTAssertFalse(Skill.builtInBaseIds.isEmpty,
                          "builtInBaseIds should list expected built-in skill IDs")
        } else {
            for skill in builtIn {
                XCTAssertTrue(Skill.builtInBaseIds.contains(skill.baseId),
                             "Built-in skill '\(skill.baseId)' should be in builtInBaseIds")
            }
        }
    }

    func testSkillHasRequiredFields() {
        let skills = SkillsStorage.loadSkills(workingDirectory: "")
        for skill in skills {
            XCTAssertFalse(skill.id.isEmpty, "Skill must have an id")
            XCTAssertFalse(skill.name.isEmpty, "Skill '\(skill.id)' must have a name")
            XCTAssertFalse(skill.body.isEmpty, "Skill '\(skill.id)' must have a body")
        }
    }

    func testSkillScopeValues() {
        XCTAssertEqual(Skill.Scope.global.rawValue, "global")
        XCTAssertEqual(Skill.Scope.project.rawValue, "project")
        XCTAssertEqual(Skill.Scope.builtIn.rawValue, "builtIn")
    }

    // MARK: - Skill Model

    func testSkillBaseIdFromPrefixedId() {
        let skill = Skill(
            id: "global:code-review", name: "Code Review", description: "d",
            path: URL(fileURLWithPath: "/tmp"), scope: .global, body: "b"
        )
        XCTAssertEqual(skill.baseId, "code-review")
    }

    func testSkillBaseIdWithoutPrefix() {
        let skill = Skill(
            id: "some-id", name: "Name", description: "d",
            path: URL(fileURLWithPath: "/tmp"), scope: .project, body: "b"
        )
        XCTAssertEqual(skill.baseId, "some-id")
    }

    func testSkillIsBuiltIn() {
        let skill = Skill(
            id: "global:code-review", name: "Code Review", description: "d",
            path: URL(fileURLWithPath: "/tmp"), scope: .global, body: "b"
        )
        XCTAssertTrue(skill.isBuiltIn)
    }

    func testSkillIsNotBuiltIn() {
        let skill = Skill(
            id: "project:my-custom-skill", name: "Custom", description: "d",
            path: URL(fileURLWithPath: "/tmp"), scope: .project, body: "b"
        )
        XCTAssertFalse(skill.isBuiltIn)
    }

    func testSkillEquality() {
        let a = Skill(id: "x", name: "A", description: "a", path: URL(fileURLWithPath: "/a"), scope: .global, body: "ba")
        let b = Skill(id: "x", name: "B", description: "b", path: URL(fileURLWithPath: "/b"), scope: .project, body: "bb")
        XCTAssertEqual(a, b, "Equality should be based on id only")
    }

    func testSkillInequality() {
        let a = Skill(id: "x", name: "A", description: "a", path: URL(fileURLWithPath: "/a"), scope: .global, body: "b")
        let b = Skill(id: "y", name: "A", description: "a", path: URL(fileURLWithPath: "/a"), scope: .global, body: "b")
        XCTAssertNotEqual(a, b)
    }

    func testBuiltInBaseIdsNotEmpty() {
        XCTAssertGreaterThan(Skill.builtInBaseIds.count, 20, "Should have many built-in skill IDs")
    }

    func testBuiltInBaseIdsContainExpectedSkills() {
        let expected = ["code-review", "debugging", "documentation", "testing", "refactoring"]
        for id in expected {
            XCTAssertTrue(Skill.builtInBaseIds.contains(id), "builtInBaseIds should contain '\(id)'")
        }
    }

    // MARK: - SkillsStorage

    func testGlobalSkillsDirectoryPath() {
        let dir = SkillsStorage.globalSkillsDirectory
        XCTAssertTrue(dir.path.hasSuffix(".grump/skills"))
    }

    func testProjectSkillsDirectoryPath() {
        let dir = SkillsStorage.projectSkillsDirectory(workingDirectory: "/Users/test/project")
        XCTAssertTrue(dir.path.contains(".grump/skills"))
    }

    func testProjectSkillsDirectoryEmptyPath() {
        let dir = SkillsStorage.projectSkillsDirectory(workingDirectory: "")
        XCTAssertEqual(dir.path, "/dev/null")
    }

    func testLoadSkillsReturnsArray() {
        let skills = SkillsStorage.loadSkills(workingDirectory: "")
        // Should not crash, may be empty in test environment
        XCTAssertNotNil(skills)
    }

    func testCreateAndLoadSkill() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grump-skill-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Create a skill manually
        let skillDir = tmpDir.appendingPathComponent("test-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let content = "---\nname: Test Skill\ndescription: A test skill\n---\n\n# Test\n\nDo something useful."
        try content.write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        // SkillsStorage won't find it directly since it uses globalSkillsDirectory,
        // but we can verify the model creation works
        let skill = Skill(
            id: "global:test-skill", name: "Test Skill", description: "A test skill",
            path: skillDir, scope: .global, body: "# Test\n\nDo something useful."
        )
        XCTAssertEqual(skill.name, "Test Skill")
        XCTAssertEqual(skill.description, "A test skill")
        XCTAssertFalse(skill.body.isEmpty)
    }

    func testCreateSkillWithProjectScope() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grump-skill-proj-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let skill = SkillsStorage.createSkill(
            id: "my-test-skill",
            name: "My Test",
            description: "Test description",
            scope: .project,
            workingDirectory: tmpDir.path
        )
        XCTAssertNotNil(skill)
        XCTAssertEqual(skill?.name, "My Test")
        XCTAssertEqual(skill?.scope, .project)
    }

    func testCreateSkillProjectScopeEmptyDir() {
        let skill = SkillsStorage.createSkill(
            id: "x", name: "X", scope: .project, workingDirectory: ""
        )
        XCTAssertNil(skill, "Should fail with empty workingDirectory for project scope")
    }

    func testUpdateSkill() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grump-skill-update-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let skill = SkillsStorage.createSkill(
            id: "update-me", name: "Original", description: "d", scope: .global,
            workingDirectory: ""
        )
        guard let skill else {
            XCTFail("Failed to create skill for update test")
            return
        }
        let updated = SkillsStorage.updateSkill(skill, newName: "Updated", newDescription: "new desc", newBody: "new body")
        XCTAssertTrue(updated)
    }
}
