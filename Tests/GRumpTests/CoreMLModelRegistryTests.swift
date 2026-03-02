import XCTest
@testable import GRump

final class CoreMLModelRegistryTests: XCTestCase {

    // MARK: - CoreMLModelCatalogEntry

    func testCatalogEntryCreation() {
        let entry = CoreMLModelCatalogEntry(
            id: "test-model",
            name: "Test Model",
            description: "A test model",
            repoID: "test/model",
            filename: "test.mlpackage",
            sizeBytes: 1_000_000_000,
            quantization: "FP16",
            parameterCount: "1B",
            contextLength: 4096,
            category: .apple
        )
        XCTAssertEqual(entry.id, "test-model")
        XCTAssertEqual(entry.name, "Test Model")
        XCTAssertEqual(entry.description, "A test model")
        XCTAssertEqual(entry.repoID, "test/model")
        XCTAssertEqual(entry.filename, "test.mlpackage")
        XCTAssertEqual(entry.sizeBytes, 1_000_000_000)
        XCTAssertEqual(entry.quantization, "FP16")
        XCTAssertEqual(entry.parameterCount, "1B")
        XCTAssertEqual(entry.contextLength, 4096)
        XCTAssertEqual(entry.category, .apple)
    }

    func testCatalogEntrySizeFormatted() {
        let entry = CoreMLModelCatalogEntry(
            id: "t", name: "T", description: "D", repoID: "r",
            filename: "f", sizeBytes: 1_073_741_824,
            quantization: "FP16", parameterCount: "1B",
            contextLength: 2048, category: .apple
        )
        let formatted = entry.sizeFormatted
        XCTAssertFalse(formatted.isEmpty)
        // 1 GB should format to something containing "GB" or "1"
        XCTAssertTrue(formatted.contains("G") || formatted.contains("1"))
    }

    func testCatalogEntryRecommendedRAM() {
        let smallEntry = CoreMLModelCatalogEntry(
            id: "s", name: "S", description: "D", repoID: "r",
            filename: "f", sizeBytes: 270_000_000,
            quantization: "FP16", parameterCount: "270M",
            contextLength: 2048, category: .apple
        )
        XCTAssertGreaterThan(smallEntry.recommendedRAMGB, 0)

        let largeEntry = CoreMLModelCatalogEntry(
            id: "l", name: "L", description: "D", repoID: "r",
            filename: "f", sizeBytes: 1_800_000_000,
            quantization: "FP16", parameterCount: "3B",
            contextLength: 2048, category: .apple
        )
        XCTAssertGreaterThan(largeEntry.recommendedRAMGB, smallEntry.recommendedRAMGB)
    }

    func testCatalogEntryEquatable() {
        let a = CoreMLModelCatalogEntry(
            id: "test", name: "T", description: "D", repoID: "r",
            filename: "f", sizeBytes: 100,
            quantization: "FP16", parameterCount: "1B",
            contextLength: 2048, category: .apple
        )
        let b = CoreMLModelCatalogEntry(
            id: "test", name: "T", description: "D", repoID: "r",
            filename: "f", sizeBytes: 100,
            quantization: "FP16", parameterCount: "1B",
            contextLength: 2048, category: .apple
        )
        XCTAssertEqual(a, b)
    }

    // MARK: - Category

    func testCategoryAllCases() {
        let cases = CoreMLModelCatalogEntry.Category.allCases
        XCTAssertFalse(cases.isEmpty)
        XCTAssertTrue(cases.contains(.apple))
    }

    func testCategoryRawValue() {
        XCTAssertEqual(CoreMLModelCatalogEntry.Category.apple.rawValue, "Apple")
    }

    // MARK: - Catalog

    func testCatalogNotEmpty() {
        let catalog = CoreMLModelRegistryService.catalog
        XCTAssertFalse(catalog.isEmpty, "Catalog should have at least one model")
    }

    func testCatalogEntriesHaveUniqueIds() {
        let catalog = CoreMLModelRegistryService.catalog
        let ids = catalog.map(\.id)
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count, "Catalog IDs should be unique")
    }

    func testCatalogEntriesHaveValidFields() {
        for entry in CoreMLModelRegistryService.catalog {
            XCTAssertFalse(entry.name.isEmpty, "\(entry.id) missing name")
            XCTAssertFalse(entry.description.isEmpty, "\(entry.id) missing description")
            XCTAssertFalse(entry.repoID.isEmpty, "\(entry.id) missing repoID")
            XCTAssertFalse(entry.filename.isEmpty, "\(entry.id) missing filename")
            XCTAssertGreaterThan(entry.sizeBytes, 0, "\(entry.id) has zero size")
            XCTAssertGreaterThan(entry.contextLength, 0, "\(entry.id) has zero context length")
            XCTAssertFalse(entry.quantization.isEmpty, "\(entry.id) missing quantization")
            XCTAssertFalse(entry.parameterCount.isEmpty, "\(entry.id) missing parameterCount")
        }
    }

    func testCatalogEntriesSizeFormattedNotEmpty() {
        for entry in CoreMLModelRegistryService.catalog {
            XCTAssertFalse(entry.sizeFormatted.isEmpty, "\(entry.id) sizeFormatted is empty")
        }
    }

    // MARK: - CoreMLDownloadState

    func testDownloadStateNotDownloaded() {
        let state = CoreMLDownloadState.notDownloaded
        XCTAssertFalse(state.isDownloading)
    }

    func testDownloadStateDownloading() {
        let state = CoreMLDownloadState.downloading(progress: 0.5, bytesReceived: 500, totalBytes: 1000)
        XCTAssertTrue(state.isDownloading)
    }

    func testDownloadStatePaused() {
        let state = CoreMLDownloadState.paused(bytesReceived: 500, totalBytes: 1000)
        XCTAssertFalse(state.isDownloading)
    }

    func testDownloadStateDownloaded() {
        let state = CoreMLDownloadState.downloaded
        XCTAssertFalse(state.isDownloading)
    }

    func testDownloadStateError() {
        let state = CoreMLDownloadState.error("Network timeout")
        XCTAssertFalse(state.isDownloading)
    }

    func testDownloadStateEquatable() {
        XCTAssertEqual(CoreMLDownloadState.notDownloaded, CoreMLDownloadState.notDownloaded)
        XCTAssertEqual(CoreMLDownloadState.downloaded, CoreMLDownloadState.downloaded)
        XCTAssertNotEqual(CoreMLDownloadState.notDownloaded, CoreMLDownloadState.downloaded)
        XCTAssertEqual(
            CoreMLDownloadState.downloading(progress: 0.5, bytesReceived: 500, totalBytes: 1000),
            CoreMLDownloadState.downloading(progress: 0.5, bytesReceived: 500, totalBytes: 1000)
        )
        XCTAssertNotEqual(
            CoreMLDownloadState.downloading(progress: 0.5, bytesReceived: 500, totalBytes: 1000),
            CoreMLDownloadState.downloading(progress: 0.8, bytesReceived: 800, totalBytes: 1000)
        )
    }
}
