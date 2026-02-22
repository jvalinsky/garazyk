#include "error_handling.h"
#include "progress_indicator.h"
#include "torus_raytracer.h"
#include <pebble.h>

static Window *s_main_window;
static Layer *s_canvas_layer;
static ProgressState progress_state;
static Torus torus;
static Light light;
static Camera camera;

static void canvas_update_proc(Layer *layer, GContext *ctx) {
  if (progress_state.is_rendering) {
    render_torus(ctx, &progress_state, &torus, &light, &camera);
  }
}

static void main_window_load(Window *window) {
  Layer *window_layer = window_get_root_layer(window);
  GRect bounds = layer_get_bounds(window_layer);

  s_canvas_layer = layer_create(bounds);
  layer_set_update_proc(s_canvas_layer, canvas_update_proc);
  layer_add_child(window_layer, s_canvas_layer);

  // Initialize rendering
  progress_state.total_pixels = 144 * 168;
  progress_state.processed_pixels = 0;
  progress_state.is_rendering = true;

  // Create torus with major radius 1.0, minor radius 0.5
  torus = create_torus(1.0, 0.5);

  // Create lighting: top-left directional light
  light = create_light((Vec3){-0.5, -0.5, 0.5}, 0.8, 0.2);

  // Setup camera: 45 degree FOV, positioned at origin looking forward
  init_camera(&camera, (Vec3){0, 0, -5}, (Vec3){0, 0, 0}, 45.0);

  // Mark layer dirty to start rendering
  layer_mark_dirty(s_canvas_layer);
}

static void main_window_unload(Window *window) {
  layer_destroy(s_canvas_layer);
}

static void init() {
  s_main_window = window_create();
  window_set_window_handlers(
      s_main_window,
      (WindowHandlers){.load = main_window_load, .unload = main_window_unload});
  window_stack_push(s_main_window, true);
}

static void deinit() { window_destroy(s_main_window); }

int main(void) {
  init();
  app_event_loop();
  deinit();
  return 0;
}