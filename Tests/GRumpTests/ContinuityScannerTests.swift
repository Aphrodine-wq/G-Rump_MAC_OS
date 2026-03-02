import XCTest
@testable import GRump

final class ContinuityScannerTests: XCTestCase {

    // MARK: - ScannerState

    func testScannerStateIdle() {
        let state = ScannerState.idle
        if case .idle = state {
            // pass
        } else {
            XCTFail("Expected .idle")
        }
    }

    func testScannerStateScanning() {
        let state = ScannerState.scanning
        if case .scanning = state {
            // pass
        } else {
            XCTFail("Expected .scanning")
        }
    }

    func testScannerStateProcessing() {
        let state = ScannerState.processing
        if case .processing = state {
            // pass
        } else {
            XCTFail("Expected .processing")
        }
    }

    func testScannerStateCompleted() {
        let state = ScannerState.completed
        if case .completed = state {
            // pass
        } else {
            XCTFail("Expected .completed")
        }
    }

    func testScannerStateError() {
        let state = ScannerState.error("Something went wrong")
        if case .error(let msg) = state {
            XCTAssertEqual(msg, "Something went wrong")
        } else {
            XCTFail("Expected .error")
        }
    }

    // MARK: - ScannerError

    func testScannerErrorNotAvailable() {
        let error = ScannerError.notAvailable
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.lowercased().contains("not available") ?? false)
    }

    func testScannerErrorCameraNotFound() {
        let error = ScannerError.cameraNotFound
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.lowercased().contains("camera") ?? false)
    }

    func testScannerErrorScanningFailed() {
        let underlying = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "test failure"])
        let error = ScannerError.scanningFailed(underlying)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("test failure") ?? false)
    }

    func testScannerErrorOCRFailed() {
        let underlying = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "ocr issue"])
        let error = ScannerError.ocrFailed(underlying)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.lowercased().contains("recognition") ?? false)
    }

    func testScannerErrorNoTextFound() {
        let error = ScannerError.noTextFound
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.lowercased().contains("no text") ?? false)
    }

    func testAllScannerErrorsHaveDescriptions() {
        let errors: [ScannerError] = [
            .notAvailable,
            .cameraNotFound,
            .scanningFailed(NSError(domain: "", code: 0)),
            .ocrFailed(NSError(domain: "", code: 0)),
            .noTextFound,
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        }
    }

    // MARK: - Diagram.DiagramType

    func testDiagramTypes() {
        let types: [Diagram.DiagramType] = [.flowchart, .uml, .wireframe, .mindMap, .unknown]
        XCTAssertEqual(types.count, 5)
    }

    func testDiagramCreation() {
        let diagram = Diagram(
            type: .flowchart,
            boundingBox: CGRect(x: 0, y: 0, width: 100, height: 100),
            confidence: 0.95
        )
        XCTAssertEqual(diagram.confidence, 0.95, accuracy: 0.001)
        XCTAssertEqual(diagram.boundingBox.width, 100)
    }

    // MARK: - CodeBlock

    func testCodeBlockCreation() {
        let block = CodeBlock(
            text: "func main() {}",
            language: "swift",
            range: NSRange(location: 0, length: 14)
        )
        XCTAssertEqual(block.text, "func main() {}")
        XCTAssertEqual(block.language, "swift")
        XCTAssertEqual(block.range.length, 14)
    }

    // MARK: - ProcessedDocument

    func testProcessedDocumentCreation() {
        let doc = ProcessedDocument(
            text: "Hello world",
            confidence: 0.92,
            codeBlocks: [],
            diagrams: [],
            timestamp: Date()
        )
        XCTAssertEqual(doc.text, "Hello world")
        XCTAssertEqual(doc.confidence, 0.92, accuracy: 0.001)
        XCTAssertTrue(doc.codeBlocks.isEmpty)
        XCTAssertTrue(doc.diagrams.isEmpty)
    }

    func testProcessedDocumentWithCodeBlocks() {
        let blocks = [
            CodeBlock(text: "let x = 1", language: "swift", range: NSRange(location: 0, length: 9)),
            CodeBlock(text: "def f(): pass", language: "python", range: NSRange(location: 20, length: 13)),
        ]
        let doc = ProcessedDocument(
            text: "let x = 1\n\ndef f(): pass",
            confidence: 0.88,
            codeBlocks: blocks,
            diagrams: [],
            timestamp: Date()
        )
        XCTAssertEqual(doc.codeBlocks.count, 2)
        XCTAssertEqual(doc.codeBlocks[0].language, "swift")
        XCTAssertEqual(doc.codeBlocks[1].language, "python")
    }

    // MARK: - Notification Name

    func testDocumentScannedNotificationName() {
        XCTAssertEqual(Notification.Name.documentScanned.rawValue, "DocumentScanned")
    }
}
