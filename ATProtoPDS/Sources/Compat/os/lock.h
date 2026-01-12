#ifndef OS_LOCK_COMPAT_H
#define OS_LOCK_COMPAT_H

#if defined(__APPLE__)
#include_next <os/lock.h>
#else

#include <pthread.h>

typedef pthread_mutex_t os_unfair_lock;
#define OS_UNFAIR_LOCK_INIT PTHREAD_MUTEX_INITIALIZER

static inline void os_unfair_lock_lock(os_unfair_lock *lock) {
    pthread_mutex_lock(lock);
}

static inline void os_unfair_lock_unlock(os_unfair_lock *lock) {
    pthread_mutex_unlock(lock);
}

#endif
#endif
