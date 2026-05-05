#import "SettingsManager.h"

NSString * const kYTNicoSettingsChangedNotification = @"com.example.ytnico.settings.changed";
static NSString * const kDomain = @"com.example.yt-nico-chat-overlay";

@implementation SettingsManager {
    NSUserDefaults *_defaults;
}

+ (instancetype)shared { static SettingsManager *s; static dispatch_once_t once; dispatch_once(&once, ^{ s = [SettingsManager new]; }); return s; }
- (instancetype)init { if ((self=[super init])) { _defaults = [[NSUserDefaults alloc] initWithSuiteName:kDomain] ?: NSUserDefaults.standardUserDefaults; } return self; }
- (void)reload { [[NSNotificationCenter defaultCenter] postNotificationName:kYTNicoSettingsChangedNotification object:nil]; }
- (BOOL)enabled { return [_defaults objectForKey:@"enabled"] ? [_defaults boolForKey:@"enabled"] : YES; }
- (CGFloat)fontSize { return [_defaults objectForKey:@"fontSize"] ? [_defaults doubleForKey:@"fontSize"] : 18.0; }
- (CGFloat)opacity { return [_defaults objectForKey:@"opacity"] ? [_defaults doubleForKey:@"opacity"] : 0.9; }
- (CGFloat)speed { return [_defaults objectForKey:@"speed"] ? [_defaults doubleForKey:@"speed"] : 90.0; }
- (NSInteger)maxLines { return [_defaults objectForKey:@"maxLines"] ? [_defaults integerForKey:@"maxLines"] : 8; }
- (BOOL)showAuthorName { return [_defaults objectForKey:@"showAuthorName"] ? [_defaults boolForKey:@"showAuthorName"] : NO; }
- (BOOL)enableShadow { return [_defaults objectForKey:@"enableShadow"] ? [_defaults boolForKey:@"enableShadow"] : YES; }
- (BOOL)enableOutline { return [_defaults objectForKey:@"enableOutline"] ? [_defaults boolForKey:@"enableOutline"] : NO; }
- (NSArray<NSString *> *)blockWords { return [_defaults arrayForKey:@"blockWords"] ?: @[]; }
- (BOOL)mockMode { return [_defaults objectForKey:@"mockMode"] ? [_defaults boolForKey:@"mockMode"] : YES; }
- (BOOL)debugLogging { return [_defaults objectForKey:@"debugLogging"] ? [_defaults boolForKey:@"debugLogging"] : NO; }
@end
