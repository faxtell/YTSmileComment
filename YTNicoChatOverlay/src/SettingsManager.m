#import "SettingsManager.h"

NSString * const kYTNicoSettingsChangedNotification = @"com.example.ytnico.settings.changed";
static NSString * const kDomain = @"com.example.yt-nico-chat-overlay";
static NSString * const kDidMigrateMockDefaultOff = @"didMigrateMockDefaultOff.v2";

@implementation SettingsManager {
    NSUserDefaults *_defaults;
}

+ (instancetype)shared { static SettingsManager *s; static dispatch_once_t once; dispatch_once(&once, ^{ s = [SettingsManager new]; }); return s; }
- (instancetype)init {
    if ((self=[super init])) {
        _defaults = [[NSUserDefaults alloc] initWithSuiteName:kDomain] ?: NSUserDefaults.standardUserDefaults;
        if (![_defaults boolForKey:kDidMigrateMockDefaultOff]) {
            [_defaults setBool:NO forKey:@"mockMode"];
            [_defaults setBool:YES forKey:kDidMigrateMockDefaultOff];
            [_defaults synchronize];
        }
    }
    return self;
}

- (void)notifyChanged { [_defaults synchronize]; [[NSNotificationCenter defaultCenter] postNotificationName:kYTNicoSettingsChangedNotification object:nil]; }
- (void)reload { [self notifyChanged]; }

- (BOOL)enabled { return [_defaults objectForKey:@"enabled"] ? [_defaults boolForKey:@"enabled"] : YES; }
- (CGFloat)fontSize { return [_defaults objectForKey:@"fontSize"] ? [_defaults doubleForKey:@"fontSize"] : 18.0; }
- (CGFloat)opacity { return [_defaults objectForKey:@"opacity"] ? [_defaults doubleForKey:@"opacity"] : 0.9; }
- (CGFloat)speed { return [_defaults objectForKey:@"speed"] ? [_defaults doubleForKey:@"speed"] : 90.0; }
- (NSInteger)maxLines { return [_defaults objectForKey:@"maxLines"] ? [_defaults integerForKey:@"maxLines"] : 8; }
- (BOOL)showAuthorName { return [_defaults objectForKey:@"showAuthorName"] ? [_defaults boolForKey:@"showAuthorName"] : NO; }
- (BOOL)enableShadow { return [_defaults objectForKey:@"enableShadow"] ? [_defaults boolForKey:@"enableShadow"] : YES; }
- (BOOL)enableOutline { return [_defaults objectForKey:@"enableOutline"] ? [_defaults boolForKey:@"enableOutline"] : NO; }
- (NSArray<NSString *> *)blockWords { NSArray *v = [_defaults arrayForKey:@"blockWords"]; return v ?: @[]; }
- (BOOL)mockMode { return [_defaults objectForKey:@"mockMode"] ? [_defaults boolForKey:@"mockMode"] : NO; }
- (BOOL)debugLogging { return [_defaults objectForKey:@"debugLogging"] ? [_defaults boolForKey:@"debugLogging"] : NO; }
- (CGFloat)commentDensity { return [_defaults objectForKey:@"commentDensity"] ? [_defaults doubleForKey:@"commentDensity"] : 0.72; }
- (CGFloat)longevity { return [_defaults objectForKey:@"longevity"] ? [_defaults doubleForKey:@"longevity"] : 0.78; }
- (BOOL)syncReplayToTimestamp { return [_defaults objectForKey:@"syncReplayToTimestamp"] ? [_defaults boolForKey:@"syncReplayToTimestamp"] : YES; }
- (BOOL)preferLiveChat { return [_defaults objectForKey:@"preferLiveChat"] ? [_defaults boolForKey:@"preferLiveChat"] : YES; }
- (BOOL)autoFetch { return [_defaults objectForKey:@"autoFetch"] ? [_defaults boolForKey:@"autoFetch"] : YES; }

- (void)setEnabled:(BOOL)value { [_defaults setBool:value forKey:@"enabled"]; [self notifyChanged]; }
- (void)setFontSize:(CGFloat)value { [_defaults setDouble:MAX(10.0, MIN(36.0, value)) forKey:@"fontSize"]; [self notifyChanged]; }
- (void)setOpacity:(CGFloat)value { [_defaults setDouble:MAX(0.15, MIN(1.0, value)) forKey:@"opacity"]; [self notifyChanged]; }
- (void)setSpeed:(CGFloat)value { [_defaults setDouble:MAX(35.0, MIN(260.0, value)) forKey:@"speed"]; [self notifyChanged]; }
- (void)setMaxLines:(NSInteger)value { [_defaults setInteger:MAX(1, MIN(20, value)) forKey:@"maxLines"]; [self notifyChanged]; }
- (void)setShowAuthorName:(BOOL)value { [_defaults setBool:value forKey:@"showAuthorName"]; [self notifyChanged]; }
- (void)setEnableShadow:(BOOL)value { [_defaults setBool:value forKey:@"enableShadow"]; [self notifyChanged]; }
- (void)setEnableOutline:(BOOL)value { [_defaults setBool:value forKey:@"enableOutline"]; [self notifyChanged]; }
- (void)setBlockWords:(NSArray<NSString *> *)value { [_defaults setObject:value ?: @[] forKey:@"blockWords"]; [self notifyChanged]; }
- (void)setMockMode:(BOOL)value { [_defaults setBool:value forKey:@"mockMode"]; [self notifyChanged]; }
- (void)setDebugLogging:(BOOL)value { [_defaults setBool:value forKey:@"debugLogging"]; [self notifyChanged]; }
- (void)setCommentDensity:(CGFloat)value { [_defaults setDouble:MAX(0.1, MIN(1.0, value)) forKey:@"commentDensity"]; [self notifyChanged]; }
- (void)setLongevity:(CGFloat)value { [_defaults setDouble:MAX(0.1, MIN(1.0, value)) forKey:@"longevity"]; [self notifyChanged]; }
- (void)setSyncReplayToTimestamp:(BOOL)value { [_defaults setBool:value forKey:@"syncReplayToTimestamp"]; [self notifyChanged]; }
- (void)setPreferLiveChat:(BOOL)value { [_defaults setBool:value forKey:@"preferLiveChat"]; [self notifyChanged]; }
- (void)setAutoFetch:(BOOL)value { [_defaults setBool:value forKey:@"autoFetch"]; [self notifyChanged]; }
@end
