#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <ServiceManagement/ServiceManagement.h>
#import "TCWorker.h"
#import "TCSession.h"
#import "TCHotkeyGate.h"
#import "TCTranslation.h"
#import "TCLifecycleAgent.h"

static NSString *const AppName = @"bro截图";

@interface TCPinnedPanel : NSPanel
@end
@implementation TCPinnedPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 53) [self close];
    else [super keyDown:event];
}
@end

@interface TCPinnedImageView : NSImageView
@end
@implementation TCPinnedImageView
- (BOOL)acceptsFirstResponder { return YES; }
- (void)mouseDown:(NSEvent *)event {
    if (event.clickCount >= 2) { [self.window close]; return; }
    [self.window makeKeyWindow];
    [self.window makeFirstResponder:self];
    [self.window performWindowDragWithEvent:event];
}
- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 53) [self.window close];
    else [super keyDown:event];
}
- (void)closePin:(id)sender { [self.window close]; }
- (void)rightMouseDown:(NSEvent *)event {
    NSMenu *menu = [NSMenu new];
    NSMenuItem *close = [menu addItemWithTitle:@"关闭这张截图" action:@selector(closePin:) keyEquivalent:@""];
    close.target = self;
    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
}
- (void)scrollWheel:(NSEvent *)event {
    if (event.scrollingDeltaY == 0) return;
    NSRect visible = (self.window.screen ?: NSScreen.mainScreen).visibleFrame;
    NSRect frame = self.window.frame;
    CGFloat factor = pow(1.06, MIN(20.0, MAX(-20.0, event.scrollingDeltaY)));
    CGFloat maximum = MIN(visible.size.width * 0.95 / frame.size.width,
                          visible.size.height * 0.95 / frame.size.height);
    CGFloat minimum = MIN(1.0, 60.0 / MIN(frame.size.width, frame.size.height));
    factor = MAX(minimum, MIN(maximum, factor));
    NSSize size = NSMakeSize(frame.size.width * factor, frame.size.height * factor);
    NSPoint origin = NSMakePoint(NSMidX(frame) - size.width / 2, NSMidY(frame) - size.height / 2);
    origin.x = MIN(MAX(origin.x, NSMinX(visible)), NSMaxX(visible) - size.width);
    origin.y = MIN(MAX(origin.y, NSMinY(visible)), NSMaxY(visible) - size.height);
    [self.window setFrame:(NSRect){origin, size} display:YES];
}
@end

