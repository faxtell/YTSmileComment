#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface DebugInspector : NSObject
+ (instancetype)shared;
- (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (void)dumpViewTreeFrom:(UIView *)view maxDepth:(NSInteger)maxDepth;
@end
NS_ASSUME_NONNULL_END
