#include "objc_interp_types.h"
#include "objc_interp_globals.h"
#include "objc_interp_ast.h"
#include "objc_interp_state.h"
#include "objc_interp_format.h"
#include "objc_interp_lexer.h"

typedef struct Parser {
    Lexer lex;
    int error;
    char error_msg[OBJC_INTERP_ERROR_SIZE];
} Parser;


/* extern for runtime bridge function */
extern void interp_emit_stream(const char *data, unsigned int len);
extern Class object_getClass(id);
extern id objc_lookUpClass(const char *name);
extern const char *sel_getName(SEL);

/* Forward declarations for parser functions still in objc_interpreter.c */
extern void set_error_from_parser(struct Parser *p);
extern void parser_init(struct Parser *p, const char *source, unsigned int length,
                        unsigned int line_offset);
extern Token parser_current(struct Parser *p);
extern void parser_advance(struct Parser *p);
extern int parser_expect(struct Parser *p, TokenType type);
extern void parser_error(struct Parser *p, const char *msg);
extern int copy_identifier_or_error(struct Parser *p, char *dst, const char *src,
                                    unsigned int capacity, const char *kind);
extern Value parse_statement(struct Parser *p);
extern Value parse_type_and_var_decl(struct Parser *p);
extern Value parse_expression(struct Parser *p);
extern Value parse_block(struct Parser *p);
extern Value parse_expression_safe(struct Parser *p);
extern Value parse_primary(struct Parser *p);
extern Value parse_message_send(struct Parser *p);
extern unsigned int find_interpreter_method(SEL sel, Value target, id receiver, int is_setter);
extern Value execute_interpreter_method(struct Parser *p, MethodImpl *method, SEL sel, id receiver, Value *keyword_args, int keyword_count);
extern InterpVar *interp_get_or_create_var(const char *name);
extern InterpVar *interp_find_var(const char *name);

/* Internal forward declarations for mutually recursive AST routines. */
AstNode *parse_block_ast(struct Parser *p);
AstNode *parse_statement_ast(struct Parser *p);
Value eval_ast(AstNode *node, const char *source);

AstNode *ast_alloc(void) {
    if (g_ast_count >= MAX_AST_NODES) return 0;
    return &g_ast_arena[g_ast_count++];
}

AstNode *ast_make_if(AstNode *condition, AstNode *then_branch, AstNode *else_branch) {
    AstNode *n = ast_alloc();
    if (!n) return 0;
    n->type = AST_IF;
    n->if_stmt.condition = condition;
    n->if_stmt.then_branch = then_branch;
    n->if_stmt.else_branch = else_branch;
    return n;
}

AstNode *ast_make_while(AstNode *condition, AstNode *body) {
    AstNode *n = ast_alloc();
    if (!n) return 0;
    n->type = AST_WHILE;
    n->while_stmt.condition = condition;
    n->while_stmt.body = body;
    return n;
}

AstNode *ast_make_do_while(AstNode *body, AstNode *condition) {
    AstNode *n = ast_alloc();
    if (!n) return 0;
    n->type = AST_DO_WHILE;
    n->do_while_stmt.body = body;
    n->do_while_stmt.condition = condition;
    return n;
}

AstNode *ast_make_for(AstNode *init, AstNode *condition, AstNode *increment, AstNode *body) {
    AstNode *n = ast_alloc();
    if (!n) return 0;
    n->type = AST_FOR;
    n->for_stmt.init = init;
    n->for_stmt.condition = condition;
    n->for_stmt.increment = increment;
    n->for_stmt.body = body;
    return n;
}

AstNode *ast_make_block(void) {
    AstNode *n = ast_alloc();
    if (!n) return 0;
    n->type = AST_BLOCK;
    n->block.count = 0;
    return n;
}

int ast_block_add(AstNode *block, AstNode *child) {
    if (block && block->type == AST_BLOCK && block->block.count < 128) {
        block->block.children[block->block.count++] = child;
        return 0;
    }
    return -1;
}

AstNode *ast_make_source(AstNodeType type, unsigned int start, unsigned int len) {
    AstNode *n = ast_alloc();
    if (!n) return 0;
    n->type = type;
    n->source_range.source_start = start;
    n->source_range.source_len = len;
    return n;
}

AstNode *ast_make_noop(void) {
    AstNode *n = ast_alloc();
    if (!n) return 0;
    n->type = AST_NOOP;
    return n;
}

int is_truthy(Value v) {
    if (v.is_int) return v.int_val != 0;
    if (v.is_float) return v.float_val != 0.0;
    if (v.is_id) return v.obj_val != 0;
    if (v.is_class) return v.cls_val != 0;
    if (v.is_void) return 0;
    return 0;
}

