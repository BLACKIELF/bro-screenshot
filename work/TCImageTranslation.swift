import AppKit
import SwiftUI
import Translation
import NaturalLanguage

private typealias ImageDone = @convention(c) (UnsafePointer<UInt8>?, Int, Int32) -> Void

@available(macOS 15.0, *)
@MainActor private final class ImageTranslationModel: ObservableObject {
    struct Group { let language: String; let units: [[String: Any]] }
    let original: Data
    var units: [[String: Any]]?
    var recognizing = false
    let done: ImageDone
    @Published var target = UserDefaults.standard.string(forKey: "ImageTranslationTarget") ?? "en"
    @Published var busy = false
    @Published var showOriginal = false
    @Published var translated: Data?
    @Published var message = "正在识别截图中的文字…"
    @Published var configuration: TranslationSession.Configuration?
    var groups: [Group] = []
    var groupIndex = 0
    var operationID = UUID()
    var translations: [String: String] = [:]
    var reusableConfiguration: TranslationSession.Configuration?
    var scheduledLanguagePair: String?
    var updateImage: ((Data) -> Void)?

    init(original: Data, units: [[String: Any]]?, done: @escaping ImageDone) {
        self.original = original; self.units = units; self.done = done
    }
    private func language(_ text: String) -> String {
        let recognizer = NLLanguageRecognizer(); recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? "auto"
    }
    private func sameLanguage(_ source: String) -> Bool {
        source == target || (source.hasPrefix("zh") && target.hasPrefix("zh"))
    }
    func start() {
        operationID = UUID(); configuration = nil; busy = true; translated = nil
        showOriginal = false; translations = [:]; groupIndex = 0; updateImage?(original)
        UserDefaults.standard.set(target, forKey: "ImageTranslationTarget")
        guard let units else {
            message = "正在本机识别截图文字… 可以取消或返回编辑。"
            guard !recognizing else { return }
            recognizing = true
            let image = original
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var error: NSError?
                let regions = TCImageTextRegions(image, &error) as? [[String: Any]]
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.recognizing = false; self.units = regions
                    guard self.busy else { return }
                    if regions != nil { self.start() }
                    else {
                        self.busy = false
                        self.message = error?.localizedDescription ?? "文字识别失败，可以重试。"
                    }
                }
            }
            return
        }
        var grouped: [String: [[String: Any]]] = [:]
        let fallback = language(units.compactMap { $0["text"] as? String }.joined(separator: "\n"))
        for unit in units {
            guard let text = unit["text"] as? String, let id = unit["id"] as? String else { continue }
            if text.rangeOfCharacter(from: .letters) == nil { translations[id] = text; continue }
            let detected = language(text)
            let source = detected == "auto" ? fallback : detected
            if sameLanguage(source) { translations[id] = text; continue }
            grouped[source, default: []].append(unit)
        }
        groups = grouped.keys.sorted().map { Group(language: $0, units: grouped[$0]!) }
        if units.isEmpty { busy = false; message = "未识别到文字，请返回编辑后重新框选。"; return }
        scheduleNext()
    }
    func cancel() {
        operationID = UUID(); configuration = nil; busy = false
        message = "已取消翻译，可以重新选择语言。"
    }
    func targetChanged() {
        cancel(); translated = nil; showOriginal = false; updateImage?(original)
        start()
    }
    func displayChanged() { updateImage?(showOriginal ? original : (translated ?? original)) }
    private func scheduleNext() {
        guard groupIndex < groups.count else { render(); return }
        let group = groups[groupIndex]
        message = "正在本机翻译 \(groupIndex + 1)/\(groups.count)… 首次语言包下载由系统确认。"
        let source = group.language == "auto" ? nil : Locale.Language(identifier: group.language)
        let pair = "\(group.language)->\(target)"
        if scheduledLanguagePair == pair, var next = reusableConfiguration {
            next.invalidate(); reusableConfiguration = next
        } else {
            reusableConfiguration = TranslationSession.Configuration(source: source, target: Locale.Language(identifier: target))
            scheduledLanguagePair = pair
        }
        configuration = reusableConfiguration
    }
    func translate(_ session: TranslationSession) async {
        guard busy, groupIndex < groups.count else { return }
        let token = operationID, index = groupIndex, group = groups[groupIndex]
        let requests = group.units.compactMap { unit -> TranslationSession.Request? in
            guard let text = unit["text"] as? String, let id = unit["id"] as? String else { return nil }
            return TranslationSession.Request(sourceText: text, clientIdentifier: id)
        }
        do {
            let responses = try await session.translations(from: requests)
            guard token == operationID, index == groupIndex, busy else { return }
            guard responses.count == requests.count else { throw CocoaError(.coderReadCorrupt) }
            let expected = Set(requests.compactMap(\.clientIdentifier))
            var received = Set<String>()
            for response in responses {
                guard let id = response.clientIdentifier, expected.contains(id),
                      received.insert(id).inserted, !response.targetText.isEmpty else {
                    throw CocoaError(.coderReadCorrupt)
                }
                translations[id] = response.targetText
            }
            groupIndex += 1; scheduleNext()
        } catch {
            guard token == operationID else { return }
            busy = false; configuration = nil; message = "翻译未完成：\(error.localizedDescription)"
            NSLog("image_translation_failed domain=%@ code=%ld", (error as NSError).domain, (error as NSError).code)
        }
    }
    private func render() {
        let token = operationID, image = original, boxes = units ?? [], text = translations
        configuration = nil; message = "正在将译文放回截图…"
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSError?
            let png = TCRenderImageTranslations(image, boxes, text, &error)
            DispatchQueue.main.async {
                guard token == self.operationID, self.busy else { return }
                self.busy = false
                if let png {
                    self.translated = png; self.showOriginal = false; self.updateImage?(png)
                    self.message = "译文已显示在原位置。可切换原图，复制或保存译图。"
                    NSLog("image_translation_completed regions=%ld", boxes.count)
                } else { self.message = error?.localizedDescription ?? "译图生成失败，请重试。" }
            }
        }
    }
    func finish(_ action: Int32) {
        let output = action == 0 ? nil : translated
        if action != 0 && output == nil { return }
        cancel(); dismissImageTranslation()
        if let output { output.withUnsafeBytes { done($0.bindMemory(to: UInt8.self).baseAddress, output.count, action) } }
        else { done(nil, 0, action) }
    }
}

