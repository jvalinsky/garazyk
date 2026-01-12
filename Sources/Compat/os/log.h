#ifndef COMPAT_OS_LOG_H
#define COMPAT_OS_LOG_H

#if defined(__APPLE__)
#include_next <os/log.h>

#elif defined(GNUSTEP) || defined(__linux__)
#include <syslog.h>
#include <stdarg.h>
#include <stdio.h>

typedef void* os_log_t;
#define OS_LOG_DEFAULT ((os_log_t)1)

static inline os_log_t os_log_create(const char *subsystem, const char *category) {
    openlog(subsystem, LOG_PID | LOG_CONS, LOG_USER);
    return (os_log_t)1;
}

static inline void os_log_internal(os_log_t log, int level, const char *format, va_list args) {
    vsyslog(LOG_USER | level, format, args);
}

#define os_log(log, format, ...) \
    do { \
        if (log == OS_LOG_DEFAULT) { \
            syslog(LOG_ERR, format, ##__VA_ARGS__); \
        } else { \
            syslog(LOG_USER | LOG_ERR, format, ##__VA_ARGS__); \
        } \
    } while(0)

#define os_log_info(log, format, ...) \
    do { \
        if (log == OS_LOG_DEFAULT) { \
            syslog(LOG_INFO, format, ##__VA_ARGS__); \
        } else { \
            syslog(LOG_USER | LOG_INFO, format, ##__VA_ARGS__); \
        } \
    } while(0)

#define os_log_error(log, format, ...) \
    do { \
        if (log == OS_LOG_DEFAULT) { \
            syslog(LOG_ERR, format, ##__VA_ARGS__); \
        } else { \
            syslog(LOG_USER | LOG_ERR, format, ##__VA_ARGS__); \
        } \
    } while(0)

#define os_log_debug(log, format, ...) \
    do { \
        if (log == OS_LOG_DEFAULT) { \
            syslog(LOG_DEBUG, format, ##__VA_ARGS__); \
        } else { \
            syslog(LOG_USER | LOG_DEBUG, format, ##__VA_ARGS__); \
        } \
    } while(0)

#define os_log_fault(log, format, ...) \
    do { \
        if (log == OS_LOG_DEFAULT) { \
            syslog(LOG_CRIT, format, ##__VA_ARGS__); \
        } else { \
            syslog(LOG_USER | LOG_CRIT, format, ##__VA_ARGS__); \
        } \
    } while(0)

#else
#error "Unsupported platform"
#endif

#endif // COMPAT_OS_LOG_H
