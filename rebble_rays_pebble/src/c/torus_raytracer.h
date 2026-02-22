#pragma once

#include <pebble.h>
#include "progress_indicator.h"

// Vector structure
typedef struct {
  double x, y, z;
} Vec3;

// Matrix structure (3x3 for 3D transformations)
typedef struct {
  double m[3][3];
} Mat3;

// Ray structure
typedef struct {
  Vec3 origin;
  Vec3 direction;
} Ray;

// Intersection structure
typedef struct {
  double t;
  Vec3 position;
  Vec3 normal;
} Intersection;

// Sphere structure for bounding volumes
typedef struct {
  Vec3 center;
  double radius;
} Sphere;

// Box structure for bounding volumes
typedef struct {
  Vec3 min;
  Vec3 max;
} Box;

// Torus structure
typedef struct {
  double majorRadius;
  double minorRadius;
  Mat3 transform;
  Vec3 position;
  Vec3 axis;
  Sphere boundingSphere;
  Box boundingBox;
} Torus;

// Light structure
typedef struct {
  Vec3 direction;
  double intensity;
  double ambient;
} Light;

// Camera structure
typedef struct {
  Vec3 position;
  Vec3 target;
  double fov;
  double aspect_ratio;
  double fov_scale;
  Mat3 rotation;
} Camera;

// Function declarations
Vec3 vec3_add(Vec3 a, Vec3 b);
Vec3 vec3_sub(Vec3 a, Vec3 b);
double vec3_dot(Vec3 a, Vec3 b);
Vec3 vec3_cross(Vec3 a, Vec3 b);
Vec3 vec3_normalize(Vec3 v);
Vec3 vec3_scale(Vec3 v, double s);

Mat3 mat3_identity();
Mat3 mat3_rotation_x(double angle);
Mat3 mat3_rotation_y(double angle);
Mat3 mat3_rotation_z(double angle);
Vec3 mat3_mult_vec3(Mat3 m, Vec3 v);

Ray create_ray(Vec3 origin, Vec3 direction);
Intersection create_intersection(double t, Vec3 position, Vec3 normal);

Sphere create_sphere(Vec3 center, double radius);
Box create_box(Vec3 min, Vec3 max);
bool intersect_bounding_sphere(Ray ray, Sphere sphere);

Torus create_torus(double majorRadius, double minorRadius);
Vec3 calculate_torus_normal(Vec3 point, Torus torus);
bool calculate_quartic_coefficients(Ray ray, Torus torus, double *coeffs);
int solve_quartic(double *coeffs, double *roots);
double find_closest_positive_root(double *roots, int root_count);
bool intersect_torus(Ray ray, Torus torus, Intersection *result);

Light create_light(Vec3 direction, double intensity, double ambient);
double calculate_intensity(Vec3 normal, Vec3 view_dir, Light light);

Camera create_camera(Vec3 position, Vec3 target, double fov);
void init_camera(Camera *camera, Vec3 position, Vec3 target, double fov);
Ray generate_ray_for_pixel(int x, int y, Camera camera);

void render_torus(GContext *ctx, ProgressState *progress, Torus *torus,
                  Light *light, Camera *camera);