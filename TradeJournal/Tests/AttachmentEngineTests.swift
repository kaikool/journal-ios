import XCTest
@testable import TradeJournal

final class AttachmentEngineTests: XCTestCase {
    
    // MARK: - 1. Magic Bytes Sniffing (1:1 port từ attachment-validation.ts)
    
    func testMagicBytesMimeDetection() {
        // PNG magic bytes
        let pngBytes: [UInt8] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00]
        XCTAssertEqual(AttachmentEngine.attachmentMime(data: Data(pngBytes)), "image/png")
        
        // JPEG magic bytes
        let jpegBytes: [UInt8] = [0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46]
        XCTAssertEqual(AttachmentEngine.attachmentMime(data: Data(jpegBytes)), "image/jpeg")
        
        // WEBP magic bytes (RIFF....WEBP)
        var webpBytes: [UInt8] = [0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00]
        webpBytes.append(contentsOf: [0x57, 0x45, 0x42, 0x50, 0x56, 0x50, 0x38])
        XCTAssertEqual(AttachmentEngine.attachmentMime(data: Data(webpBytes)), "image/webp")
        
        // PDF magic bytes (%PDF-)
        let pdfBytes: [UInt8] = [0x25, 0x50, 0x44, 0x2d, 0x31, 0x2e, 0x37]
        XCTAssertEqual(AttachmentEngine.attachmentMime(data: Data(pdfBytes)), "application/pdf")
        
        // Unallowlisted bytes (e.g. GIF, text, exe)
        let gifBytes: [UInt8] = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]
        XCTAssertNil(AttachmentEngine.attachmentMime(data: Data(gifBytes)))
        
        let emptyBytes = Data()
        XCTAssertNil(AttachmentEngine.attachmentMime(data: emptyBytes))
    }
    
    // MARK: - 2. Max Size Boundary Check
    
    func testAttachmentSizeLimit() {
        let maxAllowed = AttachmentEngine.maxAttachmentSize // 8 MB
        XCTAssertEqual(maxAllowed, 8 * 1024 * 1024)
        
        // File 8MB + 1 byte
        let oversizedData = Data(count: maxAllowed + 1)
        XCTAssertThrowsError(
            try AttachmentEngine.validateAttachment(data: oversizedData, declaredName: "test.png")
        ) { error in
            guard let attErr = error as? AttachmentError else {
                XCTFail("Expected AttachmentError")
                return
            }
            if case .fileTooLarge(let size, let max) = attErr {
                XCTAssertEqual(size, maxAllowed + 1)
                XCTAssertEqual(max, maxAllowed)
            } else {
                XCTFail("Expected fileTooLarge error")
            }
        }
    }
    
    // MARK: - 3. Safe Name Sanitizer
    
    func testSafeNameSanitization() {
        XCTAssertEqual(AttachmentEngine.safeName("chart.png"), "chart.png")
        XCTAssertEqual(AttachmentEngine.safeName("path/to/my screenshot (1).png"), "my screenshot _1_.png")
        XCTAssertEqual(AttachmentEngine.safeName("   trade   #456  .jpeg  "), "trade _456 .jpeg")
        XCTAssertEqual(AttachmentEngine.safeName(""), "attachment")
        XCTAssertEqual(AttachmentEngine.safeName("   "), "attachment")
    }
    
    // MARK: - 4. Storage Path
    
    func testStoragePathFormat() {
        let path = AttachmentEngine.storagePath(
            ownerType: "trade",
            ownerId: "acc-1:ES:2026-10-16",
            id: "att-xyz",
            name: "chart-ES.png"
        )
        XCTAssertEqual(
            path,
            "attachments/trade/acc-1%3AES%3A2026-10-16/att-xyz/chart-ES.png"
        )
    }
    
    // MARK: - 5. Chart Screenshot PNG Validator (1:1 port từ chart-screenshot-upload.test.ts)
    
    func testValidateChartScreenshotPng() throws {
        // 1x1 Transparent PNG in base64
        let validDataUrl = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let data = try AttachmentEngine.validateChartScreenshotPng(dataUrl: validDataUrl)
        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(AttachmentEngine.attachmentMime(data: data), "image/png")
        
        // Non-PNG prefix (JPEG)
        let jpegDataUrl = "data:image/jpeg;base64,abc123"
        XCTAssertThrowsError(
            try AttachmentEngine.validateChartScreenshotPng(dataUrl: jpegDataUrl)
        ) { error in
            XCTAssertEqual(error as? AttachmentError, AttachmentError.notPng)
        }
        
        // Invalid base64
        let malformedDataUrl = "data:image/png;base64,NOT_BASE_64!!!"
        XCTAssertThrowsError(
            try AttachmentEngine.validateChartScreenshotPng(dataUrl: malformedDataUrl)
        ) { error in
            XCTAssertEqual(error as? AttachmentError, AttachmentError.invalidData)
        }
        
        // Valid Base64 but NOT a PNG magic byte header
        let fakePngDataUrl = "data:image/png;base64,SGVsbG8gV29ybGQ=" // "Hello World"
        XCTAssertThrowsError(
            try AttachmentEngine.validateChartScreenshotPng(dataUrl: fakePngDataUrl)
        ) { error in
            XCTAssertEqual(error as? AttachmentError, AttachmentError.invalidData)
        }
    }
    
    // MARK: - 6. Attachment CRUD in TradeDataStore
    
    @MainActor
    func testAttachmentStoreOperations() async throws {
        let store = TradeDataStore(loadFromDisk: false)
        
        // Sample PNG bytes
        let pngBytes: [UInt8] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x01, 0x02, 0x03]
        let sampleData = Data(pngBytes)
        
        let att = try store.addAttachment(
            ownerType: "trade",
            ownerId: "trade-test-1",
            name: "setup.png",
            data: sampleData
        )
        
        XCTAssertEqual(att.ownerType, "trade")
        XCTAssertEqual(att.ownerId, "trade-test-1")
        XCTAssertEqual(att.mime, "image/png")
        XCTAssertEqual(att.size, sampleData.count)
        
        let found = store.attachmentsFor(ownerType: "trade", ownerId: "trade-test-1")
        XCTAssertTrue(found.contains(where: { $0.id == att.id }))
        
        let loadedData = store.attachmentFileData(storagePath: att.storagePath)
        XCTAssertEqual(loadedData, sampleData)
        
        // Delete attachment
        try store.deleteAttachment(id: att.id)
        let remaining = store.attachmentsFor(ownerType: "trade", ownerId: "trade-test-1")
        XCTAssertFalse(remaining.contains(where: { $0.id == att.id }))
    }
}
