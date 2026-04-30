/*
 * objc_runtime_bridge.c
 * Stable transport v2 C ABI for the browser-side Objective-C Jupyter kernel.
 *
 * JavaScript passes explicit request pointers and byte lengths into the module
 * and receives allocated response buffers plus explicit lengths back. Domain
 * failures remain JSON payloads; transport failures return integer status codes.
 */

#include "objc_interpreter.h"

#include <stdint.h>
#include <stdlib.h>

#define OBJC_KERNEL_MAX_REQUEST_BYTES 65536u
#define OBJC_KERNEL_MAX_RESPONSE_BYTES 1048576u
#define OBJC_KERNEL_SMALL_RESPONSE_BYTES 8192u
#define OBJC_KERNEL_MAX_CODE_BYTES 65536u

#define OBJC_JSON_OK 0
#define OBJC_JSON_INVALID 1
#define OBJC_JSON_MISSING_CODE 2
#define OBJC_JSON_CODE_NOT_STRING 3
#define OBJC_JSON_CODE_TOO_LARGE 4

#define OBJC_KERNEL_TRANSPORT_OK 0
#define OBJC_KERNEL_TRANSPORT_INVALID_ARGUMENT 1
#define OBJC_KERNEL_TRANSPORT_REQUEST_TOO_LARGE 2
#define OBJC_KERNEL_TRANSPORT_RESPONSE_TOO_LARGE 3
#define OBJC_KERNEL_TRANSPORT_OOM 4
#define OBJC_KERNEL_TRANSPORT_INTERNAL_ERROR 5

typedef struct {
    char *buffer;
    unsigned int capacity;
    unsigned int offset;
    int overflow;
} JsonBuilder;

static char parsed_code_buffer[OBJC_KERNEL_MAX_CODE_BYTES];
static unsigned int execution_count = 0u;

/* Forward declaration for WASM runtime initialization */
extern void __objc_wasm_init(void);

static unsigned int cstr_len(const char *value) {
    unsigned int length = 0u;
    if (value == 0) {
        return 0u;
    }
    while (value[length] != '\0') {
        length++;
    }
    return length;
}

static int cstr_eq(const char *a, const char *b) {
    unsigned int i = 0u;
    if (a == 0 || b == 0) {
        return a == b;
    }
    while (a[i] != '\0' && b[i] != '\0') {
        if (a[i] != b[i]) {
            return 0;
        }
        i++;
    }
    return a[i] == b[i];
}

static void copy_bytes(char *dst, const unsigned char *src, unsigned int length) {
    unsigned int i = 0u;
    while (i < length) {
        dst[i] = (char)src[i];
        i++;
    }
}

static void builder_init(JsonBuilder *builder, char *buffer, unsigned int capacity) {
    builder->buffer = buffer;
    builder->capacity = capacity;
    builder->offset = 0u;
    builder->overflow = 0;
    if (capacity > 0u) {
        buffer[0] = '\0';
    }
}

static void builder_append_char(JsonBuilder *builder, char value) {
    if (builder->overflow) {
        return;
    }
    if (builder->offset + 1u >= builder->capacity) {
        builder->overflow = 1;
        return;
    }
    builder->buffer[builder->offset] = value;
    builder->offset += 1u;
    builder->buffer[builder->offset] = '\0';
}

static void builder_append_literal(JsonBuilder *builder, const char *value) {
    unsigned int i = 0u;
    if (value == 0) {
        return;
    }
    while (value[i] != '\0') {
        builder_append_char(builder, value[i]);
        i++;
    }
}

static void builder_append_uint(JsonBuilder *builder, unsigned int value) {
    char digits[10u];
    unsigned int digit_count = 0u;

    if (value == 0u) {
        builder_append_char(builder, '0');
        return;
    }

    while (value > 0u && digit_count < 10u) {
        digits[digit_count] = (char)('0' + (value % 10u));
        value /= 10u;
        digit_count++;
    }

    while (digit_count > 0u) {
        digit_count--;
        builder_append_char(builder, digits[digit_count]);
    }
}

static void builder_append_json_escaped_range(
    JsonBuilder *builder,
    const char *value,
    unsigned int value_length
) {
    unsigned int i = 0u;
    while (value != 0 && i < value_length && value[i] != '\0') {
        char ch = value[i];
        if (ch == '"' || ch == '\\') {
            builder_append_char(builder, '\\');
            builder_append_char(builder, ch);
        } else if (ch == '\n') {
            builder_append_literal(builder, "\\n");
        } else if (ch == '\r') {
            builder_append_literal(builder, "\\r");
        } else if (ch == '\t') {
            builder_append_literal(builder, "\\t");
        } else if ((unsigned char)ch < 32u) {
            builder_append_char(builder, ' ');
        } else {
            builder_append_char(builder, ch);
        }
        i++;
    }
}

