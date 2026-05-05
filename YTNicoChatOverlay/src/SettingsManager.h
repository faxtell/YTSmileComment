#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface SettingsManager : NSObject
+ (instancetype)shared;
- (BOOL)enabled;
- (CGFloat)fontSize;
- (CGFloat)opacity;
- (CGFloat)speed;
- (NSInteger)maxLines;
- (BOOL)showAuthorName;
- (BOOL)enableShadow;
- (BOOL)enableOutline;
- (NSArray<NSString *> *)blockWords;
- (BOOL)mockMode;
- (BOOL)debugLogging;
- (void)reload;
@end

FOUNDATION_EXTERN NSString * const kYTNicoSettingsChangedNotification;

NS_ASSUME_NONNULL_END
