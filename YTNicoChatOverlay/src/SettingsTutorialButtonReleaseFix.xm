#import <UIKit/UIKit.h>

@interface YTNicoTutorialViewController : UIViewController
@end

@interface YTNicoCategoryViewController : UIViewController
@end

static NSString *YTNicoReleaseButtonText(UIView *view) {
    NSMutableString *out = [NSMutableString string];
    if ([view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        NSString *title = [button titleForState:UIControlStateNormal] ?: button.currentTitle ?: @"";
        if (title.length) [out appendString:title];
        NSString *attr = button.currentAttributedTitle.string ?: @"";
        if (attr.length) [out appendString:attr];
    }
    if ([view isKindOfClass:UILabel.class]) {
        NSString *text = ((UILabel *)view).text ?: @"";
        if (text.length) [out appendString:text];
    }
    for (UIView *sub in view.subviews) {
        NSString *text = YTNicoReleaseButtonText(sub);
        if (text.length) [out appendString:text];
    }
    return out;
}

%hook YTNicoCategoryViewController

- (void)buttonTapped:(UIButton *)button {
    NSString *text = YTNicoReleaseButtonText(button);
    if ([text rangeOfString:@"使い方を見る"].location != NSNotFound ||
        [text rangeOfString:@"チュートリアル"].location != NSNotFound) {
        YTNicoTutorialViewController *vc = [YTNicoTutorialViewController new];
        vc.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:vc animated:YES completion:nil];
        return;
    }
    %orig(button);
}

%end