/* ── Logical operators (extracted to objc_interp_parser.c) ─────── */

AstNode *parse_block_ast(Parser *p) {
    AstNode *block = ast_make_block();
    if (!block) {
        if (!p->error) {
            parser_error(p, "AST node limit reached (max 1024)");
        }
        return 0;
    }

    while (parser_current(p).type != TOK_EOF &&
           parser_current(p).type != TOK_CLOSE_BRACE) {
        AstNode *child = parse_statement_ast(p);
        if (!child) {
            if (!p->error) {
                parser_error(p, "AST node limit reached (max 1024)");
            }
            return 0;
        }
        if (p->error) return 0;
        if (ast_block_add(block, child) != 0) {
            parser_error(p, "block too large (max 128 statements)");
            return 0;
        }
        if (g_return_pending || g_break_pending || g_continue_pending) return block;
    }
    return block;
}

AstNode *parse_statement_ast(Parser *p) {
    Token tok = parser_current(p);

    /* if statement */
    if (tok.type == TOK_IF) {
        AstNode *condition, *then_branch, *else_branch;
        parser_advance(p);
        parser_expect(p, TOK_OPEN_PAREN);
        if (p->error) return 0;

        /* Parse condition as a source range — skip tokens, don't evaluate */
        {
            unsigned int cond_start = p->lex.token_start;
            int paren_depth = 1; /* we're inside the ( already */
            while (parser_current(p).type != TOK_EOF && paren_depth > 0) {
                if (parser_current(p).type == TOK_OPEN_PAREN) paren_depth++;
                else if (parser_current(p).type == TOK_CLOSE_PAREN) {
                    paren_depth--;
                    if (paren_depth == 0) break;
                }
                parser_advance(p);
            }
            condition = ast_make_source(AST_EXPR_STMT, cond_start,
                                       p->lex.token_start - cond_start);
            if (!condition && !p->error) {
                parser_error(p, "AST node limit reached (max 1024)");
                return 0;
            }
        }
        parser_expect(p, TOK_CLOSE_PAREN);
        if (p->error) return 0;

        /* Parse then-branch */
        if (parser_current(p).type == TOK_OPEN_BRACE) {
            parser_advance(p);
            then_branch = parse_block_ast(p);
            if (parser_current(p).type == TOK_CLOSE_BRACE) parser_advance(p);
        } else {
            then_branch = parse_statement_ast(p);
        }
        if (!then_branch) return 0;

        /* Parse optional else-branch */
        else_branch = 0;
        if (parser_current(p).type == TOK_ELSE) {
            parser_advance(p);
            if (parser_current(p).type == TOK_OPEN_BRACE) {
                parser_advance(p);
                else_branch = parse_block_ast(p);
                if (parser_current(p).type == TOK_CLOSE_BRACE) parser_advance(p);
            } else {
                else_branch = parse_statement_ast(p);
            }
            if (!else_branch) return 0;
        }

        {
            AstNode *node = ast_make_if(condition, then_branch, else_branch);
            if (!node && !p->error) {
                parser_error(p, "AST node limit reached (max 1024)");
                return 0;
            }
            return node;
        }
    }

    /* while statement */
    if (tok.type == TOK_WHILE) {
        AstNode *condition, *body;
        parser_advance(p);
        parser_expect(p, TOK_OPEN_PAREN);
        if (p->error) return 0;

        {
            unsigned int cond_start = p->lex.token_start;
            int paren_depth = 1;
            while (parser_current(p).type != TOK_EOF && paren_depth > 0) {
                if (parser_current(p).type == TOK_OPEN_PAREN) paren_depth++;
                else if (parser_current(p).type == TOK_CLOSE_PAREN) {
                    paren_depth--;
                    if (paren_depth == 0) break;
                }
                parser_advance(p);
            }
            condition = ast_make_source(AST_EXPR_STMT, cond_start,
                                        p->lex.token_start - cond_start);
        }
        parser_expect(p, TOK_CLOSE_PAREN);
        if (p->error) return 0;

        if (parser_current(p).type == TOK_OPEN_BRACE) {
            parser_advance(p);
            body = parse_block_ast(p);
            if (parser_current(p).type == TOK_CLOSE_BRACE) parser_advance(p);
        } else {
            body = parse_statement_ast(p);
        }
        if (!body) return 0;

        {
            AstNode *node = ast_make_while(condition, body);
            if (!node && !p->error) {
                parser_error(p, "AST node limit reached (max 1024)");
                return 0;
            }
            return node;
        }
    }

    /* do-while statement */
    if (tok.type == TOK_DO) {
        AstNode *body, *condition;
        parser_advance(p); /* consume 'do' */

        if (parser_current(p).type == TOK_OPEN_BRACE) {
            parser_advance(p);
            body = parse_block_ast(p);
            if (parser_current(p).type == TOK_CLOSE_BRACE) parser_advance(p);
        } else {
            body = parse_statement_ast(p);
        }
        if (!body) return 0;

        parser_expect(p, TOK_WHILE);
        if (p->error) return 0;
        parser_expect(p, TOK_OPEN_PAREN);
        if (p->error) return 0;

        {
            unsigned int cond_start = p->lex.token_start;
            int paren_depth = 1;
            while (parser_current(p).type != TOK_EOF && paren_depth > 0) {
                if (parser_current(p).type == TOK_OPEN_PAREN) paren_depth++;
                else if (parser_current(p).type == TOK_CLOSE_PAREN) {
                    paren_depth--;
                    if (paren_depth == 0) break;
                }
                parser_advance(p);
            }
            condition = ast_make_source(AST_EXPR_STMT, cond_start,
                                        p->lex.token_start - cond_start);
        }
        parser_expect(p, TOK_CLOSE_PAREN);
        if (p->error) return 0;
        parser_expect(p, TOK_SEMICOLON);
        if (p->error) return 0;

        {
            AstNode *node = ast_make_do_while(body, condition);
            if (!node && !p->error) {
                parser_error(p, "AST node limit reached (max 1024)");
                return 0;
            }
            return node;
        }
    }

    /* for statement */
    if (tok.type == TOK_FOR) {
        parser_advance(p);
        parser_expect(p, TOK_OPEN_PAREN);
        if (p->error) return 0;

        /* Check for for-in: type var in collection
         * We look ahead: if we see IDENT IDENT TOK_IN, it's for-in.
         * Otherwise, it's a standard for loop. */
        {
            Token saved = p->lex.current;
            unsigned int saved_pos = p->lex.pos;
            unsigned int saved_token_start = p->lex.token_start;
            int is_for_in = 0;
            char for_in_var[64];
            for_in_var[0] = '\0';

            /* Try to match: type var in ... */
            if (parser_current(p).type == TOK_IDENTIFIER) {
                /* Could be a type name or just 'id' */
                parser_advance(p);
                if (parser_current(p).type == TOK_STAR) {
                    /* Skip pointer: id *var */
                    parser_advance(p);
                }
                if (parser_current(p).type == TOK_IDENTIFIER) {
                    if (copy_identifier_or_error(p, for_in_var, parser_current(p).text, 64, "for-in variable")) {
                        return 0;
                    }
                    parser_advance(p);
                    if (parser_current(p).type == TOK_IN) {
                        is_for_in = 1;
                    }
                }
            }

            if (is_for_in) {
                /* for-in loop: for (type var in collection) { body } */
                unsigned int coll_start_outer;
                unsigned int coll_len_outer = 0;
                AstNode *body;
                AstNode *node;

                parser_advance(p); /* skip 'in' */

                /* Parse collection expression (skip tokens up to close paren) */
                {
                    unsigned int coll_start = p->lex.token_start;
                    int pd = 0;
                    while (parser_current(p).type != TOK_EOF) {
                        if (parser_current(p).type == TOK_CLOSE_PAREN && pd == 0) break;
                        if (parser_current(p).type == TOK_OPEN_PAREN) pd++;
                        else if (parser_current(p).type == TOK_CLOSE_PAREN) pd--;
                        parser_advance(p);
                    }
                    coll_len_outer = p->lex.token_start - coll_start;
                    coll_start_outer = coll_start;
                }

                if (parser_current(p).type == TOK_CLOSE_PAREN) parser_advance(p);

                /* Body */
                if (parser_current(p).type == TOK_OPEN_BRACE) {
                    parser_advance(p);
                    body = parse_block_ast(p);
                    if (parser_current(p).type == TOK_CLOSE_BRACE) parser_advance(p);
                } else {
                    body = parse_statement_ast(p);
                }
                if (!body) return 0;

                /* Build AST_FOR_IN node */
                node = ast_alloc();
                if (!node) {
                    if (!p->error) {
                        parser_error(p, "AST node limit reached (max 1024)");
                    }
                    return 0;
                }
                node->type = AST_FOR_IN;
                cstr_copy(node->for_in.var_name, for_in_var, 64);
                node->for_in.collection_start = coll_start_outer;
                node->for_in.collection_len = coll_len_outer;
                node->for_in.body = body;
                return node;
            }

            /* Not for-in — restore and parse as standard for */
            p->lex.current = saved;
            p->lex.pos = saved_pos;
            p->lex.token_start = saved_token_start;
        }

        /* Standard for loop: for (init; cond; incr) { body } */
        {
            AstNode *init, *condition, *increment, *body;

        /* Init: capture as source range (skip tokens, don't evaluate) */
        {
            unsigned int init_start = p->lex.token_start;
            int pd = 0;
            while (parser_current(p).type != TOK_EOF) {
                if (parser_current(p).type == TOK_SEMICOLON && pd == 0) break;
                if (parser_current(p).type == TOK_OPEN_PAREN) pd++;
                else if (parser_current(p).type == TOK_CLOSE_PAREN) pd--;
                parser_advance(p);
            }
            init = ast_make_source(AST_EXPR_STMT, init_start,
                                   p->lex.token_start - init_start);
            if (!init && !p->error) {
                parser_error(p, "AST node limit reached (max 1024)");
                return 0;
            }
            if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
        }

        /* Condition: capture as source range (skip tokens, don't evaluate) */
        {
            unsigned int cond_start = p->lex.token_start;
            int pd = 0;
            while (parser_current(p).type != TOK_EOF) {
                if (parser_current(p).type == TOK_SEMICOLON && pd == 0) break;
                if (parser_current(p).type == TOK_OPEN_PAREN) pd++;
                else if (parser_current(p).type == TOK_CLOSE_PAREN) pd--;
                parser_advance(p);
            }
            condition = ast_make_source(AST_EXPR_STMT, cond_start,
                                       p->lex.token_start - cond_start);
            if (!condition && !p->error) {
                parser_error(p, "AST node limit reached (max 1024)");
                return 0;
            }
            if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
        }

        /* Increment: capture as source range (skip tokens, don't evaluate) */
        {
            unsigned int incr_start = p->lex.token_start;
            int pd = 0;
            while (parser_current(p).type != TOK_EOF) {
                if (parser_current(p).type == TOK_CLOSE_PAREN && pd == 0) break;
                if (parser_current(p).type == TOK_OPEN_PAREN) pd++;
                else if (parser_current(p).type == TOK_CLOSE_PAREN) pd--;
                parser_advance(p);
            }
            increment = ast_make_source(AST_EXPR_STMT, incr_start,
                                       p->lex.token_start - incr_start);
            if (!increment && !p->error) {
                parser_error(p, "AST node limit reached (max 1024)");
                return 0;
            }
            if (parser_current(p).type == TOK_CLOSE_PAREN) parser_advance(p);
        }

        /* Body */
        if (parser_current(p).type == TOK_OPEN_BRACE) {
            parser_advance(p);
            body = parse_block_ast(p);
            if (parser_current(p).type == TOK_CLOSE_BRACE) parser_advance(p);
        } else {
            body = parse_statement_ast(p);
        }
        if (!body) return 0;

        {
            AstNode *node = ast_make_for(init, condition, increment, body);
            if (!node && !p->error) {
                parser_error(p, "AST node limit reached (max 1024)");
                return 0;
            }
            return node;
        }
        }
    }

    /* switch statement */
    if (tok.type == TOK_SWITCH) {
        AstNode *node = ast_alloc();
        if (!node) {
            parser_error(p, "AST node limit reached (max 1024)");
            return 0;
        }
        node->type = AST_SWITCH;
        node->switch_stmt.case_count = 0;
        node->switch_stmt.has_default = 0;
        node->switch_stmt.default_body = 0;

        parser_advance(p); /* consume 'switch' */

        /* Expect (expr) */
        if (parser_current(p).type != TOK_OPEN_PAREN) {
            parser_error(p, "Expected '(' after 'switch'");
            return 0;
        }
        parser_advance(p); /* consume ( */

        /* Capture switch expression as source range */
        node->switch_stmt.expr_start = p->lex.token_start;
        {
            int depth = 1;
            while (depth > 0 && parser_current(p).type != TOK_EOF) {
                if (parser_current(p).type == TOK_OPEN_PAREN) depth++;
                else if (parser_current(p).type == TOK_CLOSE_PAREN) {
                    depth--;
                    if (depth == 0) break; /* don't advance past the closing ) */
                }
                parser_advance(p);
            }
        }
        node->switch_stmt.expr_len = p->lex.token_start - node->switch_stmt.expr_start;

        if (parser_current(p).type == TOK_CLOSE_PAREN) parser_advance(p);

        /* Expect { */
        if (parser_current(p).type != TOK_OPEN_BRACE) {
            parser_error(p, "Expected '{' after switch expression");
            return 0;
        }
        parser_advance(p); /* consume { */

        /* Parse case/default clauses */
        while (parser_current(p).type != TOK_CLOSE_BRACE &&
               parser_current(p).type != TOK_EOF &&
               !p->error) {
            if (parser_current(p).type == TOK_CASE) {
                unsigned int ci = node->switch_stmt.case_count;
                if (ci >= 32) {
                    parser_error(p, "Too many case labels (max 32)");
                    return 0;
                }
                parser_advance(p); /* consume 'case' */

                /* Parse case value (integer constant) */
                {
                    Value case_val = parse_expression(p);
                    if (p->error) return 0;
                    if (!case_val.is_int) {
                        parser_error(p, "case expression must evaluate to an integer");
                        return 0;
                    }
                    node->switch_stmt.case_values[ci] = case_val.int_val;
                }

                if (parser_current(p).type == TOK_COLON) parser_advance(p);

                /* Parse case body (statements until next case/default/}) */
                {
                    AstNode *body = ast_alloc();
                    if (!body) {
                        parser_error(p, "AST node limit reached");
                        return 0;
                    }
                    body->type = AST_BLOCK;
                    body->block.count = 0;

                    while (parser_current(p).type != TOK_CASE &&
                           parser_current(p).type != TOK_DEFAULT &&
                           parser_current(p).type != TOK_CLOSE_BRACE &&
                           parser_current(p).type != TOK_EOF &&
                           !p->error) {
                        AstNode *stmt = parse_statement_ast(p);
                        if (!stmt) break;
                        if (body->block.count < 128) {
                            body->block.children[body->block.count++] = stmt;
                        }
                    }
                    node->switch_stmt.case_bodies[ci] = body;
                }
                node->switch_stmt.case_count++;
            } else if (parser_current(p).type == TOK_DEFAULT) {
                parser_advance(p); /* consume 'default' */
                if (parser_current(p).type == TOK_COLON) parser_advance(p);

                node->switch_stmt.has_default = 1;
                {
                    AstNode *body = ast_alloc();
                    if (!body) {
                        parser_error(p, "AST node limit reached");
                        return 0;
                    }
                    body->type = AST_BLOCK;
                    body->block.count = 0;

                    while (parser_current(p).type != TOK_CASE &&
                           parser_current(p).type != TOK_DEFAULT &&
                           parser_current(p).type != TOK_CLOSE_BRACE &&
                           parser_current(p).type != TOK_EOF &&
                           !p->error) {
                        AstNode *stmt = parse_statement_ast(p);
                        if (!stmt) break;
                        if (body->block.count < 128) {
                            body->block.children[body->block.count++] = stmt;
                        }
                    }
                    node->switch_stmt.default_body = body;
                }
            } else {
                /* Unexpected token inside switch body */
                parser_advance(p);
            }
        }

        if (parser_current(p).type == TOK_CLOSE_BRACE) parser_advance(p);

        return node;
    }

    /* break statement */
    if (tok.type == TOK_BREAK) {
        parser_advance(p);
        if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
        {
            AstNode *n = ast_alloc();
            if (!n) {
                if (!p->error) {
                    parser_error(p, "AST node limit reached (max 1024)");
                }
                return 0;
            }
            n->type = AST_BREAK;
            return n;
        }
    }

    /* continue statement */
    if (tok.type == TOK_CONTINUE) {
        parser_advance(p);
        if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
        {
            AstNode *n = ast_alloc();
            if (!n) {
                if (!p->error) {
                    parser_error(p, "AST node limit reached (max 1024)");
                }
                return 0;
            }
            n->type = AST_CONTINUE;
            return n;
        }
    }

    /* return statement → source range */
    if (tok.type == TOK_RETURN) {
        unsigned int start = p->lex.token_start;
        parser_advance(p);
        if (parser_current(p).type != TOK_SEMICOLON &&
            parser_current(p).type != TOK_CLOSE_BRACE &&
            parser_current(p).type != TOK_EOF) {
            parse_expression(p);
            if (p->error) return 0;
        }
        if (parser_current(p).type == TOK_SEMICOLON) parser_advance(p);
        {
            AstNode *node = ast_make_source(AST_RETURN, start, p->lex.token_start - start);
            if (!node && !p->error) {
                parser_error(p, "AST node limit reached (max 1024)");
                return 0;
            }
            return node;
        }
    }

    /* @interface / @implementation — execute immediately during parse phase.
     * Return AST_NOOP so eval_ast skips them — they must NOT be re-executed
     * via eval_source_range, which would cause duplicate class/method
     * registration and "Unknown identifier" errors. */
    if (tok.type == TOK_AT_KEYWORD &&
        (cstr_eq(tok.text, "@interface") || cstr_eq(tok.text, "@implementation") ||
         cstr_eq(tok.text, "@class") || cstr_eq(tok.text, "@protocol"))) {
        parse_statement(p); /* execute immediately */
        if (p->error) return 0;
        {
            AstNode *node = ast_make_noop();
            if (!node && !p->error) {
                parser_error(p, "AST node limit reached (max 1024)");
                return 0;
            }
            return node;
        }
    }

    /* Type declaration or expression statement → source range.
     * We only advance the parser to find the statement boundaries;
     * actual evaluation happens in eval_ast → eval_source_range.
     * This avoids the double-execution bug where parse_statement
     * evaluates the code during AST construction AND eval_source_range
     * evaluates it again during evaluation. */
    {
        unsigned int start = p->lex.token_start;
        int brace_depth = 0;
        /* Skip tokens until we find the statement-ending semicolon.
         * We need to track brace depth to handle nested blocks. */
        while (parser_current(p).type != TOK_EOF) {
            if (parser_current(p).type == TOK_OPEN_BRACE) brace_depth++;
            else if (parser_current(p).type == TOK_CLOSE_BRACE) {
                brace_depth--;
                if (brace_depth < 0) break; /* end of enclosing block */
            }
            else if (parser_current(p).type == TOK_SEMICOLON && brace_depth == 0) {
                parser_advance(p);
                break;
            }
            parser_advance(p);
        }
        {
            AstNode *node = ast_make_source(AST_EXPR_STMT, start, p->lex.token_start - start);
            if (!node && !p->error) {
                parser_error(p, "AST node limit reached (max 1024)");
                return 0;
            }
            return node;
        }
    }
}

