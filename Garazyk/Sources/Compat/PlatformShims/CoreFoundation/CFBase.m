#include "CFBase.h"

#if !defined(__APPLE__)

#include <Foundation/Foundation.h>

// CFBoolean constants - use NSNumber bools with ARC retention
static NSNumber *_kCFBooleanTrue = nil;
static NSNumber *_kCFBooleanFalse = nil;
static NSNull *_kCFNull = nil;

__attribute__((constructor))
static void _CFBaseInit(void) {
    _kCFBooleanTrue = [NSNumber numberWithBool:YES];
    _kCFBooleanFalse = [NSNumber numberWithBool:NO];
    _kCFNull = [NSNull null];
}

const CFBooleanRef kCFBooleanTrue = (CFBooleanRef)&_kCFBooleanTrue;
const CFBooleanRef kCFBooleanFalse = (CFBooleanRef)&_kCFBooleanFalse;
const CFNullRef kCFNull = (CFNullRef)&_kCFNull;

#endif
