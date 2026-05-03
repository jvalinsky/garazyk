/* objc_interp_globals.h
 * DEPRECATED: This header is being phased out.
 * All interpreter globals have been migrated to InterpContext in objc_interp_context.h
 *
 * This file is kept for now to avoid breaking #includes, but it simply re-exports
 * the context header.
 */

#ifndef OBJC_INTERP_GLOBALS_H
#define OBJC_INTERP_GLOBALS_H

#include "objc_interp_context.h"

/* The global interpreter context is defined in objc_interpreter.c and declared as extern below */
extern InterpContext g_ctx;

#endif /* OBJC_INTERP_GLOBALS_H */
