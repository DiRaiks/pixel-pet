import AppKit
import Foundation
import ImageIO
import PDFKit
import PetCore
import UniformTypeIdentifiers

/// Reads a dropped file into an `Attachment` on the Mac: text as is, a PDF's text through PDFKit (a scan with
/// no text sends its first pages as pictures), images scaled down with ImageIO. Nil for what can't be sent.
public enum AttachmentLoader {
    public enum Refusal: Error, Equatable, Sendable { case folder, unsupported, tooLarge, unreadable, empty }

    public static func load(_ url: URL) -> Result<Attachment, Refusal> {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { return .failure(.unreadable) }
        if isFolder.boolValue { return .failure(.folder) }
        let name = url.lastPathComponent
        guard let kind = Attachment.kind(forName: name) else { return .failure(.unsupported) }
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard bytes <= Attachment.maxFileBytes else { return .failure(.tooLarge) }
        switch kind {
        case .text, .code:
            guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable) }
            // No extension and not text (a binary tool): refuse, as for any other binary.
            guard let text = Attachment.decodeText(data) else { return .failure(.unsupported) }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.empty) }
            let cut = Attachment.cut(text)
            return .success(Attachment(name: name, kind: kind, bytes: bytes, text: cut.text, truncated: cut.truncated))
        case .pdf:
            guard let pdf = PDFDocument(url: url) else { return .failure(.unreadable) }
            let text = pdf.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty {
                let cut = Attachment.cut(text)
                return .success(Attachment(name: name, kind: .pdf, bytes: bytes, pages: pdf.pageCount, text: cut.text,
                                           truncated: cut.truncated))
            }
            // A scan: the first page as a picture (more pages would be more attachments; one keeps it simple).
            guard let page = pdf.page(at: 0), let image = render(page) else { return .failure(.empty) }
            return .success(Attachment(name: name, kind: .pdf, bytes: bytes, pages: pdf.pageCount,
                                       truncated: pdf.pageCount > 1, image: image, mediaType: "image/png"))
        case .image:
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = scaled(source) else {
                return .failure(.unreadable)
            }
            return .success(Attachment(name: name, kind: .image, bytes: bytes, image: image.data, mediaType: image.type))
        }
    }

    /// At most `Attachment.imageSide` on the longer side; PNG for pictures with transparency or few colors, JPEG
    /// for photos.
    static func scaled(_ source: CGImageSource) -> (data: Data, type: String)? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Attachment.imageSide,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let sourceType = CGImageSourceGetType(source).map { $0 as String } ?? ""
        let photo = sourceType == UTType.jpeg.identifier || sourceType == UTType.heic.identifier
        return encode(image, as: photo ? .jpeg : .png)
    }

    static func render(_ page: PDFPage) -> Data? {
        let bounds = page.bounds(for: .mediaBox)
        let scale = CGFloat(Attachment.imageSide) / max(bounds.width, bounds.height, 1)
        let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
        let thumb = page.thumbnail(of: size, for: .mediaBox)
        guard let image = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return encode(image, as: .png)?.data
    }

    private static func encode(_ image: CGImage, as type: UTType) -> (data: Data, type: String)? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        let props: [CFString: Any] = type == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.85] : [:]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return (data as Data, type == .jpeg ? "image/jpeg" : "image/png")
    }
}
