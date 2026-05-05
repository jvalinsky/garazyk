/*
 * objc_interp_types.h
 * Shared type definitions for the Objective-C interpreter.
 *
 * All struct/enum definitions, constants, and static inline string helpers
 * used across interpreter modules. This header is included by every
 * implementation file.
 */

#ifndef OBJC_INTERP_TYPES_H
#define OBJC_INTERP_TYPES_H

/* Public API constants (OBJC_INTERP_MAX_VARS, error codes, etc.) */
#include "objc_interpreter.h"

/* Runtime types: Class, SEL, id, etc. */
#include "runtime.h"
#include "slot.h"

#include <string.h>

/* ── String helpers (freestanding, no libc) ─────────────────────── */

static unsigned int cstr_len(const char *s) {
    unsigned int n = 0;
    if (s == 0) return 0;
    while (s[n] != '\0') n++;
    return n;
}

static int cstr_eq(const char *a, const char *b) {
    unsigned int i = 0;
    if (a == 0 || b == 0) return a == b;
    while (a[i] != '\0' && b[i] != '\0') {
        if (a[i] != b[i]) return 0;
        i++;
    }
    return a[i] == b[i];
}

static int cstr_eq_n(const char *a, const char *b, unsigned int n) {
    unsigned int i = 0;
    if (a == 0 || b == 0) return 0;
    while (i < n && a[i] != '\0' && b[i] != '\0') {
        if (a[i] != b[i]) return 0;
        i++;
    }
    return i == n;
}

static int cstr_starts(const char *s, const char *prefix) {
    unsigned int i = 0;
    if (s == 0 || prefix == 0) return 0;
    while (prefix[i] != '\0') {
        if (s[i] != prefix[i]) return 0;
        i++;
    }
    return 1;
}

static void cstr_copy(char *dst, const char *src, unsigned int capacity) {
    unsigned int i = 0;
    if (dst == 0 || src == 0) return;
    while (src[i] != '\0' && i + 1 < capacity) {
        dst[i] = src[i];
        i++;
    }
    dst[i] = '\0';
}

/* Same as cstr_copy but returns 1 if the source did not fit and was
 * truncated, 0 otherwise. Use at identifier-copy sites where silent
 * truncation would cause later table lookups to miss. */
static int cstr_copy_checked(char *dst, const char *src, unsigned int capacity) {
    unsigned int i = 0;
    if (dst == 0 || src == 0 || capacity == 0) return 0;
    while (src[i] != '\0' && i + 1 < capacity) {
        dst[i] = src[i];
        i++;
    }
    dst[i] = '\0';
    return src[i] != '\0';
}

/* ── Variable table ─────────────────────────────────────────────── */

typedef struct {
    char name[64];
    id value;
    Class cls;      /* if this is a Class-typed variable */
    SEL sel;        /* if this is a SEL-typed variable */
    int is_int;
    int int_value;
    int is_float;
    double float_value;
    int is_class;   /* 1 if this holds a Class */
    int is_sel;     /* 1 if this holds a SEL */
    int is_id;      /* 1 if this holds an id */
    int is_block_captured; /* 1 if __block variable — capture by reference */
    int is_static;     /* 1 if static variable — persists across cells */
} InterpVar;

#define OBJC_INTERP_MAX_BLOCKS_CAPTURED 32

/* ── Typedef table ─────────────────────────────────────────────── */

#define OBJC_INTERP_MAX_TYPEDEFS 64

typedef struct {
    char alias[64];     /* e.g., "MyInt" */
    char base_type[64]; /* e.g., "NSInteger" or "int" */
} TypeDef;

/* ── Token types ────────────────────────────────────────────────── */

