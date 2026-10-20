import Foundation
@testable import PetCore
import Testing

struct AttachmentTests {
    @Test func kindsByName() {
        #expect(Attachment.kind(forName: "App.swift") == .code)
        #expect(Attachment.kind(forName: "notes.MD") == .text)
        #expect(Attachment.kind(forName: "Makefile") == .text)
        #expect(Attachment.kind(forName: "report.pdf") == .pdf)
        #expect(Attachment.kind(forName: "shot.HEIC") == .image)
        #expect(Attachment.kind(forName: "archive.zip") == nil)
        #expect(Attachment.kind(forName: "Movie.mov") == nil)
    }

    @Test func binaryIsNotText() {
        #expect(Attachment.decodeText(Data("hello\nworld".utf8)) == "hello\nworld")
        #expect(Attachment.decodeText(Data([0x48, 0x00, 0x49])) == nil)
        #expect(Attachment.decodeText(Data([0xFF, 0xFE, 0xFD])) == nil)
    }

    @Test func longTextIsCutAtALineBreak() {
        let line = String(repeating: "x", count: 99) + "\n"
        let text = String(repeating: line, count: 3000)   // 300 000 characters
        let cut = Attachment.cut(text)
        #expect(cut.truncated)
        #expect(cut.text.count <= Attachment.maxText)
        #expect(cut.text.hasSuffix("x"))
        #expect(!Attachment.cut("short").truncated)
    }

    @Test func promptPutsFilesBeforeTheQuestion() {
        let files = [Attachment(name: "a\"b.txt", kind: .text, bytes: 3, text: "abc", truncated: true),
                     Attachment(name: "pic.png", kind: .image, bytes: 9, image: Data([1, 2]), mediaType: "image/png")]
        let prompt = Attachment.prompt(question: "What?", files: files)
        #expect(prompt == "<file name=\"a&quot;b.txt\" truncated=\"true\">\nabc\n</file>\n\n<image name=\"pic.png\"/>\n\nWhat?")
    }

    @Test func streamMessageCarriesTheImages() throws {
        let files = [Attachment(name: "pic.png", kind: .image, bytes: 9, image: Data([1, 2, 3]), mediaType: "image/png")]
        let data = Attachment.streamMessage(question: "What?", files: files)
        #expect(data.last == 0x0A)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["type"] as? String == "user")
        let content = try #require((json["message"] as? [String: Any])?["content"] as? [[String: Any]])
        #expect(content.count == 2)
        #expect(content[0]["type"] as? String == "text")
        let source = try #require(content[1]["source"] as? [String: Any])
        #expect(source["media_type"] as? String == "image/png")
        #expect(source["data"] as? String == Data([1, 2, 3]).base64EncodedString())
        #expect(files[0].needsStreamInput)
    }
}
