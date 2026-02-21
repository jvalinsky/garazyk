#ifndef OSAtomic_h
#define OSAtomic_h

#if defined(__APPLE__)
#include <libkern/OSAtomic.h>
#else

#include <stdint.h>

static inline int64_t OSAtomicIncrement64(volatile int64_t *ptr) {
    return __atomic_add_fetch(ptr, 1, __ATOMIC_SEQ_CST);
}

static inline int64_t OSAtomicDecrement64(volatile int64_t *ptr) {
    return __atomic_sub_fetch(ptr, 1, __ATOMIC_SEQ_CST);
}

static inline int32_t OSAtomicIncrement32(volatile int32_t *ptr) {
    return __atomic_add_fetch(ptr, 1, __ATOMIC_SEQ_CST);
}

static inline int32_t OSAtomicDecrement32(volatile int32_t *ptr) {
    return __atomic_sub_fetch(ptr, 1, __ATOMIC_SEQ_CST);
}

static inline void OSMemoryBarrier(void) {
    __sync_synchronize();
}

static inline bool OSAtomicCompareAndSwapPtr(void *oldVal, void *newVal, void *volatile *ptr) {
    return __atomic_compare_exchange_n(ptr, &oldVal, newVal, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
}

static inline bool OSAtomicCompareAndSwapInt(int oldVal, int newVal, volatile int *ptr) {
    return __atomic_compare_exchange_n(ptr, &oldVal, newVal, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
}

static inline bool OSAtomicCompareAndSwapLong(long oldVal, long newVal, volatile long *ptr) {
    return __atomic_compare_exchange_n(ptr, &oldVal, newVal, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
}

#endif

#endif /* OSAtomic_h */
