/*
 * objc_runtime_bridge.c
 * Stable C ABI for the browser-side Objective-C Jupyter kernel.
 *
 * This file provides the stable JSON ABI that JavaScript calls into.
 * The interpreter layer (objc_interpreter.c) evaluates ObjC source
 * against the real GNUstep libobjc2 runtime.
 *
 * Threading constraint: This ABI is single-threaded. All exported functions
 * share static buffers (request_buffer, response_buffer, etc.) and a global
 * execution_count. Calls must not overlap. The JavaScript worker enforces
 * this by processing messages sequentially.
 */

#include "objc_interpreter.h"

#define OBJC_KERNEL_REQUEST_CAPACITY 4096u
#define OBJC_KERNEL_RESPONSE_CAPACITY 8192u
#define OBJC_KERNEL_CODE_CAPACITY 2048u

#define OBJC_JSON_OK 0
#define OBJC_JSON_INVALID 1
#define OBJC_JSON_MISSING_CODE 2
#define OBJC_JSON_CODE_NOT_STRING 3
#define OBJC_JSON_CODE_TOO_LARGE 4

static char request_buffer[OBJC_KERNEL_REQUEST_CAPACITY];
static char response_buffer[OBJC_KERNEL_RESPONSE_CAPACITY];
static char complete_buffer[2048u];
static char inspect_buffer[2048u];
static char parsed_code_buffer[OBJC_KERNEL_CODE_CAPACITY];
static unsigned int execution_count = 0u;

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

static void append_char(char *buffer, unsigned int capacity, unsigned int *offset, char value) {
    if (*offset + 1u >= capacity) {
        return;
    }
    buffer[*offset] = value;
    *offset += 1u;
    buffer[*offset] = '\0';
}

static void append_literal(char *buffer, unsigned int capacity, unsigned int *offset, const char *value) {
    unsigned int i = 0u;
    if (value == 0) {
        return;
    }
    while (value[i] != '\0') {
        append_char(buffer, capacity, offset, value[i]);
        i++;
    }
}

static void append_uint(char *buffer, unsigned int capacity, unsigned int *offset, unsigned int value) {
    char digits[10u];
    unsigned int digit_count = 0u;

    if (value == 0u) {
        append_char(buffer, capacity, offset, '0');
        return;
    }

    while (value > 0u && digit_count < 10u) {
        digits[digit_count] = (char)('0' + (value % 10u));
        value /= 10u;
        digit_count++;
    }

    while (digit_count > 0u) {
        digit_count--;
        append_char(buffer, capacity, offset, digits[digit_count]);
    }
}

