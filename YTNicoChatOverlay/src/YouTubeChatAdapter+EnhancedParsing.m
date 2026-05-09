#import "YouTubeChatAdapter.h"
#import "DebugInspector.h"
#import <objc/runtime.h>

static NSString * const YTNicoEnhancedMessageNotification = @"YTNicoEnhancedMessageNotification";

@interface YouTubeChatAdapter (EnhancedPrivate)
- (void)emitAuthor:(NSString *)author text:(NSString *)text messageId:(NSString *)messageId;
@end

@implementation YouTubeChatAdapter (EnhancedParsing)

+ (void)load {
    Class cls = self;
    Method origStart = class_getInstanceMethod(cls, @selector(startObservingInRootView:));
    Method newStart = class_getInstanceMethod(cls, @selector(ytnico_startObservingInRootView:));
    if (origStart && newStart) method_exchangeImplementations(origStart, newStart);

    Method origStop = class_getInstanceMethod(cls, @selector(stopObserving));
    Method newStop = class_getInstanceMethod(cls, @selector(ytnico_stopObserving));
    if (origStop && newStop) method_exchangeImplementations(origStop, newStop);

    Method origIngest = class_getClassMethod(cls, @selector(ingestPotentialJSONObject:));
    Method newIngest = class_getClassMethod(cls, @selector(ytnico_ingestPotentialJSONObject:));
    if (origIngest && newIngest) method_exchangeImplementations(origIngest, newIngest);
}

- (void)ytnico_startObservingInRootView:(UIView *)rootView {
    [self ytnico_startObservingInRootView:rootView];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:YTNicoEnhancedMessageNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ytnico_handleEnhancedMessage:) name:YTNicoEnhancedMessageNotification object:nil];
}

- (void)ytnico_stopObserving {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:YTNicoEnhancedMessageNotification object:nil];
    [self ytnico_stopObserving];
}

- (void)ytnico_handleEnhancedMessage:(NSNotification *)note {
    NSDictionary *u = note.userInfo;
    NSString *a = u[@"author"] ?: @"";
    NSString *t = u[@"text"] ?: @"";
    NSString *i = u[@"id"] ?: @"";
    if (t.length > 0) [self emitAuthor:a text:t messageId:i];
}

+ (void)ytnico_ingestPotentialJSONObject:(id)object {
    [self ytnico_ingestPotentialJSONObject:object];
    if (!object) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSMutableArray<NSDictionary *> *messages = [NSMutableArray array];
        [self ytnico_collectFromObject:object into:messages depth:0];
        if (messages.count == 0) return;
        [[DebugInspector shared] log:@"enhanced parser found %lu messages", (unsigned long)messages.count];
        dispatch_async(dispatch_get_main_queue(), ^{
            for (NSDictionary *m in messages) {
                [[NSNotificationCenter defaultCenter] postNotificationName:YTNicoEnhancedMessageNotification object:nil userInfo:m];
            }
        });
    });
}

+ (void)ytnico_collectFromObject:(id)obj into:(NSMutableArray<NSDictionary *> *)out depth:(NSInteger)depth {
    if (!obj || depth > 100 || out.count > 1000) return;
    if ([obj isKindOfClass:NSArray.class]) {
        for (id x in (NSArray *)obj) [self ytnico_collectFromObject:x into:out depth:depth + 1];
        return;
    }
    if (![obj isKindOfClass:NSDictionary.class]) return;
    NSDictionary *d = (NSDictionary *)obj;

    [self ytnico_tryRenderer:d key:@"commentRenderer" into:out];
    [self ytnico_tryRenderer:d key:@"commentViewModel" into:out];
    [self ytnico_tryRenderer:d key:@"commentEntityPayload" into:out];
    [self ytnico_tryRenderer:d key:@"liveChatTextMessageRenderer" into:out];
    [self ytnico_tryRenderer:d key:@"liveChatPaidMessageRenderer" into:out];
    [self ytnico_tryRenderer:d key:@"liveChatPaidStickerRenderer" into:out];
    [self ytnico_tryRenderer:d key:@"liveChatMembershipItemRenderer" into:out];
    [self ytnico_tryRenderer:d key:@"liveChatSponsorshipsGiftPurchaseAnnouncementRenderer" into:out];
    [self ytnico_tryRenderer:d key:@"liveChatSponsorshipsGiftRedemptionAnnouncementRenderer" into:out];

    for (id v in d.allValues) [self ytnico_collectFromObject:v into:out depth:depth + 1];
}

