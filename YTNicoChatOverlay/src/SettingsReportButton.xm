#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface YTNicoCategoryViewController : UIViewController
@property (nonatomic, copy) NSString *categoryKind;
@end

static const NSInteger kYTNicoReportButtonTag = 951004;

static UIStackView *YTNicoFindFirstStack(UIView *view) {
    if ([view isKindOfClass:UIStackView.class]) return (UIStackView *)view;
    for (UIView *sub in view.subviews) {
        UIStackView *found = YTNicoFindFirstStack(sub);
        if (found) return found;
    }
    return nil;
}

static UIButton *YTNicoReportButton(void) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = kYTNicoReportButtonTag;
    button.backgroundColor = UIColor.secondarySystemBackgroundColor;
    button.layer.cornerRadius = 14.0;
    button.layer.masksToBounds = YES;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.contentEdgeInsets = UIEdgeInsetsMake(10, 12, 10, 12);
    NSString *title = @"🐞 不具合を報告\n開発者へDMで報告";
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:title];
    [attr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold] range:NSMakeRange(0, @"🐞 不具合を報告".length)];
    NSRange sub = [title rangeOfString:@"開発者へDMで報告"];
    [attr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular] range:sub];
    [attr addAttribute:NSForegroundColorAttributeName value:UIColor.secondaryLabelColor range:sub];
    button.titleLabel.numberOfLines = 2;
    [button setAttributedTitle:attr forState:UIControlStateNormal];
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:52].active = YES;
    return button;
}

%hook YTNicoCategoryViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (![self.categoryKind isEqualToString:@"tools"]) return;
    UIStackView *stack = YTNicoFindFirstStack(self.view);
    if (!stack || [stack viewWithTag:kYTNicoReportButtonTag]) return;
    UIButton *button = YTNicoReportButton();
    [button addTarget:self action:@selector(ytnico_reportBug) forControlEvents:UIControlEventTouchUpInside];
    [stack insertArrangedSubview:button atIndex:MIN((NSUInteger)2, stack.arrangedSubviews.count)];
}

%new
- (void)ytnico_reportBug {
    NSString *urlString = @"https://twitter.com/messages/compose?recipient_id=1678480958671163392";
    UIPasteboard.generalPasteboard.string = urlString;
    NSURL *url = [NSURL URLWithString:urlString];
    UIApplication *app = UIApplication.sharedApplication;
    if ([app respondsToSelector:@selector(openURL:options:completionHandler:)]) {
        [app openURL:url options:@{} completionHandler:nil];
    } else {
        [app openURL:url];
    }
}

%end
