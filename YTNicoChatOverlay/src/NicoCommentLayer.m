#import "NicoCommentLayer.h"
#import "NicoChatMessage.h"
#import "SettingsManager.h"

@implementation NicoCommentLayer

static CGFloat YTNicoEffectiveCommentOpacity(NSString *text, CGFloat configuredOpacity, SettingsManager *settings) {
    CGFloat op = MAX(0.15, MIN(1.0, configuredOpacity));
    if (!settings.niconicoMode) return op;

    // Niconico-style comments are basically solid, but very long comments can feel too heavy on video.
    // Treat the user's opacity setting as an upper limit, then gently adjust by text length.
    CGFloat base = MAX(0.92, op);
    NSUInteger len = text.length;
    if (len >= 80) base -= 0.08;
    else if (len >= 45) base -= 0.04;
    else if (len <= 8) base = MIN(1.0, base + 0.03);
    return MAX(0.84, MIN(1.0, base));
}

- (void)configureWithMessage:(NicoChatMessage *)message fontSize:(CGFloat)fontSize opacity:(CGFloat)opacity {
    NSString *text = message.text ?: @"";
    SettingsManager *settings = [SettingsManager shared];
    if (settings.showAuthorName && message.authorName.length > 0) {
        text = [NSString stringWithFormat:@"%@: %@", message.authorName, text];
    }

    CGFloat effectiveOpacity = YTNicoEffectiveCommentOpacity(text, opacity, settings);
    UIColor *fillColor = (message.colorHint ?: UIColor.whiteColor);
    if (settings.niconicoMode) {
        fillColor = [fillColor colorWithAlphaComponent:1.0];
    } else {
        fillColor = [fillColor colorWithAlphaComponent:effectiveOpacity];
    }

    UIFont *font = [UIFont boldSystemFontOfSize:fontSize];
    CGFloat strokeWidth = settings.enableOutline ? MAX(0.0, settings.outlineStrength) : 0.0;
    NSMutableDictionary *attrs = [@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: fillColor
    } mutableCopy];

    if (strokeWidth > 0.01) {
        attrs[NSStrokeColorAttributeName] = [UIColor.blackColor colorWithAlphaComponent:settings.niconicoMode ? 0.96 : effectiveOpacity];
        attrs[NSStrokeWidthAttributeName] = @(-strokeWidth);
    }

    self.string = [[NSAttributedString alloc] initWithString:text attributes:attrs];
    self.fontSize = fontSize;
    self.contentsScale = UIScreen.mainScreen.scale;
    self.foregroundColor = fillColor.CGColor;
    self.opacity = (float)effectiveOpacity;
    self.alignmentMode = kCAAlignmentLeft;
    self.truncationMode = kCATruncationNone;
    self.wrapped = NO;
    self.masksToBounds = NO;

    if (settings.enableShadow) {
        self.shadowColor = UIColor.blackColor.CGColor;
        self.shadowOpacity = settings.niconicoMode ? 0.68 : 0.9;
        self.shadowRadius = settings.niconicoMode ? 0.85 : 2.0;
        self.shadowOffset = settings.niconicoMode ? CGSizeMake(1.0, 1.0) : CGSizeMake(1.0, 1.0);
    } else {
        self.shadowOpacity = 0.0;
    }
}
@end