@interface CaptureApp : NSObject <NSApplicationDelegate, NSWindowDelegate> {
@public
    TCSession *_session;
    bool _shortcutDown;
    bool _escapeDown;
}
@property NSStatusItem *statusItem;
@property NSMenuItem *statusLine;
@property NSMenuItem *captureItem;
@property NSMenuItem *loginItem;
@property NSMenuItem *lifecycleItem;
@property NSMenuItem *lifecycleStatusItem;
@property NSMenuItem *pinScreenshotItem;
@property NSMenuItem *textItem;
@property NSString *recognizedText;
@property NSData *lastScreenshotPNG;
@property NSMutableArray<NSWindow *> *pinnedScreenshotWindows;
@property NSRunningApplication *previousApp;
@property EventHotKeyRef hotkey;
@property EventHotKeyRef escapeKey;
@property EventHandlerRef eventHandler;
@property BOOL registrationOK;
@property BOOL shuttingDown;
@property BOOL sessionPending;
@property BOOL showingHelp;
@property NSAlert *helpAlert;
@property NSPanel *recognitionProgressPanel;
@property NSTimer *lifecycleGuardTimer;
@property BOOL lifecycleTerminationRequested;
@property int activeWorkerPID;
- (void)capture:(id)sender;
- (void)cancelRecognition:(id)sender;
- (void)receivedSessionEvent:(NSString *)event value:(int)value;
- (void)pinLastScreenshot:(id)sender;
- (void)stopForWeChat:(id)sender;
- (void)terminateForWeChat:(id)sender;
@end
static CaptureApp *appDelegate; // strong for the entire parent lifetime
static NSString *const CapturedPNGBoardType = @"local.yichen.TencentCapture.captured-png";
static void SessionEvent(const char *event, int value, void *context) {
    NSString *name = [NSString stringWithUTF8String:event];
    NSLog(@"session_%@=%d", name, value);
    dispatch_async(dispatch_get_main_queue(), ^{ [appDelegate receivedSessionEvent:name value:value]; });
}
static OSStatus HotkeyHandler(EventHandlerCallRef next, EventRef event, void *context) {
    EventHotKeyID key = {0};
    if (GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(key), NULL, &key) != noErr || key.signature != 'TCAP') return eventNotHandledErr;
    bool pressed = GetEventKind(event) == kEventHotKeyPressed;
    bool *latch = key.id == 1 ? &appDelegate->_shortcutDown : &appDelegate->_escapeDown;
    if (!TCKeyAction(latch, pressed)) return noErr;
    if (key.id == 1) [appDelegate capture:nil];
    else if (key.id == 2) TCSessionCancel(appDelegate->_session);
    return noErr;
}
@implementation CaptureApp
- (void)setStatus:(NSString *)text {
    self.statusLine.title = text;
    self.statusItem.button.toolTip = [NSString stringWithFormat:@"%@ · %@", AppName, text];
    NSLog(@"status=%@", text);
}
- (void)showMessage:(NSString *)title detail:(NSString *)detail {
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [NSAlert new]; alert.messageText = title; alert.informativeText = detail;
    [alert addButtonWithTitle:@"知道了"]; [alert runModal];
}
- (void)showRecognitionProgress {
    if (self.recognitionProgressPanel || !self.sessionPending) return;
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 460, 150)
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                backing:NSBackingStoreBuffered defer:NO];
    panel.title = @"bro截图 · 正在提取文字";
    panel.delegate = self;
    panel.releasedWhenClosed = NO;
    panel.hidesOnDeactivate = NO;
    NSTextField *detail = [NSTextField wrappingLabelWithString:@"正在本机识别，请稍候。\n完成后会自动显示文字与翻译窗口。"];
    detail.frame = NSMakeRect(64, 69, 370, 55);
    [panel.contentView addSubview:detail];
    NSProgressIndicator *spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(24, 85, 24, 24)];
    spinner.style = NSProgressIndicatorStyleSpinning;
    [spinner startAnimation:nil];
    [panel.contentView addSubview:spinner];
    NSButton *cancel = [NSButton buttonWithTitle:@"取消识别" target:self action:@selector(cancelRecognition:)];
    cancel.frame = NSMakeRect(330, 20, 104, 32);
    [panel.contentView addSubview:cancel];
    self.recognitionProgressPanel = panel;
    [panel center];
    [panel makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}
