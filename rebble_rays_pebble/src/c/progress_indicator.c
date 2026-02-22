#include "progress_indicator.h"
#include <time.h>

void update_progress(ProgressState *state, int x, int y) {
  int pixel_index = y * 144 + x;
  state->processed_pixels = pixel_index;
}

void show_progress_message(GContext *ctx, int percent) {
  (void)ctx;
  (void)percent;
}