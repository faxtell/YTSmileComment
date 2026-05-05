#import "SettingsManager.h"

NSString * const kYTNicoSettingsChangedNotification = @"com.example.ytnico.settings.changed";
static NSString * const kDomain = @"com.example.yt-nico-chat-overlay";
static NSString * const kDidMigrateMockDefaultOff = @"didMigrateMockDefaultOff.v2";
static NSString * const kDidMigrateNiconicoDefaults = @"didMigrateNiconicoDefaults.v1";

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
        if (![_defaults boolForKey:kDidMigrateNiconicoDefaults]) {
            if (![_defaults objectForKey:@"niconicoMode"]) [_defaults setBool:YES forKey:@"niconicoMode"];
            if (![_defaults objectForKey:@"adaptiveFontSize"]) [_defaults setBool:YES forKey:@"adaptiveFontSize"];
            if (![_defaults objectForKey:@"enableOutline"]) [_defaults setBool:YES forKey:@"enableOutline"];
            if (![_defaults objectForKey:@"outlineStrength"]) [_defaults setDouble:3.0 forKey:@"outlineStrength"];
            if (![_defaults objectForKey:@"scrollDuration"]) [_defaults setDouble:5.2 forKey:@"scrollDuration"];
            if (![_defaults objectForKey:@"showAuthorName"]) [_defaults setBool:NO forKey:@"showAuthorName"];
            [_defaults setBool:YES forKey:kDidMigrateNiconicoDefaults];
            [_defaults synchronize];
        }
    }
    return self;
}

- (void)notifyChanged { [_defaults synchronize]; [[NSNotificationCenter defaultCenter] postNotificationName:kYTNicoSettingsChangedNotification object:nil]; }
- (void)reload { [self notifyChanged]; }

- (BOOL)enabled { return [_defaults objectForKey:@"enabled"] ? [_defaults boolForKey:@"enabled"] : YES; }
- (CGFloat)fontSize { return [_defaults objectForKey:@"fontSize"] ? [_defaults doubleForKey:@"fontSize"] : 18.0; }
- (CGFloat)opacity { return [_defaults objectForKey:@"opacity"] ? [_defaults doubleForKey:@"opacity"] : 0.95; }
- (CGFloat)speed { return [_defaults objectForKey:@"speed"] ? [_defaults doubleForKey:@"speed"] : 90.0; }
- (NSInteger)maxLines { return [_defaults objectForKey:@"maxLines"] ? [_defaults integerForKey:@"maxLines"] : 10; }
- (BOOL)showAuthorName { return [_defaults objectForKey:@"showAuthorName"] ? [_defaults boolForKey:@"showAuthorName"] : NO; }
- (BOOL)enableShadow { return [_defaults objectForKey:@"enableShadow"] ? [_defaults boolForKey:@"enableShadow"] : YES; }
- (BOOL)enableOutline { return [_defaults objectForKey:@"enableOutline"] ? [_defaults boolForKey:@"enableOutline"] : YES; }
- (CGFloat)outlineStrength { return [_defaults objectForKey:@"outlineStrength"] ? [_defaults doubleForKey:@"outlineStrength"] : 3.0; }
- (BOOL)niconicoMode { return [_defaults objectForKey:@"niconicoMode"] ? [_defaults boolForKey:@"niconicoMode"] : YES; }
- (BOOL)adaptiveFontSize { return [_defaults objectForKey:@"adaptiveFontSize"] ? [_defaults boolForKey:@"adaptiveFontSize"] : YES; }
- (CGFloat)scrollDuration { return [_defaults objectForKey:@"scrollDuration"] ? [_defaults doubleForKey:@"scrollDuration"] : 5.2; }
- (NSArray<NSString *> *)blockWords { NSArray *v = [_defaults arrayForKey:@"blockWords"]; return v ?: @[]; }
- (BOOL)mockMode { return [_defaults objectForKey:@"mockMode"] ? [_defaults boolForKey:@"mockMode"] : NO; }
- (BOOL)debugLogging { return [_defaults objectForKey:@"debugLogging"] ? [_defaults boolForKey:@"debugLogging"] : NO; }
- (CGFloat)commentDensity { return [_defaults objectForKey:@"commentDensity"] ? [_defaults doubleForKey:@"commentDensity"] : 0.82; }
- (CGFloat)longevity { return [_defaults objectForKey:@"longevity"] ? [_defaults doubleForKey:@"longevity"] : 0.78; }
- (BOOL)syncReplayToTimestamp { return [_defaults objectForKey:@"syncReplayToTimestamp"] ? [_defaults boolForKey:@"syncReplayToTimestamp"] : YES; }
- (BOOL)preferLiveChat { return [_defaults objectForKey:@"preferLiveChat"] ? [_defaults boolForKey:@"preferLiveChat"] : YES; }
- (BOOL)autoFetch { return [_defaults objectForKey:@"autoFetch"] ? [_defaults boolForKey:@"autoFetch"] : YES; }
- (NSInteger)maxFetchComments { return [_defaults objectForKey:@"maxFetchComments"] ? [_defaults integerForKey:@"maxFetchComments"] : 500; }

