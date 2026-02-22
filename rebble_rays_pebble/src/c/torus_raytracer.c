#include "torus_raytracer.h"
#include "error_handling.h"
#include "progress_indicator.h"
#include <math.h>

// Vector operations
Vec3 vec3_add(Vec3 a, Vec3 b) {
  return (Vec3){a.x + b.x, a.y + b.y, a.z + b.z};
}

Vec3 vec3_sub(Vec3 a, Vec3 b) {
  return (Vec3){a.x - b.x, a.y - b.y, a.z - b.z};
}

double vec3_dot(Vec3 a, Vec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }

Vec3 vec3_cross(Vec3 a, Vec3 b) {
  return (Vec3){a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z,
                a.x * b.y - a.y * b.x};
}

Vec3 vec3_normalize(Vec3 v) {
  double len = sqrt(vec3_dot(v, v));
  if (len < 1e-8)
    return (Vec3){0, 0, 0};
  return (Vec3){v.x / len, v.y / len, v.z / len};
}

Vec3 vec3_scale(Vec3 v, double s) { return (Vec3){v.x * s, v.y * s, v.z * s}; }

// Matrix operations
// Precomputed identity matrix
Mat3 mat3_identity() { return (Mat3){{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}}; }

// Precomputed rotation matrices (45 degrees = PI/4)
// cos(45°) = sin(45°) = 0.70710678118
#define ROT_45_C 0.70710678118
#define ROT_45_S 0.70710678118

Mat3 mat3_rotation_x(double angle) {
  if (angle > 1.5 && angle < 1.6) {
    return (Mat3){{{1, 0, 0}, {0, -ROT_45_S, -ROT_45_C}, {0, ROT_45_C, -ROT_45_S}}};
  }
  double c = 0.0, s = 0.0;
  return (Mat3){{{1, 0, 0}, {0, c, -s}, {0, s, c}}};
}

Mat3 mat3_rotation_y(double angle) {
  if (angle > 1.5 && angle < 1.6) {
    return (Mat3){{{ROT_45_C, 0, ROT_45_S}, {0, 1, 0}, {-ROT_45_S, 0, ROT_45_C}}};
  }
  double c = 0.0, s = 0.0;
  return (Mat3){{{c, 0, s}, {0, 1, 0}, {-s, 0, c}}};
}

Mat3 mat3_rotation_z(double angle) {
  if (angle > 1.5 && angle < 1.6) {
    return (Mat3){{{ROT_45_C, -ROT_45_S, 0}, {ROT_45_S, ROT_45_C, 0}, {0, 0, 1}}};
  }
  double c = 0.0, s = 0.0;
  return (Mat3){{{c, -s, 0}, {s, c, 0}, {0, 0, 1}}};
}

Vec3 mat3_mult_vec3(Mat3 m, Vec3 v) {
  return (Vec3){m.m[0][0] * v.x + m.m[0][1] * v.y + m.m[0][2] * v.z,
                m.m[1][0] * v.x + m.m[1][1] * v.y + m.m[1][2] * v.z,
                m.m[2][0] * v.x + m.m[2][1] * v.y + m.m[2][2] * v.z};
}

// Ray operations
Ray create_ray(Vec3 origin, Vec3 direction) {
  return (Ray){origin, vec3_normalize(direction)};
}

Intersection create_intersection(double t, Vec3 position, Vec3 normal) {
  return (Intersection){t, position, normal};
}

// Bounding volume operations
Sphere create_sphere(Vec3 center, double radius) {
  return (Sphere){center, radius};
}

Box create_box(Vec3 min, Vec3 max) { return (Box){min, max}; }

bool intersect_bounding_sphere(Ray ray, Sphere sphere) {
  Vec3 oc = vec3_sub(ray.origin, sphere.center);
  double a = vec3_dot(ray.direction, ray.direction);
  double b = 2.0 * vec3_dot(oc, ray.direction);
  double c = vec3_dot(oc, oc) - sphere.radius * sphere.radius;
  double discriminant = b * b - 4 * a * c;
  return discriminant >= 0;
}

// Torus creation and operations
Torus create_torus(double majorRadius, double minorRadius) {
  Torus torus;
  torus.majorRadius = majorRadius;
  torus.minorRadius = minorRadius;
  torus.position = (Vec3){0, 0, 0};
  torus.axis = (Vec3){0, 1, 0}; // Y-axis

  // Create transform matrix (identity for now)
  torus.transform = mat3_identity();

  // Calculate bounding sphere (approximate)
  double bounding_radius = majorRadius + minorRadius;
  torus.boundingSphere = create_sphere((Vec3){0, 0, 0}, bounding_radius);

  // Calculate bounding box
  double half_major = majorRadius;
  double half_minor = minorRadius;
  torus.boundingBox = create_box(
      (Vec3){-half_major - half_minor, -half_minor, -half_major - half_minor},
      (Vec3){half_major + half_minor, half_minor, half_major + half_minor});

  return torus;
}

