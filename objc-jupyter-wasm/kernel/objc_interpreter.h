/*
 * objc_interpreter.h
 * Thin Objective-C interpreter for the Jupyter WASM kernel.
 *
 * This interpreter parses a subset of Objective-C and evaluates it
 * against the real GNUstep libobjc2 runtime. It supports:
 *   - @interface / @implementation declarations
 *   - Message sends [target selector:arg1 key2:arg2]
 *   - Variable declarations and assignments
 *   - NSLog with format strings
 *   - Basic arithmetic and string literals
 *   - id, Class, SEL, int, void types
 *
 * It does NOT support:
 *   - Preprocessor directives (#import, #define)
 *   - C structs or unions
 *   - Blocks (^{ ... })
 *   - ARC (@autoreleasepool, __strong, __weak)
 *   - @property, @synthesize
 *   - Full C type system
 */

#ifndef OBJC_INTERPRETER_H
#define OBJC_INTERPRETER_H

/* Maximum number of local variables per execution context */
#define OBJC_INTERP_MAX_VARS 256

/* Maximum NSLog ring buffer size */
#define OBJC_INTERP_NSLOG_BUFFER_SIZE 4096

/* Maximum interpreter error message length */
#define OBJC_INTERP_ERROR_SIZE 512

/* Maximum token length */
#define OBJC_INTERP_MAX_TOKEN 256

/* Maximum number of registered classes */
#define OBJC_INTERP_MAX_CLASSES 128

/* Interpreter error codes */
#define OBJC_INTERP_OK 0
#define OBJC_INTERP_SYNTAX_ERROR 1
#define OBJC_INTERP_RUNTIME_ERROR 2
#define OBJC_INTERP_MEMORY_ERROR 3

/**
 * Initialize the interpreter. Must be called once before any
 * objc_interpret() calls. Sets up the NSLog ring buffer and
 * variable table.
 */
void objc_interp_init(void);

/**
 * Interpret Objective-C source code.
 *
 * @param source  Null-terminated ObjC source code
 * @param length  Length of the source code
 * @return 0 on success, non-zero error code on failure
 */
int objc_interp(const char *source, unsigned int length);

/**
 * Get the NSLog output captured during the last interpretation.
 * The returned pointer is valid until the next objc_interp() call.
 *
 * @return Null-terminated string of NSLog output
 */
const char *objc_interp_get_nslog_output(void);

/**
 * Get the length of the NSLog output.
 */
unsigned int objc_interp_get_nslog_length(void);

/**
 * Get the interpreter error message from the last failed interpretation.
 * The returned pointer is valid until the next objc_interp() call.
 *
 * @return Null-terminated error message, or empty string if no error
 */
const char *objc_interp_get_error(void);

/**
 * Get the interpreter error code from the last failed interpretation.
 */
int objc_interp_get_error_code(void);

/**
 * Get the last evaluated expression result as a string.
 * Used for the execute_reply data field.
 */
const char *objc_interp_get_result(void);

/**
 * Clear the interpreter state for a new execution.
 * Does NOT clear registered classes or selectors (they persist across cells).
 */
void objc_interp_reset(void);

#endif /* OBJC_INTERPRETER_H */
