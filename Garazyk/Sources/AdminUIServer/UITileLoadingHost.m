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

NSString *GZAdminUITileEmbedHTML(NSString *scheme, NSString *baseHost, NSString *parentOrigin) {
    NSString *sch = scheme.length > 0 ? [scheme lowercaseString] : @"http";
    NSString *base = GZAdminUITileNormalizedBaseHost(baseHost);
    NSString *iframeSrc = [NSString stringWithFormat:@"%@://load.%@/.well-known/web-tiles/", sch, base];
    NSString *parent = parentOrigin.length > 0 ? parentOrigin : @"";
    // Escape for HTML attribute / JS string (minimal).
    NSMutableString *escapedParent = [NSMutableString string];
    for (NSUInteger i = 0; i < parent.length; i++) {
        unichar c = [parent characterAtIndex:i];
        if (c == '\\' || c == '\'' || c == '"') {
            [escapedParent appendFormat:@"\\%C", c];
        } else if (c == '<') {
            [escapedParent appendString:@"\\u003c"];
        } else {
            [escapedParent appendFormat:@"%C", c];
        }
    }
    return [NSString stringWithFormat:
            @"<!DOCTYPE html>\n"
            "<html lang=\"en\">\n"
            "<head>\n"
            "<meta charset=\"utf-8\">\n"
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
            "<title>Web Tile Embed</title>\n"
            "<style>\n"
            "html, body { margin: 0; height: 100%%; font-family: system-ui, sans-serif; }\n"
            "header { padding: 0.75rem 1rem; border-bottom: 1px solid #ccc; }\n"
            "iframe { width: 100%%; height: calc(100%% - 3rem); border: 0; }\n"
            "#log { font-size: 0.85rem; color: #444; }\n"
            "</style>\n"
            "</head>\n"
            "<body>\n"
            "<header><strong>Garazyk tile embed</strong> <span id=\"log\"></span></header>\n"
            "<iframe id=\"tile\" title=\"Web Tile\" src=\"%@\"></iframe>\n"
            "<script>\n"
            "(function () {\n"
            "  const parentOrigin = '%@';\n"
            "  const baseHost = '%@';\n"
            "  const frame = document.getElementById('tile');\n"
            "  const log = document.getElementById('log');\n"
            "  function isTrusted(origin) {\n"
            "    try {\n"
            "      const u = new URL(origin);\n"
            "      const h = u.hostname.toLowerCase();\n"
            "      const base = baseHost.toLowerCase();\n"
            "      if (h === 'load.' + base) return true;\n"
            "      if (h.length > base.length + 1 && h.endsWith('.' + base)) {\n"
            "        const label = h.slice(0, -(base.length + 1));\n"
            "        return label.length === 20 && /^[a-z]+$/.test(label);\n"
            "      }\n"
            "    } catch (_) {}\n"
            "    return false;\n"
            "  }\n"
            "  window.addEventListener('message', (event) => {\n"
            "    if (event.source !== frame.contentWindow) return;\n"
            "    if (!isTrusted(event.origin)) return;\n"
            "    const data = event.data;\n"
            "    if (!data || typeof data.action !== 'string') return;\n"
            "    if (data.action === 'tiles-protocol-up-data-ready') {\n"
            "      log.textContent = 'tile ready';\n"
            "      event.source.postMessage({\n"
            "        action: 'tiles-protocol-down-data-payload',\n"
            "        payload: { hello: 'garazyk-host' }\n"
            "      }, event.origin);\n"
            "    } else if (data.action === 'tiles-protocol-up-data-payload') {\n"
            "      log.textContent = 'tile payload';\n"
            "    }\n"
            "  });\n"
            "})();\n"
            "</script>\n"
            "</body>\n"
            "</html>\n",
            iframeSrc, escapedParent, base];
}

