/**
 * @file GNUstepCFNetworkCompat.h
 * @brief GNUstep compatibility stubs for CFNetwork/CFHTTPMessage functions.
 *
 * These stubs allow code that uses CFHTTPMessage to compile on GNUstep/Linux.
 * They are NOT functional implementations - they return safe defaults.
 * For production use, the HTTP parsing should be refactored to use pure
 * Foundation/GNUstep types.
 *
 * @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#ifdef __APPLE__
#import <CoreFoundation/CoreFoundation.h>
#else

#import <Foundation/Foundation.h>

#ifndef __CFHTTPMESSAGE__
typedef NSObject *CFHTTPMessageRef;
typedef NSObject *CFURLRef;
typedef NSObject *CFDataRef;
typedef NSString *CFStringRef;
#endif

#ifndef kCFAllocatorDefault
#define kCFAllocatorDefault ((NSObject *)nil)
#endif

#ifndef kCFAllocatorNull
#define kCFAllocatorNull ((NSObject *)nil)
#endif

#ifndef __CFHTTPMESSAGE__
static inline CFHTTPMessageRef CFHTTPMessageCreateEmpty(NSObject *allocator, BOOL isRequest) {
    return nil;
}
#endif

#ifndef __CFHTTPMESSAGE__
static inline CFHTTPMessageRef CFHTTPMessageCreateRequest(NSObject *allocator,
                                                           NSString *method,
                                                           CFURLRef url,
                                                           NSString *version) {
    return nil;
}
#endif

#ifndef __CFHTTPMESSAGE__
static inline CFHTTPMessageRef CFHTTPMessageCreateResponse(NSObject *allocator,
                                                          NSInteger statusCode,
                                                          NSString *statusMessage,
                                                          NSString *version) {
    return nil;
}
#endif

#ifndef __CFHTTPMESSAGE__
static inline void CFHTTPMessageSetHeaderFieldValue(CFHTTPMessageRef message,
                                                     NSString *field,
                                                     NSString *value) {
}
#endif

#ifndef __CFHTTPMESSAGE__
static inline NSString * _Nullable CFHTTPMessageCopyHeaderFieldValue(CFHTTPMessageRef message,
                                                                      NSString *field) {
    return nil;
}
#endif

#ifndef __CFHTTPMESSAGE__
static inline NSDictionary * _Nullable CFHTTPMessageCopyAllHeaderFields(CFHTTPMessageRef message) {
    return nil;
}
#endif

#ifndef __CFHTTPMESSAGE__
static inline BOOL CFHTTPMessageAppendBytes(CFHTTPMessageRef message,
                                            const void *bytes,
                                            NSUInteger length) {
    return NO;
}
#endif

#ifndef __CFHTTPMESSAGE__
static inline BOOL CFHTTPMessageIsHeaderComplete(CFHTTPMessageRef message) {
    return NO;
}
#endif

#ifndef __CFHTTPMESSAGE__
static inline NSString * _Nullable CFHTTPMessageCopyRequestMethod(CFHTTPMessageRef message) {
    return nil;
}
#endif

#ifndef __CFHTTPMESSAGE__
static inline CFURLRef _Nullable CFHTTPMessageCopyRequestURL(CFHTTPMessageRef message) {
    return nil;
}
#endif

#ifndef __CFHTTPMESSAGE__
static inline NSString * _Nullable CFHTTPMessageCopyVersion(CFHTTPMessageRef message) {
    return nil;
}
#endif

#ifndef __CFHTTPMESSAGE__
static inline NSData * _Nullable CFHTTPMessageCopyBody(CFHTTPMessageRef message) {
    return nil;
}
#endif

#ifndef __CFHTTPMESSAGE__
static inline void CFHTTPMessageSetBody(CFHTTPMessageRef message, CFDataRef body) {
}
#endif

#ifndef __CFURL__
static inline void CFURLRelease(CFURLRef url) {
}

static inline CFURLRef CFURLCreateWithString(NSObject *allocator,
                                             NSString *urlString,
                                             NSURL *baseURL) {
    return nil;
}

static inline CFURLRef CFURLCreateWithBytes(NSObject *allocator,
                                             const UInt8 *bytes,
                                             NSInteger length,
                                             NSStringEncoding encoding,
                                             NSURL *baseURL) {
    return nil;
}

static inline NSURL * _Nullable CFURLToNSURL(CFURLRef cfURL) {
    return nil;
}
#endif

#ifndef __CFHOST__
typedef NSObject *CFHostRef;
typedef NSObject *CFStreamError;
typedef NSObject *CFArrayRef;
typedef NSObject *CFDataRef;
typedef CFIndex CFHostInfoType;

#define kCFHostAddresses 0
#define kCFHostReverseAddresses 1

struct CFStreamErrorStruct {
    int error;
    NSInteger domain;
};

typedef struct CFStreamErrorStruct CFStreamError;

static inline CFHostRef CFHostCreateWithName(NSObject *allocator, NSString *hostname) {
    return nil;
}

static inline BOOL CFHostStartInfoResolution(CFHostRef host,
                                              CFHostInfoType infoType,
                                              NSObject * _Nullable * _Nullable error) {
    return NO;
}

static inline CFArrayRef _Nullable CFHostGetAddressing(CFHostRef host, NSObject * _Nullable * _Nullable error) {
    return nil;
}

static inline void CFRelease(CFObjectRef cf) {
}

static inline CFIndex CFArrayGetCount(CFArrayRef array) {
    return 0;
}

static inline NSObject * _Nullable CFArrayGetValueAtIndex(CFArrayRef array, CFIndex idx) {
    return nil;
}

static inline CFTypeID CFDataGetTypeID(void) {
    return 0;
}

static inline CFTypeID CFGetTypeID(CFObjectRef cf) {
    return 0;
}

static inline const UInt8 * CFDataGetBytePtr(CFDataRef data) {
    return nil;
}

static inline CFIndex CFDataGetLength(CFDataRef data) {
    return 0;
}
#endif

#endif /* !__APPLE__ */