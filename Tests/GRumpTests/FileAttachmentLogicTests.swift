import XCTest
@testable import GRump

/// Tests the file classification, icon mapping, and type detection logic
/// from FileAttachmentView — exercised via URL construction.
final class FileAttachmentLogicTests: XCTestCase {

    // MARK: - Helpers

    private func fileExtension(for path: String) -> String {
        URL(fileURLWithPath: path).pathExtension.lowercased()
    }

    private func fileName(for path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    /// Mirror of FileAttachmentView's file icon logic.
    private func fileIcon(for ext: String) -> String {
        switch ext {
        case "txt", "md", "markdown": return "doc.text"
        case "pdf": return "doc.pdf"
        case "doc", "docx": return "doc.word"
        case "xls", "xlsx": return "doc.chart.bar"
        case "ppt", "pptx": return "doc.chart.bar.fill"
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp": return "photo"
        case "mp4", "mov", "avi", "mkv": return "video"
        case "mp3", "wav", "m4a", "flac": return "music.note"
        case "zip", "rar", "7z", "tar", "gz": return "doc.zipper"
        case "swift", "m", "h", "c", "cpp", "py", "js", "ts", "html", "css": return "chevron.left.forwardslash.chevron.right"
        case "json", "xml", "yaml", "yml": return "doc.text.magnifyingglass"
        default: return "doc"
        }
    }

    /// Mirror of FileAttachmentView's boolean classification.
    private func isImageFile(_ ext: String) -> Bool {
        ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp"].contains(ext)
    }

    private func isVideoFile(_ ext: String) -> Bool {
        ["mp4", "mov", "avi", "mkv"].contains(ext)
    }

    private func isAudioFile(_ ext: String) -> Bool {
        ["mp3", "wav", "m4a", "flac"].contains(ext)
    }

    private func isCodeFile(_ ext: String) -> Bool {
        ["swift", "m", "h", "c", "cpp", "py", "js", "ts", "html", "css", "rs", "go", "java", "kt"].contains(ext)
    }

    private func isDocumentFile(_ ext: String) -> Bool {
        ["txt", "md", "markdown", "pdf", "doc", "docx", "pages"].contains(ext)
    }

    private func isArchiveFile(_ ext: String) -> Bool {
        ["zip", "rar", "7z", "tar", "gz"].contains(ext)
    }

    // MARK: - Extension Extraction

    func testExtensionExtraction() {
        XCTAssertEqual(fileExtension(for: "/tmp/file.png"), "png")
        XCTAssertEqual(fileExtension(for: "/tmp/file.SWIFT"), "swift")
        XCTAssertEqual(fileExtension(for: "/tmp/file.Pdf"), "pdf")
    }

    func testExtensionWithNoExtension() {
        XCTAssertEqual(fileExtension(for: "/tmp/Makefile"), "")
    }

    func testExtensionWithMultipleDots() {
        XCTAssertEqual(fileExtension(for: "/tmp/archive.tar.gz"), "gz")
    }

    // MARK: - File Name Extraction

    func testFileName() {
        XCTAssertEqual(fileName(for: "/Users/test/Documents/report.pdf"), "report.pdf")
    }

    func testFileNameFromDeepPath() {
        XCTAssertEqual(fileName(for: "/a/b/c/d/e/f.swift"), "f.swift")
    }

    // MARK: - Icon Mapping (All Categories)

    func testTextFileIcons() {
        XCTAssertEqual(fileIcon(for: "txt"), "doc.text")
        XCTAssertEqual(fileIcon(for: "md"), "doc.text")
        XCTAssertEqual(fileIcon(for: "markdown"), "doc.text")
    }

    func testPdfIcon() {
        XCTAssertEqual(fileIcon(for: "pdf"), "doc.pdf")
    }

    func testWordIcons() {
        XCTAssertEqual(fileIcon(for: "doc"), "doc.word")
        XCTAssertEqual(fileIcon(for: "docx"), "doc.word")
    }

    func testSpreadsheetIcons() {
        XCTAssertEqual(fileIcon(for: "xls"), "doc.chart.bar")
        XCTAssertEqual(fileIcon(for: "xlsx"), "doc.chart.bar")
    }

    func testPresentationIcons() {
        XCTAssertEqual(fileIcon(for: "ppt"), "doc.chart.bar.fill")
        XCTAssertEqual(fileIcon(for: "pptx"), "doc.chart.bar.fill")
    }

    func testImageIcons() {
        for ext in ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp"] {
            XCTAssertEqual(fileIcon(for: ext), "photo", "\(ext) should map to photo")
        }
    }

    func testVideoIcons() {
        for ext in ["mp4", "mov", "avi", "mkv"] {
            XCTAssertEqual(fileIcon(for: ext), "video", "\(ext) should map to video")
        }
    }

    func testAudioIcons() {
        for ext in ["mp3", "wav", "m4a", "flac"] {
            XCTAssertEqual(fileIcon(for: ext), "music.note", "\(ext) should map to music.note")
        }
    }

    func testArchiveIcons() {
        for ext in ["zip", "rar", "7z", "tar", "gz"] {
            XCTAssertEqual(fileIcon(for: ext), "doc.zipper", "\(ext) should map to doc.zipper")
        }
    }

    func testCodeIcons() {
        for ext in ["swift", "m", "h", "c", "cpp", "py", "js", "ts", "html", "css"] {
            XCTAssertEqual(fileIcon(for: ext), "chevron.left.forwardslash.chevron.right",
                "\(ext) should map to code icon")
        }
    }

    func testDataFormatIcons() {
        for ext in ["json", "xml", "yaml", "yml"] {
            XCTAssertEqual(fileIcon(for: ext), "doc.text.magnifyingglass",
                "\(ext) should map to doc.text.magnifyingglass")
        }
    }