static int match_literal(const char *cursor, const char *literal) {
    unsigned int i = 0u;
    if (cursor == 0 || literal == 0) {
        return 0;
    }
    while (literal[i] != '\0') {
        if (cursor[i] != literal[i]) {
            return 0;
        }
        i++;
    }
    return 1;
}

static int is_space(char value) {
    return value == ' ' || value == '\n' || value == '\r' || value == '\t';
}

static int is_digit(char value) {
    return value >= '0' && value <= '9';
}

static int is_hex(char value) {
    return (value >= '0' && value <= '9') ||
        (value >= 'a' && value <= 'f') ||
        (value >= 'A' && value <= 'F');
}

static void skip_space(const char **cursor) {
    while (*cursor != 0 && is_space(**cursor)) {
        *cursor += 1;
    }
}

static int parse_json_string(const char **cursor, char *out, unsigned int out_capacity, unsigned int *out_length) {
    unsigned int offset = 0u;
    const char *source = *cursor;

    *out_length = 0u;

    if (source == 0 || *source != '"') {
        return OBJC_JSON_INVALID;
    }

    source++;
    while (*source != '\0') {
        char ch = *source;

        if (ch == '"') {
            if (out != 0 && out_capacity > 0u) {
                out[offset] = '\0';
            }
            *cursor = source + 1;
            *out_length = offset;
            return OBJC_JSON_OK;
        }

        if ((unsigned char)ch < 32u) {
            return OBJC_JSON_INVALID;
        }

        if (ch == '\\') {
            source++;
            if (*source == '\0') {
                return OBJC_JSON_INVALID;
            }

            if (*source == '"' || *source == '\\' || *source == '/') {
                ch = *source;
            } else if (*source == 'b') {
                ch = '\b';
            } else if (*source == 'f') {
                ch = '\f';
            } else if (*source == 'n') {
                ch = '\n';
            } else if (*source == 'r') {
                ch = '\r';
            } else if (*source == 't') {
                ch = '\t';
            } else if (*source == 'u') {
                unsigned int i = 0u;
                for (i = 0u; i < 4u; i++) {
                    source++;
                    if (!is_hex(*source)) {
                        return OBJC_JSON_INVALID;
                    }
                }
                ch = '?';
            } else {
                return OBJC_JSON_INVALID;
            }
        }

        if (out != 0 && out_capacity > 0u) {
            if (offset + 1u >= out_capacity) {
                return OBJC_JSON_CODE_TOO_LARGE;
            }
            out[offset] = ch;
        }
        offset++;
        source++;
    }

    return OBJC_JSON_INVALID;
}

static int parse_literal_value(const char **cursor, const char *literal) {
    if (!match_literal(*cursor, literal)) {
        return OBJC_JSON_INVALID;
    }
    while (*literal != '\0') {
        *cursor += 1;
        literal++;
    }
    return OBJC_JSON_OK;
}

static int skip_json_number(const char **cursor) {
    const char *source = *cursor;

    if (*source == '-') {
        source++;
    }

    if (!is_digit(*source)) {
        return OBJC_JSON_INVALID;
    }

    if (*source == '0') {
        source++;
    } else {
        while (is_digit(*source)) {
            source++;
        }
    }

    if (*source == '.') {
        source++;
        if (!is_digit(*source)) {
            return OBJC_JSON_INVALID;
        }
        while (is_digit(*source)) {
            source++;
        }
    }

    if (*source == 'e' || *source == 'E') {
        source++;
        if (*source == '+' || *source == '-') {
            source++;
        }
        if (!is_digit(*source)) {
            return OBJC_JSON_INVALID;
        }
        while (is_digit(*source)) {
            source++;
        }
    }

    *cursor = source;
    return OBJC_JSON_OK;
}

static int skip_json_value(const char **cursor) {
    unsigned int ignored_length = 0u;
    skip_space(cursor);

    if (**cursor == '"') {
        return parse_json_string(cursor, 0, 0u, &ignored_length);
    }
    if (**cursor == '-' || is_digit(**cursor)) {
        return skip_json_number(cursor);
    }
    if (**cursor == 't') {
        return parse_literal_value(cursor, "true");
    }
    if (**cursor == 'f') {
        return parse_literal_value(cursor, "false");
    }
    if (**cursor == 'n') {
        return parse_literal_value(cursor, "null");
    }

    return OBJC_JSON_INVALID;
}

