#import <Foundation/Foundation.h>
#import "YouTubeChatAdapter.h"

static NSString *YTNicoGuardTrim(NSString *s) {
    if (![s isKindOfClass:NSString.class]) return @"";
    s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([s rangeOfString:@"  "].location != NSNotFound) s = [s stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    return s ?: @"";
}

static NSString *YTNicoGuardNormalizeDigits(NSString *s) {
    NSMutableString *m = [NSMutableString stringWithString:s ?: @""];
    NSDictionary *map = @{@"０":@"0", @"１":@"1", @"２":@"2", @"３":@"3", @"４":@"4", @"５":@"5", @"６":@"6", @"７":@"7", @"８":@"8", @"９":@"9", @"，":@",", @"．":@"."};
    for (NSString *k in map) [m replaceOccurrencesOfString:k withString:map[k] options:0 range:NSMakeRange(0, m.length)];
    return m;
}

static BOOL YTNicoGuardIsJapaneseShortReaction(NSString *text) {
    text = YTNicoGuardTrim(text);
    if (text.length == 0 || text.length > 24) return NO;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^(w{1,}|ｗ{1,}|草+|笑+|www+|WWW+|お+|うん+|いいね+|すご+|すごい+|それな+|せやね+|そやね+|たしかに|確かに|ふむ+|へぇ+|ええ+|やば+|かわい+|かわいい+|キタ+|きた+|！？+|!!+|！+|\\?+|？+|😂+|🤣+|😭+|🥹+)$" options:NSRegularExpressionCaseInsensitive error:nil];
    return [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
}

static BOOL YTNicoGuardShouldDropMetadataText(NSString *text) {
    text = YTNicoGuardTrim(text);
    if (text.length == 0) return YES;
    if (YTNicoGuardIsJapaneseShortReaction(text)) return NO;

    NSString *normalized = YTNicoGuardNormalizeDigits(text);

    // View counters / video metadata. Handles full-width digits as well.
    if ([normalized rangeOfString:@"回視聴"].location != NSNotFound) return YES;
    if ([normalized rangeOfString:@"人が視聴中"].location != NSNotFound) return YES;
    if ([normalized rangeOfString:@"高評価"].location != NSNotFound) return YES;
    if ([normalized rangeOfString:@"低評価"].location != NSNotFound) return YES;

    NSRegularExpression *viewCount = [NSRegularExpression regularExpressionWithPattern:@"^[0-9, .]+(回視聴|人が視聴中|件)$" options:0 error:nil];
    if ([viewCount firstMatchInString:normalized options:0 range:NSMakeRange(0, normalized.length)]) return YES;

    // Large standalone numbers are usually video/game UI, not chat. Keep short numbers
    // like "89" because those can be real chat comments.
    NSString *compact = [[normalized stringByReplacingOccurrencesOfString:@"," withString:@""] stringByReplacingOccurrencesOfString:@" " withString:@""];
    NSRegularExpression *largeNumberOnly = [NSRegularExpression regularExpressionWithPattern:@"^[0-9]{4,}$" options:0 error:nil];
    if ([largeNumberOnly firstMatchInString:compact options:0 range:NSMakeRange(0, compact.length)]) return YES;

    // Common non-chat controls/metadata that can be picked up by broad UI scanning.
    NSArray *exact = @[@"共有", @"保存", @"チャンネル登録", @"ライブチャット", @"チャットのリプレイ", @"上位のメッセージ", @"上位チャット", @"すべてのチャット", @"何かボタンを押してください"];
    for (NSString *x in exact) if ([text isEqualToString:x]) return YES;

    return NO;
}

%hook YouTubeChatAdapter

+ (void)emitNowAuthor:(NSString *)author text:(NSString *)text messageId:(NSString *)messageId {
    if (YTNicoGuardShouldDropMetadataText(text)) return;
    %orig(author, text, messageId);
}

+ (void)broadcastAuthor:(NSString *)author text:(NSString *)text messageId:(NSString *)messageId {
    if (YTNicoGuardShouldDropMetadataText(text)) return;
    %orig(author, text, messageId);
}

%end