/* Count newlines in source[0..pos) to compute line offset for error reporting. */
static unsigned int count_lines_up_to(const char *source, unsigned int pos) {
    unsigned int lines = 0;
    unsigned int i;
    for (i = 0; i < pos; i++) {
        if (source[i] == '\n') lines++;
    }
    return lines;
}

Value eval_source_range(unsigned int start, unsigned int len,
                        const char *source,
                        unsigned int line_offset) {
    Parser p;
    Value last = value_void();
    unsigned int saved_parse_depth = g_parse_depth;
    g_parse_depth = 0;
    if (len == 0) {
        g_parse_depth = saved_parse_depth;
        return value_void();
    }
    parser_init(&p, source + start, len, line_offset);
    /* Parse all statements in the source range, not just the first one.
     * This is needed for method bodies with multiple statements.
     * For control flow (if/while/for), use the two-phase AST approach.
     * For other statements, evaluate directly. */
    while (p.lex.current.type != TOK_EOF && !p.error) {
        Token tok = parser_current(&p);
        if (tok.type == TOK_IF || tok.type == TOK_WHILE ||
            tok.type == TOK_FOR || tok.type == TOK_SWITCH ||
            tok.type == TOK_DO) {
            /* Control flow: use two-phase AST approach.
             * Save and restore AST count to avoid corrupting
             * the outer AST arena. */
            unsigned int saved_ast_count = g_ast_count;
            AstNode *root = parse_block_ast(&p);
            if (p.error) {
                set_error_from_parser(&p);
                g_ast_count = saved_ast_count;
                g_parse_depth = saved_parse_depth;
                return last;
            }
            if (root) {
                last = eval_ast(root, source + start);
            }
            g_ast_count = saved_ast_count;
            if (p.error) {
                set_error_from_parser(&p);
                g_parse_depth = saved_parse_depth;
                return last;
            }
        } else {
            last = parse_statement(&p);
            if (p.error) {
                set_error_from_parser(&p);
                g_parse_depth = saved_parse_depth;
                return last;
            }
        }
    }
    g_parse_depth = saved_parse_depth;
    return last;
}

