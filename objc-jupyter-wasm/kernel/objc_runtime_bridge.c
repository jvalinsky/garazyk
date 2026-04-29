/*
 * objc_runtime_bridge.c
 * Stable C ABI for the browser-side Objective-C Jupyter kernel smoke slice.
 *
 * This file is intentionally freestanding: it builds to WebAssembly without a
 * libc, Objective-C compiler support, or libobjc2. Later runtime layers can
 * replace the fake evaluator behind this ABI without changing JavaScript.
 */

#define OBJC_KERNEL_REQUEST_CAPACITY 4096u
#define OBJC_KERNEL_RESPONSE_CAPACITY 8192u

static char request_buffer[OBJC_KERNEL_REQUEST_CAPACITY];
static char response_buffer[OBJC_KERNEL_RESPONSE_CAPACITY];
static char complete_buffer[2048u];
static char inspect_buffer[2048u];
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

static const char *find_json_code_value(const char *json, unsigned int *value_length) {
    unsigned int i = 0u;
    *value_length = 0u;

    if (json == 0) {
        return "";
    }

    while (json[i] != '\0') {
        if (match_literal(json + i, "\"code\"")) {
            unsigned int cursor = i + 6u;
            while (is_space(json[cursor])) {
                cursor++;
            }
            if (json[cursor] != ':') {
                i++;
                continue;
            }
            cursor++;
            while (is_space(json[cursor])) {
                cursor++;
            }
            if (json[cursor] != '"') {
                i++;
                continue;
            }
            cursor++;

            {
                unsigned int start = cursor;
                int escaped = 0;
                while (json[cursor] != '\0') {
                    if (!escaped && json[cursor] == '"') {
                        *value_length = cursor - start;
                        return json + start;
                    }
                    escaped = (!escaped && json[cursor] == '\\') ? 1 : 0;
                    if (escaped && json[cursor] != '\\') {
                        escaped = 0;
                    }
                    cursor++;
                }
            }
        }
        i++;
    }

    *value_length = cstr_len(json);
    return json;
}

__attribute__((used))
int objc_kernel_init(void) {
    execution_count = 0u;
    request_buffer[0] = '\0';
    response_buffer[0] = '\0';
    complete_buffer[0] = '\0';
    inspect_buffer[0] = '\0';
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
    const char *code = find_json_code_value(request_json, &code_length);

    execution_count++;
    response_buffer[0] = '\0';

    append_literal(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, "{");
    append_literal(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, "\"status\":\"ok\",");
    append_literal(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, "\"execution_count\":");
    append_uint(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, execution_count);
    append_literal(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, ",\"data\":{\"text/plain\":\"Objective-C WASM smoke executed: ");
    append_json_escaped_range(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, code, code_length);
    append_literal(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, "\"},");
    append_literal(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, "\"metadata\":{},");
    append_literal(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, "\"streams\":[{\"name\":\"stdout\",\"text\":\"Objective-C WASM smoke executed\\n\"}]");
    append_literal(response_buffer, OBJC_KERNEL_RESPONSE_CAPACITY, &offset, "}");

    return response_buffer;
}

__attribute__((used))
char *objc_kernel_complete_json(char *request_json) {
    unsigned int offset = 0u;
    (void)request_json;
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
    (void)request_json;
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
