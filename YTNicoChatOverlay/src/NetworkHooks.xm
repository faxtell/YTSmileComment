#import <Foundation/Foundation.h>
#import "YouTubeChatAdapter.h"
#import "DebugInspector.h"

static BOOL YTNicoShouldInspectURL(NSURL *url) {
    NSString *s = url.absoluteString.lowercaseString ?: @"";
    if (s.length == 0) return YES;
    return [s containsString:@"youtube"] ||
           [s containsString:@"googlevideo"] ||
           [s containsString:@"googleapis"] ||
           [s containsString:@"ytimg"];
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data.length > 0 && YTNicoShouldInspectURL(request.URL)) {
            [YouTubeChatAdapter ingestPotentialInnertubeData:data request:request];
        }
        if (completionHandler) completionHandler(data, response, error);
    };
    return %orig(request, wrapped);
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data.length > 0 && YTNicoShouldInspectURL(url)) {
            NSURLRequest *req = [NSURLRequest requestWithURL:url];
            [YouTubeChatAdapter ingestPotentialInnertubeData:data request:req];
        }
        if (completionHandler) completionHandler(data, response, error);
    };
    return %orig(url, wrapped);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromData:(NSData *)bodyData
                                completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data.length > 0 && YTNicoShouldInspectURL(request.URL)) {
            [YouTubeChatAdapter ingestPotentialInnertubeData:data request:request];
        }
        if (completionHandler) completionHandler(data, response, error);
    };
    return %orig(request, bodyData, wrapped);
}

%end

%hook NSJSONSerialization

+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
    id obj = %orig(data, opt, error);
    if (obj) [YouTubeChatAdapter ingestPotentialJSONObject:obj];
    return obj;
}

%end

%ctor {
    if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) {
        [[DebugInspector shared] log:@"YTNico network hooks loaded"];
    }
}
