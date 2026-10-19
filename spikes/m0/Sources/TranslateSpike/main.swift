// M0 spike: on-device Translation without SwiftUI, plus language detection.
import Foundation
import NaturalLanguage
import Translation

let text = CommandLine.arguments.dropFirst().joined(separator: " ").isEmpty
    ? "Пиксельный кубик живёт в чёлке и следит за агентами."
    : CommandLine.arguments.dropFirst().joined(separator: " ")

let recognizer = NLLanguageRecognizer()
recognizer.processString(text)
let detected = recognizer.dominantLanguage?.rawValue ?? "und"
let source = Locale.Language(identifier: detected)
let target = Locale.Language(identifier: detected == "ru" ? "en" : "ru")
print("detected=\(detected) target=\(target.minimalIdentifier)")

let availability = LanguageAvailability()
let status = await availability.status(from: source, to: target)
print("availability=\(status)")

do {
    let t0 = Date()
    let session = TranslationSession(installedSource: source, target: target)
    let response = try await session.translate(text)
    print(String(format: "translated in %.0f ms: %@", Date().timeIntervalSince(t0) * 1000, response.targetText))
} catch {
    print("translate error: \(error)")
}