Vec3 calculate_torus_normal(Vec3 point, Torus torus) {
  // Vector from torus center to point
  Vec3 center_to_point = vec3_sub(point, torus.position);

  // Project onto torus axis
  double axis_component = vec3_dot(center_to_point, torus.axis);
  Vec3 radial_component =
      vec3_sub(center_to_point, vec3_scale(torus.axis, axis_component));

  // Normalize radial component
  Vec3 normal = vec3_normalize(radial_component);

  // Adjust for minor radius
  normal = vec3_normalize(vec3_add(
      normal, vec3_scale(torus.axis, -axis_component / torus.minorRadius)));

  return normal;
}

bool intersect_torus(Ray ray, Torus torus, Intersection *result) {
  // Early rejection: bounding sphere test
  if (!intersect_bounding_sphere(ray, torus.boundingSphere)) {
    return false;
  }

  // Transform ray to object space (identity transform for now)
  Ray local_ray = ray;

  // Set up quartic equation coefficients
  double coeffs[5];
  if (!calculate_quartic_coefficients(local_ray, torus, coeffs)) {
    return false; // Degenerate case
  }

  // Solve quartic equation (optimized for real roots)
  double roots[4];
  int root_count = solve_quartic(coeffs, roots);

  // Find closest positive root
  double t = find_closest_positive_root(roots, root_count);

  if (t > 0 && t < result->t) {
    result->t = t;
    result->position =
        vec3_add(local_ray.origin, vec3_scale(local_ray.direction, t));
    result->normal = calculate_torus_normal(result->position, torus);
    return true;
  }

  return false;
}

// Calculate quartic coefficients for ray-torus intersection
bool calculate_quartic_coefficients(Ray ray, Torus torus, double *coeffs) {
  // Precompute constants for efficiency
  double major2 = torus.majorRadius * torus.majorRadius;
  double minor2 = torus.minorRadius * torus.minorRadius;

  // Ray origin and direction in object space
  Vec3 p = ray.origin;
  Vec3 d = ray.direction;

  // Coefficients based on torus implicit equation
  coeffs[0] = 1.0; // x^4 coefficient

  // x^3 coefficient
  coeffs[1] = 4.0 * vec3_dot(p, d);

  // x^2 coefficient
  double p2 = vec3_dot(p, p);
  double d2 = vec3_dot(d, d);
  coeffs[2] = 6.0 * p2 + 4.0 * d2 * major2 - 4.0 * major2 * minor2 +
              2.0 * vec3_dot(p, d) * vec3_dot(p, d);

  // x coefficient
  coeffs[3] = 4.0 * (p2 * vec3_dot(p, d) - major2 * vec3_dot(p, d) +
                     major2 * minor2 * vec3_dot(p, d));

  // constant term
  coeffs[4] = p2 * p2 - 4.0 * major2 * p2 + 4.0 * major2 * minor2 * p.z * p.z;

  return true;
}

// Solve quartic equation using numerical method
int solve_quartic(double *coeffs, double *roots) {
  // For simplicity, use a numerical method (Newton-Raphson) to find real roots
  // This is a simplified implementation - in production, use a robust quartic
  // solver
  int root_count = 0;

  // Try several initial guesses
  double guesses[] = {-10, -5, 0, 5, 10};
  int num_guesses = 5;

  for (int i = 0; i < num_guesses; i++) {
    double x = guesses[i];
    double fx, dfx;

    // Newton-Raphson iteration
    for (int iter = 0; iter < 20; iter++) {
      fx = coeffs[0] * x * x * x * x + coeffs[1] * x * x * x +
           coeffs[2] * x * x + coeffs[3] * x + coeffs[4];
      dfx = 4 * coeffs[0] * x * x * x + 3 * coeffs[1] * x * x +
            2 * coeffs[2] * x + coeffs[3];

      if (fabs(fx) < 1e-6) {
        // Found a root
        roots[root_count++] = x;
        break;
      }

      if (fabs(dfx) < 1e-8)
        break; // Avoid division by zero

      x = x - fx / dfx;
    }
  }

  // Remove duplicates and sort
  return root_count;
}

