#import <Foundation/Foundation.h>
#import "CLI/PDSCLIDefinitions.h"
#import "Core/NSDateFormatter+ATProto.h"
#import "Debug/PDSLogger.h"
#import <execinfo.h>
#import <signal.h>
#import <fcntl.h>
#import <unistd.h>
#import <string.h>
#ifdef LINUX
#import <ucontext.h>
#endif

/**
 * @file main.m
 * @brief Entry point for the PDS command-line interface.
 *
 * This file implements the main function that parses command-line arguments,
 * initializes the execution context, and dispatches commands to the appropriate
 * handlers. The CLI supports various global options and commands for managing
 * the ATProto PDS server.
 */

// On Linux/GNUstep with GNU ld, +load methods in unreferenced objects within
// static archives are stripped. Import the explicit registration function
// so all CLI commands are available.
extern void PDSCLIRegisterAllCommands(void);

// Force NSDateFormatter category to be linked
extern void NSDateFormatterLinkATProtoCategory(void);

/// The name of the executable for usage messages.
static const char *executable_name = "kaszlak";

#pragma mark - Crash Diagnostics

/// Writes a crash report to /tmp/kaszlak-crash.log using async-signal-safe calls.
/// Avoids fprintf/backtrace_symbols (not async-signal-safe) to prevent re-crash
/// inside the handler when the stack is corrupted.
static void crash_signal_handler(int sig, siginfo_t *si, void *ctx) {
    const char *signame = (sig == SIGSEGV) ? "SIGSEGV" :
                          (sig == SIGABRT) ? "SIGABRT" :
                          (sig == SIGBUS)  ? "SIGBUS"  :
                          (sig == SIGFPE)  ? "SIGFPE"  : "UNKNOWN";

    // Use write() (async-signal-safe) instead of fprintf
    char buf[512];
    int len = snprintf(buf, sizeof(buf),
        "\n=== FATAL SIGNAL %s (%d) in kaszlak ===\n"
        "Fault address: %p (si_code=%d)\n",
        signame, sig, si->si_addr, si->si_code);
    write(STDERR_FILENO, buf, (size_t)len);

    // Extract the PC (program counter) from the ucontext
#ifdef LINUX
    ucontext_t *uc = (ucontext_t *)ctx;
#if defined(__aarch64__)
    uint64_t pc = uc->uc_mcontext.pc;
    uint64_t lr = uc->uc_mcontext.regs[30]; // x30 = link register
    len = snprintf(buf, sizeof(buf),
        "Crash PC: 0x%llx (LR: 0x%llx)\n", pc, lr);
    write(STDERR_FILENO, buf, (size_t)len);
#elif defined(__x86_64__)
    uint64_t pc = uc->uc_mcontext.gregs[REG_RIP];
    uint64_t bp = uc->uc_mcontext.gregs[REG_RBP];
    len = snprintf(buf, sizeof(buf),
        "Crash PC: 0x%llx (RBP: 0x%llx)\n", pc, bp);
    write(STDERR_FILENO, buf, (size_t)len);
#endif
#endif

    // backtrace() from signal handler context gives the handler's stack,
    // not the original crash site. But we already have the PC from ucontext.
    // Try backtrace anyway for additional context.
    void *frames[32];
    int frame_count = (int)backtrace(frames, 32);
    // Replace frame 0 with the actual crash PC if available
#if (defined(__aarch64__) || defined(__x86_64__)) && defined(LINUX)
    if (frame_count > 1) {
        frames[1] = (void *)pc; // Put crash PC in frame 1
    }
#endif
    // Write raw frame addresses to stderr (always safe)
    for (int i = 0; i < frame_count; i++) {
        char frame_buf[64];
        int flen = snprintf(frame_buf, sizeof(frame_buf),
                            "  #%d %p\n", i, frames[i]);
        write(STDERR_FILENO, frame_buf, (size_t)flen);
    }

    // Try symbolic names (may crash if heap is corrupted)
    char **symbols = backtrace_symbols(frames, frame_count);
    if (symbols) {
        for (int i = 0; i < frame_count; i++) {
            char sym_buf[256];
            int slen = snprintf(sym_buf, sizeof(sym_buf),
                                "  #%d %s\n", i, symbols[i] ?: "?");
            write(STDERR_FILENO, sym_buf, (size_t)slen);
        }
        free(symbols);
    }

    // Re-raise with default handler to produce core dump
    signal(sig, SIG_DFL);
    raise(sig);
}

/// Logs an uncaught ObjC exception before the runtime aborts.
static void uncaught_exception_handler(NSException *exception) {
    fprintf(stderr, "\n=== UNCAUGHT EXCEPTION ===\n");
    fprintf(stderr, "Name: %s\n", exception.name.UTF8String ?: "?");
    fprintf(stderr, "Reason: %s\n", exception.reason.UTF8String ?: "?");
    fprintf(stderr, "User Info: %s\n",
            exception.userInfo.description.UTF8String ?: "");

    // Write to crash log file
    int fd = open("/tmp/kaszlak-crash.log",
                  O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        char buf[1024];
        int len = snprintf(buf, sizeof(buf),
            "=== UNCAUGHT EXCEPTION ===\nName: %s\nReason: %s\n",
            exception.name.UTF8String ?: "?",
            exception.reason.UTF8String ?: "?");
        write(fd, buf, (size_t)len);
        close(fd);
    }

    fflush(stderr);
}