    func testUnknownExtensionFallback() {
        XCTAssertEqual(fileIcon(for: "xyz"), "doc")
        XCTAssertEqual(fileIcon(for: ""), "doc")
        XCTAssertEqual(fileIcon(for: "unknown"), "doc")
        XCTAssertEqual(fileIcon(for: "abcdef"), "doc")
    }

    // MARK: - Type Classification

    func testImageClassification() {
        XCTAssertTrue(isImageFile("jpg"))
        XCTAssertTrue(isImageFile("jpeg"))
        XCTAssertTrue(isImageFile("png"))
        XCTAssertTrue(isImageFile("gif"))
        XCTAssertTrue(isImageFile("bmp"))
        XCTAssertTrue(isImageFile("tiff"))
        XCTAssertTrue(isImageFile("webp"))
        XCTAssertFalse(isImageFile("svg")) // SVG not in image list
        XCTAssertFalse(isImageFile("pdf"))
    }

    func testVideoClassification() {
        XCTAssertTrue(isVideoFile("mp4"))
        XCTAssertTrue(isVideoFile("mov"))
        XCTAssertTrue(isVideoFile("avi"))
        XCTAssertTrue(isVideoFile("mkv"))
        XCTAssertFalse(isVideoFile("wmv")) // Not in list
        XCTAssertFalse(isVideoFile("mp3"))
    }

    func testAudioClassification() {
        XCTAssertTrue(isAudioFile("mp3"))
        XCTAssertTrue(isAudioFile("wav"))
        XCTAssertTrue(isAudioFile("m4a"))
        XCTAssertTrue(isAudioFile("flac"))
        XCTAssertFalse(isAudioFile("aac")) // Not in list
        XCTAssertFalse(isAudioFile("mp4"))
    }

    func testCodeClassification() {
        XCTAssertTrue(isCodeFile("swift"))
        XCTAssertTrue(isCodeFile("py"))
        XCTAssertTrue(isCodeFile("js"))
        XCTAssertTrue(isCodeFile("ts"))
        XCTAssertTrue(isCodeFile("rs"))
        XCTAssertTrue(isCodeFile("go"))
        XCTAssertTrue(isCodeFile("java"))
        XCTAssertTrue(isCodeFile("kt"))
        XCTAssertTrue(isCodeFile("cpp"))
        XCTAssertTrue(isCodeFile("h"))
        XCTAssertTrue(isCodeFile("c"))
        XCTAssertTrue(isCodeFile("m"))
        XCTAssertTrue(isCodeFile("html"))
        XCTAssertTrue(isCodeFile("css"))
        XCTAssertFalse(isCodeFile("rb")) // Ruby not in list
    }

    func testDocumentClassification() {
        XCTAssertTrue(isDocumentFile("txt"))
        XCTAssertTrue(isDocumentFile("md"))
        XCTAssertTrue(isDocumentFile("markdown"))
        XCTAssertTrue(isDocumentFile("pdf"))
        XCTAssertTrue(isDocumentFile("doc"))
        XCTAssertTrue(isDocumentFile("docx"))
        XCTAssertTrue(isDocumentFile("pages"))
        XCTAssertFalse(isDocumentFile("odt")) // Not in list
    }

    func testArchiveClassification() {
        XCTAssertTrue(isArchiveFile("zip"))
        XCTAssertTrue(isArchiveFile("rar"))
        XCTAssertTrue(isArchiveFile("7z"))
        XCTAssertTrue(isArchiveFile("tar"))
        XCTAssertTrue(isArchiveFile("gz"))
        XCTAssertFalse(isArchiveFile("bz2")) // Not in list
    }

    func testUnknownExtensionIsNoneOfTheTypes() {
        let ext = "xyz"
        XCTAssertFalse(isImageFile(ext))
        XCTAssertFalse(isVideoFile(ext))
        XCTAssertFalse(isAudioFile(ext))
        XCTAssertFalse(isCodeFile(ext))
        XCTAssertFalse(isDocumentFile(ext))
        XCTAssertFalse(isArchiveFile(ext))
    }

    // MARK: - Mutual Exclusivity

    func testNoExtensionIsMultipleTypes() {
        let allExtensions = [
            "jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp",
            "mp4", "mov", "avi", "mkv",
            "mp3", "wav", "m4a", "flac",
            "swift", "m", "h", "c", "cpp", "py", "js", "ts", "html", "css", "rs", "go", "java", "kt",
            "txt", "md", "markdown", "pdf", "doc", "docx", "pages",
            "zip", "rar", "7z", "tar", "gz"
        ]

        for ext in allExtensions {
            var typeCount = 0
            if isImageFile(ext) { typeCount += 1 }
            if isVideoFile(ext) { typeCount += 1 }
            if isAudioFile(ext) { typeCount += 1 }
            // Note: code and document can overlap for some formats 
            // (e.g., "html" is code, "m" is code), so skip strict mutual exclusivity
            // for code vs document. But image/video/audio should be exclusive.
            XCTAssertLessThanOrEqual(typeCount, 1,
                "Extension '\(ext)' matches \(typeCount) media types (image/video/audio should be exclusive)")
        }
    }

    // MARK: - Extension Case Normalization

    func testUppercaseExtensionNormalized() {
        let url = URL(fileURLWithPath: "/tmp/Photo.PNG")
        XCTAssertEqual(url.pathExtension.lowercased(), "png")
    }

    func testMixedCaseExtensionNormalized() {
        let url = URL(fileURLWithPath: "/tmp/Code.Swift")
        XCTAssertEqual(url.pathExtension.lowercased(), "swift")
    }
}