@available(macOS 15.0, *)
private struct ImageTranslationToolbar: View {
    @ObservedObject var model: ImageTranslationModel
    let width: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker("译为", selection: $model.target) {
                    Text("英文").tag("en"); Text("简体中文").tag("zh-Hans")
                    Text("日文").tag("ja"); Text("韩文").tag("ko")
                }.frame(width: 145)
                Button(model.busy ? "翻译中…" : "翻译") { model.start() }.disabled(model.busy)
                if model.busy { Button("取消翻译") { model.cancel() } }
                Toggle("原图", isOn: $model.showOriginal).toggleStyle(.switch).disabled(model.translated == nil)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button("复制译图") { model.finish(1) }.disabled(model.busy || model.translated == nil)
                Button("保存译图") { model.finish(2) }.disabled(model.busy || model.translated == nil)
                Button("返回编辑") { model.finish(0) }
                Spacer(minLength: 0)
            }
            Text(model.message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
        }
        .padding(10).frame(width: width, height: 116, alignment: .leading)
        .background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear { model.start() }
        .onChange(of: model.target) { model.targetChanged() }
        .onChange(of: model.showOriginal) { model.displayChanged() }
        .translationTask(model.configuration) { session in await model.translate(session) }
    }
}

@MainActor private final class TranslationImagePanel: NSPanel {
    var escapeAction: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { escapeAction?() } else { super.keyDown(with: event) }
    }
}
@MainActor private var imagePanel: NSPanel?
@MainActor private var imageModel: AnyObject?
@MainActor private weak var imageOwner: NSWindow?
@MainActor private var ownerIgnoredMouse = false

@_cdecl("TCDismissImageTranslation")
@MainActor public func dismissImageTranslation() {
    if #available(macOS 15.0, *), let model = imageModel as? ImageTranslationModel { model.cancel() }
    if let panel = imagePanel { imageOwner?.removeChildWindow(panel); panel.close() }
    imageOwner?.ignoresMouseEvents = ownerIgnoredMouse
    imagePanel = nil; imageModel = nil; imageOwner = nil
}

@_cdecl("TCShowImageTranslation")
@MainActor public func showImageTranslation(_ dataPointer: UnsafeRawPointer, _ regionsPointer: UnsafeRawPointer?,
    _ ownerPointer: UnsafeRawPointer, _ x: Double, _ y: Double, _ width: Double, _ height: Double,
    _ done: @escaping @convention(c) (UnsafePointer<UInt8>?, Int, Int32) -> Void) {
    dismissImageTranslation()
    guard #available(macOS 15.0, *) else {
        let alert = NSAlert(); alert.messageText = "截图原位翻译需要 macOS 15 或更新版本。"; alert.runModal()
        done(nil, 0, 0); return
    }
    let data = Unmanaged<NSData>.fromOpaque(dataPointer).takeUnretainedValue() as Data
    let units = regionsPointer.flatMap { Unmanaged<NSArray>.fromOpaque($0).takeUnretainedValue() as? [[String: Any]] }
    let owner = Unmanaged<NSWindow>.fromOpaque(ownerPointer).takeUnretainedValue()
    guard let image = NSImage(data: data), width > 0, height > 0 else { done(nil, 0, 0); return }
    let model = ImageTranslationModel(original: data, units: units, done: done)
    let imageFrame = NSRect(x: x, y: y, width: width, height: height)
    let screen = (owner.screen ?? NSScreen.main!).visibleFrame
    var toolbarFrame = NSRect.zero
    let panelFrame = TCImageTranslationPanelFrame(imageFrame, screen, &toolbarFrame)
    let panel = TranslationImagePanel(contentRect: panelFrame,
        styleMask: [.borderless], backing: .buffered, defer: false)
    panel.title = "bro截图 · 原位翻译"; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
    panel.level = NSWindow.Level(rawValue: owner.level.rawValue + 1); panel.collectionBehavior = owner.collectionBehavior
    panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
    let content = NSView(frame: NSRect(origin: .zero, size: panelFrame.size))
    let view = NSImageView(frame: imageFrame.offsetBy(dx: -panelFrame.minX, dy: -panelFrame.minY))
    view.image = image; view.imageScaling = .scaleProportionallyUpOrDown; view.setAccessibilityLabel("截图原位译文")
    content.addSubview(view); panel.contentView = content
    model.updateImage = { [weak view] png in view?.image = NSImage(data: png) }
    let toolbar = NSHostingView(rootView: ImageTranslationToolbar(model: model, width: toolbarFrame.width))
    toolbar.frame = toolbarFrame.offsetBy(dx: -panelFrame.minX, dy: -panelFrame.minY)
    content.addSubview(toolbar)
    let returnToEditor = { @MainActor in model.finish(0) }
    panel.escapeAction = returnToEditor
    imageOwner = owner; ownerIgnoredMouse = owner.ignoresMouseEvents; owner.ignoresMouseEvents = true
    imagePanel = panel; imageModel = model
    owner.addChildWindow(panel, ordered: .above)
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil); panel.makeMain()
}