typedef enum {
    TOK_EOF = 0,
    TOK_IDENTIFIER,
    TOK_AT_KEYWORD,     /* @interface, @implementation, @end, @\"string\" */
    TOK_STRING_LITERAL, /* @\"...\" or \"...\" */
    TOK_INT_LITERAL,
    TOK_FLOAT_LITERAL,
    TOK_OPEN_BRACKET,   /* [ */
    TOK_CLOSE_BRACKET,  /* ] */
    TOK_OPEN_BRACE,     /* { */
    TOK_CLOSE_BRACE,    /* } */
    TOK_OPEN_PAREN,     /* ( */
    TOK_CLOSE_PAREN,    /* ) */
    TOK_SEMICOLON,      /* ; */
    TOK_COLON,          /* : */
    TOK_COMMA,          /* , */
    TOK_DOT,            /* . */
    TOK_ARROW,          /* -> */
    TOK_STAR,           /* * */
    TOK_AMPERSAND,      /* & */
    TOK_ASSIGN,         /* = */
    TOK_EQ,             /* == */
    TOK_NEQ,            /* != */
    TOK_PLUS,           /* + */
    TOK_MINUS,          /* - */
    TOK_SLASH,          /* / */
    TOK_PERCENT,        /* % */
    TOK_LT,            /* < */
    TOK_GT,            /* > */
    TOK_LE,            /* <= */
    TOK_GE,            /* >= */
    TOK_PLUS_ASSIGN,   /* += */
    TOK_MINUS_ASSIGN,  /* -= */
    TOK_STAR_ASSIGN,   /* *= */
    TOK_SLASH_ASSIGN,  /* /= */
    TOK_PERCENT_ASSIGN,/* %= */
    TOK_QUESTION,      /* ? (ternary) */
    TOK_RETURN,        /* return keyword */
    TOK_IF,            /* if keyword */
    TOK_ELSE,          /* else keyword */
    TOK_WHILE,         /* while keyword */
    TOK_FOR,           /* for keyword */
    TOK_DO,            /* do keyword */
    TOK_BREAK,         /* break keyword */
    TOK_CONTINUE,     /* continue keyword */
    TOK_IN,            /* in keyword (for-in) */
    TOK_AND,           /* && */
    TOK_OR,            /* || */
    TOK_NOT,           /* ! (logical not) */
    TOK_PLUS_PLUS,     /* ++ */
    TOK_MINUS_MINUS,   /* -- */
    TOK_CARET,         /* ^ (block literal) */
    TOK_SWITCH,        /* switch keyword */
    TOK_CASE,          /* case keyword */
    TOK_DEFAULT,       /* default keyword */
    TOK_NIL,           /* nil keyword */
    TOK_SUPER,         /* super keyword */
    TOK_BITWISE_OR,    /* | (bitwise OR) */
    TOK_LEFT_SHIFT,    /* << */
    TOK_RIGHT_SHIFT,   /* >> */
    TOK_UNKNOWN
} TokenType;

typedef struct {
    TokenType type;
    char text[OBJC_INTERP_MAX_TOKEN];
    unsigned int line;
    unsigned int column;
    int truncated;
} Token;

/* ── Lexer ──────────────────────────────────────────────────────── */

typedef struct {
    const char *source;
    unsigned int source_len;
    unsigned int pos;       /* position after current token */
    unsigned int token_start; /* position where current token began */
    unsigned int line;
    unsigned int column;
    unsigned int lex_line_offset; /* offset to add to line for error reporting */
    Token current;
} Lexer;

/* ── Value type ─────────────────────────────────────────────────── */

typedef struct {
    id obj_val;
    Class cls_val;
    SEL sel_val;
    int int_val;
    double float_val;
    int is_int;
    int is_float;
    int is_class;
    int is_sel;
    int is_id;
    int is_void;
} Value;

static Value value_from_id(id obj) {
    Value v;
    v.obj_val = obj;
    v.cls_val = 0;
    v.sel_val = 0;
    v.int_val = 0;
    v.float_val = 0.0;
    v.is_int = 0;
    v.is_float = 0;
    v.is_class = 0;
    v.is_sel = 0;
    v.is_id = 1;
    v.is_void = 0;
    return v;
}

static Value value_from_class(Class cls) {
    Value v;
    v.obj_val = 0;
    v.cls_val = cls;
    v.sel_val = 0;
    v.int_val = 0;
    v.float_val = 0.0;
    v.is_int = 0;
    v.is_float = 0;
    v.is_class = 1;
    v.is_sel = 0;
    v.is_id = 0;
    v.is_void = 0;
    return v;
}

