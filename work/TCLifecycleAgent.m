#import "TCLifecycleAgent.h"

#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>
#import <unistd.h>

static NSString *const TCLifecycleAppPath = @"/Applications/bro截图.app";
static NSString *const TCLifecycleBundleID = @"local.yichen.TencentCapture";
static NSString *const TCLifecycleAgentPlistName = @"local.yichen.TencentCapture.Lifecycle.plist";
static NSString *const TCLifecycleErrorDomain = @"local.yichen.TencentCapture.LifecycleAgent";
static NSString *const TCWeChatBundleID = @"com.tencent.xinWeChat";
static NSString *const TCLifecycleUserDisabledKey = @"TCLifecycleAgentUserDisabled";

static NSURL *TCStandardAppURL(void) {
    return [[NSURL fileURLWithPath:TCLifecycleAppPath isDirectory:YES] URLByStandardizingPath];
}

static NSURL *TCStandardizedBundleURL(NSURL *url) {
    return url ? [url URLByStandardizingPath] : nil;
}

static BOOL TCURLIsStandardApp(NSURL *url) {
    NSURL *standard = TCStandardizedBundleURL(url);
    return standard && [standard.path isEqualToString:TCLifecycleAppPath];
}

static BOOL TCMainBundleIsStandardApp(void) {
    return TCURLIsStandardApp(NSBundle.mainBundle.bundleURL) &&
           [NSBundle.mainBundle.bundleIdentifier isEqualToString:TCLifecycleBundleID];
}

BOOL TCLifecycleAppIsInstalled(void) {
    NSURL *url = TCStandardAppURL();
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&isDirectory] || !isDirectory) {
        return NO;
    }
    NSBundle *bundle = [NSBundle bundleWithURL:url];
    return bundle && [bundle.bundleIdentifier isEqualToString:TCLifecycleBundleID] &&
           bundle.executableURL && [[NSFileManager defaultManager] isExecutableFileAtPath:bundle.executableURL.path];
}

static SMAppService *TCServiceForStandardMainBundle(void) {
    if (!TCMainBundleIsStandardApp()) return nil;
    return [SMAppService agentServiceWithPlistName:TCLifecycleAgentPlistName];
}

static NSString *TCStatusForService(SMAppService *service) {
    if (!service) return @"不可用：请从 /Applications/bro截图.app 管理登录启动";
    switch (service.status) {
        case SMAppServiceStatusNotRegistered:
            return @"未启用";
        case SMAppServiceStatusEnabled:
            return @"已启用";
        case SMAppServiceStatusRequiresApproval:
            return @"等待系统批准：请在系统设置 > 通用 > 登录项中允许bro截图";
        case SMAppServiceStatusNotFound:
            return @"未找到内嵌的生命周期 LaunchAgent plist";
    }
    return @"生命周期代理状态未知";
}

BOOL TCLifecycleAgentEnabled(void) {
    SMAppService *service = TCServiceForStandardMainBundle();
    return service && service.status == SMAppServiceStatusEnabled;
}

BOOL TCLifecycleAgentRegistered(void) {
    SMAppService *service = TCServiceForStandardMainBundle();
    return service && service.status != SMAppServiceStatusNotRegistered &&
           service.status != SMAppServiceStatusNotFound;
}

BOOL TCLifecycleAgentCanRegister(void) {
    if ([NSUserDefaults.standardUserDefaults boolForKey:TCLifecycleUserDisabledKey]) return NO;
    SMAppService *service = TCServiceForStandardMainBundle();
    if (!service) return NO;
    if (service.status == SMAppServiceStatusNotRegistered) return YES;
    // A fresh install can report NotFound before its first registration even
    // when the embedded plist exists. Let register validate it and its signature.
    if (service.status == SMAppServiceStatusNotFound) {
        NSString *plistPath = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:
                              [@"Contents/Library/LaunchAgents" stringByAppendingPathComponent:TCLifecycleAgentPlistName]];
        return [NSFileManager.defaultManager isReadableFileAtPath:plistPath];
    }
    return NO;
}

NSString *TCLifecycleAgentStatus(void) {
    if (!TCMainBundleIsStandardApp()) {
        return @"不可用：请从 /Applications/bro截图.app 管理登录启动";
    }
    return TCStatusForService(TCServiceForStandardMainBundle());
}

