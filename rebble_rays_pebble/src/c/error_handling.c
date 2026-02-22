#include "error_handling.h"
#include <time.h>

int* __errno(void) {
  static int errno_value = 0;
  return &errno_value;
}

void handle_render_error(RenderError error) {
  switch (error) {
  case ERROR_MEMORY_ALLOCATION:
    show_error_message("Memory Error");
    break;
  case ERROR_MATH_COMPUTATION:
    show_error_message("Math Error");
    break;
  case ERROR_RENDER_TIMEOUT:
    show_error_message("Timeout");
    break;
  case ERROR_MEMORY:
    show_error_message("No Memory");
    break;
  default:
    show_error_message("Unknown Error");
    break;
  }
}

void show_error_message(const char *message) {
  (void)message;
}