import AppKit
import SwiftUI
import Translation

// Use the public property-wrapper type, avoiding the newer SDK's same-named
// compiler macro. This needs no compiler plugin process to build.
private typealias ViewState<Value> = SwiftUI.State<Value>

@available(macOS 15.0, *)
private struct RecognizedTextView: View {
    @ViewState var source: String
    @ViewState private var target = "en"
    @ViewState private var translated = ""
    @ViewState private var message = ""
    @ViewState private var busy = false
    @ViewState private var configuration: TranslationSession.Configuration?
    @ViewState private var submittedText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("提取文字").font(.headline)
            TextEditor(text: $source).font(.body).frame(minHeight: 140)
                .disabled(busy)
            HStack {
                Button("复制原文") { copy(source) }.disabled(source.isEmpty)
                Spacer()
                Picker("译为", selection: $target) {
                    Text("英文").tag("en")
                    Text("简体中文").tag("zh-Hans")
                    Text("日文").tag("ja")
                    Text("韩文").tag("ko")
                }.frame(width: 180).disabled(busy)
                Button(busy ? "翻译中…" : "本机翻译") {
                    submittedText = source
                    translated = ""
                    message = "等待系统翻译；如需语言包，请在系统提示中确认或取消。"
                    busy = true
                    let next = TranslationSession.Configuration(source: nil, target: Locale.Language(identifier: target))
                    if configuration == next { configuration?.invalidate() }
                    else { configuration = next }
                }.disabled(busy || source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(message).font(.callout).foregroundStyle(.secondary)
            if !translated.isEmpty {
                Text("译文").font(.headline)
                ScrollView { Text(translated).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(minHeight: 100)
                Button("复制译文") { copy(translated) }
            }
            Text("使用 macOS 本机翻译。首次使用可能需要您确认下载语言包。译文显示在此窗口，不覆盖截图中的文字。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(minWidth: 560, minHeight: 380)
        .translationTask(configuration) { session in
            NSLog("translation_started chars=%ld target=%@", submittedText.count, target)
            do {
                // translate supplies the text needed to detect the source language
                // and presents the normal system language-download consent if needed.
                let response = try await session.translate(submittedText)
                translated = response.targetText
                message = "翻译完成；点击“复制译文”后才会替换剪贴板。"
                NSLog("translation_completed chars=%ld", response.targetText.count)
            } catch {
                let failure = error as NSError
                NSLog("translation_failed domain=%@ code=%ld", failure.domain, failure.code)
                message = "翻译未完成：\(error.localizedDescription)"
            }
            busy = false
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

@MainActor private var resultWindow: NSWindowController?
@MainActor private final class ResultWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        resultWindow = nil
    }
}
@MainActor private let resultWindowDelegate = ResultWindowDelegate()

@_cdecl("TCShowRecognizedText")
@MainActor public func showRecognizedText(_ utf8Text: UnsafePointer<CChar>?) {
    guard let utf8Text else { return }
    let text = String(cString: utf8Text)
    guard !text.isEmpty else { return }
    if #available(macOS 15.0, *) {
        // Close any previous result and its task before displaying a new result.
        resultWindow?.close()
        let controller = NSHostingController(rootView: RecognizedTextView(source: text))
        let window = NSWindow(contentViewController: controller)
        window.title = "提取文字与本机翻译"
        window.delegate = resultWindowDelegate
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 640, height: 480))
        window.center()
        resultWindow = NSWindowController(window: window)
        resultWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    } else {
        let alert = NSAlert()
        alert.messageText = "文字已复制；本机翻译需要 macOS 15 或更新版本"
        alert.informativeText = "此版本不提供其他翻译服务。"
        alert.runModal()
    }
}
