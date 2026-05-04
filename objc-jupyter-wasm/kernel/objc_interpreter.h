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
#define OBJC_INTERP_MAX_VARS 1024

/* Maximum NSLog ring buffer size */
#define OBJC_INTERP_NSLOG_BUFFER_SIZE 262144

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
#define OBJC_INTERP_INTERRUPTED 4
#define OBJC_INTERP_RESOURCE_ERROR 5  /* Resource limit exceeded (table full, pool exhausted) */

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

/**
 * Full reset: clears ALL persistent state (variables, methods, properties,
 * collections, blocks, string pool) and re-initializes Foundation classes.
 * Use for test isolation between test groups.
 */
void objc_interp_full_reset(void);

/**
 * Perform garbage collection on the string pool.
 * Reclaims unreachable string pool entries. Called automatically
 * between cell executions.  Defined in objc_interp_format.c.
 */

/**
 * Get the number of variables in the interpreter's variable table.
 * Used by tab completion to suggest variable names.
 */
unsigned int objc_interp_get_var_count(void);

/**
 * Get the name of the variable at the given index.
 * Returns NULL if index is out of bounds.
 * Used by tab completion to suggest variable names.
 */
const char *objc_interp_get_var_name(unsigned int index);

/**
 * Check if the variable at the given index is a class variable.
 * Returns 1 if it's a class, 0 otherwise.
 */
int objc_interp_get_var_is_class(unsigned int index);

/**
 * Get the line number where the last error occurred.
 * Returns 0 if no error or line is unknown.
 */
unsigned int objc_interp_get_error_line(void);

/**
 * Get the column number where the last error occurred.
 * Returns 0 if no error or column is unknown.
 */
unsigned int objc_interp_get_error_column(void);

#endif /* OBJC_INTERPRETER_H */
