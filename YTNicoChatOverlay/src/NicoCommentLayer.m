#import "NicoCommentLayer.h"
#import "NicoChatMessage.h"
#import "SettingsManager.h"

@implementation NicoCommentLayer
- (void)configureWithMessage:(NicoChatMessage *)message fontSize:(CGFloat)fontSize opacity:(CGFloat)opacity {
    NSString *text = message.text ?: @"";
    if ([SettingsManager shared].showAuthorName && message.authorName.length > 0) {
        text = [NSString stringWithFormat:@"%@: %@", message.authorName, text];
    }
    self.string = text;
    self.fontSize = fontSize;
    self.contentsScale = UIScreen.mainScreen.scale;
    self.foregroundColor = (message.colorHint ?: UIColor.whiteColor).CGColor;
    self.opacity = (float)opacity;
    self.alignmentMode = kCAAlignmentLeft;
    self.truncationMode = kCATruncationEnd;
    self.wrapped = NO;
    if ([SettingsManager shared].enableShadow) {
        self.shadowColor = UIColor.blackColor.CGColor;
        self.shadowOpacity = 0.9;
        self.shadowRadius = 2.0;
        self.shadowOffset = CGSizeMake(1, 1);
    }
}
@end
