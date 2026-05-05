#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "YTNicoSettingsViewController.h"
#import "SettingsManager.h"

static const void *kYTNicoFetchValueLabelKey = &kYTNicoFetchValueLabelKey;
static const void *kYTNicoFetchProgressKey = &kYTNicoFetchProgressKey;

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
    objc_setAssociatedObject(slider, kYTNicoFetchValueLabelKey, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slider, kYTNicoFetchProgressKey, progress, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    value.text = [NSString stringWithFormat:@"%.0f 件", slider.value];
    progress.progress = (slider.value - 100.0f) / 2900.0f;
    [slider addTarget:self action:@selector(ytnico_fetchCountSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [stack insertArrangedSubview:card atIndex:MIN((NSUInteger)4, stack.arrangedSubviews.count)];
}

%new
- (void)ytnico_fetchCountSliderChanged:(UISlider *)slider {
    UILabel *value = objc_getAssociatedObject(slider, kYTNicoFetchValueLabelKey);
    UIProgressView *progress = objc_getAssociatedObject(slider, kYTNicoFetchProgressKey);
    [SettingsManager.shared setMaxFetchComments:(NSInteger)roundf(slider.value)];
    value.text = [NSString stringWithFormat:@"%.0f 件", slider.value];
    progress.progress = (slider.value - 100.0f) / 2900.0f;
}
%end