BOOL TCSetLifecycleAgentEnabled(BOOL enabled, NSError **error) {
    SMAppService *service = TCServiceForStandardMainBundle();
    if (!service) {
        if (error) {
            *error = [NSError errorWithDomain:TCLifecycleErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"只能由标准路径 /Applications/bro截图.app 管理生命周期代理。"}];
        }
        return NO;
    }

    NSError *serviceError = nil;
    BOOL success = enabled ? [service registerAndReturnError:&serviceError]
                           : [service unregisterAndReturnError:&serviceError];
    if (!success) {
        if (error) *error = serviceError ?: [NSError errorWithDomain:TCLifecycleErrorDomain
                                                                  code:2
                                                              userInfo:@{NSLocalizedDescriptionKey:
                                                                             @"系统未能更新生命周期代理状态。"}];
        return NO;
    }

    if (error) *error = nil;
    [NSUserDefaults.standardUserDefaults setBool:!enabled forKey:TCLifecycleUserDisabledKey];
    // A successful registration can still require the user's explicit approval in System Settings.
    return YES;
}

@interface TCLifecycleAgentRunner : NSObject
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) NSMutableSet<NSNumber *> *terminationRequestedPIDs;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSDate *> *launchingWeChatPIDs;
@property(nonatomic) BOOL launchInFlight;
@property(nonatomic) BOOL hasPreviousState;
@property(nonatomic) BOOL previousWeChatRunning;
@property(nonatomic) BOOL previousToolRunning;
@property(nonatomic) BOOL previousLaunchInFlight;
@end

@implementation TCLifecycleAgentRunner

- (instancetype)init {
    self = [super init];
    if (self) {
        _terminationRequestedPIDs = [NSMutableSet set];
        _launchingWeChatPIDs = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)applicationLifecycleChanged:(NSNotification *)notification {
    NSRunningApplication *application = notification.userInfo[NSWorkspaceApplicationKey];
    if (!application || application.processIdentifier == getpid()) return;
    BOOL isWeChat = [application.bundleIdentifier isEqualToString:TCWeChatBundleID];
    if (!isWeChat && ![self isStandardToolApplication:application]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (isWeChat) {
            NSNumber *pid = @(application.processIdentifier);
            if ([notification.name isEqualToString:NSWorkspaceWillLaunchApplicationNotification]) {
                self.launchingWeChatPIDs[pid] = NSDate.date;
            } else {
                [self.launchingWeChatPIDs removeObjectForKey:pid];
            }
        }
        [self poll:nil];
    });
}

- (BOOL)isStandardToolApplication:(NSRunningApplication *)application {
    return [application.bundleIdentifier isEqualToString:TCLifecycleBundleID] &&
           TCURLIsStandardApp(application.bundleURL);
}

