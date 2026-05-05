#import "NicoChatOverlayView.h"
#import "NicoCommentLayer.h"
#import "NicoChatMessage.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

@interface NicoChatOverlayView ()
@property (nonatomic, strong) NSMutableArray<NSNumber *> *laneAvailableAt;
@property (nonatomic, assign) NSInteger laneCount;
@property (nonatomic, assign) CGFloat laneHeight;
@property (nonatomic, assign) UIEdgeInsets contentInsets;
@property (nonatomic, assign) CGSize lastLayoutSize;
@end

@implementation NicoChatOverlayView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = YES;
        self.layer.masksToBounds = YES;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.laneAvailableAt = [NSMutableArray array];
        [self rebuildLanesForce:YES];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self rebuildLanesForce:NO];
}

- (CGFloat)effectiveFontSize {
    return MAX(10.0, [SettingsManager shared].fontSize);
}

- (CGFloat)effectiveLaneHeight {
    return ceil([self effectiveFontSize] + 9.0);
}

- (NSInteger)wantedLaneCountForBounds {
    CGFloat font = [self effectiveFontSize];
    CGFloat laneHeight = [self effectiveLaneHeight];
    CGFloat top = 6.0;
    CGFloat bottom = 6.0;
    if (@available(iOS 11.0, *)) {
        top += MAX(0.0, self.safeAreaInsets.top * 0.25);
        bottom += MAX(0.0, self.safeAreaInsets.bottom * 0.25);
    }

    CGFloat usableHeight = MAX(0.0, CGRectGetHeight(self.bounds) - top - bottom);
    NSInteger byHeight = MAX(1, (NSInteger)floor(usableHeight / MAX(laneHeight, 1.0)));
    NSInteger settingMax = MAX(1, [SettingsManager shared].maxLines);

    // Use the video area well, but respect user maxLines. If the overlay is tall and the user left maxLines low,
    // allow at least a few lanes so comments do not collapse into one row.
    NSInteger minimumPractical = CGRectGetHeight(self.bounds) >= font * 4.0 ? MIN(4, byHeight) : 1;
    NSInteger wanted = MIN(byHeight, MAX(settingMax, minimumPractical));
    return MAX(1, wanted);
}

- (void)rebuildLanesForce:(BOOL)force {
    CGSize size = self.bounds.size;
    CGFloat laneHeight = [self effectiveLaneHeight];
    NSInteger wanted = [self wantedLaneCountForBounds];
    CGFloat top = 6.0;
    CGFloat bottom = 6.0;
    if (@available(iOS 11.0, *)) {
        top += MAX(0.0, self.safeAreaInsets.top * 0.25);
        bottom += MAX(0.0, self.safeAreaInsets.bottom * 0.25);
    }

    BOOL sizeChanged = fabs(size.width - self.lastLayoutSize.width) > 1.0 || fabs(size.height - self.lastLayoutSize.height) > 1.0;
    BOOL changed = force || sizeChanged || wanted != self.laneCount || fabs(laneHeight - self.laneHeight) > 0.5;
    if (!changed && self.laneAvailableAt.count == wanted) return;

    self.lastLayoutSize = size;
    self.laneCount = wanted;
    self.laneHeight = laneHeight;
    self.contentInsets = UIEdgeInsetsMake(top, 0, bottom, 0);

    NSMutableArray<NSNumber *> *newLanes = [NSMutableArray arrayWithCapacity:wanted];
    CFTimeInterval now = CACurrentMediaTime();
    for (NSInteger i = 0; i < wanted; i++) {
        if (!force && i < self.laneAvailableAt.count) [newLanes addObject:self.laneAvailableAt[i]];
        else [newLanes addObject:@(now)];
    }
    self.laneAvailableAt = newLanes;
    [[DebugInspector shared] log:@"lanes rebuilt count=%ld height=%.1f bounds=%@", (long)wanted, laneHeight, NSStringFromCGRect(self.bounds)];
}

