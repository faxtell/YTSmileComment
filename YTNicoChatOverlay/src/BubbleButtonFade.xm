#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "SettingsManager.h"
#import "DebugInspector.h"

static const void *kYTNicoBubbleFadeArmedKey = &kYTNicoBubbleFadeArmedKey;

static BOOL YTNicoIsBubbleButton(UIButton *button) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) return NO;
    if (![button isKindOfClass:UIButton.class]) return NO;
    NSString *title = [button titleForState:UIControlStateNormal] ?: @"";
    if (![title isEqualToString:@"💬"] && ![title isEqualToString:@"💭"]) return NO;
    CGRect f = button.frame;
    if (fabs(f.size.width - 44.0) > 8.0 || fabs(f.size.height - 44.0) > 8.0) return NO;
    if (![button.superview isKindOfClass:UIWindow.class]) return NO;
    return YES;
}

static CGFloat YTNicoBubbleIdleAlpha(UIButton *button) {
    NSString *title = [button titleForState:UIControlStateNormal] ?: @"";
    if ([title isEqualToString:@"💭"]) return 0.20;
    return 0.32;
}

static void YTNicoScheduleBubbleFade(UIButton *button) {
    if (!YTNicoIsBubbleButton(button)) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:button selector:@selector(ytnico_applyIdleBubbleFade) object:nil];
    [button performSelector:@selector(ytnico_applyIdleBubbleFade) withObject:nil afterDelay:3.0];
}

%hook UIButton

- (void)didMoveToSuperview {
    %orig;
    if (!YTNicoIsBubbleButton(self)) return;
    if (![objc_getAssociatedObject(self, kYTNicoBubbleFadeArmedKey) boolValue]) {
        objc_setAssociatedObject(self, kYTNicoBubbleFadeArmedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [[DebugInspector shared] log:@"bubble fade armed"];
    }
    YTNicoScheduleBubbleFade(self);
}

- (void)layoutSubviews {
    %orig;
    if (YTNicoIsBubbleButton(self)) YTNicoScheduleBubbleFade(self);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (YTNicoIsBubbleButton(self)) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(ytnico_applyIdleBubbleFade) object:nil];
        [UIView animateWithDuration:0.12 animations:^{ self.alpha = 0.96; }];
    }
    %orig(touches, event);
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    %orig(touches, event);
    if (YTNicoIsBubbleButton(self)) YTNicoScheduleBubbleFade(self);
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    %orig(touches, event);
    if (YTNicoIsBubbleButton(self)) YTNicoScheduleBubbleFade(self);
}

%new
- (void)ytnico_applyIdleBubbleFade {
    if (!YTNicoIsBubbleButton(self)) return;
    if (self.highlighted || self.tracking) {
        YTNicoScheduleBubbleFade(self);
        return;
    }
    CGFloat alpha = YTNicoBubbleIdleAlpha(self);
    [UIView animateWithDuration:0.35 animations:^{ self.alpha = alpha; }];
}

%end
