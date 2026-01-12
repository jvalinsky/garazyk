#ifndef OS_LOG_COMPAT_H
#define OS_LOG_COMPAT_H

#if defined(__APPLE__)
#include_next <os/log.h>
#else

#import <Foundation/Foundation.h>

#define os_log_t id
#define OS_LOG_TYPE_DEFAULT 0
#define OS_LOG_TYPE_INFO 1
#define OS_LOG_TYPE_DEBUG 2
#define OS_LOG_TYPE_ERROR 3
#define OS_LOG_TYPE_FAULT 4

#define os_log(log, format, ...) NSLog(format, ##__VA_ARGS__)
#define os_log_error(log, format, ...) NSLog(@"[ERROR] " format, ##__VA_ARGS__)
#define os_log_info(log, format, ...) NSLog(@"[INFO] " format, ##__VA_ARGS__)
#define os_log_debug(log, format, ...) NSLog(@"[DEBUG] " format, ##__VA_ARGS__)
#define os_log_create(subsystem, category) [NSString stringWithFormat:@"%s:%s", subsystem, category]

#endif
#endif
