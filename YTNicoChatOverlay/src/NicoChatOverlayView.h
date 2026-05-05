#import <UIKit/UIKit.h>
@class NicoChatMessage;

@interface NicoChatOverlayView : UIView
- (void)enqueueMessage:(NicoChatMessage *)message;
- (void)clearComments;
@end
