#import "NicoChatOverlayView.h"
#import "NicoCommentLayer.h"
#import "NicoChatMessage.h"
#import "SettingsManager.h"

@interface NicoChatOverlayView ()
@property (nonatomic, strong) NSMutableArray<NSDate *> *laneLastUsed;
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
- (void)layoutSubviews {
    [super layoutSubviews];
    self.clipsToBounds = YES;
    self.layer.masksToBounds = YES;
    [self resetLanes];
}
- (void)resetLanes {
    NSInteger maxLines = MAX(1, [SettingsManager shared].maxLines);
    self.laneLastUsed = [NSMutableArray arrayWithCapacity:maxLines];
    for (NSInteger i = 0; i < maxLines; i++) [self.laneLastUsed addObject:[NSDate dateWithTimeIntervalSince1970:0]];
}
- (NSInteger)pickLane {
    NSInteger index = 0; NSDate *oldest = self.laneLastUsed.firstObject ?: NSDate.distantPast;
    for (NSInteger i=1;i<self.laneLastUsed.count;i++) if ([self.laneLastUsed[i] compare:oldest] == NSOrderedAscending) { oldest = self.laneLastUsed[i]; index = i; }
    self.laneLastUsed[index] = NSDate.date; return index;
}
- (void)enqueueMessage:(NicoChatMessage *)message {
    if (!message || ![SettingsManager shared].enabled || message.text.length == 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        CGFloat font = [SettingsManager shared].fontSize;
        CGFloat laneHeight = font + 8.0;
        NSInteger lane = [self pickLane];
        CGFloat y = lane * laneHeight + 12.0;
        NicoCommentLayer *layer = [NicoCommentLayer layer];
        [layer configureWithMessage:message fontSize:font opacity:[SettingsManager shared].opacity];

        NSString *renderText = message.text ?: @"";
        if ([SettingsManager shared].showAuthorName && message.authorName.length > 0) {
            renderText = [NSString stringWithFormat:@"%@: %@", message.authorName, message.text ?: @""];
        }
        NSDictionary *attrs = @{NSFontAttributeName:[UIFont boldSystemFontOfSize:font]};
        CGFloat width = MIN(self.bounds.size.width * 1.2, [renderText sizeWithAttributes:attrs].width + 40.0);

        layer.frame = CGRectMake(self.bounds.size.width + 8.0, y, width, laneHeight);
        [self.layer addSublayer:layer];
        CGFloat speed = MAX(40.0, [SettingsManager shared].speed);
        NSTimeInterval duration = (self.bounds.size.width + width + 20.0) / speed;
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
- (void)clearComments { dispatch_async(dispatch_get_main_queue(), ^{ self.layer.sublayers = nil; }); }
@end