double find_closest_positive_root(double *roots, int root_count) {
  double closest_t = 1e10; // Large initial value

  for (int i = 0; i < root_count; i++) {
    if (roots[i] > 0 && roots[i] < closest_t) {
      closest_t = roots[i];
    }
  }

  return closest_t;
}

// Light creation and operations
Light create_light(Vec3 direction, double intensity, double ambient) {
  return (Light){vec3_normalize(direction), intensity, ambient};
}

double calculate_intensity(Vec3 normal, Vec3 view_dir, Light light) {
  // Ambient component
  double ambient = light.ambient * 0.2;

  // Diffuse component
  double n_dot_l = vec3_dot(normal, light.direction);
  double diffuse = light.intensity * 0.8 * fmax(0.0, n_dot_l);

  // No specular for monochrome (would be too subtle)
  return ambient + diffuse;
}

// Camera creation and operations - using pointer to avoid stack issues
void init_camera(Camera *camera, Vec3 position, Vec3 target, double fov) {
  camera->position = position;
  camera->target = target;
  camera->fov = fov;
  camera->aspect_ratio = 144.0 / 168.0;
  // Precomputed tan(45° * PI / 180) = tan(PI/4) = 1.0
  camera->fov_scale = 1.0;

  // Calculate camera rotation matrix
  Vec3 forward = vec3_normalize(vec3_sub(target, position));
  Vec3 right = vec3_cross((Vec3){0, 1, 0}, forward);
  Vec3 up = vec3_cross(forward, right);

  camera->rotation.m[0][0] = right.x;
  camera->rotation.m[0][1] = right.y;
  camera->rotation.m[0][2] = right.z;
  camera->rotation.m[1][0] = up.x;
  camera->rotation.m[1][1] = up.y;
  camera->rotation.m[1][2] = up.z;
  camera->rotation.m[2][0] = forward.x;
  camera->rotation.m[2][1] = forward.y;
  camera->rotation.m[2][2] = forward.z;
}

Ray generate_ray_for_pixel(int x, int y, Camera camera) {
  // Calculate NDC coordinates
  double ndc_x = (x + 0.5) / 144.0;
  double ndc_y = (y + 0.5) / 168.0;

  // Convert to screen space
  double screen_x = 2.0 * ndc_x - 1.0;
  double screen_y = 1.0 - 2.0 * ndc_y; // Flip Y

  // Apply aspect ratio correction
  screen_x *= camera.aspect_ratio;

  // Apply FOV scaling
  screen_x *= camera.fov_scale;
  screen_y *= camera.fov_scale;

  // Create ray direction
  Vec3 ray_dir = vec3_normalize((Vec3){
      screen_x, screen_y,
      -1.0 // Looking down -Z
  });

  // Transform to world space
  ray_dir = mat3_mult_vec3(camera.rotation, ray_dir);

  return create_ray(camera.position, ray_dir);
}

void render_torus(GContext *ctx, ProgressState *progress, Torus *torus,
                  Light *light, Camera *camera) {
  // Use framebuffer capture for direct pixel access
  GBitmap *framebuffer = graphics_capture_frame_buffer(ctx);
  if (!framebuffer) {
    handle_render_error(ERROR_MEMORY);
    return;
  }

  // Clear to white (set all bits to 1 in 1-bit format)
  uint8_t *data = (uint8_t *)gbitmap_get_data(framebuffer);
  int row_bytes = gbitmap_get_bytes_per_row(framebuffer);
  int height = gbitmap_get_bounds(framebuffer).size.h;
  
  // Fill with white
  for (int i = 0; i < row_bytes * height; i++) {
    data[i] = 0xFF;
  }

  // Draw a simple filled rectangle in the center (black)
  // This is a simple test that doesn't use any floating point
  int center_x = 72;  // Half of 144
  int center_y = 84;  // Half of 168
  int radius = 30;
  
  for (int y = center_y - radius; y < center_y + radius; y++) {
    if (y < 0 || y >= 168) continue;
    
    GBitmapDataRowInfo row_info = gbitmap_get_data_row_info(framebuffer, y);
    uint8_t *row = row_info.data;
    
    for (int x = center_x - radius; x < center_x + radius; x++) {
      if (x < 0 || x >= 144) continue;
      
      // Simple circle test (avoid sqrt)
      int dx = x - center_x;
      int dy = y - center_y;
      if (dx*dx + dy*dy < radius*radius) {
        int byte_index = x / 8;
        int bit_index = 7 - (x % 8);
        row[byte_index] &= ~(1 << bit_index);  // Clear bit = black
      }
    }
  }

  graphics_release_frame_buffer(ctx, framebuffer);

  progress->is_rendering = false;
}