static int parse_kernel_request_code(const char *json, char *code, unsigned int code_capacity, unsigned int *code_length) {
    const char *cursor = json;
    int found_code = 0;

    *code_length = 0u;
    if (code_capacity > 0u) {
        code[0] = '\0';
    }

    if (json == 0) {
        return OBJC_JSON_INVALID;
    }

    skip_space(&cursor);
    if (*cursor != '{') {
        return OBJC_JSON_INVALID;
    }
    cursor++;
    skip_space(&cursor);

    if (*cursor == '}') {
        cursor++;
        skip_space(&cursor);
        return *cursor == '\0' ? OBJC_JSON_MISSING_CODE : OBJC_JSON_INVALID;
    }

    while (*cursor != '\0') {
        char key[32];
        unsigned int key_length = 0u;
        int status = parse_json_string(&cursor, key, 32u, &key_length);
        (void)key_length;
        if (status != OBJC_JSON_OK) {
            return status;
        }

        skip_space(&cursor);
        if (*cursor != ':') {
            return OBJC_JSON_INVALID;
        }
        cursor++;
        skip_space(&cursor);

        if (match_literal(key, "code")) {
            if (*cursor != '"') {
                if (*cursor == '\0' || *cursor == ',' || *cursor == '}') {
                    return OBJC_JSON_INVALID;
                }
                return OBJC_JSON_CODE_NOT_STRING;
            }
            status = parse_json_string(&cursor, code, code_capacity, code_length);
            if (status != OBJC_JSON_OK) {
                return status;
            }
            found_code = 1;
        } else {
            status = skip_json_value(&cursor);
            if (status != OBJC_JSON_OK) {
                return status;
            }
        }

        skip_space(&cursor);
        if (*cursor == '}') {
            cursor++;
            skip_space(&cursor);
            if (*cursor != '\0') {
                return OBJC_JSON_INVALID;
            }
            return found_code ? OBJC_JSON_OK : OBJC_JSON_MISSING_CODE;
        }

        if (*cursor != ',') {
            return OBJC_JSON_INVALID;
        }
        cursor++;
        skip_space(&cursor);
    }

    return OBJC_JSON_INVALID;
}

static const char *json_error_name(int status) {
    if (status == OBJC_JSON_MISSING_CODE) {
        return "MissingCode";
    }
    if (status == OBJC_JSON_CODE_NOT_STRING) {
        return "InvalidCode";
    }
    if (status == OBJC_JSON_CODE_TOO_LARGE) {
        return "RequestTooLarge";
    }
    return "InvalidJSON";
}

static const char *json_error_value(int status) {
    if (status == OBJC_JSON_MISSING_CODE) {
        return "Kernel request must include a code string.";
    }
    if (status == OBJC_JSON_CODE_NOT_STRING) {
        return "Kernel request field code must be a JSON string.";
    }
    if (status == OBJC_JSON_CODE_TOO_LARGE) {
        return "Kernel request code exceeds the WASM transport limit.";
    }
    return "Kernel request is not valid JSON for the Objective-C transport.";
}

static int validate_output_args(unsigned int *out_ptr_ptr, unsigned int *out_len_ptr) {
    if (out_ptr_ptr == 0 || out_len_ptr == 0) {
        return OBJC_KERNEL_TRANSPORT_INVALID_ARGUMENT;
    }
    *out_ptr_ptr = 0u;
    *out_len_ptr = 0u;
    return OBJC_KERNEL_TRANSPORT_OK;
}

static char *copy_request_json(const unsigned char *request_bytes, unsigned int request_len, int *transport_status) {
    char *request_json;
    if (request_len > OBJC_KERNEL_MAX_REQUEST_BYTES) {
        *transport_status = OBJC_KERNEL_TRANSPORT_REQUEST_TOO_LARGE;
        return 0;
    }
    if (request_bytes == 0 && request_len > 0u) {
        *transport_status = OBJC_KERNEL_TRANSPORT_INVALID_ARGUMENT;
        return 0;
    }

    request_json = (char *)malloc((size_t)request_len + 1u);
    if (request_json == 0) {
        *transport_status = OBJC_KERNEL_TRANSPORT_OOM;
        return 0;
    }
    if (request_len > 0u) {
        copy_bytes(request_json, request_bytes, request_len);
    }
    request_json[request_len] = '\0';
    *transport_status = OBJC_KERNEL_TRANSPORT_OK;
    return request_json;
}

