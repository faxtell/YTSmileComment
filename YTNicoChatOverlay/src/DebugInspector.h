#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface DebugInspector : NSObject
+ (instancetype)shared;
- (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (void)important:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (NSArray<NSString *> *)recentLogs;
- (NSString *)recentLogText;
- (void)clearLogs;
- (void)dumpViewTreeFrom:(UIView *)view maxDepth:(NSInteger)maxDepth;
@end
NS_ASSUME_NONNULL_END
