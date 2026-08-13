// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UITileLoadingHost.h"
#import "AdminUIServer/UITileExecutionPolicy.h"
#include <stdlib.h>
#include <string.h>

static NSString *GZAdminUITileNormalizedBaseHost(NSString *baseHost) {
    NSString *trimmed = [[baseHost lowercaseString]
                         stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([trimmed hasPrefix:@"."]) {
        trimmed = [trimmed substringFromIndex:1];
    }
    return trimmed;
}

BOOL GZAdminUITileIsLoadHost(NSString *hostname, NSString *baseHost) {
    if (hostname.length == 0 || baseHost.length == 0) return NO;
    NSString *base = GZAdminUITileNormalizedBaseHost(baseHost);
    NSString *expected = [@"load." stringByAppendingString:base];
    return [[hostname lowercaseString] isEqualToString:expected];
}

BOOL GZAdminUITileIsUniqueOriginHost(NSString *hostname, NSString *baseHost) {
    if (hostname.length == 0 || baseHost.length == 0) return NO;
    NSString *host = [hostname lowercaseString];
    NSString *base = GZAdminUITileNormalizedBaseHost(baseHost);
    NSString *suffix = [@"." stringByAppendingString:base];
    if (host.length <= suffix.length || ![host hasSuffix:suffix]) return NO;
    NSString *label = [host substringToIndex:host.length - suffix.length];
    if (label.length != 20) return NO;
    static NSCharacterSet *allowed = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz"];
    });
    return [label rangeOfCharacterFromSet:[allowed invertedSet]].location == NSNotFound;
}

NSString *GZAdminUITileMakeUniqueOriginLabel(void) {
    static const char alphabet[] = "abcdefghijklmnopqrstuvwxyz";
    char label[21];
    for (int i = 0; i < 20; i++) {
        label[i] = alphabet[arc4random_uniform(26)];
    }
    label[20] = '\0';
    return [[NSString alloc] initWithBytes:label length:20 encoding:NSASCIIStringEncoding];
}

NSString *GZAdminUITileUniqueOriginRedirectURL(NSString *scheme,
                                               NSString *baseHost,
                                               NSString *pathAndQuery) {
    NSString *safeScheme = scheme.length > 0 ? [scheme lowercaseString] : @"https";
    NSString *base = GZAdminUITileNormalizedBaseHost(baseHost);
    NSString *path = pathAndQuery.length > 0 ? pathAndQuery : @"/";
    if (![path hasPrefix:@"/"]) {
        path = [@"/" stringByAppendingString:path];
    }
    NSString *label = GZAdminUITileMakeUniqueOriginLabel();
    return [NSString stringWithFormat:@"%@://%@.%@%@", safeScheme, label, base, path];
}

NSString *GZAdminUITileShuttleHTML(void) {
    return @"<!DOCTYPE html>\n"
           "<html lang=\"en\">\n"
           "<head>\n"
           "<meta charset=\"utf-8\">\n"
           "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
           "<title>Web Tile Shuttle</title>\n"
           "<style>\n"
           "* { box-sizing: border-box; }\n"
           "html, body { margin: 0; padding: 0; width: 100%; height: 100%; }\n"
           "iframe { width: 100%; height: 100%; border: 0; }\n"
           "</style>\n"
           "</head>\n"
           "<body>\n"
           "<script src=\"/.well-known/web-tiles/shuttle.js\"></script>\n"
           "</body>\n"
           "</html>\n";
}

NSString *GZAdminUITileShuttleJavaScript(void) {
    return @"const PFX = 'tiles-shuttle-';\n"
           "const RCV_LOAD = PFX + 'load';\n"
           "const SND_READY = PFX + 'ready';\n"
           "const SND_ERROR = PFX + 'error';\n"
           "let workerId, mothership, worker;\n"
           "let readyResolve;\n"
           "const readyToLoad = new Promise((resolve) => { readyResolve = resolve; });\n"
           "window.addEventListener('message', async (ev) => {\n"
           "  const action = ev.data && ev.data.action;\n"
           "  if (action && action.startsWith(PFX)) {\n"
           "    if (action === RCV_LOAD) {\n"
           "      workerId = ev.data.id;\n"
           "      mothership = ev.source;\n"
           "      await loadWorker();\n"
           "      window.parent.postMessage({ id: workerId, action: SND_READY }, '*');\n"
           "    }\n"
           "  } else {\n"
           "    await readyToLoad;\n"
           "    if (worker) worker.postMessage(ev.data);\n"
           "  }\n"
           "});\n"
           "navigator.serviceWorker.onmessage = (ev) => {\n"
           "  window.parent.postMessage(ev.data, '*');\n"
           "};\n"
           "async function loadWorker() {\n"
           "  let reg = await navigator.serviceWorker.getRegistration();\n"
           "  if (!reg) {\n"
           "    reg = await navigator.serviceWorker.register('/.well-known/web-tiles/worker.js', { scope: '/' });\n"
           "  }\n"
           "  await navigator.serviceWorker.ready;\n"
           "  worker = reg.active;\n"
           "  readyResolve();\n"
           "}\n";
}