static void append_json_escaped_range(
    char *buffer,
    unsigned int capacity,
    unsigned int *offset,
    const char *value,
    unsigned int value_length
) {
    unsigned int i = 0u;
    while (value != 0 && i < value_length && value[i] != '\0') {
        char ch = value[i];
        if (ch == '"' || ch == '\\') {
            append_char(buffer, capacity, offset, '\\');
            append_char(buffer, capacity, offset, ch);
        } else if (ch == '\n') {
            append_literal(buffer, capacity, offset, "\\n");
        } else if (ch == '\r') {
            append_literal(buffer, capacity, offset, "\\r");
        } else if (ch == '\t') {
            append_literal(buffer, capacity, offset, "\\t");
        } else if ((unsigned char)ch < 32u) {
            append_char(buffer, capacity, offset, ' ');
        } else {
            append_char(buffer, capacity, offset, ch);
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

    if (cstr_len(json) >= (OBJC_KERNEL_REQUEST_CAPACITY - 1u)) {
        return OBJC_JSON_CODE_TOO_LARGE;
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
        return "Kernel request exceeds the WASM smoke request limit.";
    }
    return "Kernel request is not valid JSON for the smoke ABI.";
}

static char *write_error_json(char *buffer, unsigned int capacity, int status) {
    unsigned int offset = 0u;
    buffer[0] = '\0';
    append_literal(buffer, capacity, &offset, "{");
    append_literal(buffer, capacity, &offset, "\"status\":\"error\",");
    append_literal(buffer, capacity, &offset, "\"ename\":\"");
    append_literal(buffer, capacity, &offset, json_error_name(status));
    append_literal(buffer, capacity, &offset, "\",");
    append_literal(buffer, capacity, &offset, "\"evalue\":\"");
    append_literal(buffer, capacity, &offset, json_error_value(status));
    append_literal(buffer, capacity, &offset, "\",");
    append_literal(buffer, capacity, &offset, "\"traceback\":[]");
    append_literal(buffer, capacity, &offset, "}");
    return buffer;
}

/* Forward declaration for WASM runtime initialization */
extern void __objc_wasm_init(void);

__attribute__((used))
int objc_kernel_init(void) {
    execution_count = 0u;
    request_buffer[0] = '\0';
    response_buffer[0] = '\0';
    complete_buffer[0] = '\0';
    inspect_buffer[0] = '\0';

    /* Initialize the ObjC runtime's class table before any
     * class lookups or allocations. This seeds the table with
     * the Object root class and prevents division-by-zero in
     * the hash table lookup. */
    __objc_wasm_init();

    objc_interp_init();
    return 0;
}

__attribute__((used))
char *objc_kernel_request_buffer(void) {
    request_buffer[0] = '\0';
    return request_buffer;
}

__attribute__((used))
int objc_kernel_request_buffer_size(void) {
    return (int)OBJC_KERNEL_REQUEST_CAPACITY;
}

__attribute__((used))
char *objc_kernel_info_json(void) {
    return "{"
        "\"protocol_version\":\"5.3\","
        "\"implementation\":\"objc-jupyter-wasm\","
        "\"implementation_version\":\"0.1.0\","
        "\"language_info\":{"
            "\"name\":\"objective-c\","
            "\"version\":\"2.2\","
            "\"mimetype\":\"text/x-objective-c\","
            "\"file_extension\":\".m\","
            "\"pygments_lexer\":\"objective-c\","
            "\"codemirror_mode\":\"clike\""
        "},"
        "\"banner\":\"Objective-C WASM smoke kernel\""
    "}";
}

__attribute__((used))
char *objc_kernel_execute_json(char *request_json) {
    unsigned int offset = 0u;
    unsigned int code_length = 0u;
    int status = parse_kernel_request_code(
        request_json,
        parsed_code_buffer,
        OBJC_KERNEL_CODE_CAPACITY,
        &code_length
    );

    if (status != OBJC_JSON_OK) {
        return write_error_json(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, status);
    }

    execution_count++;

    /* Interpret the ObjC source code */
    {
        int interp_result = objc_interp(parsed_code_buffer, code_length);

        if (interp_result != OBJC_INTERP_OK) {
            /* Interpreter error */
            const char *error_msg = objc_interp_get_error();
            unsigned int error_len = cstr_len(error_msg);

            offset = 0u;
            response_buffer[0] = '\0';
            append_literal(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, "{");
            append_literal(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, "\"status\":\"error\",");
            append_literal(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, "\"execution_count\":");
            append_uint(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, execution_count);
            append_literal(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, ",\"ename\":\"ObjCRuntimeError\",");
            append_literal(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, "\"evalue\":\"");
            append_json_escaped_range(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, error_msg, error_len);
            append_literal(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, "\",\"traceback\":[]}");
            return response_buffer;
        }

        /* Success — format response with NSLog output */
        const char *nslog_output = objc_interp_get_nslog_output();
        unsigned int nslog_len = objc_interp_get_nslog_length();

        offset = 0u;
        response_buffer[0] = '\0';
        append_literal(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, "{");
        append_literal(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, "\"status\":\"ok\",");
        append_literal(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, "\"execution_count\":");
        append_uint(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, execution_count);
        append_literal(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, ",\"data\":{},");
        append_literal(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, "\"metadata\":{},");

        /* Include NSLog output as stream */
        if (nslog_len > 0u) {
            append_literal(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, "\"streams\":[{\"name\":\"stdout\",\"text\":\"");
            append_json_escaped_range(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, nslog_output, nslog_len);
            append_literal(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, "\"}]");
        } else {
            append_literal(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, "\"streams\":[]");
        }

        append_literal(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, "}");
        return response_buffer;
    }
}

__attribute__((used))
char *objc_kernel_complete_json(char *request_json) {
    unsigned int offset = 0u;
    unsigned int code_length = 0u;
    int status = parse_kernel_request_code(
        request_json,
        parsed_code_buffer,
        OBJC_KERNEL_CODE_CAPACITY,
        &code_length
    );
    (void)code_length;

    if (status != OBJC_JSON_OK) {
        return write_error_json(complete_buffer, 2048u, status);
    }

    complete_buffer[0] = '\0';

    append_literal(complete_buffer, 2048u, &offset, "{");
    append_literal(complete_buffer, 2048u, &offset, "\"status\":\"ok\",");
    append_literal(complete_buffer, 2048u, &offset, "\"matches\":[\"@interface\",\"@implementation\",\"@end\",\"NSString\",\"NSArray\",\"NSDictionary\"],");
    append_literal(complete_buffer, 2048u, &offset, "\"cursor_start\":0,\"cursor_end\":0,\"metadata\":{}");
    append_literal(complete_buffer, 2048u, &offset, "}");
    return complete_buffer;
}

__attribute__((used))
char *objc_kernel_inspect_json(char *request_json) {
    unsigned int offset = 0u;
    unsigned int code_length = 0u;
    int status = parse_kernel_request_code(
        request_json,
        parsed_code_buffer,
        OBJC_KERNEL_CODE_CAPACITY,
        &code_length
    );
    (void)code_length;

    if (status != OBJC_JSON_OK) {
        return write_error_json(inspect_buffer, 2048u, status);
    }

    inspect_buffer[0] = '\0';

    append_literal(inspect_buffer, 2048u, &offset, "{");
    append_literal(inspect_buffer, 2048u, &offset, "\"status\":\"ok\",\"found\":false,\"data\":{},\"metadata\":{}");
    append_literal(inspect_buffer, 2048u, &offset, "}");
    return inspect_buffer;
}

__attribute__((used))
void objc_kernel_free(char *value) {
    (void)value;
}