- (void)setEnabled:(BOOL)value { [_defaults setBool:value forKey:@"enabled"]; [self notifyChanged]; }
- (void)setFontSize:(CGFloat)value { [_defaults setDouble:MAX(10.0, MIN(42.0, value)) forKey:@"fontSize"]; [self notifyChanged]; }
- (void)setOpacity:(CGFloat)value { [_defaults setDouble:MAX(0.15, MIN(1.0, value)) forKey:@"opacity"]; [self notifyChanged]; }
- (void)setSpeed:(CGFloat)value { [_defaults setDouble:MAX(35.0, MIN(320.0, value)) forKey:@"speed"]; [self notifyChanged]; }
- (void)setMaxLines:(NSInteger)value { [_defaults setInteger:MAX(1, MIN(30, value)) forKey:@"maxLines"]; [self notifyChanged]; }
- (void)setShowAuthorName:(BOOL)value { [_defaults setBool:value forKey:@"showAuthorName"]; [self notifyChanged]; }
- (void)setEnableShadow:(BOOL)value { [_defaults setBool:value forKey:@"enableShadow"]; [self notifyChanged]; }
- (void)setEnableOutline:(BOOL)value { [_defaults setBool:value forKey:@"enableOutline"]; [self notifyChanged]; }
- (void)setOutlineStrength:(CGFloat)value { [_defaults setDouble:MAX(0.0, MIN(8.0, value)) forKey:@"outlineStrength"]; [self notifyChanged]; }
- (void)setNiconicoMode:(BOOL)value { [_defaults setBool:value forKey:@"niconicoMode"]; [self notifyChanged]; }
- (void)setAdaptiveFontSize:(BOOL)value { [_defaults setBool:value forKey:@"adaptiveFontSize"]; [self notifyChanged]; }
- (void)setScrollDuration:(CGFloat)value { [_defaults setDouble:MAX(2.5, MIN(10.0, value)) forKey:@"scrollDuration"]; [self notifyChanged]; }
- (void)setBlockWords:(NSArray<NSString *> *)value { [_defaults setObject:value ?: @[] forKey:@"blockWords"]; [self notifyChanged]; }
- (void)setMockMode:(BOOL)value { [_defaults setBool:value forKey:@"mockMode"]; [self notifyChanged]; }
- (void)setDebugLogging:(BOOL)value { [_defaults setBool:value forKey:@"debugLogging"]; [self notifyChanged]; }
- (void)setCommentDensity:(CGFloat)value { [_defaults setDouble:MAX(0.1, MIN(1.0, value)) forKey:@"commentDensity"]; [self notifyChanged]; }
- (void)setLongevity:(CGFloat)value { [_defaults setDouble:MAX(0.1, MIN(1.0, value)) forKey:@"longevity"]; [self notifyChanged]; }
- (void)setSyncReplayToTimestamp:(BOOL)value { [_defaults setBool:value forKey:@"syncReplayToTimestamp"]; [self notifyChanged]; }
- (void)setPreferLiveChat:(BOOL)value { [_defaults setBool:value forKey:@"preferLiveChat"]; [self notifyChanged]; }
- (void)setAutoFetch:(BOOL)value { [_defaults setBool:value forKey:@"autoFetch"]; [self notifyChanged]; }
- (void)setMaxFetchComments:(NSInteger)value { [_defaults setInteger:MAX(100, MIN(3000, value)) forKey:@"maxFetchComments"]; [self notifyChanged]; }

- (void)applyNiconicoPreset {
    [_defaults setBool:YES forKey:@"niconicoMode"];
    [_defaults setBool:YES forKey:@"adaptiveFontSize"];
    [_defaults setBool:YES forKey:@"enableOutline"];
    [_defaults setBool:YES forKey:@"enableShadow"];
    [_defaults setBool:NO forKey:@"showAuthorName"];
    [_defaults setDouble:3.2 forKey:@"outlineStrength"];
    [_defaults setDouble:5.2 forKey:@"scrollDuration"];
    [_defaults setDouble:0.95 forKey:@"opacity"];
    [_defaults setDouble:0.86 forKey:@"commentDensity"];
    [_defaults setInteger:12 forKey:@"maxLines"];
    [self notifyChanged];
}
@end
