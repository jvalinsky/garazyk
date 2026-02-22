#pragma once

#include <pebble.h>

typedef enum {
  ERROR_NONE,
  ERROR_MEMORY_ALLOCATION,
  ERROR_MATH_COMPUTATION,
  ERROR_RENDER_TIMEOUT,
  ERROR_MEMORY,
  ERROR_UNKNOWN
} RenderError;

void handle_render_error(RenderError error);
void show_error_message(const char *message);