- (void)cancelRecognition:(id)sender {
    if (self.sessionPending && _session && TCSessionIsActive(_session)) {
        TCSessionCancel(_session);
        [self setStatus:@"正在取消文字识别…"];
    }
}
- (BOOL)windowShouldClose:(NSWindow *)window {
    if (window == self.recognitionProgressPanel && self.sessionPending) {
        [self cancelRecognition:nil];
        return NO;
    }
    return YES;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // Parent never loads JietuFramework and never creates a capture window.
    _session = TCSessionCreate(NSBundle.mainBundle.executablePath.fileSystemRepresentation, NULL, SessionEvent, NULL);
    self.pinnedScreenshotWindows = [NSMutableArray array];
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"viewfinder" accessibilityDescription:AppName];
    NSMenu *menu = [NSMenu new]; menu.autoenablesItems = NO;
    self.captureItem = [menu addItemWithTitle:@"截图  ⌘⌃A" action:@selector(capture:) keyEquivalent:@""]; self.captureItem.target = self;
    self.statusLine = [menu addItemWithTitle:@"正在注册快捷键…" action:nil keyEquivalent:@""]; self.statusLine.enabled = NO;
    self.textItem = [menu addItemWithTitle:@"上次提取文字与翻译…" action:@selector(showRecognizedText:) keyEquivalent:@""];
    self.textItem.target = self; self.textItem.enabled = NO;
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *retry = [menu addItemWithTitle:@"重新注册 ⌘⌃A" action:@selector(registerShortcut:) keyEquivalent:@""]; retry.target = self;
    NSMenuItem *help = [menu addItemWithTitle:@"录屏权限与说明…" action:@selector(showHelp:) keyEquivalent:@""]; help.target = self;
    self.loginItem = [menu addItemWithTitle:@"登录时启动" action:@selector(toggleLogin:) keyEquivalent:@""]; self.loginItem.target = self;
    self.loginItem.state = SMAppService.mainAppService.status == SMAppServiceStatusEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.pinScreenshotItem = [menu addItemWithTitle:@"将上次截图置顶到桌面" action:@selector(pinLastScreenshot:) keyEquivalent:@""];
    self.pinScreenshotItem.target = self;
    self.pinScreenshotItem.enabled = NO;
    self.lifecycleItem = [menu addItemWithTitle:@"微信联动设置…" action:@selector(toggleLifecycleAgent:) keyEquivalent:@""];
    self.lifecycleItem.target = self;
    self.lifecycleItem.state = TCLifecycleAgentEnabled() ? NSControlStateValueOn : NSControlStateValueOff;
    self.lifecycleStatusItem = [menu addItemWithTitle:TCLifecycleAgentStatus() action:nil keyEquivalent:@""];
    self.lifecycleStatusItem.enabled = NO;
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [menu addItemWithTitle:@"退出bro截图" action:@selector(terminate:) keyEquivalent:@"q"]; quit.target = NSApp;
    self.statusItem.menu = menu;
    NSLog(@"lifecycle_preflight status=%@ can_register=%d enabled=%d", TCLifecycleAgentStatus(), TCLifecycleAgentCanRegister(), TCLifecycleAgentEnabled());
    if (TCLifecycleAgentCanRegister()) {
        NSError *lifecycleError = nil;
        if (!TCSetLifecycleAgentEnabled(YES, &lifecycleError)) {
            NSLog(@"lifecycle_autoregistration_failed=%@", lifecycleError.localizedDescription ?: @"unknown");
        }
        self.lifecycleItem.state = TCLifecycleAgentEnabled() ? NSControlStateValueOn : NSControlStateValueOff;
        self.lifecycleStatusItem.title = TCLifecycleAgentStatus();
    }
    self.lifecycleGuardTimer = [NSTimer timerWithTimeInterval:0.5 target:self selector:@selector(stopForWeChat:) userInfo:nil repeats:YES];
    for (NSString *mode in @[NSRunLoopCommonModes, NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode])
        [NSRunLoop.mainRunLoop addTimer:self.lifecycleGuardTimer forMode:mode];
    [self stopForWeChat:nil];
    if (self.lifecycleTerminationRequested) return;
    EventTypeSpec types[] = {{kEventClassKeyboard, kEventHotKeyPressed}, {kEventClassKeyboard, kEventHotKeyReleased}};
    OSStatus result = InstallEventHandler(GetApplicationEventTarget(), HotkeyHandler, 2, types, NULL, &_eventHandler);
    if (result == noErr && _session) [self registerShortcut:nil];
    else { self.captureItem.enabled = _session != NULL; [self setStatus:@"初始化失败 · 请退出后重试"]; }
}
- (void)stopForWeChat:(id)sender {
    if (self.shuttingDown || self.lifecycleTerminationRequested || !TCLifecycleAgentEnabled()) return;
    BOOL running = NO;
    for (NSRunningApplication *application in [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.tencent.xinWeChat"])
        if (!application.terminated) { running = YES; break; }
    if (!running) return;
    self.lifecycleTerminationRequested = YES;
    NSLog(@"lifecycle_ui_exit wechat_running=1 modal=%d", NSApp.modalWindow != nil);
    NSWindow *modal = NSApp.modalWindow;
    if (modal) { [NSApp abortModal]; [modal orderOut:nil]; }
    [self.statusItem.menu cancelTracking];
    // Finish after the modal/menu loop returns, so normal termination is accepted.
    [self performSelector:@selector(terminateForWeChat:) withObject:nil afterDelay:0 inModes:@[NSDefaultRunLoopMode]];
}
- (void)terminateForWeChat:(id)sender {
    [NSApp terminate:nil];
}
- (void)registerShortcut:(id)sender {
    if (self.hotkey || !self.eventHandler) return;
    OSStatus result = RegisterEventHotKey(kVK_ANSI_A, controlKey | cmdKey, (EventHotKeyID){'TCAP', 1}, GetApplicationEventTarget(), kEventHotKeyExclusive, &_hotkey);
    self.registrationOK = result == noErr;
    NSLog(@"hotkey_registration status=%d exclusive=1 fixed=Command+Control+A", (int)result);
    if (!self.registrationOK) [self setStatus:[NSString stringWithFormat:@"⌘⌃A 注册失败（%d）· 快捷键可能被其他应用占用", (int)result]];
    else [self setStatus:@"准备就绪 · ⌘⌃A · 微信和 QQ 无需运行"];
}
- (void)capture:(id)sender {
    if (self.shuttingDown || !_session) return;
    if (self.showingHelp) {
        // A physical hotkey can arrive while the help alert's modal loop runs.
        // End that loop before capture/OCR creates its result window.
        [NSApp abortModal];
        [self.helpAlert.window orderOut:nil];
    }
    if (self.sessionPending || TCSessionIsActive(_session)) {
        TCSessionCancel(_session); [self setStatus:@"正在结束本次截图…"]; return;
    }
    if (!CGPreflightScreenCaptureAccess()) { [self showHelp:nil]; return; }
    NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
    if (front.processIdentifier != getpid()) self.previousApp = front;
    self.sessionPending = YES;
    int result = TCSessionStart(_session);
    if (result != 0) { self.sessionPending = NO; [self setStatus:[NSString stringWithFormat:@"截图工作进程启动失败（%d）", result]]; return; }
    self.captureItem.title = @"取消本次截图  ⌘⌃A / Esc";
    [self setStatus:@"正在采集屏幕… 再按 ⌘⌃A 可取消"];
    // Parent owns an emergency Esc binding independent of the editor's main thread.
    OSStatus escapeStatus = RegisterEventHotKey(kVK_Escape, 0, (EventHotKeyID){'TCAP', 2}, GetApplicationEventTarget(), kEventHotKeyExclusive, &_escapeKey);
    if (escapeStatus != noErr) { NSLog(@"escape_registration_failed=%d local_escape_only=1", (int)escapeStatus); [self setStatus:@"截图启动中 · 全局 Esc 不可用，可再按 ⌘⌃A 退出"]; }
}
- (void)receivedSessionEvent:(NSString *)event value:(int)value {
    if (self.shuttingDown) return;
    if ([event isEqualToString:@"spawn"]) {
        self.activeWorkerPID = value;
    } else if ([event isEqualToString:@"state"]) {
        NSDictionary *names = @{@('P'):@"正在采集屏幕…", @('E'):@"正在截图 · Esc 或再次 ⌘⌃A 取消", @('L'):@"原生长截图中 · Esc 或再次 ⌘⌃A 取消", @('S'):@"等待保存位置 · 取消不会改动剪贴板", @('O'):@"正在本机识别文字…", @('F'):@"正在处理截图…"};
        NSString *name = names[@(value)]; if (name) [self setStatus:name];
        if (value == 'O') [self showRecognitionProgress];
    } else if ([event isEqualToString:@"timeout"]) {
        [self setStatus:@"截图工作进程无响应，正在自动回收窗口…"];
    } else if ([event isEqualToString:@"exit"]) {
        BOOL wasRecognizing = self.recognitionProgressPanel != nil;
        self.sessionPending = NO;
        [self.recognitionProgressPanel close];
        self.recognitionProgressPanel = nil;
        if (self.escapeKey) { UnregisterEventHotKey(self.escapeKey); self.escapeKey = NULL; }
        _escapeDown = false;
        self.captureItem.title = @"截图  ⌘⌃A";
        NSDictionary *results = @{@0:@"图片已复制", @1:@"图片已保存", @2:@"识别文字已复制", @10:@"已取消 · 剪贴板保持原样", @11:@"已取消保存 · 剪贴板保持原样", @12:@"未识别到文字 · 剪贴板保持原样", @20:@"截图进程缺少录屏权限，请从菜单正常授权", @21:@"截图组件接口不兼容，已停止", @22:@"屏幕采集失败或显示器发生变化，已退出", @23:@"原生编辑器未启动，已退出", @24:@"图片转换或复制失败", @25:@"长截图未能完成，已退出", @26:@"截图组件异常，已回收窗口", @27:@"图像处理超时，已退出", @28:@"图片保存失败", @29:@"文字识别失败", @30:@"工作进程监管初始化失败", @31:@"截图已置顶在桌面"};
        NSString *message = results[@(value)] ?: [NSString stringWithFormat:@"截图工作进程已结束（%d），可以重试", value];
        if (!self.registrationOK) message = [message stringByAppendingString:@" · ⌘⌃A 未注册"];
        [self setStatus:message];
        NSRunningApplication *previous = self.previousApp; self.previousApp = nil;
        if (value == TC_WORKER_EXIT_SUCCESS) {
            self.lastScreenshotPNG = [NSPasteboard.generalPasteboard dataForType:CapturedPNGBoardType];
            self.pinScreenshotItem.enabled = self.lastScreenshotPNG.length > 0;
        } else if (value == TC_WORKER_EXIT_PIN_SUCCESS) {
            NSPasteboard *board = self.activeWorkerPID > 0 ? [NSPasteboard pasteboardWithName:[NSString stringWithFormat:@"local.yichen.TencentCapture.pin-%d", self.activeWorkerPID]] : nil;
            NSData *png = [board dataForType:@"local.yichen.TencentCapture.pin-png"];
            [board releaseGlobally];
            if (png.length && [[NSImage alloc] initWithData:png]) {
                self.lastScreenshotPNG = png;
                self.pinScreenshotItem.enabled = YES;
                [self pinLastScreenshot:nil];
            } else {
                [self setStatus:@"置顶图片未能读取，请重新截图"];
            }
        }
        self.activeWorkerPID = 0;
        if (value == TC_WORKER_EXIT_OCR_SUCCESS) {
            // Only accept the worker's tagged OCR result; never translate an
            // unrelated clipboard string automatically after a failed capture.
            NSString *text = [NSPasteboard.generalPasteboard stringForType:@"local.yichen.TencentCapture.ocr-text"];
            if (text.length) {
                self.recognizedText = text;
                self.textItem.enabled = YES;
                [self showRecognizedText:nil];
                return;
            }
            [self showMessage:@"未能读取识别结果" detail:@"请重新框选文字，再次提取。"];
            return;
        }
        if (wasRecognizing && value != TC_WORKER_EXIT_OCR_SUCCESS && value != 10) {
            [self showMessage:message detail:@"请重新框选清晰的文字再试。"];
            return;
        }
        // Avoid stealing focus after a long edit if the user has switched elsewhere.
        NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
        if (previous && !previous.terminated && (!front || [front.bundleIdentifier isEqualToString:NSBundle.mainBundle.bundleIdentifier])) [previous activateWithOptions:0];
    }
}
- (void)pinLastScreenshot:(id)sender {
    NSImage *image = self.lastScreenshotPNG.length ? [[NSImage alloc] initWithData:self.lastScreenshotPNG] : nil;
    NSScreen *screen = NSScreen.mainScreen;
    if (!image || !screen || image.size.width <= 0 || image.size.height <= 0) {
        self.pinScreenshotItem.enabled = NO;
        [self showMessage:@"无法置顶截图" detail:@"请先完成一次截图并复制图片。"];
        return;
    }

    NSRect visible = screen.visibleFrame;
    CGFloat scale = MIN(1.0, MIN((visible.size.width * 0.72) / image.size.width,
                                 (visible.size.height * 0.72) / image.size.height));
    NSSize imageSize = NSMakeSize(image.size.width * scale, image.size.height * scale);
    TCPinnedPanel *window = [[TCPinnedPanel alloc] initWithContentRect:NSMakeRect(0, 0, imageSize.width, imageSize.height)
                                                          styleMask:NSWindowStyleMaskBorderless
                                                            backing:NSBackingStoreBuffered defer:NO];
    window.title = @"bro截图 · 置顶";
    window.releasedWhenClosed = NO;
    window.level = NSFloatingWindowLevel;
    window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                NSWindowCollectionBehaviorStationary |
                                NSWindowCollectionBehaviorFullScreenAuxiliary;
    window.hidesOnDeactivate = NO;

    TCPinnedImageView *imageView = [[TCPinnedImageView alloc] initWithFrame:NSMakeRect(0, 0, imageSize.width, imageSize.height)];
    imageView.image = image;
    imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    imageView.toolTip = @"拖动移动 · 滚轮缩放 · 双击或 Esc 关闭 · 右键关闭";
    imageView.accessibilityLabel = @"置顶截图";
    imageView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    window.contentView = imageView;

    [self.pinnedScreenshotWindows addObject:window];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(pinnedScreenshotWillClose:)
                                                 name:NSWindowWillCloseNotification
                                               object:window];
    [window center];
    [window orderFrontRegardless];
    [self setStatus:@"截图已置顶在桌面"];
    NSLog(@"screenshot_pinned size=%.0fx%.0f", imageSize.width, imageSize.height);
}
- (void)pinnedScreenshotWillClose:(NSNotification *)notification {
    NSWindow *window = notification.object;
    [self.pinnedScreenshotWindows removeObject:window];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowWillCloseNotification object:window];
}
- (void)showRecognizedText:(id)sender {
    if (self.recognizedText.length) TCShowRecognizedText(self.recognizedText.UTF8String);
}
- (void)showHelp:(id)sender {
    if (self.showingHelp) return;
    self.showingHelp = YES;
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [NSAlert new];
    BOOL hasScreenPermission = CGPreflightScreenCaptureAccess();
    NSLog(@"screen_permission_preflight=%d", hasScreenPermission);
    alert.messageText = @"bro截图 · 1001v8";
    alert.informativeText = [NSString stringWithFormat:@"录屏权限：%@。\n微信联动：%@。\n\n固定快捷键：Command + Control + A。\n再次按下或 Esc 可取消本次截图。快捷键注册失败时会明确提示。\n\n保留原生标注编辑器；保存为 PNG，文字识别在本机完成。识别成功后可在文字窗口点击本机翻译（macOS 15+）；首次语言包下载由系统确认。\n\n录屏权限需由 macOS 正常授予。", hasScreenPermission ? @"已获得" : @"未获得", TCLifecycleAgentStatus()];
    [alert addButtonWithTitle:@"关闭"]; [alert addButtonWithTitle:@"请求录屏权限"];
    [alert addButtonWithTitle:@"开始截图"].enabled = hasScreenPermission;
    self.helpAlert = alert;
    NSModalResponse response = [alert runModal];
    self.helpAlert = nil;
    self.showingHelp = NO;
    if (response == NSAlertSecondButtonReturn && !CGPreflightScreenCaptureAccess()) CGRequestScreenCaptureAccess();
    else if (response == NSAlertThirdButtonReturn) [self capture:nil];
}
- (void)toggleLogin:(id)sender {
    NSError *error = nil;
    BOOL enabled = SMAppService.mainAppService.status == SMAppServiceStatusEnabled;
    BOOL ok = enabled ? [SMAppService.mainAppService unregisterAndReturnError:&error] : [SMAppService.mainAppService registerAndReturnError:&error];
    self.loginItem.state = SMAppService.mainAppService.status == SMAppServiceStatusEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    if (!ok) [self showMessage:@"登录启动设置未完成" detail:error.localizedDescription ?: @"请通过系统设置检查。"];
    else if (SMAppService.mainAppService.status == SMAppServiceStatusRequiresApproval) [self showMessage:@"等待系统确认" detail:@"请在系统设置的登录项中确认。"];
}
- (void)toggleLifecycleAgent:(id)sender {
    BOOL registered = TCLifecycleAgentRegistered();
    NSError *error = nil;
    BOOL ok = TCSetLifecycleAgentEnabled(!registered, &error);
    self.lifecycleItem.state = TCLifecycleAgentEnabled() ? NSControlStateValueOn : NSControlStateValueOff;
    self.lifecycleStatusItem.title = TCLifecycleAgentStatus();
    if (!ok) {
        [self showMessage:@"微信联动设置未完成" detail:error.localizedDescription ?: TCLifecycleAgentStatus()];
    } else if (!registered && !TCLifecycleAgentEnabled()) {
        [self showMessage:@"等待系统批准" detail:TCLifecycleAgentStatus()];
    }
}
- (void)applicationWillTerminate:(NSNotification *)notification {
    self.shuttingDown = YES;
    [self.lifecycleGuardTimer invalidate];
    self.lifecycleGuardTimer = nil;
    [self.recognitionProgressPanel close];
    self.recognitionProgressPanel = nil;
    TCSessionDestroy(_session); _session = NULL;
    if (self.escapeKey) UnregisterEventHotKey(self.escapeKey);
    if (self.hotkey) UnregisterEventHotKey(self.hotkey);
    if (self.eventHandler) RemoveEventHandler(self.eventHandler);
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    if (!flag && !self.sessionPending && !TCSessionIsActive(_session)) [self showHelp:nil];
    return YES;
}
@end
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && !strcmp(argv[1], "--capture-worker")) return TCRunCaptureWorker();
        if (argc > 1 && !strcmp(argv[1], "--lifecycle-agent")) return TCLifecycleAgentMain();
        if (argc > 2 && !strcmp(argv[1], "--fake-worker")) return TCSessionRunFakeWorker(argv[2]);
        if (argc > 1 && !strcmp(argv[1], "--lifecycle-status")) {
            NSDictionary *report = @{@"bundlePath":NSBundle.mainBundle.bundlePath ?: @"", @"bundleID":NSBundle.mainBundle.bundleIdentifier ?: @"", @"installed":@(TCLifecycleAppIsInstalled()), @"canRegister":@(TCLifecycleAgentCanRegister()), @"registered":@(TCLifecycleAgentRegistered()), @"enabled":@(TCLifecycleAgentEnabled()), @"status":TCLifecycleAgentStatus()};
            NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL];
            puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String); return 0;
        }
        if (argc > 1 && (!strcmp(argv[1], "--lifecycle-enable") || !strcmp(argv[1], "--lifecycle-disable"))) {
            NSError *error = nil;
            BOOL enabled = !strcmp(argv[1], "--lifecycle-enable");
            BOOL ok = TCSetLifecycleAgentEnabled(enabled, &error);
            NSDictionary *report = @{@"success":@(ok), @"enabled":@(TCLifecycleAgentEnabled()), @"status":TCLifecycleAgentStatus(), @"errorDomain":error.domain ?: @"", @"errorCode":@(error.code), @"error":error.localizedDescription ?: @""};
            NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL];
            puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String); return ok ? 0 : 1;
        }
        if (argc > 1 && (!strcmp(argv[1], "--verify-engine") || !strcmp(argv[1], "--diagnose"))) {
            NSError *error = nil; BOOL ok = TCVerifyEngine(&error);
            NSDictionary *report = @{@"version":@"1001v8-candidate", @"fullPrivateABIValidated":@(ok), @"error":error.localizedDescription ?: @"", @"guiTested":@NO, @"appPermissionVerified":@NO, @"note":@"No NSApplication, capture, permission request or editor started."};
            NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL];
            puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String); return ok ? 0 : 1;
        }
        if (argc > 1) { fprintf(stderr, "Unknown mode; refusing GUI launch.\n"); return 64; }
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        appDelegate = [CaptureApp new]; NSApp.delegate = appDelegate;
        [NSApp run];
    }
    return 0;
}
