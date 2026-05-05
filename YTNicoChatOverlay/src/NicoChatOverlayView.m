#import "NicoChatOverlayView.h"
#import "NicoCommentLayer.h"
#import "NicoChatMessage.h"
#import "SettingsManager.h"

@interface NicoChatOverlayView ()
@property (nonatomic, strong) NSMutableArray<NSNumber *> *laneAvailableAt;
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
    NSInteger expected = MAX(1, [SettingsManager shared].maxLines);
    if (self.laneAvailableAt.count != expected) {
        [self resetLanes];
    }
}

- (void)resetLanes {
    NSInteger maxLines = MAX(1, [SettingsManager shared].maxLines);
    self.laneAvailableAt = [NSMutableArray arrayWithCapacity:maxLines];
    for (NSInteger i = 0; i < maxLines; i++) {
        [self.laneAvailableAt addObject:@0];
    }
}

- (NSInteger)pickLaneForCommentWidth:(CGFloat)width speed:(CGFloat)speed {
    CFTimeInterval now = CACurrentMediaTime();
    NSInteger bestIndex = NSNotFound;
    CFTimeInterval bestAvailable = DBL_MAX;

    for (NSInteger i = 0; i < self.laneAvailableAt.count; i++) {
        CFTimeInterval availableAt = self.laneAvailableAt[i].doubleValue;
        if (availableAt <= now) {
            bestIndex = i;
            break;
        }
        if (availableAt < bestAvailable) {
            bestAvailable = availableAt;
            bestIndex = i;
        }
    }

    if (bestIndex == NSNotFound) return NSNotFound;

    // If all lanes are still busy, skip this comment instead of overlapping.
    if (self.laneAvailableAt[bestIndex].doubleValue > now) return NSNotFound;

    CGFloat gap = 44.0;
    CFTimeInterval delayUntilNextCanStart = (width + gap) / MAX(speed, 1.0);
    self.laneAvailableAt[bestIndex] = @(now + delayUntilNextCanStart);
    return bestIndex;
}

- (NSString *)renderedTextForMessage:(NicoChatMessage *)message {
    NSString *text = message.text ?: @"";
    if ([SettingsManager shared].showAuthorName && message.authorName.length > 0) {
        text = [NSString stringWithFormat:@"%@: %@", message.authorName, text];
    }
    return text;
}

- (void)enqueueMessage:(NicoChatMessage *)message {
    if (!message || ![SettingsManager shared].enabled || message.text.length == 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.bounds.size.width < 80 || self.bounds.size.height < 40) return;

        CGFloat font = [SettingsManager shared].fontSize;
        CGFloat laneHeight = font + 8.0;
        NSInteger maxLinesByHeight = MAX(1, (NSInteger)floor((self.bounds.size.height - 16.0) / MAX(laneHeight, 1.0)));
        NSInteger wantedLines = MAX(1, MIN([SettingsManager shared].maxLines, maxLinesByHeight));
        if (self.laneAvailableAt.count != wantedLines) {
            self.laneAvailableAt = [NSMutableArray arrayWithCapacity:wantedLines];
            for (NSInteger i = 0; i < wantedLines; i++) [self.laneAvailableAt addObject:@0];
        }

        NSString *renderedText = [self renderedTextForMessage:message];
        NSDictionary *attrs = @{NSFontAttributeName:[UIFont boldSystemFontOfSize:font]};
        CGFloat measured = [renderedText sizeWithAttributes:attrs].width + 40.0;
        CGFloat width = MIN(MAX(80.0, measured), self.bounds.size.width * 1.7);
        CGFloat speed = MAX(40.0, [SettingsManager shared].speed);
        NSInteger lane = [self pickLaneForCommentWidth:width speed:speed];
        if (lane == NSNotFound) return;

        CGFloat y = 8.0 + lane * laneHeight;
        if (y + laneHeight > self.bounds.size.height) return;

        NicoCommentLayer *layer = [NicoCommentLayer layer];
        [layer configureWithMessage:message fontSize:font opacity:[SettingsManager shared].opacity];
        layer.frame = CGRectMake(self.bounds.size.width + 8.0, y, width, laneHeight);
        [self.layer addSublayer:layer];

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

- (void)clearComments {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.layer.sublayers = nil;
        [self resetLanes];
    });
}
@end