Value eval_ast(AstNode *node, const char *source) {
    Value last = value_void();
    if (!node) return last;

    switch (node->type) {
    case AST_IF: {
        Value cond = eval_ast(node->if_stmt.condition, source);
        if (is_truthy(cond)) {
            last = eval_ast(node->if_stmt.then_branch, source);
        } else if (node->if_stmt.else_branch) {
            last = eval_ast(node->if_stmt.else_branch, source);
        }
        break;
    }

    case AST_WHILE: {
        while (1) {
            Value cond = eval_ast(node->while_stmt.condition, source);
            if (!is_truthy(cond)) break;
            g_break_pending = 0;
            g_continue_pending = 0;
            eval_ast(node->while_stmt.body, source);
            if (g_break_pending) {
                g_break_pending = 0;
                break;
            }
            if (g_continue_pending) {
                g_continue_pending = 0;
                continue; /* re-evaluate condition */
            }
            if (g_return_pending) return last;
            if (interp_should_interrupt()) return last;
        }
        break;
    }

    case AST_DO_WHILE: {
        do {
            g_break_pending = 0;
            g_continue_pending = 0;
            eval_ast(node->do_while_stmt.body, source);
            if (g_break_pending) {
                g_break_pending = 0;
                break;
            }
            if (g_continue_pending) {
                g_continue_pending = 0;
                /* skip to condition check */
            }
            if (g_return_pending) return last;
            if (interp_should_interrupt()) return last;
            {
                Value cond = eval_ast(node->do_while_stmt.condition, source);
                if (!is_truthy(cond)) break;
            }
        } while (1);
        break;
    }

    case AST_FOR: {
        /* Init is already evaluated during parsing (for side effects).
         * But we need to re-evaluate it for loop correctness — actually,
         * the init only runs once, so we evaluate it here. */
        eval_ast(node->for_stmt.init, source);

        while (1) {
            /* Check condition (empty condition = always true) */
            if (node->for_stmt.condition != 0 && node->for_stmt.condition->source_range.source_len > 0) {
                Value cond = eval_ast(node->for_stmt.condition, source);
                if (!is_truthy(cond)) break;
            }

            g_break_pending = 0;
            g_continue_pending = 0;
            eval_ast(node->for_stmt.body, source);

            if (g_break_pending) {
                g_break_pending = 0;
                break;
            }
            if (g_continue_pending) {
                g_continue_pending = 0;
                /* Skip to increment */
            }
            if (g_return_pending) return last;
            if (interp_should_interrupt()) return last;

            /* Increment */
            eval_ast(node->for_stmt.increment, source);
        }
        break;
    }

    case AST_FOR_IN: {
        /* for (type var in collection) { body }
         * Evaluate the collection expression, then iterate.
         * For NSArray/NSMutableArray: iterate by index, yield elements.
         * For NSDictionary/NSMutableDictionary: iterate by keys.
         * For NSSet: iterate by elements.
         * For NSString: iterate by character. */
        Value coll = eval_source_range(node->for_in.collection_start,
                                       node->for_in.collection_len, source,
                                       count_lines_up_to(source, node->for_in.collection_start));
        const char *coll_str = (const char *)coll.obj_val;
        unsigned int cid = 0;
        int is_nsstring = 0;

        if (coll.is_id && coll_str != 0) {
            cid = coll_id_from_marker(coll_str, "NSArr:");
            if (cid == 0) cid = coll_id_from_marker(coll_str, "NSMutArr:");
            if (cid == 0) cid = coll_id_from_marker(coll_str, "NSDict:");
            if (cid == 0) cid = coll_id_from_marker(coll_str, "NSMutDict:");
            if (cid == 0) cid = coll_id_from_marker(coll_str, "NSSet:");
            if (cid == 0) {
                /* Not a collection marker — check if it's a string */
                is_nsstring = (!cstr_eq_n(coll_str, "NSNumber:", 9) &&
                               !cstr_eq_n(coll_str, "FDObj:", 6));
            }
        }

        if (cid > 0) {
            /* Collection iteration using side table */
            unsigned int cnt = coll_count(cid);
            unsigned int idx;
            for (idx = 0; idx < cnt; idx++) {
                int entry_idx = coll_get_nth(cid, idx);
                if (entry_idx < 0) break;
                InterpVar *var = interp_get_or_create_var(node->for_in.var_name);
                if (var) {
                    /* For dicts, yield the key; for arrays/sets, yield the element */
                    var->is_id = g_coll_entries[entry_idx].key.is_id;
                    var->value = g_coll_entries[entry_idx].key.obj_val;
                    var->is_int = g_coll_entries[entry_idx].key.is_int;
                    var->int_value = g_coll_entries[entry_idx].key.int_val;
                    var->is_class = g_coll_entries[entry_idx].key.is_class;
                    var->cls = g_coll_entries[entry_idx].key.cls_val;
                    var->is_sel = g_coll_entries[entry_idx].key.is_sel;
                    var->sel = g_coll_entries[entry_idx].key.sel_val;
                }
                g_break_pending = 0;
                g_continue_pending = 0;
                eval_ast(node->for_in.body, source);
                if (g_break_pending) { g_break_pending = 0; break; }
                if (g_continue_pending) { g_continue_pending = 0; continue; }
                if (g_return_pending) return last;
                if (interp_should_interrupt()) return last;
            }
        } else if (is_nsstring) {
            /* NSString: iterate by character */
            unsigned int len = (unsigned int)cstr_len(coll_str);
            unsigned int ci;
            for (ci = 0; ci < len; ci++) {
                InterpVar *var = interp_get_or_create_var(node->for_in.var_name);
                if (var) {
                    /* Store single character as a string in the pool */
                    {
                        char *ch_ptr = string_pool_alloc(2);
                        if (ch_ptr == 0) {
                            g_error_code = OBJC_INTERP_RESOURCE_ERROR;
                            cstr_copy(g_error_buffer, "string pool exhausted — restart kernel", OBJC_INTERP_ERROR_SIZE);
                            interp_emit_stream("warning: string pool exhausted — restart kernel\n", cstr_len("warning: string pool exhausted — restart kernel\n"));
                            break;
                        }
                        ch_ptr[0] = coll_str[ci];
                        ch_ptr[1] = '\0';
                        var->is_id = 1;
                        var->value = (id)ch_ptr;
                        var->is_int = 0;
                    }
                }
                g_break_pending = 0;
                g_continue_pending = 0;
                eval_ast(node->for_in.body, source);
                if (g_break_pending) { g_break_pending = 0; break; }
                if (g_continue_pending) { g_continue_pending = 0; continue; }
                if (g_return_pending) return last;
                if (interp_should_interrupt()) return last;
            }
        } else {
            /* Unknown collection type — just skip */
        }
        break;
    }

    case AST_BLOCK: {
        unsigned int i;
        for (i = 0; i < node->block.count; i++) {
            last = eval_ast(node->block.children[i], source);
            if (g_return_pending || g_break_pending || g_continue_pending)
                return last;
        }
        break;
    }

    case AST_EXPR_STMT:
    case AST_VAR_DECL:
        last = eval_source_range(node->source_range.source_start,
                                 node->source_range.source_len, source,
                                 count_lines_up_to(source, node->source_range.source_start));
        break;

    case AST_NOOP:
        /* Already executed during parse phase — skip */
        break;

    case AST_RETURN:
        last = eval_source_range(node->source_range.source_start,
                                 node->source_range.source_len, source,
                                 count_lines_up_to(source, node->source_range.source_start));
        g_return_pending = 1;
        break;

    case AST_BREAK:
        g_break_pending = 1;
        break;

    case AST_CONTINUE:
        g_continue_pending = 1;
        break;

    case AST_SWITCH: {
        /* Evaluate the switch expression */
        Value switch_val = eval_source_range(
            node->switch_stmt.expr_start,
            node->switch_stmt.expr_len, source,
            count_lines_up_to(source, node->switch_stmt.expr_start));
        if (g_error_code != OBJC_INTERP_OK) return switch_val;

        /* Find matching case */
        int matched_case = -1;
        {
            unsigned int ci;
            for (ci = 0; ci < node->switch_stmt.case_count; ci++) {
                if (switch_val.is_int && node->switch_stmt.case_values[ci] == switch_val.int_val) {
                    matched_case = (int)ci;
                    break;
                }
            }
        }

        /* Execute from matched case (fall-through) or from default.
         * A break inside a switch exits the switch (not the enclosing loop).
         * We use a local flag to track switch-break separately from
         * g_break_pending (which would exit the enclosing for/while). */
        {
            int switch_break = 0;
            if (matched_case >= 0) {
                unsigned int ci;
                for (ci = (unsigned int)matched_case; ci < node->switch_stmt.case_count; ci++) {
                    g_break_pending = 0;
                    eval_ast(node->switch_stmt.case_bodies[ci], source);
                    if (g_break_pending) {
                        switch_break = 1;
                        g_break_pending = 0; /* consume the break — it exits switch, not loop */
                        break;
                    }
                    if (g_return_pending) return last;
                }
                /* Fall through to default if no break */
                if (!switch_break && !g_return_pending &&
                    node->switch_stmt.has_default && node->switch_stmt.default_body) {
                    g_break_pending = 0;
                    eval_ast(node->switch_stmt.default_body, source);
                    if (g_break_pending) {
                        switch_break = 1;
                        g_break_pending = 0; /* consume break */
                    }
                }
            } else if (node->switch_stmt.has_default && node->switch_stmt.default_body) {
                g_break_pending = 0;
                eval_ast(node->switch_stmt.default_body, source);
                if (g_break_pending) {
                    switch_break = 1;
                    g_break_pending = 0; /* consume break */
                }
            }
            (void)switch_break; /* break was consumed — enclosing loop continues */
        }
        break;
    }
    }

}
