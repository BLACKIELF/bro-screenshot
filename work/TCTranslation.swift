import AppKit
import SwiftUI
import Translation

// Use the public property-wrapper type, avoiding the newer SDK's same-named
// compiler macro. This needs no compiler plugin process to build.
private typealias ViewState<Value> = SwiftUI.State<Value>

@available(macOS 15.0, *)
private struct RecognizedTextView: View {
    @ViewState var source: String
    let sourceTitle: String
    @ViewState private var target = "en"
    @ViewState private var translated = ""
    @ViewState private var message = ""
    @ViewState private var busy = false
    @ViewState private var configuration: TranslationSession.Configuration?
    @ViewState private var submittedText = ""
    @ViewState private var operationID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(sourceTitle).font(.headline)
            TextEditor(text: $source).font(.body).frame(minHeight: 140)
                .disabled(busy)
            HStack {
                Button(sourceTitle == "提取文字" ? "复制原文" : "复制内容") { copy(source) }.disabled(source.isEmpty)
                Spacer()
                Picker("译为", selection: $target) {
                    Text("英文").tag("en")
                    Text("简体中文").tag("zh-Hans")
                    Text("日文").tag("ja")
                    Text("韩文").tag("ko")
                }.frame(width: 180).disabled(busy)
                Button(busy ? "翻译中…" : "本机翻译") {
                    operationID = UUID()
                    submittedText = source
                    translated = ""
                    message = "等待系统翻译；如需语言包，请在系统提示中确认或取消。"
                    busy = true
                    let next = TranslationSession.Configuration(source: nil, target: Locale.Language(identifier: target))
                    if configuration == next { configuration?.invalidate() }
                    else { configuration = next }
                }.disabled(busy || source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if busy {
                    Button("取消") {
                        operationID = UUID()
                        configuration = nil
                        busy = false
                        message = "已取消翻译，可以修改原文或重试。"
                    }
                }
            }
            Text(message).font(.callout).foregroundStyle(.secondary)
            if !translated.isEmpty {
                Text("译文").font(.headline)
                ScrollView { Text(translated).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(minHeight: 100)
                Button("复制译文") { copy(translated) }
            }
            Text(sourceTitle == "提取文字" ? "使用 macOS 本机翻译。首次使用可能需要您确认下载语言包。译文显示在此窗口，不覆盖截图中的文字。" : "二维码/条码只显示文字，不会自动打开链接；点击复制后才会替换剪贴板。本机翻译的语言包由系统确认。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(minWidth: 560, minHeight: 380)
        .onChange(of: source) { if !busy { translated = ""; message = "" } }
        .onChange(of: target) { if !busy { translated = ""; message = "" } }
        .translationTask(configuration) { session in
            let requestID = operationID
            let input = submittedText
            NSLog("translation_started chars=%ld target=%@", submittedText.count, target)
            do {
                // translate supplies the text needed to detect the source language
                // and presents the normal system language-download consent if needed.
                let response = try await session.translate(input)
                guard requestID == operationID else { return }
                translated = response.targetText
                message = "翻译完成；点击“复制译文”后才会替换剪贴板。"
                NSLog("translation_completed chars=%ld", response.targetText.count)
            } catch {
                guard requestID == operationID else { return }
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

@MainActor private final class AppKitTextResult: NSView {
    var textView: NSTextView?
    @objc func copyContent(_ sender: NSButton) {
        guard let text = textView?.string, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

@_cdecl("TCShowRecognizedText")
@MainActor public func showRecognizedText(_ utf8Text: UnsafePointer<CChar>?) {
    showTextResult(utf8Text, nil)
}

@_cdecl("TCShowTextResult")
@MainActor public func showTextResult(_ utf8Text: UnsafePointer<CChar>?, _ utf8Title: UnsafePointer<CChar>?) {
    guard let utf8Text else { return }
    let text = String(cString: utf8Text)
    let title = utf8Title.map { String(cString: $0) } ?? "提取文字"
    guard !text.isEmpty else { return }
    resultWindow?.close()
    if #available(macOS 15.0, *) {
        // Close any previous result and its task before displaying a new result.
        let controller = NSHostingController(rootView: RecognizedTextView(source: text, sourceTitle: title))
        let window = NSWindow(contentViewController: controller)
        window.title = title == "提取文字" ? "提取文字与本机翻译" : title
        window.delegate = resultWindowDelegate
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 640, height: 480))
        window.center()
        resultWindow = NSWindowController(window: window)
        resultWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    } else {
        let content = AppKitTextResult(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 90, width: 600, height: 310))
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        let editor = NSTextView(frame: scroll.bounds)
        editor.isRichText = false
        editor.string = text
        editor.font = .systemFont(ofSize: 14)
        editor.autoresizingMask = [.width]
        scroll.documentView = editor
        content.textView = editor
        content.addSubview(scroll)
        let copy = NSButton(title: "复制内容", target: content, action: #selector(AppKitTextResult.copyContent(_:)))
        copy.frame = NSRect(x: 20, y: 45, width: 110, height: 32)
        content.addSubview(copy)
        let note = NSTextField(wrappingLabelWithString: "点击复制后才替换剪贴板。本机翻译需要 macOS 15 或更新版本。")
        note.frame = NSRect(x: 20, y: 12, width: 600, height: 26)
        note.autoresizingMask = [.width]
        content.addSubview(note)
        let window = NSWindow(contentRect: content.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.contentView = content
        window.delegate = resultWindowDelegate
        window.center()
        resultWindow = NSWindowController(window: window)
        resultWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
