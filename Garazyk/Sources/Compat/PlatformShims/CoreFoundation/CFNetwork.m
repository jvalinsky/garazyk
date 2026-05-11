// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#if !defined(__APPLE__)

#import "CoreFoundation/CFNetwork.h"
#import <Foundation/Foundation.h>

// Simple HTTP message parser for Linux/GNUstep

struct __CFHTTPMessage {
    NSMutableData *data;
    NSString *method;
    NSString *path;
    NSString *version;
    NSMutableDictionary *headers;
    NSData *body;
    BOOL isRequest;
    BOOL headerComplete;
    NSUInteger headerEndOffset;
};

struct __CFURL {
    NSString *urlString;
    NSString *path;
};

CFHTTPMessageRef CFHTTPMessageCreateEmpty(CFAllocatorRef alloc, Boolean isRequest) {
    struct __CFHTTPMessage *msg = calloc(1, sizeof(struct __CFHTTPMessage));
    if (!msg) return NULL;
    
    msg->data = [[NSMutableData alloc] init];
    msg->headers = [[NSMutableDictionary alloc] init];
    msg->isRequest = isRequest;
    msg->headerComplete = NO;
    msg->headerEndOffset = 0;
    return msg;
}

static void parseRequestLine(CFHTTPMessageRef msg, NSString *line) {
    NSArray *parts = [line componentsSeparatedByString:@" "];
    if (parts.count >= 3) {
        msg->method = [parts[0] copy];
        msg->path = [parts[1] copy];
        msg->version = [parts[2] copy];
    }
}

static void parseHeaderLine(CFHTTPMessageRef msg, NSString *line) {
    NSRange colonRange = [line rangeOfString:@":"];
    if (colonRange.location != NSNotFound) {
        NSString *name = [[line substringToIndex:colonRange.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *value = [[line substringFromIndex:colonRange.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        msg->headers[name] = value;
    }
}

Boolean CFHTTPMessageAppendBytes(CFHTTPMessageRef msg, const UInt8 *bytes, CFIndex numBytes) {
    if (!msg || !bytes || numBytes <= 0) return false;
    
    [msg->data appendBytes:bytes length:numBytes];
    
    // Check if headers are complete (look for \r\n\r\n)
    if (!msg->headerComplete) {
        NSString *dataStr = [[NSString alloc] initWithData:msg->data encoding:NSUTF8StringEncoding];
        if (!dataStr) {
            dataStr = [[NSString alloc] initWithData:msg->data encoding:NSISOLatin1StringEncoding];
        }
        
        if (dataStr) {
            NSRange headerEnd = [dataStr rangeOfString:@"\r\n\r\n"];
            if (headerEnd.location != NSNotFound) {
                msg->headerComplete = YES;
                msg->headerEndOffset = headerEnd.location + 4;
                
                // Parse the headers
                NSString *headerSection = [dataStr substringToIndex:headerEnd.location];
                NSArray *lines = [headerSection componentsSeparatedByString:@"\r\n"];
                
                BOOL firstLine = YES;
                for (NSString *line in lines) {
                    if (line.length == 0) continue;
                    if (firstLine && msg->isRequest) {
                        parseRequestLine(msg, line);
                        firstLine = NO;
                    } else {
                        parseHeaderLine(msg, line);
                    }
                }
            }
        }
    }
    
    return true;
}

Boolean CFHTTPMessageIsHeaderComplete(CFHTTPMessageRef msg) {
    return msg ? msg->headerComplete : false;
}

CFStringRef CFHTTPMessageCopyRequestMethod(CFHTTPMessageRef msg) {
    if (!msg || !msg->method) return NULL;
    return (__bridge_retained CFStringRef)[msg->method copy];
}

CFURLRef CFHTTPMessageCopyRequestURL(CFHTTPMessageRef msg) {
    if (!msg || !msg->path) return NULL;
    
    struct __CFURL *url = calloc(1, sizeof(struct __CFURL));
    if (!url) return NULL;
    
    url->urlString = [msg->path copy];
    url->path = [msg->path copy];
    
    // Strip query string from path
    NSRange queryRange = [url->path rangeOfString:@"?"];
    if (queryRange.location != NSNotFound) {
        url->path = [url->path substringToIndex:queryRange.location];
    }
    
    return url;
}

CFDictionaryRef CFHTTPMessageCopyAllHeaderFields(CFHTTPMessageRef msg) {
    if (!msg || !msg->headers) return NULL;
    return (__bridge_retained CFDictionaryRef)[msg->headers copy];
}

CFDataRef CFHTTPMessageCopyBody(CFHTTPMessageRef msg) {
    if (!msg || !msg->headerComplete) return NULL;
    
    if (msg->data.length > msg->headerEndOffset) {
        NSData *body = [msg->data subdataWithRange:NSMakeRange(msg->headerEndOffset, msg->data.length - msg->headerEndOffset)];
        return (__bridge_retained CFDataRef)[body copy];
    }
    return NULL;
}

CFStringRef CFHTTPMessageCopyVersion(CFHTTPMessageRef msg) {
    if (!msg || !msg->version) return NULL;
    return (__bridge_retained CFStringRef)[msg->version copy];
}

void CFHTTPMessageSetBody(CFHTTPMessageRef msg, CFDataRef bodyData) {
    if (!msg) return;
    msg->body = (__bridge NSData *)bodyData;
}

CFStringRef CFURLCopyPath(CFURLRef url) {
    if (!url) return NULL;
    struct __CFURL *u = (struct __CFURL *)url;
    return (__bridge_retained CFStringRef)[u->path copy];
}

CFStringRef CFURLGetString(CFURLRef url) {
    if (!url) return NULL;
    struct __CFURL *u = (struct __CFURL *)url;
    return (__bridge CFStringRef)u->urlString;
}

CFStringRef CFHTTPMessageCopyHeaderFieldValue(CFHTTPMessageRef msg, CFStringRef headerField) {
    if (!msg || !msg->headers || !headerField) return NULL;
    NSString *fieldName = (__bridge NSString *)headerField;
    NSString *value = msg->headers[fieldName];
    if (!value) {
        // Try case-insensitive lookup
        for (NSString *key in msg->headers) {
            if ([key caseInsensitiveCompare:fieldName] == NSOrderedSame) {
                value = msg->headers[key];
                break;
            }
        }
    }
    return value ? (__bridge_retained CFStringRef)[value copy] : NULL;
}

NSURL *CFURLToNSURL(CFURLRef url) {
    if (!url) return nil;
    struct __CFURL *u = (struct __CFURL *)url;
    return [NSURL URLWithString:u->urlString];
}

void CFURLRelease(CFURLRef url) {
    if (!url) return;
    struct __CFURL *u = (struct __CFURL *)url;
    u->urlString = nil;
    u->path = nil;
    free(u);
}

#endif
