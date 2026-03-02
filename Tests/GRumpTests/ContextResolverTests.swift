import XCTest
@testable import GRump

@MainActor
final class ContextResolverTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialState() {
        let resolver = ContextResolver()
        XCTAssertTrue(resolver.resolvedFiles.isEmpty)
        XCTAssertEqual(resolver.projectType, .unknown)
        XCTAssertFalse(resolver.isScanning)
    }

    // MARK: - Project Type Detection

    func testDetectsSwiftProject() async {
        let packageSwift = tempDir.appendingPathComponent("Package.swift")
        try! "// swift-tools-version:5.9".write(to: packageSwift, atomically: true, encoding: .utf8)

        let resolver = ContextResolver()
        await resolver.resolve(userMessage: "Hello", recentMessages: [], workingDirectory: tempDir.path)
        XCTAssertEqual(resolver.projectType, .swift)
    }

    func testDetectsNodeProject() async {
        let packageJson = tempDir.appendingPathComponent("package.json")
        try! "{}".write(to: packageJson, atomically: true, encoding: .utf8)

        let resolver = ContextResolver()
        await resolver.resolve(userMessage: "Hello", recentMessages: [], workingDirectory: tempDir.path)
        XCTAssertEqual(resolver.projectType, .node)
    }

    func testDetectsPythonProject() async {
        let requirements = tempDir.appendingPathComponent("requirements.txt")
        try! "flask".write(to: requirements, atomically: true, encoding: .utf8)

        let resolver = ContextResolver()
        await resolver.resolve(userMessage: "Hello", recentMessages: [], workingDirectory: tempDir.path)
        XCTAssertEqual(resolver.projectType, .python)
    }

    func testDetectsRustProject() async {
        let cargo = tempDir.appendingPathComponent("Cargo.toml")
        try! "[package]".write(to: cargo, atomically: true, encoding: .utf8)

        let resolver = ContextResolver()
        await resolver.resolve(userMessage: "Hello", recentMessages: [], workingDirectory: tempDir.path)
        XCTAssertEqual(resolver.projectType, .rust)
    }

    func testDetectsGoProject() async {
        let goMod = tempDir.appendingPathComponent("go.mod")
        try! "module example".write(to: goMod, atomically: true, encoding: .utf8)

        let resolver = ContextResolver()
        await resolver.resolve(userMessage: "Hello", recentMessages: [], workingDirectory: tempDir.path)
        XCTAssertEqual(resolver.projectType, .go)
    }

    // MARK: - File Reference Extraction

    func testResolvesBacktickedFilePaths() async {
        let testFile = tempDir.appendingPathComponent("src/main.swift")
        try! FileManager.default.createDirectory(at: tempDir.appendingPathComponent("src"), withIntermediateDirectories: true)
        try! "print(\"hi\")".write(to: testFile, atomically: true, encoding: .utf8)

        let resolver = ContextResolver()
        await resolver.resolve(
            userMessage: "Look at `src/main.swift` please",
            recentMessages: [],
            workingDirectory: tempDir.path
        )
        XCTAssertTrue(resolver.resolvedFiles.contains(where: { $0.relativePath == "src/main.swift" }))
    }

    func testResolvesToolCallFiles() async {
        let testFile = tempDir.appendingPathComponent("app.py")
        try! "print('hi')".write(to: testFile, atomically: true, encoding: .utf8)

        let toolCall = ToolCall(id: "tc1", name: "read_file", arguments: "{\"path\":\"\(testFile.path)\"}")
        let msg = Message(role: .assistant, content: "", toolCalls: [toolCall])

        let resolver = ContextResolver()
        await resolver.resolve(
            userMessage: "Check the file",
            recentMessages: [msg],
            workingDirectory: tempDir.path
        )
        XCTAssertTrue(resolver.resolvedFiles.contains(where: { $0.path == testFile.path }))
    }

    // MARK: - Empty Working Directory

    func testEmptyWorkingDirectoryNoOp() async {
        let resolver = ContextResolver()
        await resolver.resolve(userMessage: "Hello", recentMessages: [], workingDirectory: "")
        XCTAssertTrue(resolver.resolvedFiles.isEmpty)
    }

    // MARK: - Caps Results

    func testCapsResultsAtTen() async {
        // Create many files
        for i in 0..<15 {
            let f = tempDir.appendingPathComponent("file\(i).swift")
            try! "code".write(to: f, atomically: true, encoding: .utf8)
        }

        var mentions: [String] = []
        for i in 0..<15 {
            mentions.append("`file\(i).swift`")
        }
        let msg = mentions.joined(separator: " and ")

        let resolver = ContextResolver()
        await resolver.resolve(userMessage: msg, recentMessages: [], workingDirectory: tempDir.path)
        XCTAssertLessThanOrEqual(resolver.resolvedFiles.count, 10)
    }

    // MARK: - ResolvedFile Properties

    func testResolvedFileHasLanguage() async {
        let testFile = tempDir.appendingPathComponent("test.swift")
        try! "code".write(to: testFile, atomically: true, encoding: .utf8)

        let resolver = ContextResolver()
        await resolver.resolve(
            userMessage: "Check `test.swift`",
            recentMessages: [],
            workingDirectory: tempDir.path
        )
        let file = resolver.resolvedFiles.first(where: { $0.relativePath == "test.swift" })
        XCTAssertEqual(file?.language, "swift")
    }
}
