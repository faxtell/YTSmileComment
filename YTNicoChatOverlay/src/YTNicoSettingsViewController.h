#import <UIKit/UIKit.h>

@interface YTNicoSettingsViewController : UIViewController
@property (nonatomic, copy) void (^displayTestHandler)(void);
@property (nonatomic, copy) void (^clipboardFetchHandler)(void);
@end