- (NSInteger)pickLaneForCommentWidth:(CGFloat)width speed:(CGFloat)speed {
    [self rebuildLanesForce:NO];
    if (self.laneAvailableAt.count == 0) return NSNotFound;

    CFTimeInterval now = CACurrentMediaTime();
    NSInteger bestIndex = 0;
    CFTimeInterval bestAvailable = DBL_MAX;
    NSMutableArray<NSNumber *> *freeLanes = [NSMutableArray array];

    for (NSInteger i = 0; i < self.laneAvailableAt.count; i++) {
        CFTimeInterval availableAt = self.laneAvailableAt[i].doubleValue;
        if (availableAt <= now) [freeLanes addObject:@(i)];
        if (availableAt < bestAvailable) {
            bestAvailable = availableAt;
            bestIndex = i;
        }
    }

    if (freeLanes.count > 0) {
        // Spread comments visually instead of always choosing lane 0.
        NSUInteger pick = arc4random_uniform((uint32_t)freeLanes.count);
        bestIndex = [freeLanes[pick] integerValue];
    }

    CGFloat gap = 42.0;
    CFTimeInterval nextAvailable = now + ((width + gap) / MAX(speed, 1.0));
    // If all lanes are busy, still choose the earliest lane but push its next-available time forward.
    CFTimeInterval laneCurrent = self.laneAvailableAt[bestIndex].doubleValue;
    if (laneCurrent > now) nextAvailable = laneCurrent + ((width + gap) / MAX(speed, 1.0));
    self.laneAvailableAt[bestIndex] = @(nextAvailable);
    return bestIndex;
}

- (NSString *)renderedTextForMessage:(NicoChatMessage *)message {
    NSString *text = message.text ?: @"";
    if ([SettingsManager shared].showAuthorName && message.authorName.length > 0) {
        text = [NSString stringWithFormat:@"%@: %@", message.authorName, text];
    }
    return text;
}

- (CGFloat)yForLane:(NSInteger)lane {
    CGFloat usableHeight = MAX(1.0, CGRectGetHeight(self.bounds) - self.contentInsets.top - self.contentInsets.bottom);
    CGFloat laneHeight = MAX(1.0, self.laneHeight);
    CGFloat y = self.contentInsets.top + lane * laneHeight;
    CGFloat maxY = self.contentInsets.top + usableHeight - laneHeight;
    return MIN(MAX(self.contentInsets.top, y), MAX(self.contentInsets.top, maxY));
}

- (void)enqueueMessage:(NicoChatMessage *)message {
    if (!message || ![SettingsManager shared].enabled || message.text.length == 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.bounds.size.width < 80 || self.bounds.size.height < 40) return;
        [self rebuildLanesForce:NO];

        CGFloat font = [self effectiveFontSize];
        CGFloat laneHeight = MAX(1.0, self.laneHeight);
        NSString *renderedText = [self renderedTextForMessage:message];
        NSDictionary *attrs = @{NSFontAttributeName:[UIFont boldSystemFontOfSize:font]};
        CGFloat measured = [renderedText sizeWithAttributes:attrs].width + 44.0;
        CGFloat width = MIN(MAX(84.0, measured), self.bounds.size.width * 1.8);
        CGFloat speed = MAX(40.0, [SettingsManager shared].speed);
        NSInteger lane = [self pickLaneForCommentWidth:width speed:speed];
        if (lane == NSNotFound) return;

        CGFloat y = [self yForLane:lane];
        NicoCommentLayer *layer = [NicoCommentLayer layer];
        [layer configureWithMessage:message fontSize:font opacity:[SettingsManager shared].opacity];
        layer.frame = CGRectMake(self.bounds.size.width + 8.0, y, width, laneHeight);
        layer.zPosition = 10 + lane;
        [self.layer addSublayer:layer];

        NSTimeInterval duration = (self.bounds.size.width + width + 20.0) / speed;
        [[DebugInspector shared] log:@"comment lane=%ld/%ld y=%.1f width=%.1f duration=%.1f text=%@", (long)lane, (long)self.laneCount, y, width, duration, renderedText];

        [CATransaction begin];
        [CATransaction setCompletionBlock:^{ [layer removeFromSuperlayer]; }];
        CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"position.x"];
        anim.fromValue = @(CGRectGetMidX(layer.frame));
        anim.toValue = @(-width / 2.0);
        anim.duration = duration;
        anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        layer.position = CGPointMake(-width/2.0, CGRectGetMidY(layer.frame));
        [layer addAnimation:anim forKey:@"nico.scroll"];
        [CATransaction commit];
    });
}

- (void)clearComments {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.layer.sublayers = nil;
        [self rebuildLanesForce:YES];
    });
}
@end
