#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>
#import <QuartzCore/QuartzCore.h>
#import "SettingsManager.h"
#import "DebugInspector.h"

static NSString * const kYTNicoPiPBridgeDomain = @"com.example.ytnico.pipbridge";
static NSString * const kYTNicoPiPBridgeCommentsKey = @"comments";
static NSString * const kYTNicoPiPBridgeActiveKey = @"active";
static NSString * const kYTNicoPiPBridgeNotify = @"com.example.ytnico.pipbridge.changed";

static UIWindow *gYTNicoSBPiPWindow = nil;
static UIView *gYTNicoSBPiPView = nil;
static NSUInteger gYTNicoSBPiPLaneCursor = 0;
static NSInteger gYTNicoSBLastSerial = 0;
static BOOL gYTNicoSBPiPActive = NO;

static BOOL YTNicoIsYouTubeProcess(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"];
}

static BOOL YTNicoIsSpringBoardProcess(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"];
}

static NSUserDefaults *YTNicoPiPBridgeDefaults(void) {
    return [[NSUserDefaults alloc] initWithSuiteName:kYTNicoPiPBridgeDomain] ?: NSUserDefaults.standardUserDefaults;
}

static void YTNicoPiPBridgePostNotification(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)kYTNicoPiPBridgeNotify, NULL, NULL, YES);
}

static void YTNicoPiPBridgeSetActive(BOOL active) {
    NSUserDefaults *d = YTNicoPiPBridgeDefaults();
    [d setBool:active forKey:kYTNicoPiPBridgeActiveKey];
    [d synchronize];
    YTNicoPiPBridgePostNotification();
    [[DebugInspector shared] important:@"PiP bridge active=%d", active];
}

static void YTNicoPiPBridgePublishComment(NSString *author, NSString *text, NSString *messageId) {
    if (!YTNicoIsYouTubeProcess()) return;
    if (!text.length) return;
    if ([author isEqualToString:@"YTNico"]) return;

    NSUserDefaults *d = YTNicoPiPBridgeDefaults();
    NSMutableArray *comments = [[d arrayForKey:kYTNicoPiPBridgeCommentsKey] mutableCopy] ?: [NSMutableArray array];
    NSInteger serial = [[comments.lastObject objectForKey:@"serial"] integerValue] + 1;
    if (serial <= 0) serial = (NSInteger)[NSDate.date timeIntervalSince1970];

    NSDictionary *entry = @{
        @"serial": @(serial),
        @"author": author ?: @"",
        @"text": text ?: @"",
        @"messageId": messageId ?: NSUUID.UUID.UUIDString,
        @"time": @([NSDate.date timeIntervalSince1970])
    };
    [comments addObject:entry];
    while (comments.count > 80) [comments removeObjectAtIndex:0];
    [d setObject:comments forKey:kYTNicoPiPBridgeCommentsKey];
    [d synchronize];
    YTNicoPiPBridgePostNotification();
}

static CGRect YTNicoSBPiPFrame(void) {
    CGRect s = UIScreen.mainScreen.bounds;
    CGFloat width = MIN(CGRectGetWidth(s) - 24.0, 320.0);
    CGFloat height = width * 9.0 / 16.0;
    CGFloat x = CGRectGetWidth(s) - width - 12.0;
    CGFloat y = CGRectGetHeight(s) - height - 116.0;
    if (y < 72.0) y = 72.0;
    return CGRectMake(x, y, width, height);
}

static void YTNicoSBEnsurePiPOverlay(void) {
    if (!YTNicoIsSpringBoardProcess()) return;
    if (!gYTNicoSBPiPActive) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gYTNicoSBPiPWindow) {
            if (@available(iOS 13.0, *)) {
                UIWindowScene *scene = nil;
                for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
                    if ([s isKindOfClass:UIWindowScene.class] && s.activationState == UISceneActivationStateForegroundActive) {
                        scene = (UIWindowScene *)s;
                        break;
                    }
                }
                if (scene) gYTNicoSBPiPWindow = [[UIWindow alloc] initWithWindowScene:scene];
                else gYTNicoSBPiPWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
            } else {
                gYTNicoSBPiPWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
            }
            gYTNicoSBPiPWindow.windowLevel = UIWindowLevelAlert + 500.0;
            gYTNicoSBPiPWindow.backgroundColor = UIColor.clearColor;
            gYTNicoSBPiPWindow.userInteractionEnabled = NO;
            gYTNicoSBPiPWindow.rootViewController = [UIViewController new];
            gYTNicoSBPiPWindow.rootViewController.view.backgroundColor = UIColor.clearColor;
            gYTNicoSBPiPWindow.hidden = NO;

            gYTNicoSBPiPView = [[UIView alloc] initWithFrame:YTNicoSBPiPFrame()];
            gYTNicoSBPiPView.backgroundColor = UIColor.clearColor;
            gYTNicoSBPiPView.userInteractionEnabled = NO;
            gYTNicoSBPiPView.clipsToBounds = YES;
            gYTNicoSBPiPView.layer.cornerRadius = 12.0;
            [gYTNicoSBPiPWindow.rootViewController.view addSubview:gYTNicoSBPiPView];
        }
        gYTNicoSBPiPWindow.frame = UIScreen.mainScreen.bounds;
        gYTNicoSBPiPWindow.hidden = NO;
        gYTNicoSBPiPView.frame = YTNicoSBPiPFrame();
    });
}

static void YTNicoSBHidePiPOverlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [gYTNicoSBPiPView removeFromSuperview];
        gYTNicoSBPiPView = nil;
        gYTNicoSBPiPWindow.hidden = YES;
        gYTNicoSBPiPWindow = nil;
        gYTNicoSBPiPLaneCursor = 0;
    });
}

static void YTNicoSBEmitPiPText(NSString *author, NSString *text) {
    if (!gYTNicoSBPiPActive || !text.length) return;
    YTNicoSBEnsurePiPOverlay();
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *view = gYTNicoSBPiPView;
        if (!view) return;
        NSString *display = author.length ? [NSString stringWithFormat:@"%@: %@", author, text] : text;
        CGFloat fontSize = 13.0;
        UIFont *font = [UIFont boldSystemFontOfSize:fontSize];
        CGRect r = [display boundingRectWithSize:CGSizeMake(1000, 24) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName:font} context:nil];
        CGFloat w = MIN(MAX(80.0, ceil(r.size.width) + 18.0), view.bounds.size.width * 1.6);
        CGFloat h = 20.0;
        NSInteger lanes = MAX(3, (NSInteger)floor(MAX(1.0, view.bounds.size.height - 6.0) / h));
        NSUInteger lane = gYTNicoSBPiPLaneCursor++ % (NSUInteger)lanes;
        CGFloat y = 3.0 + lane * h;

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(view.bounds.size.width + 8.0, y, w, h)];
        label.text = display;
        label.font = font;
        label.textColor = UIColor.whiteColor;
        label.backgroundColor = UIColor.clearColor;
        label.layer.shadowColor = UIColor.blackColor.CGColor;
        label.layer.shadowOpacity = 1.0;
        label.layer.shadowRadius = 1.3;
        label.layer.shadowOffset = CGSizeMake(1, 1);
        [view addSubview:label];
        NSTimeInterval duration = MAX(4.2, MIN(7.2, 4.8 + display.length * 0.016));
        [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveLinear animations:^{
            CGRect f = label.frame;
            f.origin.x = -w - 12.0;
            label.frame = f;
        } completion:^(__unused BOOL finished) {
            [label removeFromSuperview];
        }];
    });
}

static void YTNicoSBReadBridge(void) {
    if (!YTNicoIsSpringBoardProcess()) return;
    NSUserDefaults *d = YTNicoPiPBridgeDefaults();
    BOOL active = [d boolForKey:kYTNicoPiPBridgeActiveKey];
    if (active != gYTNicoSBPiPActive) {
        gYTNicoSBPiPActive = active;
        if (active) YTNicoSBEnsurePiPOverlay();
        else YTNicoSBHidePiPOverlay();
    }
    if (!gYTNicoSBPiPActive) return;

    NSArray *comments = [d arrayForKey:kYTNicoPiPBridgeCommentsKey] ?: @[];
    NSTimeInterval now = [NSDate.date timeIntervalSince1970];
    for (NSDictionary *entry in comments) {
        NSInteger serial = [entry[@"serial"] integerValue];
        NSTimeInterval t = [entry[@"time"] doubleValue];
        if (serial <= gYTNicoSBLastSerial) continue;
        if (now - t > 30.0) continue;
        gYTNicoSBLastSerial = serial;
        YTNicoSBEmitPiPText(entry[@"author"] ?: @"", entry[@"text"] ?: @"");
    }
}

static void YTNicoSBBridgeCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    YTNicoSBReadBridge();
}

%hook AVPictureInPictureController

- (void)startPictureInPicture {
    %orig;
    if (YTNicoIsYouTubeProcess()) YTNicoPiPBridgeSetActive(YES);
}

- (void)stopPictureInPicture {
    if (YTNicoIsYouTubeProcess()) YTNicoPiPBridgeSetActive(NO);
    %orig;
}

- (void)setPictureInPicturePossible:(BOOL)possible {
    %orig;
}

%end

%hook YouTubeChatAdapter

+ (void)emitNowAuthor:(NSString *)author text:(NSString *)text messageId:(NSString *)messageId {
    %orig(author, text, messageId);
    YTNicoPiPBridgePublishComment(author, text, messageId);
}

+ (void)broadcastAuthor:(NSString *)author text:(NSString *)text messageId:(NSString *)messageId {
    %orig(author, text, messageId);
    YTNicoPiPBridgePublishComment(author, text, messageId);
}

%end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (YTNicoIsSpringBoardProcess()) {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, YTNicoSBBridgeCallback, (__bridge CFStringRef)kYTNicoPiPBridgeNotify, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
            [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                if (gYTNicoSBPiPActive) YTNicoSBEnsurePiPOverlay();
            }];
            YTNicoSBReadBridge();
        }
    });
}