static int finalize_response_buffer(
    char *response_buffer,
    JsonBuilder *builder,
    unsigned int *out_ptr_ptr,
    unsigned int *out_len_ptr
) {
    if (builder->overflow || builder->offset > OBJC_KERNEL_MAX_RESPONSE_BYTES) {
        free(response_buffer);
        return OBJC_KERNEL_TRANSPORT_RESPONSE_TOO_LARGE;
    }
    *out_ptr_ptr = (unsigned int)(uintptr_t)response_buffer;
    *out_len_ptr = builder->offset;
    return OBJC_KERNEL_TRANSPORT_OK;
}

static int allocate_response(JsonBuilder *builder, unsigned int capacity, char **response_buffer_ptr) {
    char *response_buffer = (char *)malloc((size_t)capacity + 1u);
    if (response_buffer == 0) {
        return OBJC_KERNEL_TRANSPORT_OOM;
    }
    builder_init(builder, response_buffer, capacity + 1u);
    *response_buffer_ptr = response_buffer;
    return OBJC_KERNEL_TRANSPORT_OK;
}

static int write_domain_error_json(
    const char *ename,
    const char *evalue,
    unsigned int execution_count_value,
    int include_execution_count,
    unsigned int *out_ptr_ptr,
    unsigned int *out_len_ptr
) {
    JsonBuilder builder;
    char *response_buffer = 0;
    int status = allocate_response(&builder, OBJC_KERNEL_SMALL_RESPONSE_BYTES, &response_buffer);
    if (status != OBJC_KERNEL_TRANSPORT_OK) {
        return status;
    }

    builder_append_literal(&builder, "{");
    builder_append_literal(&builder, "\"status\":\"error\",");
    if (include_execution_count) {
        builder_append_literal(&builder, "\"execution_count\":");
        builder_append_uint(&builder, execution_count_value);
        builder_append_literal(&builder, ",");
    }
    builder_append_literal(&builder, "\"ename\":\"");
    builder_append_literal(&builder, ename);
    builder_append_literal(&builder, "\",");
    builder_append_literal(&builder, "\"evalue\":\"");
    builder_append_json_escaped_range(&builder, evalue, cstr_len(evalue));
    builder_append_literal(&builder, "\",\"traceback\":[]}");

    return finalize_response_buffer(response_buffer, &builder, out_ptr_ptr, out_len_ptr);
}

static int build_kernel_info_response(unsigned int *out_ptr_ptr, unsigned int *out_len_ptr) {
    JsonBuilder builder;
    char *response_buffer = 0;
    int status = allocate_response(&builder, OBJC_KERNEL_SMALL_RESPONSE_BYTES, &response_buffer);
    if (status != OBJC_KERNEL_TRANSPORT_OK) {
        return status;
    }

    builder_append_literal(&builder, "{");
    builder_append_literal(&builder, "\"protocol_version\":\"5.3\",");
    builder_append_literal(&builder, "\"implementation\":\"objc-jupyter-wasm\",");
    builder_append_literal(&builder, "\"implementation_version\":\"0.1.0\",");
    builder_append_literal(&builder, "\"language_info\":{");
    builder_append_literal(&builder, "\"name\":\"objective-c\",");
    builder_append_literal(&builder, "\"version\":\"2.2\",");
    builder_append_literal(&builder, "\"mimetype\":\"text/x-objective-c\",");
    builder_append_literal(&builder, "\"file_extension\":\".m\",");
    builder_append_literal(&builder, "\"pygments_lexer\":\"objective-c\",");
    builder_append_literal(&builder, "\"codemirror_mode\":\"clike\"");
    builder_append_literal(&builder, "},");
    builder_append_literal(&builder, "\"help_links\":[],");
    builder_append_literal(&builder, "\"banner\":\"Objective-C WASM smoke kernel\"");
    builder_append_literal(&builder, "}");

    return finalize_response_buffer(response_buffer, &builder, out_ptr_ptr, out_len_ptr);
}

