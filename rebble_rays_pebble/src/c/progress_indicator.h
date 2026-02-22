#pragma once

#include <pebble.h>
#include "error_handling.h"

typedef struct {
  int total_pixels;
  int processed_pixels;
  bool is_rendering;
} ProgressState;

void update_progress(ProgressState *state, int x, int y);
void show_progress_message(GContext *ctx, int percent);