static Value value_from_int(int n) {
    Value v;
    v.obj_val = 0;
    v.cls_val = 0;
    v.sel_val = 0;
    v.int_val = n;
    v.float_val = 0.0;
    v.is_int = 1;
    v.is_float = 0;
    v.is_class = 0;
    v.is_sel = 0;
    v.is_id = 0;
    v.is_void = 0;
    return v;
}

static Value value_from_float(double f) {
    Value v;
    v.obj_val = 0;
    v.cls_val = 0;
    v.sel_val = 0;
    v.int_val = 0;
    v.float_val = f;
    v.is_int = 0;
    v.is_float = 1;
    v.is_class = 0;
    v.is_sel = 0;
    v.is_id = 0;
    v.is_void = 0;
    return v;
}

static Value value_from_sel(SEL s) {
    Value v;
    v.obj_val = 0;
    v.cls_val = 0;
    v.sel_val = s;
    v.int_val = 0;
    v.float_val = 0.0;
    v.is_int = 0;
    v.is_float = 0;
    v.is_class = 0;
    v.is_sel = 1;
    v.is_id = 0;
    v.is_void = 0;
    return v;
}

static Value value_void(void) {
    Value v;
    v.obj_val = 0;
    v.cls_val = 0;
    v.sel_val = 0;
    v.int_val = 0;
    v.float_val = 0.0;
    v.is_int = 0;
    v.is_float = 0;
    v.is_class = 0;
    v.is_sel = 0;
    v.is_id = 0;
    v.is_void = 1;
    return v;
}

/* ── Method dispatch state ─────────────────────────────────────── */

/* Method implementation context — stored for interpreter method dispatch */
typedef struct {
    char source[2048]; /* method body source (without outer braces) */
    unsigned int source_len;
    Class class_ptr;
    SEL selector;
    int is_class_method;
    char arg_names[8][64]; /* argument names (up to 8 keyword args) */
    unsigned int arg_count; /* number of keyword arguments */
} MethodImpl;

#define MAX_METHODS 64

/* ── Property declarations ─────────────────────────────────────── */

typedef struct {
    char name[64];       /* property name */
    char ivar_name[64];  /* ivar name from @synthesize (e.g., _count from @synthesize count = _count) */
    char type_name[64];  /* type: int, id, Class, SEL, etc. */
    char class_name[64]; /* which class this property belongs to */
    int is_int;          /* 1 if type is int */
    int synthesized;     /* 1 if @synthesize was seen — enables property dispatch */
} PropertyDecl;

#define MAX_PROPERTIES 64

/* ── Instance variable side table ───────────────────────────────── */

#define MAX_INSTANCE_VARS 256

typedef struct {
    id object;           /* object pointer (FDObj: marker in string pool) */
    char prop_name[64];  /* property name */
    Value value;         /* stored value */
} InstanceVar;

/* ── Collection side table ─────────────────────────────────────── */

typedef struct {
    unsigned int coll_id;     /* which collection this entry belongs to */
    Value key;                /* key (for dicts) or element (for arrays/sets) */
    Value value;              /* value (for dicts only) */
} CollEntry;

#define MAX_COLLECTIONS 64
#define MAX_COLL_ENTRIES 512

/* ── GC relocation entries ──────────────────────────────────────── */

#define MAX_STRING_POOL_MARKS 4096

typedef struct {
    unsigned int old_off;
    unsigned int new_off;
} RelocEntry;

/* ── Block side table ──────────────────────────────────────────── */

typedef struct {
    char name[64];   /* captured variable name */
    Value value;     /* captured value (by-value snapshot) */
    int is_by_ref;   /* 1 if __block — capture by reference */
    unsigned int var_index; /* index into g_vars[] for by-reference access */
} BlockCapture;

typedef struct {
    unsigned int block_id;        /* unique ID */
    char source[2048];            /* block body source (without outer braces) */
    unsigned int source_len;
    char arg_names[8][64];       /* parameter names */
    unsigned int arg_count;
    BlockCapture captures[16];   /* captured variable values */
    unsigned int capture_count;
} BlockImpl;

#define MAX_BLOCKS 32

/* ── Protocol declarations ─────────────────────────────────────── */