NSString *GZAdminUITileServiceWorkerJavaScript(void) {
    return @"const PFX = 'tiles-worker-';\n"
           "const RCV_LOAD = PFX + 'load';\n"
           "const SND_READY = PFX + 'ready';\n"
           "const SND_REQUEST = PFX + 'request';\n"
           "const RCV_RESPONSE = PFX + 'response';\n"
           "let id, shuttle;\n"
           "let readyResolve;\n"
           "const readyToLoad = new Promise((resolve) => { readyResolve = resolve; });\n"
           "const requestMap = new Map();\n"
           "let currentRequest = 0;\n"
           "self.skipWaiting();\n"
           "async function request(type, payload) {\n"
           "  currentRequest++;\n"
           "  const p = new Promise((resolve, reject) => {\n"
           "    requestMap.set(currentRequest, { resolve, reject });\n"
           "  });\n"
           "  shuttle.postMessage({ action: SND_REQUEST, id, type, payload: { requestId: currentRequest, ...payload } });\n"
           "  return p;\n"
           "}\n"
           "self.addEventListener('message', (ev) => {\n"
           "  const action = ev.data && ev.data.action;\n"
           "  if (action === RCV_LOAD) {\n"
           "    id = ev.data.id;\n"
           "    readyResolve();\n"
           "    shuttle = ev.source;\n"
           "    ev.source.postMessage({ action: SND_READY, id });\n"
           "  } else if (action === RCV_RESPONSE) {\n"
           "    const payload = ev.data.payload || {};\n"
           "    const entry = requestMap.get(payload.requestId);\n"
           "    if (!entry) return;\n"
           "    requestMap.delete(payload.requestId);\n"
           "    if (ev.data.error) entry.reject(ev.data.error);\n"
           "    else entry.resolve(payload.response);\n"
           "  }\n"
           "});\n"
           "self.addEventListener('fetch', (ev) => {\n"
           "  const url = new URL(ev.request.url);\n"
           "  if (/^\\/\\.well-known\\/web-tiles\\//.test(url.pathname)) return;\n"
           "  ev.respondWith((async () => {\n"
           "    await readyToLoad;\n"
           "    if (!id) return new Response('Not in a loaded state.', { status: 503 });\n"
           "    const r = await request('resolve-path', { path: url.pathname });\n"
           "    return new Response(r.body, { status: r.status || 200, headers: r.headers || { 'content-type': 'text/plain' } });\n"
           "  })());\n"
           "});\n";
}

void GZAdminUITileApplyUniqueOriginHeaders(ATProtoHttpResponse *response) {
    if (![response isKindOfClass:[ATProtoHttpResponse class]]) return;
    NSDictionary *headers = GZAdminUITileExecutionSecurityHeaders();
    [headers enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        [response setHeader:(NSString *)value forKey:(NSString *)key];
    }];
    [response setHeader:@"/" forKey:@"service-worker-allowed"];
    [response setHeader:@"N" forKey:@"tk"];
    [response setHeader:@"noai, noimageai" forKey:@"x-robots-tag"];
}

NSString *GZAdminUITileUniqueOriginURL(NSString *scheme, NSString *baseHost, NSString *label) {
    NSString *base = GZAdminUITileNormalizedBaseHost(baseHost);
    NSString *sch = scheme.length > 0 ? scheme : @"https";
    return [NSString stringWithFormat:@"%@://%@.%@", sch, label, base];
}

BOOL GZAdminUITileIsTrustedEmbedOrigin(NSString *origin, NSString *baseHost) {
    if (origin.length == 0 || baseHost.length == 0) return NO;
    NSURL *url = [NSURL URLWithString:origin];
    if (!url.host) return NO;
    NSString *host = url.host;
    if (GZAdminUITileIsUniqueOriginHost(host, baseHost)) return YES;
    if (GZAdminUITileIsLoadHost(host, baseHost)) return YES;
    return NO;
}
