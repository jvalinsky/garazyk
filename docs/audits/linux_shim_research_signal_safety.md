# Async-Signal Safety Research: Linux/POSIX Crash Handlers

## Overview
When writing C/C++ crash handlers on Linux/POSIX systems (such as those handling `SIGSEGV` or `SIGABRT`), it is crucial to understand the concept of **async-signal-safety**. A function is considered async-signal-safe if it can be safely called from within a signal handler, regardless of what the program was executing when the signal was delivered.

Many standard library functions, notably those involving dynamic memory allocation like `malloc()`, are **not** async-signal-safe. Calling them from a signal handler introduces a severe risk of deadlocks and truncated crash logs.

## The Mechanism of Deadlock with `malloc()`
The primary danger of using `malloc()` inside a signal handler stems from its internal reliance on synchronization primitives (e.g., mutexes) to protect the global heap data structures. The sequence of events leading to a deadlock typically looks like this:

1. **Interruption:** The main thread of the program is actively executing a call to `malloc()` (or `free()`), and has acquired the internal heap lock to modify the heap structure.
2. **Signal Delivery:** An asynchronous signal (like `SIGSEGV`) is delivered to the process, pausing the execution of the main thread precisely while it holds the heap lock.
3. **Re-entry in Signal Handler:** The registered signal handler begins execution on the same thread. If the signal handler calls a function that invokes `malloc()`, it attempts to acquire the exact same heap lock.
4. **Deadlock:** Because the lock is already held by the interrupted main thread context, the signal handler blocks indefinitely waiting for the lock. Since the signal handler must finish before the main thread can resume, the lock is never released, resulting in a permanent deadlock.

This deadlock completely halts the signal handler, preventing it from finishing the crash dump or cleanly terminating the program, often resulting in an unresponsive process and a truncated or non-existent crash log.

## Stack Traces: `backtrace_symbols` vs. `backtrace_symbols_fd`
A common task in a crash handler is dumping a stack trace. This is typically done using the `backtrace()` function to gather the stack frames, followed by a function to translate those frames into readable symbols.

### `backtrace_symbols()` (Unsafe)
The `backtrace_symbols()` function takes an array of addresses and returns an array of strings representing the symbols. To return these strings, **it internally calls `malloc()` to allocate memory for the string array.** Because of this implicit dynamic allocation, `backtrace_symbols()` is **not async-signal-safe** and carries the exact same deadlock risks as calling `malloc()` directly.

### `backtrace_symbols_fd()` (Safe Alternative)
To safely print a backtrace from a signal handler, POSIX provides `backtrace_symbols_fd()`. Instead of allocating memory and returning strings, this function writes the translated symbol strings directly to a provided file descriptor (such as `STDOUT_FILENO`, `STDERR_FILENO`, or a previously opened file descriptor for a log file).

Because `backtrace_symbols_fd()` bypasses dynamic memory allocation entirely and relies internally on the async-signal-safe `write()` system call, it avoids the heap lock and is generally considered **async-signal-safe**. 

## Best Practices for Signal Handlers

When designing robust crash handlers on POSIX systems, follow these best practices:

1. **Avoid Dynamic Allocation:** Never call `malloc()`, `free()`, `new`, `delete`, or any functions that wrap them (including many STL containers in C++, `printf()`, `fprintf()`, and `syslog()`).
2. **Use Only Async-Signal-Safe Functions:** Refer to the `signal-safety(7)` man page for a definitive list of safe functions. Rely on functions like `write()`, `read()`, `fsync()`, `abort()`, and `_exit()`.
3. **Minimize Handler Logic:** The safest signal handler does as little work as possible. A common pattern is to simply set a `volatile sig_atomic_t` flag or write a byte to a self-pipe, allowing the main event loop to safely process the signal outside of the handler context. (However, for fatal crashes like `SIGSEGV`, this is not possible, so the handler must do the reporting and then exit).
4. **Pre-allocate Resources:** If your crash handler requires memory (e.g., for stack buffers or file paths), allocate it during program initialization, long before any signal is delivered.
5. **Pre-load Libraries:** Be aware that even functions that appear safe (like `backtrace()`) might trigger dynamic loading (e.g., lazy loading `libgcc` for stack unwinding) on their first invocation, which could call `malloc()`. It is recommended to perform a "dummy" call to these functions during program startup to ensure all necessary libraries are loaded and initialized before a signal handler runs.
