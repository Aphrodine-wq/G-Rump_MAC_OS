import XCTest
@testable import GRump

final class SkillTests: XCTestCase {

    func testBuiltInSkillsLoad() {
        let skills = SkillsStorage.loadSkills(workingDirectory: "")
        let builtIn = skills.filter { $0.isBuiltIn }
        XCTAssertFalse(builtIn.isEmpty, "Should have built-in skills bundled")
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
}
