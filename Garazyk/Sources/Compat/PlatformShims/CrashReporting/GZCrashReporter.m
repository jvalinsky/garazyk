// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file GZCrashReporter.m

 @abstract Implementation of shared crash signal and exception handler.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "GZCrashReporter.h"
#import <signal.h>
#import <unistd.h>
#import <fcntl.h>
#import <string.h>
#import <execinfo.h>

#if defined(__APPLE__)
#import <TargetConditionals.h>
#endif

#ifdef LINUX
#import <ucontext.h>
#endif

/// Path prefix for crash log files. The executable name is appended.
static const char *kCrashLogPathPrefix = "/tmp/";

/// Currently active executable name (set during install).
static const char *gExecutableName = "unknown";

#pragma mark - Crash Signal Handler

/*!
 @abstract Async-signal-safe crash signal handler.

 @discussion Writes a crash report to /tmp/<name>-crash.log and stderr using
 only async-signal-safe calls. Extracts the program counter from ucontext_t
 on all supported architectures. Re-raises the signal with default disposition
 to produce a core dump.
 */
static void GZCrashSignalHandler(int sig, siginfo_t *si, void *ctx) {
    const char *signame = (sig == SIGSEGV) ? "SIGSEGV" :
                          (sig == SIGABRT) ? "SIGABRT" :
                          (sig == SIGBUS)  ? "SIGBUS"  :
                          (sig == SIGFPE)  ? "SIGFPE"  :
                          (sig == SIGTRAP) ? "SIGTRAP" : "UNKNOWN";

    // Write to stderr
    char buf[512];
    int len = snprintf(buf, sizeof(buf),
        "\n=== FATAL SIGNAL %s (%d) in %s ===\n"
        "Fault address: %p (si_code=%d)\n",
        signame, sig, gExecutableName, si->si_addr, si->si_code);
    write(STDERR_FILENO, buf, (size_t)len);

    // Extract PC from ucontext_t (platform-specific)
    uint64_t pc = 0;
    uint64_t lr = 0;
    uint64_t bp = 0;

#if defined(__APPLE__) && defined(__arm64__)
    // macOS ARM64: use arm_unified_thread_state_t via _STRUCT_MCONTEXT
    ucontext_t *uc = (ucontext_t *)ctx;
    if (uc && uc->uc_mcontext) {
        _STRUCT_MCONTEXT *mc = uc->uc_mcontext;
        pc = mc->__ss.__pc;
        lr = mc->__ss.__lr;
        len = snprintf(buf, sizeof(buf),
            "Crash PC: 0x%llx (LR: 0x%llx)\n", pc, lr);
        write(STDERR_FILENO, buf, (size_t)len);
    }
#elif defined(__APPLE__) && defined(__x86_64__)
    ucontext_t *uc = (ucontext_t *)ctx;
    if (uc && uc->uc_mcontext) {
        _STRUCT_MCONTEXT *mc = uc->uc_mcontext;
        pc = mc->__ss.__rip;
        bp = mc->__ss.__rbp;
        len = snprintf(buf, sizeof(buf),
            "Crash PC: 0x%llx (RBP: 0x%llx)\n", pc, bp);
        write(STDERR_FILENO, buf, (size_t)len);
    }
#elif defined(LINUX) && defined(__aarch64__)
    ucontext_t *uc = (ucontext_t *)ctx;
    pc = uc->uc_mcontext.pc;
    lr = uc->uc_mcontext.regs[30]; // x30 = link register
    len = snprintf(buf, sizeof(buf),
        "Crash PC: 0x%llx (LR: 0x%llx)\n",
        (unsigned long long)pc, (unsigned long long)lr);
    write(STDERR_FILENO, buf, (size_t)len);
#elif defined(LINUX) && defined(__x86_64__)
    ucontext_t *uc = (ucontext_t *)ctx;
    pc = (uint64_t)uc->uc_mcontext.gregs[REG_RIP];
    bp = (uint64_t)uc->uc_mcontext.gregs[REG_RBP];
    len = snprintf(buf, sizeof(buf),
        "Crash PC: 0x%llx (RBP: 0x%llx)\n",
        (unsigned long long)pc, (unsigned long long)bp);
    write(STDERR_FILENO, buf, (size_t)len);
#endif

    // Write crash log file
    char logPath[256];
    len = snprintf(logPath, sizeof(logPath), "%s%s-crash.log",
                   kCrashLogPathPrefix, gExecutableName);
    int fd = open(logPath, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        // Header
        len = snprintf(buf, sizeof(buf),
            "\n=== FATAL SIGNAL %s (%d) in %s ===\n"
            "Fault address: %p (si_code=%d)\n",
            signame, sig, gExecutableName, si->si_addr, si->si_code);
        write(fd, buf, (size_t)len);

        // PC info
        if (pc != 0) {
#if defined(__arm64__) || (defined(LINUX) && defined(__aarch64__))
            len = snprintf(buf, sizeof(buf),
                "Crash PC: 0x%llx (LR: 0x%llx)\n",
                (unsigned long long)pc, (unsigned long long)lr);
#elif defined(__x86_64__)
            len = snprintf(buf, sizeof(buf),
                "Crash PC: 0x%llx (RBP: 0x%llx)\n",
                (unsigned long long)pc, (unsigned long long)bp);
#else
            len = snprintf(buf, sizeof(buf),
                "Crash PC: 0x%llx\n", (unsigned long long)pc);
#endif
            write(fd, buf, (size_t)len);
        }

        // Backtrace (try — may crash if heap is corrupted)
        void *frames[32];
        int frame_count = (int)backtrace(frames, 32);
        // Replace frame 1 with the actual crash PC if available
        if (pc != 0 && frame_count > 1) {
            frames[1] = (void *)pc;
        }
        for (int i = 0; i < frame_count; i++) {
            char frame_buf[64];
            int flen = snprintf(frame_buf, sizeof(frame_buf),
                                "  #%d %p\n", i, frames[i]);
            write(fd, frame_buf, (size_t)flen);
        }

        char **symbols = backtrace_symbols(frames, frame_count);
        if (symbols) {
            for (int i = 0; i < frame_count; i++) {
                char sym_buf[256];
                int slen = snprintf(sym_buf, sizeof(sym_buf),
                                    "  #%d %s\n", i, symbols[i] ?: "?");
                write(fd, sym_buf, (size_t)slen);
            }
            free(symbols);
        }

        close(fd);
    }

    // Re-raise with default handler to produce core dump
    signal(sig, SIG_DFL);
    raise(sig);
}