/// Installs crash signal handlers using sigaction (more reliable than signal())
/// and the uncaught exception handler.
static void install_crash_handlers(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = crash_signal_handler;
    sa.sa_flags = SA_SIGINFO | SA_RESETHAND; // Use 3-arg handler + reset on first trigger
    sigemptyset(&sa.sa_mask);

    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGABRT, &sa, NULL);
    sigaction(SIGBUS,  &sa, NULL);
    sigaction(SIGFPE,  &sa, NULL);
    NSSetUncaughtExceptionHandler(&uncaught_exception_handler);
}

/**
 * @brief Prints usage information for the PDS CLI.
 *
 * Displays a summary of available commands and general usage instructions.
 */
void print_usage(void) {
    printf("Usage: %s <command> [options]\n\n", executable_name);
    printf("A command-line interface for managing kaszlak (ATProto PDS).\n\n");
    printf("Commands:\n");
    printf("  serve       Start the kaszlak server\n");
    printf("  status      Check kaszlak status\n");
    printf("  account     Manage accounts\n");
    printf("  invite      Manage invite codes\n");
    printf("  help        Show help information\n");
    printf("  version     Show version information\n\n");
    printf("Use '%s help <command>' for more information about a command.\n", executable_name);
}

/**
 * @brief Parses global command-line options from command args.
 *
 * Global options are only accepted after the command token.
 *
 * @param commandArgs Mutable command argument array.
 * @param context   The command context to configure.
 * @param errorMessage Receives a human-readable error on invalid arguments.
 * @return YES on success, NO when parsing fails.
 */
static BOOL parse_global_options(NSMutableArray<NSString *> *commandArgs,
                                 PDSCLICommandContext *context,
                                 NSString **errorMessage) {
    for (NSUInteger i = 0; i < commandArgs.count;) {
        NSString *arg = commandArgs[i];
        if ([arg isEqualToString:@"--data-dir"] || [arg isEqualToString:@"-d"]) {
            if (i + 1 >= commandArgs.count) {
                if (errorMessage) {
                    *errorMessage = @"Missing value for --data-dir";
                }
                return NO;
            }
            context.dataDir = commandArgs[i + 1];
            [commandArgs removeObjectsInRange:NSMakeRange(i, 2)];
            continue;
        }
        if ([arg isEqualToString:@"--config"] || [arg isEqualToString:@"-c"]) {
            if (i + 1 >= commandArgs.count) {
                if (errorMessage) {
                    *errorMessage = @"Missing value for --config";
                }
                return NO;
            }
            context.configPath = commandArgs[i + 1];
            [commandArgs removeObjectsInRange:NSMakeRange(i, 2)];
            continue;
        }
        if ([arg isEqualToString:@"--verbose"] || [arg isEqualToString:@"-v"]) {
            context.verbose = YES;
            [[PDSLogger sharedLogger] setLogLevel:PDSLogLevelDebug];
            [commandArgs removeObjectAtIndex:i];
            continue;
        }
        if ([arg isEqualToString:@"--json"] || [arg isEqualToString:@"-j"]) {
            context.jsonOutput = YES;
            [commandArgs removeObjectAtIndex:i];
            continue;
        }

        i++;
    }

    return YES;
}

static int fail_with_usage(NSString *errorMessage) {
    if (errorMessage.length > 0) {
        fprintf(stderr, "Error: %s\n\n", [errorMessage UTF8String]);
    }
    print_usage();
    return PDSCLIExitCodeInvalidArguments;
}

/**
 * @brief The entry point for the PDS CLI application.
 *
 * Enforces strict invocation format:
 *   kaszlak <command> [options]
 * Flags before command are rejected.
 */
int main(int argc, const char * argv[]) {
    signal(SIGPIPE, SIG_IGN);
    signal(SIGHUP, SIG_IGN);
    install_crash_handlers();
    @autoreleasepool {
        PDSCLIRegisterAllCommands();
        // Force linkage of NSDateFormatter category on static builds
        NSDateFormatterLinkATProtoCategory();
#ifdef LINUX
        // On Linux/GNUstep, verify critical categories are loaded
        if (![NSDateFormatter respondsToSelector:NSSelectorFromString(@"atproto_dateFromString:")]) {
            fprintf(stderr, "FATAL: Objective-C category NSDateFormatter(ATProto) not loaded. Check linker settings.\n");
            return PDSCLIExitCodeGeneralError;
        }
#endif

        if (argc < 2) {
            return fail_with_usage(@"Missing command");
        }

        NSString *commandName = [NSString stringWithUTF8String:argv[1]];
        if ([commandName hasPrefix:@"-"]) {
            return fail_with_usage(@"Flags must follow the command name");
        }

        NSMutableArray<NSString *> *commandArgs = [NSMutableArray array];
        for (int i = 2; i < argc; i++) {
            [commandArgs addObject:[NSString stringWithUTF8String:argv[i]]];
        }

        PDSCLICommandContext *context = [[PDSCLICommandContext alloc] init];
        NSString *parseError = nil;
        if (!parse_global_options(commandArgs, context, &parseError)) {
            return fail_with_usage(parseError);
        }

        @try {
            int result = [[PDSCLIDispatcher sharedDispatcher] dispatchWithCommandName:commandName
                                                                            arguments:commandArgs
                                                                              context:context];
            return result;
        } @catch (NSException *exception) {
            if ([exception.name isEqualToString:@"PDSCLIUnknownCommandException"]) {
                return PDSCLIExitCodeNotFound;
            }
            if ([exception.name isEqualToString:@"PDSCLICommandFailedException"]) {
                return PDSCLIExitCodeGeneralError;
            }
            [context printError:[NSString stringWithFormat:@"Unexpected error: %@", exception.reason]];
            return PDSCLIExitCodeGeneralError;
        }
    }
    return PDSCLIExitCodeSuccess;
}
