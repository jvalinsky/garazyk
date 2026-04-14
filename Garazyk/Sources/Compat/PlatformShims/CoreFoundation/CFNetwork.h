#ifndef CFNetwork_h
#define CFNetwork_h

#if defined(__APPLE__)
#import <CFNetwork/CFNetwork.h>
#else

// Import CF types FIRST (no Foundation dependency)
#include "CFTypes.h"

// Then import Foundation for other needs
#include <Foundation/Foundation.h>

// Then import Security (needs CF types)
#include "Security/Security.h"

// CFURL type (must be defined before use)
typedef struct __CFURL *CFURLRef;

// CFHTTPMessage types
typedef struct __CFHTTPMessage *CFHTTPMessageRef;

// CFHTTPMessage functions (implemented in CFNetwork.m)
CFHTTPMessageRef CFHTTPMessageCreateEmpty(CFAllocatorRef alloc, Boolean isRequest);
Boolean CFHTTPMessageAppendBytes(CFHTTPMessageRef message, const UInt8 *bytes, CFIndex numBytes);
Boolean CFHTTPMessageIsHeaderComplete(CFHTTPMessageRef message);
CFStringRef CFHTTPMessageCopyRequestMethod(CFHTTPMessageRef message);
CFURLRef CFHTTPMessageCopyRequestURL(CFHTTPMessageRef message);
CFDictionaryRef CFHTTPMessageCopyAllHeaderFields(CFHTTPMessageRef message);
CFDataRef CFHTTPMessageCopyBody(CFHTTPMessageRef message);
CFStringRef CFHTTPMessageCopyVersion(CFHTTPMessageRef message);
void CFHTTPMessageSetBody(CFHTTPMessageRef message, CFDataRef bodyData);

// CFURL functions
CFStringRef CFURLCopyPath(CFURLRef url);
CFStringRef CFURLGetString(CFURLRef url);

// Helper function to get specific header field
CFStringRef CFHTTPMessageCopyHeaderFieldValue(CFHTTPMessageRef message, CFStringRef headerField);

// CFSTR macro for creating constant strings
#define CFSTR(cStr) ((__bridge CFStringRef)@cStr)

// Helper to convert CFURLRef to NSURL (for Linux compat)
NSURL *CFURLToNSURL(CFURLRef url);

// Helper to release CFURLRef (for Linux compat)
void CFURLRelease(CFURLRef url);

#endif

#endif /* CFNetwork_h */
