#import <UIKit/UIKit.h>
#import "YTNicoSettingsViewController.h"
#import "SettingsManager.h"

%hook YTNicoSettingsViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if ([objc_getAssociatedObject(self, @selector(ytnico_addFetchCountSlider)) boolValue]) return;
    objc_setAssociatedObject(self, @selector(ytnico_addFetchCountSlider), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIStackView *stack = nil;
    @try { stack = [self valueForKey:@"stack"]; } @catch (__unused NSException *e) {}
    if (![stack isKindOfClass:UIStackView.class]) return;
    SettingsManager *settings = SettingsManager.shared;
    UIView *card = [UIView new];
    card.backgroundColor = UIColor.secondarySystemBackgroundColor;
    card.layer.cornerRadius = 16.0;
    card.layer.masksToBounds = YES;
    UIStackView *box = [UIStackView new];
    box.axis = UILayoutConstraintAxisVertical;
    box.spacing = 8.0;
    box.layoutMargins = UIEdgeInsetsMake(14,14,14,14);
    box.layoutMarginsRelativeArrangement = YES;
    box.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:box];
    [NSLayoutConstraint activateConstraints:@[
        [box.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [box.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [box.topAnchor constraintEqualToAnchor:card.topAnchor],
        [box.bottomAnchor constraintEqualToAnchor:card.bottomAnchor]
    ]];
    UILabel *title = [UILabel new];
    title.text = @"取得コメント数";
    title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    UILabel *value = [UILabel new];
    value.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    value.textAlignment = NSTextAlignmentRight;
    UIStackView *top = [UIStackView new];
    top.axis = UILayoutConstraintAxisHorizontal;
    [top addArrangedSubview:title];
    [top addArrangedSubview:value];
    [box addArrangedSubview:top];
    UILabel *sub = [UILabel new];
    sub.text = @"多いほど途切れにくくなります。デフォルト500件、最大3000件です。";
    sub.numberOfLines = 0;
    sub.font = [UIFont systemFontOfSize:12];
    sub.textColor = UIColor.secondaryLabelColor;
    [box addArrangedSubview:sub];
    UIProgressView *progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    [box addArrangedSubview:progress];
    UISlider *slider = [UISlider new];
    slider.minimumValue = 100;
    slider.maximumValue = 3000;
    slider.value = settings.maxFetchComments;
    [box addArrangedSubview:slider];
    void (^update)(float) = ^(float v) { value.text = [NSString stringWithFormat:@"%.0f 件", v]; progress.progress = (v - 100.0f) / 2900.0f; };
    update(slider.value);
    [slider addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        UISlider *s = (UISlider *)action.sender;
        [settings setMaxFetchComments:(NSInteger)roundf(s.value)];
        update(s.value);
    }] forControlEvents:UIControlEventValueChanged];
    [stack insertArrangedSubview:card atIndex:MIN((NSUInteger)4, stack.arrangedSubviews.count)];
}
%end
