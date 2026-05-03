#ifndef OBJC_INTERP_FORMAT_H
#define OBJC_INTERP_FORMAT_H

/* ── NSLog and formatting operations ────────────────────────────── */
/* NSLog buffer management, format string processing, value display,
 * and string pool garbage collection. */

/* NSLog buffer management */
void nslog_append(const char *text, unsigned int len);
void nslog_append_char(char ch);
void nslog_append_int(int value);
void nslog_append_long(long value);

/* Format a value into a buffer for display (REPL output) */
void format_value(Value v, char *buf, unsigned int capacity);

/* Format values using NSLog-style format string.
 * Returns a Value containing the formatted string in the string pool. */
Value format_values_to_pool(const char *fmt, Value *args, int arg_count);

/* String pool garbage collection — compact live strings, update pointers */
void objc_interp_gc_strings(void);

#endif /* OBJC_INTERP_FORMAT_H */
