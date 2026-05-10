/*!
 @file MSTAtomicReference.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Core/MSTAtomicReference.h"
#import "Repository/MST.h"
#include <pthread.h>

@implementation MSTAtomicReference {
    MST *_mst;
}

- (instancetype)initWithMST:(MST *)mst {
    self = [super init];
    if (self) {
        pthread_mutex_init(&_mutex, NULL);
        _mst = mst;  // ARC retains
    }
    return self;
}

- (void)dealloc {
    pthread_mutex_destroy(&_mutex);
    // ARC releases _mst
}

- (MST *)currentSnapshot {
    pthread_mutex_lock(&_mutex);
    MST *result = _mst;
    pthread_mutex_unlock(&_mutex);
    return result;
}

- (void)swapMST:(MST *)newMst {
    pthread_mutex_lock(&_mutex);
    _mst = newMst;  // ARC releases old, retains new
    pthread_mutex_unlock(&_mutex);
}

- (void)clear {
    pthread_mutex_lock(&_mutex);
    _mst = nil;
    pthread_mutex_unlock(&_mutex);
}

@end