#define MAX_PROTOCOLS 32
#define MAX_PROTOCOL_METHODS 32
#define MAX_PROTOCOL_NAME 64

typedef struct {
    char name[MAX_PROTOCOL_NAME];
    char conforms_to[8][MAX_PROTOCOL_NAME];  /* protocols this protocol conforms to */
    unsigned int conforms_count;
    /* Method declarations: stored as selector names for checking */
    char required_methods[MAX_PROTOCOL_METHODS][256];
    unsigned int required_count;
    char optional_methods[MAX_PROTOCOL_METHODS][256];
    unsigned int optional_count;
} ProtocolDecl;

/* ── Exception/try-catch state ────────────────────────────────── */

typedef struct {
    int exception_pending;
    Value exception_obj;
    int catch_active;
    char catch_var[64];
} TryFrame;

#define MAX_TRY_DEPTH 16

/* ── AST nodes for control flow ─────────────────────────────────── */

typedef enum {
    AST_IF,
    AST_WHILE,
    AST_FOR,
    AST_FOR_IN,
    AST_BLOCK,
    AST_EXPR_STMT,
    AST_VAR_DECL,
    AST_RETURN,
    AST_BREAK,
    AST_CONTINUE,
    AST_SWITCH,
    AST_DO_WHILE,
    AST_NOOP,  /* already-executed declaration (@interface, @implementation, etc.) */
    AST_PROTOCOL,  /* @protocol declaration — executed at parse time */
    AST_TRY_CATCH,  /* @try / @catch / @finally */
    AST_THROW,  /* @throw statement */
    AST_AUTORELEASEPOOL  /* @autoreleasepool { ... } */
} AstNodeType;

typedef struct AstNode AstNode;

struct AstNode {
    AstNodeType type;
    union {
        struct { /* AST_IF */
            AstNode *condition;
            AstNode *then_branch;
            AstNode *else_branch;
        } if_stmt;
        struct { /* AST_WHILE */
            AstNode *condition;
            AstNode *body;
        } while_stmt;
        struct { /* AST_FOR */
            AstNode *init;
            AstNode *condition;
            AstNode *increment;
            AstNode *body;
        } for_stmt;
        struct { /* AST_FOR_IN */
            char var_name[64];   /* iteration variable name */
            unsigned int collection_start; /* source range for collection expr */
            unsigned int collection_len;
            AstNode *body;
        } for_in;
        struct { /* AST_SWITCH */
            unsigned int expr_start;  /* source range for switch expression */
            unsigned int expr_len;
            int case_values[32];      /* integer values for each case */
            AstNode *case_bodies[32]; /* body block for each case */
            unsigned int case_count;
            int has_default;
            AstNode *default_body;
        } switch_stmt;
        struct { /* AST_DO_WHILE */
            AstNode *condition;
            AstNode *body;
        } do_while_stmt;
        struct { /* AST_PROTOCOL */
            /* Protocol already executed at parse time, no AST data needed */
        } protocol_decl;
        struct { /* AST_TRY_CATCH */
            AstNode *try_body;
            char catch_var[64];
            AstNode *catch_body;
            AstNode *finally_body;
        } try_catch;
        struct { /* AST_THROW */
            unsigned int source_start;
            unsigned int source_len;
        } throw_stmt;
        struct { /* AST_AUTORELEASEPOOL */
            AstNode *body;
        } autoreleasepool;
        struct { /* AST_BLOCK */
            AstNode *children[128];
            unsigned int count;
        } block;
        struct { /* AST_EXPR_STMT, AST_VAR_DECL, AST_RETURN */
            unsigned int source_start;
            unsigned int source_len;
        } source_range;
    };
};

#define MAX_AST_NODES 1024
#define MAX_PARSE_DEPTH 64

/* ── String pool ────────────────────────────────────────────────── */

#define OBJC_INTERP_STRING_POOL_SIZE 65536

/* ── Parser ────────────────────────────────────────────────────── */

typedef struct Parser {
    Lexer lex;
    int error;
    char error_msg[OBJC_INTERP_ERROR_SIZE];
    unsigned int error_line;
    unsigned int error_column;
} Parser;

#endif /* OBJC_INTERP_TYPES_H */
