#import <UIKit/UIKit.h>

@interface YTNicoSettingsViewController : UIViewController
@end

static const NSInteger kYTNicoBrandHeaderTag = 962101;
static const NSInteger kYTNicoTopReportButtonTag = 962102;

static UIStackView *YTNicoFindFirstStackForBranding(UIView *view) {
    if ([view isKindOfClass:UIStackView.class]) return (UIStackView *)view;
    for (UIView *sub in view.subviews) {
        UIStackView *found = YTNicoFindFirstStackForBranding(sub);
        if (found) return found;
    }
    return nil;
}

static NSString *YTNicoTextFromViewForBranding(UIView *view) {
    NSMutableString *out = [NSMutableString string];
    if ([view isKindOfClass:UILabel.class]) {
        NSString *t = ((UILabel *)view).text ?: @"";
        if (t.length) [out appendFormat:@" %@", t];
    }
    if ([view isKindOfClass:UIButton.class]) {
        UIButton *b = (UIButton *)view;
        NSString *t = [b titleForState:UIControlStateNormal] ?: b.currentTitle ?: @"";
        if (t.length) [out appendFormat:@" %@", t];
        NSString *at = b.currentAttributedTitle.string ?: @"";
        if (at.length) [out appendFormat:@" %@", at];
    }
    NSString *a = view.accessibilityLabel ?: @"";
    if (a.length) [out appendFormat:@" %@", a];
    for (UIView *sub in view.subviews) {
        NSString *s = YTNicoTextFromViewForBranding(sub);
        if (s.length) [out appendString:s];
    }
    return out;
}

static UIView *YTNicoBrandHeader(void) {
    UIView *card = [UIView new];
    card.tag = kYTNicoBrandHeaderTag;
    card.backgroundColor = UIColor.clearColor;

    UIStackView *box = [UIStackView new];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    box.axis = UILayoutConstraintAxisVertical;
    box.alignment = UIStackViewAlignmentCenter;
    box.spacing = 2.0;
    box.layoutMargins = UIEdgeInsetsMake(2, 0, 8, 0);
    box.layoutMarginsRelativeArrangement = YES;
    [card addSubview:box];

    UILabel *shark = [UILabel new];
    shark.text = @"🦈";
    shark.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    shark.textAlignment = NSTextAlignmentCenter;
    [box addArrangedSubview:shark];

    UILabel *version = [UILabel new];
    version.text = @"0.9.1(2026.05)";
    version.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    version.textColor = UIColor.secondaryLabelColor;
    version.textAlignment = NSTextAlignmentCenter;
    [box addArrangedSubview:version];

    [NSLayoutConstraint activateConstraints:@[
        [box.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [box.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [box.topAnchor constraintEqualToAnchor:card.topAnchor],
        [box.bottomAnchor constraintEqualToAnchor:card.bottomAnchor]
    ]];
    return card;
}

static UIButton *YTNicoTopReportButton(void) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = kYTNicoTopReportButtonTag;
    button.backgroundColor = UIColor.secondarySystemBackgroundColor;
    button.layer.cornerRadius = 14.0;
    button.layer.masksToBounds = YES;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.contentEdgeInsets = UIEdgeInsetsMake(9, 12, 9, 12);
    button.accessibilityLabel = @"不具合を報告";

    NSString *title = @"🐞 不具合を報告\n開発者へDMで報告";
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:title];
    [attr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold] range:NSMakeRange(0, @"🐞 不具合を報告".length)];
    NSRange sub = [title rangeOfString:@"開発者へDMで報告"];
    [attr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular] range:sub];
    [attr addAttribute:NSForegroundColorAttributeName value:UIColor.secondaryLabelColor range:sub];
    button.titleLabel.numberOfLines = 2;
    [button setAttributedTitle:attr forState:UIControlStateNormal];
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:45].active = YES;
    return button;
}

%hook YTNicoSettingsViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UIStackView *stack = YTNicoFindFirstStackForBranding(self.view);
    if (!stack) return;

    if (![stack viewWithTag:kYTNicoBrandHeaderTag]) {
        [stack insertArrangedSubview:YTNicoBrandHeader() atIndex:0];
    }

    if ([stack viewWithTag:kYTNicoTopReportButtonTag]) return;

    NSUInteger insertIndex = NSNotFound;
    for (NSUInteger i = 0; i < stack.arrangedSubviews.count; i++) {
        UIView *v = stack.arrangedSubviews[i];
        NSString *text = YTNicoTextFromViewForBranding(v);
        if ([text rangeOfString:@"開発者"].location != NSNotFound || [text rangeOfString:@"sa_me_kun"].location != NSNotFound) {
            insertIndex = i + 1;
            break;
        }
    }
    if (insertIndex == NSNotFound) insertIndex = stack.arrangedSubviews.count;

    UIButton *report = YTNicoTopReportButton();
    [report addTarget:self action:@selector(ytnico_openTopReportIssue) forControlEvents:UIControlEventTouchUpInside];
    [stack insertArrangedSubview:report atIndex:MIN(insertIndex, stack.arrangedSubviews.count)];
}

%new
- (void)ytnico_openTopReportIssue {
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
