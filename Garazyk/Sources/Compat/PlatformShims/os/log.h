// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
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

#define GZ_LOG_CONVERT(fmt) @fmt

#define os_log(log, format, ...) \
    NSLog(GZ_LOG_CONVERT(format), ##__VA_ARGS__)

#define os_log_info(log, format, ...) \
    NSLog(@"[ATProtoPDS INFO] " GZ_LOG_CONVERT(format), ##__VA_ARGS__)

#define os_log_error(log, format, ...) \
    NSLog(@"[ATProtoPDS ERROR] " GZ_LOG_CONVERT(format), ##__VA_ARGS__)

#define os_log_debug(log, format, ...) \
    NSLog(@"[ATProtoPDS DEBUG] " GZ_LOG_CONVERT(format), ##__VA_ARGS__)

#define os_log_fault(log, format, ...) \
    NSLog(@"[ATProtoPDS FAULT] " GZ_LOG_CONVERT(format), ##__VA_ARGS__)

#else
#error "Unsupported platform"
#endif

#endif // COMPAT_OS_LOG_H