static int build_execute_response(
    const char *code,
    unsigned int code_length,
    unsigned int *out_ptr_ptr,
    unsigned int *out_len_ptr
) {
    JsonBuilder builder;
    char *response_buffer = 0;
    int status;
    int interp_result;

    execution_count++;
    interp_result = objc_interp(code, code_length);

    if (interp_result != OBJC_INTERP_OK) {
        const char *error_msg = objc_interp_get_error();
        const char *ename = "ObjCRuntimeError";
        if (objc_interp_get_error_code() == OBJC_INTERP_INTERRUPTED) {
            ename = "Interrupted";
        }
        return write_domain_error_json(
            ename,
            error_msg,
            execution_count,
            1,
            out_ptr_ptr,
            out_len_ptr
        );
    }

    status = allocate_response(&builder, OBJC_KERNEL_MAX_RESPONSE_BYTES, &response_buffer);
    if (status != OBJC_KERNEL_TRANSPORT_OK) {
        return status;
    }

    builder_append_literal(&builder, "{");
    builder_append_literal(&builder, "\"status\":\"ok\",");
    builder_append_literal(&builder, "\"execution_count\":");
    builder_append_uint(&builder, execution_count);
    builder_append_literal(&builder, ",");

    {
        const char *result_str = objc_interp_get_result();
        unsigned int result_len = cstr_len(result_str);
        if (result_len > 0u) {
            builder_append_literal(&builder, "\"data\":{\"text/plain\":\"");
            builder_append_json_escaped_range(&builder, result_str, result_len);
            builder_append_literal(&builder, "\"},");
        } else {
            builder_append_literal(&builder, "\"data\":{},");
        }
    }

    builder_append_literal(&builder, "\"metadata\":{}");
    builder_append_literal(&builder, "}");

    return finalize_response_buffer(response_buffer, &builder, out_ptr_ptr, out_len_ptr);
}

static int build_complete_response(unsigned int *out_ptr_ptr, unsigned int *out_len_ptr) {
    JsonBuilder builder;
    char *response_buffer = 0;
    int status = allocate_response(&builder, OBJC_KERNEL_SMALL_RESPONSE_BYTES, &response_buffer);
    if (status != OBJC_KERNEL_TRANSPORT_OK) {
        return status;
    }

    builder_append_literal(&builder, "{");
    builder_append_literal(&builder, "\"status\":\"ok\",");
    builder_append_literal(&builder, "\"matches\":[");
    builder_append_literal(&builder, "\"@interface\",\"@implementation\",\"@end\",\"@class\",\"@protocol\",");
    builder_append_literal(&builder, "\"NSLog\",\"NSString\",\"NSObject\",\"NSArray\",\"NSDictionary\",\"NSData\",\"NSNumber\",");
    builder_append_literal(&builder, "\"int\",\"id\",\"Class\",\"SEL\",\"BOOL\",\"void\",");
    builder_append_literal(&builder, "\"alloc\",\"init\",\"class\",\"sel_registerName\",\"objc_getClass\"");
    builder_append_literal(&builder, "],");
    builder_append_literal(&builder, "\"cursor_start\":0,\"cursor_end\":0,\"metadata\":{}");
    builder_append_literal(&builder, "}");

    return finalize_response_buffer(response_buffer, &builder, out_ptr_ptr, out_len_ptr);
}

static int build_inspect_response(unsigned int *out_ptr_ptr, unsigned int *out_len_ptr) {
    JsonBuilder builder;
    char *response_buffer = 0;
    int status = allocate_response(&builder, OBJC_KERNEL_SMALL_RESPONSE_BYTES, &response_buffer);
    if (status != OBJC_KERNEL_TRANSPORT_OK) {
        return status;
    }

    builder_append_literal(&builder, "{");
    builder_append_literal(&builder, "\"status\":\"ok\",\"found\":false,\"data\":{},\"metadata\":{}");
    builder_append_literal(&builder, "}");

    return finalize_response_buffer(response_buffer, &builder, out_ptr_ptr, out_len_ptr);
}

static int handle_request_with_code(
    const unsigned char *request_bytes,
    unsigned int request_len,
    unsigned int *out_ptr_ptr,
    unsigned int *out_len_ptr,
    int (*handler)(const char *code, unsigned int code_length, unsigned int *out_ptr_ptr, unsigned int *out_len_ptr)
) {
    char *request_json = 0;
    unsigned int code_length = 0u;
    int parse_status;
    int transport_status;

    request_json = copy_request_json(request_bytes, request_len, &transport_status);
    if (transport_status != OBJC_KERNEL_TRANSPORT_OK) {
        return transport_status;
    }

    parse_status = parse_kernel_request_code(
        request_json,
        parsed_code_buffer,
        OBJC_KERNEL_MAX_CODE_BYTES,
        &code_length
    );
    free(request_json);

    if (parse_status != OBJC_JSON_OK) {
        return write_domain_error_json(
            json_error_name(parse_status),
            json_error_value(parse_status),
            0u,
            0,
            out_ptr_ptr,
            out_len_ptr
        );
    }

    return handler(parsed_code_buffer, code_length, out_ptr_ptr, out_len_ptr);
}

