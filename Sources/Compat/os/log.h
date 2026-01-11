#ifndef COMPAT_OS_LOG_H
#define COMPAT_OS_LOG_H

#ifdef GNUSTEP
#import <Foundation/Foundation.h>

typedef void* os_log_t;
#define OS_LOG_DEFAULT ((os_log_t)0)

static inline os_log_t os_log_create(const char *subsystem, const char *category) {
    return (os_log_t)0;
}

#define os_log(log, format, ...) NSLog([NSString stringWithUTF8String:format], ##__VA_ARGS__)
#define os_log_info(log, format, ...) NSLog([NSString stringWithUTF8String:format], ##__VA_ARGS__)
#define os_log_error(log, format, ...) NSLog([NSString stringWithUTF8String:format], ##__VA_ARGS__)
#define os_log_debug(log, format, ...) NSLog([NSString stringWithUTF8String:format], ##__VA_ARGS__)
#define os_log_fault(log, format, ...) NSLog([NSString stringWithUTF8String:format], ##__VA_ARGS__)

#else
#include_next <os/log.h>
#endif

#endif // COMPAT_OS_LOG_H
