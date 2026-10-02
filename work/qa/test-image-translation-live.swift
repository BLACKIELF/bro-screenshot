import Foundation
import Translation
import NaturalLanguage

// Uses already-installed Apple language models; never requests downloads or
// starts NSApplication, a screenshot worker, window, hotkey or login service.
@main struct ImageTranslationIntegrationTest {
    static func main() async {
        do { try await run() }
        catch {
            let failure = error as NSError
            fputs("FAIL image translation integration domain=\(failure.domain) code=\(failure.code): \(failure.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    static func run() async throws {
        guard #available(macOS 26.0, *) else { fatalError("Live test requires macOS 26+; product supports macOS 15+ through SwiftUI consent.") }
        guard (2...3).contains(CommandLine.arguments.count) else { fatalError("Pass the synthetic fixture folder and optional --render-only.") }
        let renderOnly = CommandLine.arguments.count == 3 && CommandLine.arguments[2] == "--render-only"
        if CommandLine.arguments.count == 3 && !renderOnly { fatalError("Unknown test option") }
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let original = try Data(contentsOf: folder.appendingPathComponent("inline-before.png"))
        var error: NSError?
        guard let boxes = TCImageTextRegions(original, &error) as? [[String: Any]], boxes.count >= 3 else {
            throw error ?? CocoaError(.coderReadCorrupt)
        }
        for target in ["en", "zh-Hans"] {
            var grouped: [String: [[String: Any]]] = [:]
            var translations: [String: String] = [:]
            for box in boxes {
                let text = box["text"] as! String, id = box["id"] as! String
                let recognizer = NLLanguageRecognizer(); recognizer.processString(text)
                let source = recognizer.dominantLanguage?.rawValue ?? "zh-Hans"
                if source == target || (source.hasPrefix("zh") && target.hasPrefix("zh")) {
                    translations[id] = text
                } else { grouped[source, default: []].append(box) }
            }
            for language in grouped.keys.sorted() {
                let units = grouped[language]!
                let session = TranslationSession(installedSource: Locale.Language(identifier: language),
                                                 target: Locale.Language(identifier: target))
                guard await session.isReady else { fatalError("Required models are not installed; no download requested.") }
                let requests = units.map { TranslationSession.Request(sourceText: $0["text"] as! String, clientIdentifier: $0["id"] as? String) }
                let result = try await session.translations(from: requests)
                precondition(result.count == requests.count)
                let expected = Set(requests.compactMap(\.clientIdentifier))
                var received = Set<String>()
                for response in result {
                    guard let id = response.clientIdentifier else { fatalError("Missing text-region identifier") }
                    precondition(expected.contains(id) && received.insert(id).inserted)
                    precondition(!response.targetText.isEmpty)
                    translations[id] = response.targetText
                }
            }
            guard let png = TCRenderImageTranslations(original, boxes, translations, &error) else {
                throw error ?? CocoaError(.coderReadCorrupt)
            }
            try png.write(to: folder.appendingPathComponent("inline-actual-\(target).png"), options: .atomic)
            print("PASS installed Apple batch translation and PNG rendering -> \(target), \(boxes.count) regions.")
            fflush(stdout)
            // On this macOS 27 host, a second Vision request in the same process
            // can fail with e5rtError 13. This explicit mode tests the production
            // one-OCR flow; verify each resulting PNG separately with the probe.
            if renderOnly { continue }
            guard let output = TCImageTextRegions(png, &error) as? [[String: Any]] else {
                fputs("FAIL rendered-image Vision roundtrip -> \(target)\n", stderr)
                throw error ?? CocoaError(.coderReadCorrupt)
            }
            let sourceStrings = boxes.compactMap { $0["text"] as? String }
            let resultStrings = output.compactMap { $0["text"] as? String }
            precondition(!resultStrings.isEmpty && resultStrings != sourceStrings)
            let resultText = resultStrings.joined(separator: " ")
            if target == "en" {
                precondition(resultText.contains("Hello") && !resultText.contains("截图完成"))
            } else {
                precondition(resultText.contains("截图完成") && !resultText.contains("Hello"))
            }
            print("PASS installed Apple batch translation -> \(target), \(boxes.count) OCR regions, rendered PNG recognizes target text and preserves same-language text.")
        }
    }
}
