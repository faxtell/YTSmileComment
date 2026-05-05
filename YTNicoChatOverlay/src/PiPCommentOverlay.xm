#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <AVKit/AVKit.h>
#import "SettingsManager.h"
#import "DebugInspector.h"
#import "YouTubeChatAdapter.h"

static BOOL gYTNicoPiPActive = NO;
static UIWindow *gYTNicoPiPOverlayWindow = nil;
static UIView *gYTNicoPiPOverlayView = nil;
static NSUInteger gYTNicoPiPLaneCursor = 0;
static NSMutableSet<NSString *> *gYTNicoPiPSeenIds = nil;

static BOOL YTNicoStringContainsAny(NSString *s, NSArray<NSString *> *needles) {
    for (NSString *n in needles) {
        if ([s rangeOfString:n options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

static UIWindow *YTNicoFindPiPWindow(void) {
    NSArray<NSString *> *needles = @[@"PiP", @"PIP", @"PictureInPicture", @"Picture", @"Pinnable"];
    for (UIWindow *window in UIApplication.sharedApplication.windows.reverseObjectEnumerator) {
        if (window.hidden || window.alpha <= 0.01) continue;
        NSString *name = NSStringFromClass(window.class);
        if (YTNicoStringContainsAny(name, needles)) return window;
        NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:window];
        NSUInteger scanned = 0;
        while (stack.count && scanned < 120) {
            UIView *v = stack.lastObject;
            [stack removeLastObject];
            scanned++;
            NSString *vn = NSStringFromClass(v.class);
            if (YTNicoStringContainsAny(vn, needles)) return window;
            for (UIView *sub in v.subviews) [stack addObject:sub];
        }
    }
    return nil;
}

static UIWindow *YTNicoKeyWindow(void) {
    UIWindow *best = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (ws.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) return w;
                if (!best && !w.hidden && w.alpha > 0.01) best = w;
            }
        }
    }
    if (!best) best = UIApplication.sharedApplication.keyWindow;
    if (!best) {
        for (UIWindow *w in UIApplication.sharedApplication.windows) {
            if (!w.hidden && w.alpha > 0.01) { best = w; break; }
        }
    }
    return best;
}

static CGRect YTNicoDefaultPiPOverlayFrame(void) {
    CGRect screen = UIScreen.mainScreen.bounds;
    CGFloat width = MIN(CGRectGetWidth(screen) - 24.0, 310.0);
    CGFloat height = width * 9.0 / 16.0;
    CGFloat x = CGRectGetWidth(screen) - width - 12.0;
    CGFloat y = CGRectGetHeight(screen) - height - 110.0;
    if (y < 80.0) y = 80.0;
    return CGRectMake(x, y, width, height);
}

static void YTNicoPiPAttachOverlay(void) {
    if (!gYTNicoPiPActive || !SettingsManager.shared.enabled) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *pipWindow = YTNicoFindPiPWindow();
        if (pipWindow) {
            if (!gYTNicoPiPOverlayView || gYTNicoPiPOverlayView.superview != pipWindow) {
                [gYTNicoPiPOverlayView removeFromSuperview];
                gYTNicoPiPOverlayView = [[UIView alloc] initWithFrame:pipWindow.bounds];
                gYTNicoPiPOverlayView.userInteractionEnabled = NO;
                gYTNicoPiPOverlayView.backgroundColor = UIColor.clearColor;
                gYTNicoPiPOverlayView.clipsToBounds = YES;
                gYTNicoPiPOverlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [pipWindow addSubview:gYTNicoPiPOverlayView];
                [[DebugInspector shared] important:@"PiP comment overlay attached to PiP-like window %@", NSStringFromClass(pipWindow.class)];
            }
            gYTNicoPiPOverlayView.frame = pipWindow.bounds;
            return;
        }

        if (!gYTNicoPiPOverlayWindow) {
            UIWindow *base = YTNicoKeyWindow();
            if (!base) return;
            if (@available(iOS 13.0, *)) {
                gYTNicoPiPOverlayWindow = [[UIWindow alloc] initWithWindowScene:base.windowScene];
            } else {
                gYTNicoPiPOverlayWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
            }
            gYTNicoPiPOverlayWindow.windowLevel = UIWindowLevelAlert + 20.0;
            gYTNicoPiPOverlayWindow.backgroundColor = UIColor.clearColor;
            gYTNicoPiPOverlayWindow.userInteractionEnabled = NO;
            gYTNicoPiPOverlayWindow.hidden = NO;
            gYTNicoPiPOverlayWindow.rootViewController = [UIViewController new];
            gYTNicoPiPOverlayWindow.rootViewController.view.backgroundColor = UIColor.clearColor;

            gYTNicoPiPOverlayView = [[UIView alloc] initWithFrame:YTNicoDefaultPiPOverlayFrame()];
            gYTNicoPiPOverlayView.userInteractionEnabled = NO;
            gYTNicoPiPOverlayView.backgroundColor = UIColor.clearColor;
            gYTNicoPiPOverlayView.clipsToBounds = YES;
            gYTNicoPiPOverlayView.layer.cornerRadius = 10.0;
            [gYTNicoPiPOverlayWindow.rootViewController.view addSubview:gYTNicoPiPOverlayView];
            [[DebugInspector shared] important:@"PiP comment overlay fallback window created"];
        }
        gYTNicoPiPOverlayWindow.frame = UIScreen.mainScreen.bounds;
        gYTNicoPiPOverlayView.frame = YTNicoDefaultPiPOverlayFrame();
        gYTNicoPiPOverlayWindow.hidden = NO;
    });
}

static void YTNicoPiPDetachOverlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [gYTNicoPiPOverlayView removeFromSuperview];
        gYTNicoPiPOverlayView = nil;
        gYTNicoPiPOverlayWindow.hidden = YES;
        gYTNicoPiPOverlayWindow = nil;
        gYTNicoPiPLaneCursor = 0;
        [gYTNicoPiPSeenIds removeAllObjects];
    });
}

static void YTNicoPiPSetActive(BOOL active, NSString *reason) {
    gYTNicoPiPActive = active;
    [[DebugInspector shared] important:@"PiP comment mode %@ reason=%@", active ? @"ON" : @"OFF", reason ?: @"unknown"];
    if (active) {
        [SettingsManager.shared setEnabled:YES];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"com.example.ytnico.settings.changed" object:nil];
        YTNicoPiPAttachOverlay();
    } else {
        YTNicoPiPDetachOverlay();
    }
}

static void YTNicoPiPEmitComment(NSString *author, NSString *text, NSString *messageId) {
    if (!gYTNicoPiPActive || !SettingsManager.shared.enabled || text.length == 0) return;
    if ([author isEqualToString:@"YTNico"]) return;
    if (!gYTNicoPiPSeenIds) gYTNicoPiPSeenIds = [NSMutableSet set];
    NSString *key = messageId.length ? messageId : [NSString stringWithFormat:@"%@|%@", author ?: @"", text ?: @""];
    if ([gYTNicoPiPSeenIds containsObject:key]) return;
    [gYTNicoPiPSeenIds addObject:key];
    if (gYTNicoPiPSeenIds.count > 240) [gYTNicoPiPSeenIds removeAllObjects];

    YTNicoPiPAttachOverlay();
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *view = gYTNicoPiPOverlayView;
        if (!view) return;
        NSString *display = SettingsManager.shared.showAuthorName && author.length ? [NSString stringWithFormat:@"%@: %@", author, text] : text;
        CGFloat fontSize = MAX(10.0, MIN(18.0, SettingsManager.shared.fontSize * 0.72));
        UIFont *font = [UIFont boldSystemFontOfSize:fontSize];
        CGSize max = CGSizeMake(1000, fontSize * 1.6);
        CGRect rect = [display boundingRectWithSize:max options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: font} context:nil];
        CGFloat width = MIN(MAX(70.0, ceil(rect.size.width) + 18.0), view.bounds.size.width * 1.5);
        CGFloat height = ceil(fontSize * 1.55);
        NSInteger lanes = MAX(2, (NSInteger)floor(MAX(1.0, view.bounds.size.height - 6.0) / MAX(16.0, height)));
        NSUInteger lane = gYTNicoPiPLaneCursor++ % (NSUInteger)lanes;
        CGFloat y = 3.0 + lane * height;

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(view.bounds.size.width + 8.0, y, width, height)];
        label.text = display;
        label.font = font;
        label.textColor = UIColor.whiteColor;
        label.backgroundColor = UIColor.clearColor;
        label.layer.shadowColor = UIColor.blackColor.CGColor;
        label.layer.shadowOpacity = 0.95;
        label.layer.shadowRadius = 1.2;
        label.layer.shadowOffset = CGSizeMake(1, 1);
        label.numberOfLines = 1;
        label.adjustsFontSizeToFitWidth = NO;
        [view addSubview:label];

        NSTimeInterval duration = MAX(4.2, MIN(7.5, 4.8 + (double)display.length * 0.018));
        [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveLinear animations:^{
            CGRect f = label.frame;
            f.origin.x = -width - 12.0;
            label.frame = f;
        } completion:^(__unused BOOL finished) {
            [label removeFromSuperview];
        }];
    });
}

%hook AVPictureInPictureController

- (void)startPictureInPicture {
    %orig;
    YTNicoPiPSetActive(YES, @"AVPictureInPictureController startPictureInPicture");
}

- (void)stopPictureInPicture {
    YTNicoPiPSetActive(NO, @"AVPictureInPictureController stopPictureInPicture");
    %orig;
}

%end

%hook YouTubeChatAdapter

+ (void)emitNowAuthor:(NSString *)author text:(NSString *)text messageId:(NSString *)messageId {
    %orig(author, text, messageId);
    YTNicoPiPEmitComment(author, text, messageId);
}

+ (void)broadcastAuthor:(NSString *)author text:(NSString *)text messageId:(NSString *)messageId {
    %orig(author, text, messageId);
    YTNicoPiPEmitComment(author, text, messageId);
}

%end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        gYTNicoPiPSeenIds = [NSMutableSet set];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            if (gYTNicoPiPActive) YTNicoPiPAttachOverlay();
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            if (gYTNicoPiPActive) YTNicoPiPAttachOverlay();
        }];
    });
}
