import AppKit
import CoreText
import Foundation
@testable import PetCore
@testable import PetIntegrations
import Testing

struct AttachmentLoaderTests {
    let dir: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pixelpet-attach-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    func file(_ name: String, _ data: Data) -> URL {
        let url = dir.appendingPathComponent(name)
        try? data.write(to: url)
        return url
    }

    @Test func textCodeAndRefusals() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let code = try AttachmentLoader.load(file("main.swift", Data("print(1)\n".utf8))).get()
        #expect(code.kind == .code && code.text == "print(1)\n" && code.bytes == 9)
        #expect(AttachmentLoader.load(file("tool", Data([0x7F, 0x45, 0x00, 0x00]))) == .failure(.unsupported))
        #expect(AttachmentLoader.load(file("empty.txt", Data("  \n".utf8))) == .failure(.empty))
        #expect(AttachmentLoader.load(file("a.zip", Data([1]))) == .failure(.unsupported))
        #expect(AttachmentLoader.load(dir) == .failure(.folder))
        #expect(AttachmentLoader.load(dir.appendingPathComponent("missing.txt")) == .failure(.unreadable))
    }

    @Test func bigImagesAreScaledDown() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3000, pixelsHigh: 1000, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let image = try AttachmentLoader.load(file("wide.png", png)).get()
        #expect(image.kind == .image && image.mediaType == "image/png")
        let data = try #require(image.image)
        let back = try #require(NSBitmapImageRep(data: data))
        #expect(back.pixelsWide == Attachment.imageSide)
        #expect(back.pixelsHigh == 523)
    }

    @Test func pdfTextIsRead() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("doc.pdf")
        var box = CGRect(x: 0, y: 0, width: 300, height: 200)
        let ctx = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        for page in 1...2 {
            ctx.beginPDFPage(nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Hello page \(page)",
                                                                           attributes: [.font: NSFont.systemFont(ofSize: 14)]))
            ctx.textPosition = CGPoint(x: 20, y: 100)
            CTLineDraw(line, ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        let pdf = try AttachmentLoader.load(url).get()
        #expect(pdf.kind == .pdf && pdf.pages == 2)
        #expect(pdf.text?.contains("Hello page 1") == true)
        #expect(pdf.text?.contains("Hello page 2") == true)
        #expect(pdf.image == nil)
    }
}