#pragma mark - Uncaught Exception Handler

/*!
 @abstract Logs an uncaught ObjC exception before the runtime aborts.
 */
static void GZCrashUncaughtExceptionHandler(NSException *exception) {
    fprintf(stderr, "\n=== UNCAUGHT EXCEPTION ===\n");
    fprintf(stderr, "Name: %s\n", exception.name.UTF8String ?: "?");
    fprintf(stderr, "Reason: %s\n", exception.reason.UTF8String ?: "?");

    char logPath[256];
    int len = snprintf(logPath, sizeof(logPath), "%s%s-crash.log",
                       kCrashLogPathPrefix, gExecutableName);
    int fd = open(logPath, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        char buf[1024];
        len = snprintf(buf, sizeof(buf),
            "=== UNCAUGHT EXCEPTION ===\nName: %s\nReason: %s\n",
            exception.name.UTF8String ?: "?",
            exception.reason.UTF8String ?: "?");
        write(fd, buf, (size_t)len);
        close(fd);
    }

    fflush(stderr);
}

#pragma mark - GZCrashReporter

@implementation GZCrashReporter

+ (void)installCrashHandlersWithExecutableName:(const char *)name {
    gExecutableName = name ?: "unknown";

    // Allocate alternate signal stack for overflow protection
    stack_t ss;
    ss.ss_sp = malloc(SIGSTKSZ);
    ss.ss_size = SIGSTKSZ;
    ss.ss_flags = 0;
    if (sigaltstack(&ss, NULL) != 0) {
        // Non-fatal: continue without alt stack
    }

    // Install crash signal handlers via sigaction
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = GZCrashSignalHandler;
    sa.sa_flags = SA_SIGINFO | SA_RESETHAND | SA_ONSTACK;
    sigemptyset(&sa.sa_mask);

    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGABRT, &sa, NULL);
    sigaction(SIGBUS,  &sa, NULL);
    sigaction(SIGFPE,  &sa, NULL);
    sigaction(SIGTRAP, &sa, NULL);

    // Install uncaught exception handler
    NSSetUncaughtExceptionHandler(&GZCrashUncaughtExceptionHandler);
}

@end
