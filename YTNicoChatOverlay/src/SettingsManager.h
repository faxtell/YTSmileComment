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
- (CGFloat)outlineStrength;
- (BOOL)niconicoMode;
- (BOOL)adaptiveFontSize;
- (CGFloat)scrollDuration;
- (NSArray<NSString *> *)blockWords;
- (BOOL)mockMode;
- (BOOL)debugLogging;
- (CGFloat)commentDensity;
- (CGFloat)longevity;
- (BOOL)syncReplayToTimestamp;
- (BOOL)preferLiveChat;
- (BOOL)autoFetch;
- (NSInteger)maxFetchComments;

- (void)setEnabled:(BOOL)value;
- (void)setFontSize:(CGFloat)value;
- (void)setOpacity:(CGFloat)value;
- (void)setSpeed:(CGFloat)value;
- (void)setMaxLines:(NSInteger)value;
- (void)setShowAuthorName:(BOOL)value;
- (void)setEnableShadow:(BOOL)value;
- (void)setEnableOutline:(BOOL)value;
- (void)setOutlineStrength:(CGFloat)value;
- (void)setNiconicoMode:(BOOL)value;
- (void)setAdaptiveFontSize:(BOOL)value;
- (void)setScrollDuration:(CGFloat)value;
- (void)setBlockWords:(NSArray<NSString *> *)value;
- (void)setMockMode:(BOOL)value;
- (void)setDebugLogging:(BOOL)value;
- (void)setCommentDensity:(CGFloat)value;
- (void)setLongevity:(CGFloat)value;
- (void)setSyncReplayToTimestamp:(BOOL)value;
- (void)setPreferLiveChat:(BOOL)value;
- (void)setAutoFetch:(BOOL)value;
- (void)setMaxFetchComments:(NSInteger)value;
- (void)applyNiconicoPreset;
- (void)reload;
@end

FOUNDATION_EXTERN NSString * const kYTNicoSettingsChangedNotification;

NS_ASSUME_NONNULL_END
