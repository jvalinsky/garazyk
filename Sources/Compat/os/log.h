#ifndef COMPAT_OS_LOG_H
#define COMPAT_OS_LOG_H

#if defined(__APPLE__)
#include_next <os/log.h>

#elif defined(GNUSTEP) || defined(__linux__)
#import <Foundation/Foundation.h>

typedef void* os_log_t;
#define OS_LOG_DEFAULT ((os_log_t)1)

static inline os_log_t os_log_create(const char *subsystem, const char *category) {
    return (os_log_t)1;
}

static inline void os_log_internal(os_log_t log, NSString *level, NSString *format, ...) {
    NSMutableString *fullFormat = [NSMutableString stringWithFormat:@"[%s] %@", subsystem ?: "unknown", format];
    va_list args;
    va_start(args, format);
    NSLogv(fullFormat, args);
    va_end(args);
}

#define os_log(log, format, ...) \
    do { \
        NSString *_fmt = [NSString stringWithFormat:format, ##__VA_ARGS__]; \
        NSLog(@"[ATProtoPDS] %@", _fmt); \
    } while(0)

#define os_log_info(log, format, ...) \
    do { \
        NSString *_fmt = [NSString stringWithFormat:format, ##__VA_ARGS__]; \
        NSLog(@"[ATProtoPDS INFO] %@", _fmt); \
    } while(0)

#define os_log_error(log, format, ...) \
    do { \
        NSString *_fmt = [NSString stringWithFormat:format, ##__VA_ARGS__]; \
        NSLog(@"[ATProtoPDS ERROR] %@", _fmt); \
    } while(0)

#define os_log_debug(log, format, ...) \
    do { \
        NSString *_fmt = [NSString stringWithFormat:format, ##__VA_ARGS__]; \
        NSLog(@"[ATProtoPDS DEBUG] %@", _fmt); \
    } while(0)

#define os_log_fault(log, format, ...) \
    do { \
        NSString *_fmt = [NSString stringWithFormat:format, ##__VA_ARGS__]; \
        NSLog(@"[ATProtoPDS FAULT] %@", _fmt); \
    } while(0)

#else
#error "Unsupported platform"
#endif

#endif // COMPAT_OS_LOG_H
