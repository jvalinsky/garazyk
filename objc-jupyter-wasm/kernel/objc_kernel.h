/*
 * objc_kernel.h
 * Stable C ABI for the Objective-C WASM Jupyter kernel.
 *
 * The kernel exposes a flat C interface for use by the JavaScript host.
 * The JavaScript side allocates request buffers and passes byte-length-delimited
 * JSON requests; the kernel returns malloc'd response buffers that the caller
 * must free via objc_kernel_free().
 */

#ifndef OBJC_KERNEL_H
#define OBJC_KERNEL_H

/* Transport status codes — caller checks the integer return value. */
#define OBJC_KERNEL_TRANSPORT_OK 0
#define OBJC_KERNEL_TRANSPORT_INVALID_ARGUMENT 1
#define OBJC_KERNEL_TRANSPORT_REQUEST_TOO_LARGE 2
#define OBJC_KERNEL_TRANSPORT_RESPONSE_TOO_LARGE 3
#define OBJC_KERNEL_TRANSPORT_OOM 4
#define OBJC_KERNEL_TRANSPORT_INTERNAL_ERROR 5

/* Interpreter error codes (also used as transport codes for domain errors). */
#define OBJC_INTERP_RUNTIME_ERROR 6  /* uncaught exception */

/* Request and response size limits. */
#define OBJC_KERNEL_MAX_REQUEST_BYTES 65536u
#define OBJC_KERNEL_MAX_RESPONSE_BYTES 1048576u

/**
 * Initialize the kernel. Must be called once before any execute/complete/inspect calls.
 *
 * @return 0 on success, non-zero on failure.
 */
int objc_kernel_init(void);

/**
 * Get the maximum request size in bytes.
 */
unsigned int objc_kernel_max_request_bytes(void);

/**
 * Get the maximum response size in bytes.
 */
unsigned int objc_kernel_max_response_bytes(void);

/**
 * Allocate a buffer for the caller.
 *
 * @param size Bytes to allocate.
 * @return Pointer to the buffer, or NULL if allocation failed.
 */
void *objc_kernel_alloc(unsigned int size);

/**
 * Free a buffer previously allocated by objc_kernel_alloc or returned
 * in an execute/complete/inspect call.
 *
 * @param ptr Pointer to free, or NULL (safe).
 */
void objc_kernel_free(void *ptr);

/**
 * Get kernel information (protocol version, language, etc.).
 *
 * @param out_ptr_ptr Pointer to receive the output buffer address.
 *                    Caller must objc_kernel_free() the buffer after use.
 * @param out_len_ptr Pointer to receive the output buffer length in bytes.
 *
 * @return OBJC_KERNEL_TRANSPORT_OK on success, or a transport error code.
 *         On error, *out_ptr_ptr == 0 and no allocation is made.
 */
int objc_kernel_info_json(unsigned int *out_ptr_ptr, unsigned int *out_len_ptr);

/**
 * Execute Objective-C source code.
 *
 * Request JSON format:
 *   { "code": "...", ... other fields ignored ... }
 *
 * Response JSON format on success:
 *   { "status": "ok", "execution_count": N, "data": {...}, "metadata": {} }
 *
 * Response JSON format on error:
 *   { "status": "error", "execution_count": N, "ename": "...", "evalue": "...", "traceback": [...] }
 *
 * @param request_ptr  Byte pointer to the request JSON (not null-terminated; see request_len).
 * @param request_len  Length of the request in bytes.
 * @param out_ptr_ptr  Pointer to receive the response buffer address.
 *                     Caller must objc_kernel_free() the buffer after use.
 * @param out_len_ptr  Pointer to receive the response buffer length in bytes.
 *
 * @return OBJC_KERNEL_TRANSPORT_OK on success, or a transport error code.
 *         On transport error, *out_ptr_ptr == 0 and no allocation is made.
 *         Domain errors (parse/runtime) are returned as JSON with status != "ok".
 */
int objc_kernel_execute_json(
    const unsigned char *request_ptr,
    unsigned int request_len,
    unsigned int *out_ptr_ptr,
    unsigned int *out_len_ptr
);

/**
 * Get code completion matches.
 *
 * Request JSON format:
 *   { "code": "...", "cursorPos": N }
 *
 * Response JSON format:
 *   { "status": "ok", "matches": [...], "cursor_start": N, "cursor_end": N, "metadata": {} }
 *
 * @param request_ptr  Byte pointer to the request JSON.
 * @param request_len  Length of the request in bytes.
 * @param out_ptr_ptr  Pointer to receive the response buffer address.
 * @param out_len_ptr  Pointer to receive the response buffer length.
 *
 * @return OBJC_KERNEL_TRANSPORT_OK on success, or a transport error code.
 */
int objc_kernel_complete_json(
    const unsigned char *request_ptr,
    unsigned int request_len,
    unsigned int *out_ptr_ptr,
    unsigned int *out_len_ptr
);

/**
 * Inspect an identifier at a cursor position (hover docstring, variable info, etc.).
 *
 * Request JSON format:
 *   { "code": "...", "cursorPos": N, "detailLevel": N }
 *
 * Response JSON format:
 *   { "status": "ok", "found": true/false, "data": {...}, "metadata": {} }
 *
 * @param request_ptr  Byte pointer to the request JSON.
 * @param request_len  Length of the request in bytes.
 * @param out_ptr_ptr  Pointer to receive the response buffer address.
 * @param out_len_ptr  Pointer to receive the response buffer length.
 *
 * @return OBJC_KERNEL_TRANSPORT_OK on success, or a transport error code.
 */
int objc_kernel_inspect_json(
    const unsigned char *request_ptr,
    unsigned int request_len,
    unsigned int *out_ptr_ptr,
    unsigned int *out_len_ptr
);

#endif /* OBJC_KERNEL_H */
