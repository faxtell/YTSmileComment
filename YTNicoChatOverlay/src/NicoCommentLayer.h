#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
@class NicoChatMessage;

@interface NicoCommentLayer : CATextLayer
- (void)configureWithMessage:(NicoChatMessage *)message fontSize:(CGFloat)fontSize opacity:(CGFloat)opacity;
@end