- (void)poll:(NSTimer *)timer {
    NSArray<NSRunningApplication *> *applications = NSWorkspace.sharedWorkspace.runningApplications;
    // A failed launch must not suppress the tool indefinitely if no final event arrives.
    NSDate *now = NSDate.date;
    for (NSNumber *pid in self.launchingWeChatPIDs.allKeys) {
        if ([now timeIntervalSinceDate:self.launchingWeChatPIDs[pid]] >= 10.0) {
            [self.launchingWeChatPIDs removeObjectForKey:pid];
        }
    }
    BOOL wechatRunning = self.launchingWeChatPIDs.count > 0;
    NSRunningApplication *toolApplication = nil;
    pid_t ownPID = getpid();

    for (NSRunningApplication *application in applications) {
        if (application.isTerminated) continue;
        // WeChat detection is deliberately limited to its bundle identifier.
        if ([application.bundleIdentifier isEqualToString:TCWeChatBundleID]) wechatRunning = YES;

        // The LaunchAgent shares the app bundle; never count or terminate itself as the UI app.
        if (application.processIdentifier == ownPID || ![self isStandardToolApplication:application]) continue;
        if (!toolApplication) toolApplication = application;
    }

    BOOL toolRunning = toolApplication != nil;
    if (!self.hasPreviousState || wechatRunning != self.previousWeChatRunning ||
        toolRunning != self.previousToolRunning || self.launchInFlight != self.previousLaunchInFlight) {
        NSLog(@"lifecycle_state wechat=%d tool=%d launch_in_flight=%d",
              wechatRunning, toolRunning, self.launchInFlight);
        self.hasPreviousState = YES;
        self.previousWeChatRunning = wechatRunning;
        self.previousToolRunning = toolRunning;
        self.previousLaunchInFlight = self.launchInFlight;
    }

    // Drop completed requests so a future process with the same PID can be handled.
    NSMutableSet<NSNumber *> *livePIDs = [NSMutableSet set];
    for (NSRunningApplication *application in applications) {
        if (!application.isTerminated && application.processIdentifier != ownPID && [self isStandardToolApplication:application]) {
            [livePIDs addObject:@(application.processIdentifier)];
        }
    }
    [self.terminationRequestedPIDs intersectSet:livePIDs];

    TCLifecycleDecision decision = TCLifecycleDecide(wechatRunning, toolRunning, self.launchInFlight);
    if (decision == TCLifecycleDecisionTerminate && toolApplication) {
        NSNumber *pid = @(toolApplication.processIdentifier);
        if (![self.terminationRequestedPIDs containsObject:pid]) {
            if ([toolApplication terminate]) {
                [self.terminationRequestedPIDs addObject:pid];
            } else {
                NSLog(@"lifecycle_failure terminate_refused pid=%d", toolApplication.processIdentifier);
            }
        }
    } else if (decision == TCLifecycleDecisionLaunch) {
        NSURL *appURL = TCStandardAppURL();
        if (!TCLifecycleAppIsInstalled()) {
            NSLog(@"lifecycle_failure standard_app_missing path=%@", appURL.path);
            return;
        }

        self.launchInFlight = YES;
        NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration new];
        configuration.activates = NO;
        configuration.addsToRecentItems = NO;
        configuration.createsNewApplicationInstance = YES;
        [NSWorkspace.sharedWorkspace openApplicationAtURL:appURL
                                            configuration:configuration
                                       completionHandler:^(NSRunningApplication * _Nullable application,
                                                           NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.launchInFlight = NO;
                if (error || !application) {
                    NSLog(@"lifecycle_failure launch_error=%@", error.localizedDescription ?: @"no application returned");
                    return;
                }

                BOOL wechatStartedDuringLaunch = self.launchingWeChatPIDs.count > 0;
                for (NSRunningApplication *current in NSWorkspace.sharedWorkspace.runningApplications) {
                    if (!current.isTerminated && [current.bundleIdentifier isEqualToString:TCWeChatBundleID]) {
                        wechatStartedDuringLaunch = YES;
                        break;
                    }
                }
                if (wechatStartedDuringLaunch && application.processIdentifier != ownPID &&
                    [self isStandardToolApplication:application]) {
                    [application terminate];
                    NSLog(@"lifecycle_transition wechat_started_during_tool_launch pid=%d",
                          application.processIdentifier);
                }
            });
        }];
    }
}

@end

int TCLifecycleAgentMain(void) {
    @autoreleasepool {
        if (!TCMainBundleIsStandardApp() || !TCLifecycleAppIsInstalled()) {
            NSLog(@"lifecycle_failure invalid_standard_app_bundle");
            return 2;
        }

        TCLifecycleAgentRunner *runner = [TCLifecycleAgentRunner new];
        NSNotificationCenter *workspaceNotifications = NSWorkspace.sharedWorkspace.notificationCenter;
        for (NSNotificationName name in @[NSWorkspaceWillLaunchApplicationNotification,
                                         NSWorkspaceDidLaunchApplicationNotification,
                                         NSWorkspaceDidTerminateApplicationNotification]) {
            [workspaceNotifications addObserver:runner
                                       selector:@selector(applicationLifecycleChanged:)
                                           name:name
                                         object:nil];
        }
        [runner poll:nil];
        runner.timer = [NSTimer timerWithTimeInterval:1.0
                                              target:runner
                                            selector:@selector(poll:)
                                            userInfo:nil
                                             repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:runner.timer forMode:NSRunLoopCommonModes];
        NSLog(@"lifecycle_agent_started events=workspace_launch_terminate fallback_interval=1");
        CFRunLoopRun();
        [workspaceNotifications removeObserver:runner];
        [runner.timer invalidate];
        return 0;
    }
}