static int handle_request_without_code(
    const unsigned char *request_bytes,
    unsigned int request_len,
    unsigned int *out_ptr_ptr,
    unsigned int *out_len_ptr,
    int (*handler)(unsigned int *out_ptr_ptr, unsigned int *out_len_ptr)
) {
    char *request_json = 0;
    int parse_status;
    int transport_status;
    unsigned int code_length = 0u;

    request_json = copy_request_json(request_bytes, request_len, &transport_status);
    if (transport_status != OBJC_KERNEL_TRANSPORT_OK) {
        return transport_status;
    }

    parse_status = parse_kernel_request_code(
        request_json,
        parsed_code_buffer,
        OBJC_KERNEL_MAX_CODE_BYTES,
        &code_length
    );
    free(request_json);

    if (parse_status != OBJC_JSON_OK) {
        return write_domain_error_json(
            json_error_name(parse_status),
            json_error_value(parse_status),
            0u,
            0,
            out_ptr_ptr,
            out_len_ptr
        );
    }

    return handler(out_ptr_ptr, out_len_ptr);
}

__attribute__((used))
int objc_kernel_init(void) {
    execution_count = 0u;

    /* Initialize the ObjC runtime's class table before any
     * class lookups or allocations. This seeds the table with
     * the Object root class and prevents division-by-zero in
     * the hash table lookup. */
    __objc_wasm_init();

    objc_interp_init();
    return 0;
}

__attribute__((used))
unsigned int objc_kernel_max_request_bytes(void) {
    return OBJC_KERNEL_MAX_REQUEST_BYTES;
}

__attribute__((used))
unsigned int objc_kernel_max_response_bytes(void) {
    return OBJC_KERNEL_MAX_RESPONSE_BYTES;
}

__attribute__((used))
void *objc_kernel_alloc(unsigned int size) {
    unsigned int alloc_size = size == 0u ? 1u : size;
    return malloc((size_t)alloc_size);
}

__attribute__((used))
void objc_kernel_free(void *value) {
    if (value != 0) {
        free(value);
    }
}

__attribute__((used))
int objc_kernel_info_json(unsigned int *out_ptr_ptr, unsigned int *out_len_ptr) {
    int status = validate_output_args(out_ptr_ptr, out_len_ptr);
    if (status != OBJC_KERNEL_TRANSPORT_OK) {
        return status;
    }
    return build_kernel_info_response(out_ptr_ptr, out_len_ptr);
}

__attribute__((used))
int objc_kernel_execute_json(
    const unsigned char *request_bytes,
    unsigned int request_len,
    unsigned int *out_ptr_ptr,
    unsigned int *out_len_ptr
) {
    int status = validate_output_args(out_ptr_ptr, out_len_ptr);
    if (status != OBJC_KERNEL_TRANSPORT_OK) {
        return status;
    }
    return handle_request_with_code(
        request_bytes,
        request_len,
        out_ptr_ptr,
        out_len_ptr,
        build_execute_response
    );
}

__attribute__((used))
int objc_kernel_complete_json(
    const unsigned char *request_bytes,
    unsigned int request_len,
    unsigned int *out_ptr_ptr,
    unsigned int *out_len_ptr
) {
    int status = validate_output_args(out_ptr_ptr, out_len_ptr);
    if (status != OBJC_KERNEL_TRANSPORT_OK) {
        return status;
    }
    return handle_request_without_code(
        request_bytes,
        request_len,
        out_ptr_ptr,
        out_len_ptr,
        build_complete_response
    );
}

__attribute__((used))
int objc_kernel_inspect_json(
    const unsigned char *request_bytes,
    unsigned int request_len,
    unsigned int *out_ptr_ptr,
    unsigned int *out_len_ptr
) {
    int status = validate_output_args(out_ptr_ptr, out_len_ptr);
    if (status != OBJC_KERNEL_TRANSPORT_OK) {
        return status;
    }
    return handle_request_without_code(
        request_bytes,
        request_len,
        out_ptr_ptr,
        out_len_ptr,
        build_inspect_response
    );
}
