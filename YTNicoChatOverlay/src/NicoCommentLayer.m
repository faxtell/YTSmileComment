#import "NicoCommentLayer.h"
#import "NicoChatMessage.h"
#import "SettingsManager.h"

@implementation NicoCommentLayer

static NSString *YTNicoTrimText(NSString *s) {
    if (![s isKindOfClass:NSString.class]) return @"";
    s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([s rangeOfString:@"  "].location != NSNotFound) {
        s = [s stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    }
    return s ?: @"";
}

static BOOL YTNicoLooksLikeAtHandle(NSString *s) {
    s = YTNicoTrimText(s);
    if (![s hasPrefix:@"@"] || s.length < 2) return NO;
    if ([s rangeOfString:@" "].location != NSNotFound || [s rangeOfString:@"　"].location != NSNotFound) return NO;
    if (s.length > 48) return NO;
    return YES;
}

static NSString *YTNicoStripLeadingAtHandle(NSString *text) {
    text = YTNicoTrimText(text);
    if (![text hasPrefix:@"@"]) return text;

    // @handle: body / @handle body / @handle　body
    NSRegularExpression *basic = [NSRegularExpression regularExpressionWithPattern:@"^@[^\\s　:：]+[\\s　:：-－—–|｜・]+(.+)$" options:0 error:nil];
    NSTextCheckingResult *m = [basic firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (m && m.numberOfRanges >= 2) return YTNicoTrimText([text substringWithRange:[m rangeAtIndex:1]]);

    // If YouTube collapsed the username and body without a visible separator, try to
    // remove a typical ASCII handle prefix and leave the Japanese/body portion.
    NSRegularExpression *ascii = [NSRegularExpression regularExpressionWithPattern:@"^@[A-Za-z0-9._-]{2,32}(.+)$" options:0 error:nil];
    m = [ascii firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (m && m.numberOfRanges >= 2) {
        NSString *rest = YTNicoTrimText([text substringWithRange:[m rangeAtIndex:1]]);
        if (rest.length > 0) return rest;
    }

    // If it is only the handle, do not render it as a comment.
    if (YTNicoLooksLikeAtHandle(text)) return @"";
    return text;
}

static CGFloat YTNicoEffectiveCommentOpacity(NSString *text, CGFloat configuredOpacity, SettingsManager *settings) {
    CGFloat op = MAX(0.15, MIN(1.0, configuredOpacity));
    if (!settings.niconicoMode) return op;

    // Niconico-style comments are basically solid, but very long comments can feel too heavy on video.
    // Treat the user's opacity setting as an upper limit, then gently adjust by text length.
    CGFloat base = MAX(0.92, op);
    NSUInteger len = text.length;
    if (len >= 80) base -= 0.08;
    else if (len >= 45) base -= 0.04;
    else if (len <= 8) base = MIN(1.0, base + 0.03);
    return MAX(0.84, MIN(1.0, base));
}

- (void)configureWithMessage:(NicoChatMessage *)message fontSize:(CGFloat)fontSize opacity:(CGFloat)opacity {
    NSString *text = YTNicoStripLeadingAtHandle(message.text ?: @"");
    SettingsManager *settings = [SettingsManager shared];
    NSString *author = YTNicoTrimText(message.authorName ?: @"");

    // YouTube chat/replay authors are usually @handles. For Niconico-style display,
    // never prepend @handles; render only the comment body.
    BOOL authorIsHandle = YTNicoLooksLikeAtHandle(author) || [author hasPrefix:@"@"];
    if (settings.showAuthorName && author.length > 0 && !authorIsHandle) {
        text = [NSString stringWithFormat:@"%@: %@", author, text];
    }

    if (text.length == 0) text = @" ";

    CGFloat effectiveOpacity = YTNicoEffectiveCommentOpacity(text, opacity, settings);
    UIColor *fillColor = (message.colorHint ?: UIColor.whiteColor);
    if (settings.niconicoMode) {
        fillColor = [fillColor colorWithAlphaComponent:1.0];
    } else {
        fillColor = [fillColor colorWithAlphaComponent:effectiveOpacity];
    }

    UIFont *font = [UIFont boldSystemFontOfSize:fontSize];
    CGFloat strokeWidth = settings.enableOutline ? MAX(0.0, settings.outlineStrength) : 0.0;
    NSMutableDictionary *attrs = [@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: fillColor
    } mutableCopy];

    if (strokeWidth > 0.01) {
        attrs[NSStrokeColorAttributeName] = [UIColor.blackColor colorWithAlphaComponent:settings.niconicoMode ? 0.96 : effectiveOpacity];
        attrs[NSStrokeWidthAttributeName] = @(-strokeWidth);
    }

    self.string = [[NSAttributedString alloc] initWithString:text attributes:attrs];
    self.fontSize = fontSize;
    self.contentsScale = UIScreen.mainScreen.scale;
    self.foregroundColor = fillColor.CGColor;
    self.opacity = (float)effectiveOpacity;
    self.alignmentMode = kCAAlignmentLeft;
    self.truncationMode = kCATruncationNone;
    self.wrapped = NO;
    self.masksToBounds = NO;

    if (settings.enableShadow) {
        self.shadowColor = UIColor.blackColor.CGColor;
        self.shadowOpacity = settings.niconicoMode ? 0.68 : 0.9;
        self.shadowRadius = settings.niconicoMode ? 0.85 : 2.0;
        self.shadowOffset = settings.niconicoMode ? CGSizeMake(1.0, 1.0) : CGSizeMake(1.0, 1.0);
    } else {
        self.shadowOpacity = 0.0;
    }
}
@end
