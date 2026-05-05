#import "NicoCommentLayer.h"
#import "NicoChatMessage.h"
#import "SettingsManager.h"

@implementation NicoCommentLayer
- (void)configureWithMessage:(NicoChatMessage *)message fontSize:(CGFloat)fontSize opacity:(CGFloat)opacity {
    NSString *text = message.text ?: @"";
    SettingsManager *settings = [SettingsManager shared];
    if (settings.showAuthorName && message.authorName.length > 0) {
        text = [NSString stringWithFormat:@"%@: %@", message.authorName, text];
    }

    UIColor *fillColor = message.colorHint ?: UIColor.whiteColor;
    UIFont *font = [UIFont boldSystemFontOfSize:fontSize];
    CGFloat strokeWidth = settings.enableOutline ? MAX(0.0, settings.outlineStrength) : 0.0;
    NSMutableDictionary *attrs = [@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: fillColor
    } mutableCopy];

    if (strokeWidth > 0.01) {
        // Negative stroke width draws both fill and outline. This is closer to Niconico's white text + black edge.
        attrs[NSStrokeColorAttributeName] = UIColor.blackColor;
        attrs[NSStrokeWidthAttributeName] = @(-strokeWidth);
    }

    self.string = [[NSAttributedString alloc] initWithString:text attributes:attrs];
    self.fontSize = fontSize;
    self.contentsScale = UIScreen.mainScreen.scale;
    self.foregroundColor = fillColor.CGColor;
    self.opacity = (float)opacity;
    self.alignmentMode = kCAAlignmentLeft;
    self.truncationMode = kCATruncationNone;
    self.wrapped = NO;
    self.masksToBounds = NO;

    if (settings.enableShadow) {
        self.shadowColor = UIColor.blackColor.CGColor;
        self.shadowOpacity = settings.niconicoMode ? 0.75 : 0.9;
        self.shadowRadius = settings.niconicoMode ? 1.0 : 2.0;
        self.shadowOffset = settings.niconicoMode ? CGSizeMake(1.0, 1.0) : CGSizeMake(1.0, 1.0);
    } else {
        self.shadowOpacity = 0.0;
    }
}
@end
