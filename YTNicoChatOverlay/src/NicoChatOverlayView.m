#import "NicoChatOverlayView.h"
#import "NicoCommentLayer.h"
#import "NicoChatMessage.h"
#import "SettingsManager.h"

@interface NicoChatOverlayView ()
@property (nonatomic, strong) NSMutableArray<NSDate *> *laneAvailableAt;
@end

@implementation NicoChatOverlayView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = YES;
        self.layer.masksToBounds = YES;
        [self resetLanes];
    }
    return self;
}
- (void)layoutSubviews { [super layoutSubviews]; self.clipsToBounds = YES; self.layer.masksToBounds = YES; [self resetLanes]; }
- (void)resetLanes {
    NSInteger maxLines = MAX(1, [SettingsManager shared].maxLines);
    self.laneAvailableAt = [NSMutableArray arrayWithCapacity:maxLines];
    for (NSInteger i=0;i<maxLines;i++) [self.laneAvailableAt addObject:[NSDate dateWithTimeIntervalSince1970:0]];
}
- (NSInteger)pickLaneForNow:(NSDate *)now delay:(NSTimeInterval *)delayOut {
    NSInteger idx = 0; NSDate *earliest = self.laneAvailableAt.firstObject ?: NSDate.distantPast;
    for (NSInteger i=1;i<self.laneAvailableAt.count;i++) if ([self.laneAvailableAt[i] compare:earliest] == NSOrderedAscending) { earliest = self.laneAvailableAt[i]; idx = i; }
    NSTimeInterval delay = MAX(0, [earliest timeIntervalSinceDate:now]);
    if (delayOut) *delayOut = delay;
    return idx;
}
- (void)enqueueMessage:(NicoChatMessage *)message {
    if (!message || ![SettingsManager shared].enabled || message.text.length == 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        CGFloat font = [SettingsManager shared].fontSize;
        CGFloat laneHeight = font + 8.0;
        NSString *renderText = message.text ?: @"";
        if ([SettingsManager shared].showAuthorName && message.authorName.length > 0) renderText = [NSString stringWithFormat:@"%@: %@", message.authorName, message.text ?: @""];
        NSDictionary *attrs = @{NSFontAttributeName:[UIFont boldSystemFontOfSize:font]};
        CGFloat width = MIN(self.bounds.size.width * 1.2, [renderText sizeWithAttributes:attrs].width + 40.0);
        CGFloat speed = MAX(40.0, [SettingsManager shared].speed);
        NSTimeInterval duration = (self.bounds.size.width + width + 20.0) / speed;

        NSDate *now = NSDate.date;
        NSTimeInterval delay = 0;
        NSInteger lane = [self pickLaneForNow:now delay:&delay];
        // same lane collision防止: 前コメントの尻尾が十分離れるまで待つ
        NSTimeInterval laneLock = MAX(0.5, (width + 24.0) / speed);
        self.laneAvailableAt[lane] = [now dateByAddingTimeInterval:delay + laneLock];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            CGFloat y = lane * laneHeight + 8.0;
            if (y + laneHeight > self.bounds.size.height) return;
            NicoCommentLayer *layer = [NicoCommentLayer layer];
            [layer configureWithMessage:message fontSize:font opacity:[SettingsManager shared].opacity];
            layer.frame = CGRectMake(self.bounds.size.width + 8.0, y, width, laneHeight);
            [self.layer addSublayer:layer];
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
    });
}
- (void)clearComments { dispatch_async(dispatch_get_main_queue(), ^{ self.layer.sublayers = nil; }); }
@end
