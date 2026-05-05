#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "YTNicoSettingsViewController.h"
#import "DebugInspector.h"

@interface YTNicoTutorialViewController : UIViewController
+ (BOOL)shouldShowTutorial;
+ (void)markTutorialShown;
@end

@interface YTNicoCategoryViewController : UIViewController
@property (nonatomic, copy) NSString *categoryKind;
@end

static const void *kYTNicoTutorialTriedKey = &kYTNicoTutorialTriedKey;
static const NSInteger kYTNicoTutorialButtonTag = 950531;

static UIStackView *YTNicoFindFirstStack(UIView *view) {
    if ([view isKindOfClass:UIStackView.class]) return (UIStackView *)view;
    for (UIView *sub in view.subviews) {
        UIStackView *found = YTNicoFindFirstStack(sub);
        if (found) return found;
    }
    return nil;
}

static UIButton *YTNicoTutorialButton(void) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = kYTNicoTutorialButtonTag;
    button.backgroundColor = UIColor.secondarySystemBackgroundColor;
    button.layer.cornerRadius = 14.0;
    button.layer.masksToBounds = YES;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.contentEdgeInsets = UIEdgeInsetsMake(10, 12, 10, 12);
    NSString *title = @"🧭 チュートリアルを見る\n使い方をもう一度表示";
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:title];
    [attr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold] range:NSMakeRange(0, @"🧭 チュートリアルを見る".length)];
    NSRange sub = [title rangeOfString:@"使い方をもう一度表示"];
    [attr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular] range:sub];
    [attr addAttribute:NSForegroundColorAttributeName value:UIColor.secondaryLabelColor range:sub];
    button.titleLabel.numberOfLines = 2;
    [button setAttributedTitle:attr forState:UIControlStateNormal];
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:52].active = YES;
    return button;
}

%hook YTNicoSettingsViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if ([objc_getAssociatedObject(self, kYTNicoTutorialTriedKey) boolValue]) return;
    objc_setAssociatedObject(self, kYTNicoTutorialTriedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (![YTNicoTutorialViewController shouldShowTutorial]) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.presentedViewController) return;
        YTNicoTutorialViewController *vc = [YTNicoTutorialViewController new];
        vc.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:vc animated:YES completion:nil];
        [[DebugInspector shared] log:@"tutorial presented first launch"];
    });
}

%end

%hook YTNicoCategoryViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (![self.categoryKind isEqualToString:@"tools"]) return;
    UIStackView *stack = YTNicoFindFirstStack(self.view);
    if (!stack || [stack viewWithTag:kYTNicoTutorialButtonTag]) return;
    UIButton *button = YTNicoTutorialButton();
    [button addTarget:self action:@selector(ytnico_showTutorialAgain) forControlEvents:UIControlEventTouchUpInside];
    [stack insertArrangedSubview:button atIndex:MIN((NSUInteger)1, stack.arrangedSubviews.count)];
}

%new
- (void)ytnico_showTutorialAgain {
    YTNicoTutorialViewController *vc = [YTNicoTutorialViewController new];
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:vc animated:YES completion:nil];
}

%end
