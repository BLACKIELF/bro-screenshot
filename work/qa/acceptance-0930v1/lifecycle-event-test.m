#import <Cocoa/Cocoa.h>
#import <assert.h>
#import <unistd.h>

// Exercise the production event handler without launching, quitting, or
// posting synthetic workspace notifications to other applications.
@interface TCLifecycleAgentRunner : NSObject
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSDate *> *launchingWeChatPIDs;
- (void)applicationLifecycleChanged:(NSNotification *)notification;
- (void)poll:(NSTimer *)timer;
@end

@interface TCEventProbe : TCLifecycleAgentRunner
@property(nonatomic) NSUInteger reconciliationCount;
@end
@implementation TCEventProbe
- (void)poll:(NSTimer *)timer { self.reconciliationCount++; }
@end

@interface TCEventApplication : NSObject
@property(nonatomic, copy) NSString *bundleIdentifier;
@property(nonatomic, strong) NSURL *bundleURL;
@property(nonatomic) pid_t processIdentifier;
@end
@implementation TCEventApplication
@end

static TCEventApplication *App(NSString *bundleID, NSString *path, pid_t pid) {
    TCEventApplication *app = [TCEventApplication new];
    app.bundleIdentifier = bundleID;
    app.bundleURL = path ? [NSURL fileURLWithPath:path] : nil;
    app.processIdentifier = pid;
    return app;
}
static void Event(TCEventProbe *runner, NSNotificationName name, TCEventApplication *app) {
    NSDictionary *info = app ? @{NSWorkspaceApplicationKey: app} : @{};
    [runner applicationLifecycleChanged:[NSNotification notificationWithName:name object:nil userInfo:info]];
}
static void Drain(TCEventProbe *runner, NSUInteger expected) {
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + 1.0;
    while (runner.reconciliationCount < expected && CFAbsoluteTimeGetCurrent() < deadline)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
    assert(runner.reconciliationCount == expected);
}
int main(void) {
    @autoreleasepool {
        TCEventProbe *runner = [TCEventProbe new];
        TCEventApplication *first = App(@"com.tencent.xinWeChat", @"/Applications/WeChat.app", 10101);
        TCEventApplication *second = App(@"com.tencent.xinWeChat", @"/Applications/WeChat.app", 10102);
        Event(runner, NSWorkspaceWillLaunchApplicationNotification, first);
        Drain(runner, 1);
        assert(runner.launchingWeChatPIDs.count == 1);
        Event(runner, NSWorkspaceWillLaunchApplicationNotification, first);
        Drain(runner, 2);
        assert(runner.launchingWeChatPIDs.count == 1);
        Event(runner, NSWorkspaceWillLaunchApplicationNotification, second);
        Drain(runner, 3);
        assert(runner.launchingWeChatPIDs.count == 2);
        Event(runner, NSWorkspaceDidTerminateApplicationNotification, first);
        Drain(runner, 4);
        assert(!runner.launchingWeChatPIDs[@10101] && runner.launchingWeChatPIDs[@10102]);
        Event(runner, NSWorkspaceDidLaunchApplicationNotification, second);
        Drain(runner, 5);
        assert(runner.launchingWeChatPIDs.count == 0);
        Event(runner, NSWorkspaceDidTerminateApplicationNotification, second);
        Drain(runner, 6);
        assert(runner.launchingWeChatPIDs.count == 0);

        Event(runner, NSWorkspaceDidLaunchApplicationNotification, App(@"unrelated.app", nil, 10103));
        Event(runner, NSWorkspaceDidLaunchApplicationNotification, nil);
        Event(runner, NSWorkspaceWillLaunchApplicationNotification, App(@"com.tencent.xinWeChat", nil, getpid()));
        Event(runner, NSWorkspaceDidLaunchApplicationNotification, App(@"local.yichen.TencentCapture", @"/tmp/bro截图.app", 10104));
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
        assert(runner.reconciliationCount == 6 && runner.launchingWeChatPIDs.count == 0);
        Event(runner, NSWorkspaceDidLaunchApplicationNotification, App(@"local.yichen.TencentCapture", @"/Applications/bro截图.app", 10105));
        Drain(runner, 7);
        assert(runner.launchingWeChatPIDs.count == 0);
        puts("Lifecycle event tests passed: launch, duplicate, concurrent, terminate, identity and path guards.");
    }
    return 0;
}