+ (void)ytnico_tryRenderer:(NSDictionary *)container key:(NSString *)key into:(NSMutableArray<NSDictionary *> *)out {
    id raw = container[key];
    if (![raw isKindOfClass:NSDictionary.class]) return;
    NSDictionary *r = raw;

    NSString *author = @"";
    NSString *text = @"";
    NSString *mid = @"";

    if ([key hasPrefix:@"liveChat"]) {
        author = [self ytnico_text:r[@"authorName"]];
        text = [self ytnico_text:r[@"message"]];
        NSString *amount = [self ytnico_text:r[@"purchaseAmountText"]];
        if (text.length == 0) text = [self ytnico_text:r[@"headerSubtext"]];
        if (text.length == 0) text = amount;
        if (amount.length > 0 && text.length > 0 && [text rangeOfString:amount].location == NSNotFound) {
            text = [NSString stringWithFormat:@"%@ %@", amount, text];
        }
        mid = [self ytnico_norm:r[@"id"]];
        if (author.length == 0) author = @"live";
    } else {
        author = [self ytnico_firstText:@[r[@"authorText"], r[@"author"], r[@"authorName"], r[@"displayName"], r[@"name"]]];
        text = [self ytnico_firstText:@[r[@"contentText"], r[@"content"], r[@"commentText"], r[@"bodyText"], r[@"message"], r[@"properties"]]];
        mid = [self ytnico_firstText:@[r[@"commentId"], r[@"commentKey"], r[@"id"]]];

        NSDictionary *props = [r[@"properties"] isKindOfClass:NSDictionary.class] ? r[@"properties"] : nil;
        if (props) {
            if (text.length == 0) text = [self ytnico_firstText:@[props[@"content"], props[@"contentText"], props[@"commentText"]]];
            if (mid.length == 0) mid = [self ytnico_firstText:@[props[@"commentId"], props[@"commentKey"], props[@"id"]]];
        }
        NSDictionary *a = [r[@"author"] isKindOfClass:NSDictionary.class] ? r[@"author"] : nil;
        if (a && author.length == 0) author = [self ytnico_firstText:@[a[@"displayName"], a[@"name"], a[@"title"]]];
        if (author.length == 0) author = @"comment";
    }

    [self ytnico_addAuthor:author text:text mid:mid into:out];
}

+ (NSString *)ytnico_firstText:(NSArray *)items {
    for (id item in items) {
        NSString *s = [self ytnico_text:item];
        if (s.length > 0) return s;
    }
    return @"";
}

+ (NSString *)ytnico_text:(id)obj {
    if (!obj || obj == NSNull.null) return @"";
    if ([obj isKindOfClass:NSString.class]) return [self ytnico_norm:obj];
    if ([obj isKindOfClass:NSNumber.class]) return [self ytnico_norm:[(NSNumber *)obj stringValue]];
    if ([obj isKindOfClass:NSArray.class]) {
        NSMutableArray *parts = [NSMutableArray array];
        for (id x in (NSArray *)obj) {
            NSString *s = [self ytnico_text:x];
            if (s.length) [parts addObject:s];
        }
        return [self ytnico_norm:[parts componentsJoinedByString:@""]];
    }
    if (![obj isKindOfClass:NSDictionary.class]) return @"";
    NSDictionary *d = obj;
    if ([d[@"simpleText"] isKindOfClass:NSString.class]) return [self ytnico_norm:d[@"simpleText"]];
    if ([d[@"text"] isKindOfClass:NSString.class]) return [self ytnico_norm:d[@"text"]];
    if ([d[@"content"] isKindOfClass:NSString.class]) return [self ytnico_norm:d[@"content"]];
    if ([d[@"label"] isKindOfClass:NSString.class]) return [self ytnico_norm:d[@"label"]];
    if ([d[@"runs"] isKindOfClass:NSArray.class]) return [self ytnico_text:d[@"runs"]];
    if ([d[@"accessibilityData"] isKindOfClass:NSDictionary.class]) return [self ytnico_text:d[@"accessibilityData"]];
    if ([d[@"accessibility"] isKindOfClass:NSDictionary.class]) return [self ytnico_text:d[@"accessibility"]];
    if ([d[@"commandRuns"] isKindOfClass:NSArray.class]) return [self ytnico_text:d[@"commandRuns"]];
    return @"";
}

+ (void)ytnico_addAuthor:(NSString *)author text:(NSString *)text mid:(NSString *)mid into:(NSMutableArray<NSDictionary *> *)out {
    author = [self ytnico_norm:author];
    text = [self ytnico_norm:text];
    mid = [self ytnico_norm:mid];
    if (text.length == 0) return;
    if (mid.length == 0) mid = [NSString stringWithFormat:@"%lu", (unsigned long)[[NSString stringWithFormat:@"%@|%@", author, text] hash]];
    for (NSDictionary *e in out) if ([e[@"id"] isEqualToString:mid]) return;
    [out addObject:@{@"author": author ?: @"", @"text": text, @"id": mid}];
}

+ (NSString *)ytnico_norm:(id)obj {
    if (![obj isKindOfClass:NSString.class]) return @"";
    NSString *s = [(NSString *)obj stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([s rangeOfString:@"  "].location != NSNotFound) s = [s stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    return s;
}

@end
