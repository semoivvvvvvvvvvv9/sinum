// LunarMP iOS — Traffic redirector
// Redirects all Fortnite Epic Games traffic to the LunarMP private backend.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// ── Backend URL (no trailing slash) ──────────────────────────────────────────
#define BACKEND_URL @"http://178.239.114.166:3551"

// ── Epic Games domains to intercept ──────────────────────────────────────────
// All requests to these domains will be redirected to BACKEND_URL
static NSArray<NSString *> *epicDomains() {
    return @[
        @"ol.epicgames.com",
        @"fngw-mcp-gc-livefn.ol.epicgames.com",
        @"account-public-service-prod.ol.epicgames.com",
        @"fortnite-public-service-prod11.ol.epicgames.com",
        @"lightswitch-public-service-prod06.ol.epicgames.com",
        @"launcher-public-service-prod06.ol.epicgames.com",
        @"catalog-public-service-prod06.ol.epicgames.com",
        @"entitlement-public-service-prod08.ol.epicgames.com",
        @"datastorage-public-service-prod01.ol.epicgames.com",
        @"channels-public-service-prod.ol.epicgames.com",
        @"cloudstorage-public-service-prod.ol.epicgames.com",
        @"statsproxy-public-service-prod.ol.epicgames.com",
        @"party-service-prod.ak.epicgames.com",
        @"xmpp-service-prod.ol.epicgames.com",
        @"api.epicgames.dev",
    ];
}

// Paths that must NOT be redirected (CDN content, etc.)
static NSArray<NSString *> *excludedPaths() {
    return @[
        @"/CloudDir/",
        @"/Bundles/",
        @"/ChunksV4/",
        @"/ChunksV3/",
        @"/BuildsV2/",
    ];
}

// ── NSURLProtocol subclass ────────────────────────────────────────────────────
@interface LunarMPURLProtocol : NSURLProtocol
@end

@implementation LunarMPURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    // Already handled — avoid infinite loop
    if ([NSURLProtocol propertyForKey:@"LunarMPHandled" inRequest:request]) {
        return NO;
    }

    NSString *host = request.URL.host ?: @"";
    NSString *path = request.URL.path ?: @"";

    // Check if host matches any Epic domain
    BOOL isEpic = NO;
    for (NSString *domain in epicDomains()) {
        if ([host isEqualToString:domain] || [host hasSuffix:[@"." stringByAppendingString:domain]]) {
            isEpic = YES;
            break;
        }
    }
    if (!isEpic) return NO;

    // Check excluded paths
    for (NSString *excluded in excludedPaths()) {
        if ([path hasPrefix:excluded]) return NO;
    }

    return YES;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    return request;
}

+ (BOOL)requestIsCacheEquivalent:(NSURLRequest *)a toRequest:(NSURLRequest *)b
{
    return NO;
}

- (void)startLoading
{
    NSMutableURLRequest *modified = [self.request mutableCopy];

    // Build the new URL: replace scheme+host with BACKEND_URL, keep path+query
    NSURLComponents *original = [NSURLComponents componentsWithURL:modified.URL
                                           resolvingAgainstBaseURL:NO];
    NSURLComponents *backend  = [NSURLComponents componentsWithString:BACKEND_URL];

    backend.path       = original.path;
    backend.queryItems = original.queryItems;
    backend.fragment   = original.fragment;

    NSURL *newURL = backend.URL;
    if (!newURL) {
        // Fallback: string replacement
        NSString *src = modified.URL.absoluteString;
        NSString *schemeHost = [NSString stringWithFormat:@"%@://%@",
                                modified.URL.scheme ?: @"https",
                                modified.URL.host   ?: @""];
        NSString *dst = [src stringByReplacingOccurrencesOfString:schemeHost
                                                       withString:BACKEND_URL];
        newURL = [NSURL URLWithString:dst];
    }

    if (newURL) {
        [modified setURL:newURL];
    }

    // Mark as handled so we don't loop
    [NSURLProtocol setProperty:@YES forKey:@"LunarMPHandled" inRequest:modified];

    // Use NSURLSession to actually perform the request
    NSURLSession *session = [NSURLSession sessionWithConfiguration:
                             NSURLSessionConfiguration.defaultSessionConfiguration
                                                          delegate:nil
                                                     delegateQueue:nil];

    NSURLSessionDataTask *task = [session dataTaskWithRequest:modified
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                [self.client URLProtocol:self didFailWithError:error];
                return;
            }
            if (response) {
                [self.client URLProtocol:self didReceiveResponse:response
                      cacheStoragePolicy:NSURLCacheStorageNotAllowed];
            }
            if (data.length > 0) {
                [self.client URLProtocol:self didLoadData:data];
            }
            [self.client URLProtocolDidFinishLoading:self];
        }];

    [task resume];

    // Store the task so stopLoading can cancel it
    objc_setAssociatedObject(self, "task", task, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)stopLoading
{
    NSURLSessionDataTask *task = objc_getAssociatedObject(self, "task");
    if (task) {
        [task cancel];
    }
}

@end

// ── Entry point ───────────────────────────────────────────────────────────────
__attribute__((constructor)) void LunarMPEntry()
{
    [NSURLProtocol registerClass:[LunarMPURLProtocol class]];
    NSLog(@"[LunarMP] Traffic redirector registered → %s", BACKEND_URL);
}
