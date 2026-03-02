import XCTest
import SwiftUI
@testable import GRump

final class XcodeProjectParserTests: XCTestCase {

    // MARK: - XcodeTarget

    func testTargetCreation() {
        let target = XcodeTarget(
            id: "t1", name: "MyApp", type: .app,
            bundleId: "com.test.myapp", deploymentTarget: "17.0"
        )
        XCTAssertEqual(target.id, "t1")
        XCTAssertEqual(target.name, "MyApp")
        XCTAssertEqual(target.type, .app)
        XCTAssertEqual(target.bundleId, "com.test.myapp")
        XCTAssertEqual(target.deploymentTarget, "17.0")
    }

    func testTargetNilOptionals() {
        let target = XcodeTarget(
            id: "t2", name: "Lib", type: .staticLibrary,
            bundleId: nil, deploymentTarget: nil
        )
        XCTAssertNil(target.bundleId)
        XCTAssertNil(target.deploymentTarget)
    }

    func testTargetHashable() {
        let a = XcodeTarget(id: "a", name: "A", type: .app, bundleId: nil, deploymentTarget: nil)
        let b = XcodeTarget(id: "a", name: "A", type: .app, bundleId: nil, deploymentTarget: nil)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    // MARK: - TargetType

    func testAllTargetTypesHaveRawValues() {
        let types: [XcodeTarget.TargetType] = [
            .app, .framework, .staticLibrary, .unitTest, .uiTest,
            .appExtension, .watchApp, .widgetExtension, .unknown
        ]
        for type in types {
            XCTAssertFalse(type.rawValue.isEmpty, "\(type) missing rawValue")
        }
    }

    func testAllTargetTypesHaveIcons() {
        let types: [XcodeTarget.TargetType] = [
            .app, .framework, .staticLibrary, .unitTest, .uiTest,
            .appExtension, .watchApp, .widgetExtension, .unknown
        ]
        for type in types {
            XCTAssertFalse(type.icon.isEmpty, "\(type) missing icon")
        }
    }

    func testAllTargetTypesHaveColors() {
        let types: [XcodeTarget.TargetType] = [
            .app, .framework, .staticLibrary, .unitTest, .uiTest,
            .appExtension, .watchApp, .widgetExtension, .unknown
        ]
        for type in types {
            let color = type.color
            XCTAssertNotEqual(color.description, Color.clear.description,
                "\(type) color should not be clear")
        }
    }

    func testSpecificTargetTypeRawValues() {
        XCTAssertEqual(XcodeTarget.TargetType.app.rawValue, "Application")
        XCTAssertEqual(XcodeTarget.TargetType.framework.rawValue, "Framework")
        XCTAssertEqual(XcodeTarget.TargetType.unitTest.rawValue, "Unit Tests")
        XCTAssertEqual(XcodeTarget.TargetType.unknown.rawValue, "Unknown")
    }

    // MARK: - XcodeScheme

    func testSchemeCreation() {
        let scheme = XcodeScheme(id: "s1", name: "MyApp", isShared: true)
        XCTAssertEqual(scheme.id, "s1")
        XCTAssertEqual(scheme.name, "MyApp")
        XCTAssertTrue(scheme.isShared)
    }

    func testSchemeHashable() {
        let a = XcodeScheme(id: "s1", name: "A", isShared: true)
        let b = XcodeScheme(id: "s1", name: "A", isShared: true)
        XCTAssertEqual(a, b)
    }

    // MARK: - XcodeBuildConfig

    func testBuildConfigCreation() {
        let config = XcodeBuildConfig(id: "c1", name: "Debug")
        XCTAssertEqual(config.id, "c1")
        XCTAssertEqual(config.name, "Debug")
    }

    func testBuildConfigHashable() {
        let a = XcodeBuildConfig(id: "c1", name: "Debug")
        let b = XcodeBuildConfig(id: "c1", name: "Debug")
        XCTAssertEqual(a, b)
    }

    // MARK: - XcodeSigningInfo

    func testSigningInfoCreation() {
        let info = XcodeSigningInfo(
            teamId: "ABCD1234",
            signingStyle: "Automatic",
            provisioningProfile: "MyProfile",
            isValid: true
        )
        XCTAssertEqual(info.teamId, "ABCD1234")
        XCTAssertEqual(info.signingStyle, "Automatic")
        XCTAssertEqual(info.provisioningProfile, "MyProfile")
        XCTAssertTrue(info.isValid)
    }

    func testSigningInfoNilFields() {
        let info = XcodeSigningInfo(
            teamId: nil, signingStyle: "Manual",
            provisioningProfile: nil, isValid: false
        )
        XCTAssertNil(info.teamId)
        XCTAssertNil(info.provisioningProfile)
        XCTAssertFalse(info.isValid)
    }

    func testSigningInfoHasUUID() {
        let info = XcodeSigningInfo(
            teamId: nil, signingStyle: "Automatic",
            provisioningProfile: nil, isValid: true
        )
        XCTAssertNotNil(info.id)
    }
}
