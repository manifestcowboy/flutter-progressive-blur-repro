#version 460 core
#include <flutter/runtime_effect.glsl>

// Maximum blur radius. Must be a compile-time constant to satisfy SkSL loop constraints.
//
// ── Patch 2 MAX_RADIUS · PATCHED vs upstream (was 64 / 64.0). ───────────────
// `radius = ceil(3.0 * sigma)` below is TRUNCATED to this and then
// renormalised, not clamped — so past the ceiling the Gaussian silently
// degenerates into a box blur. There is no error and no banner; it just goes
// boxy.
//
// The ceiling is in whatever units the sigma uniform arrived in, and the two
// child-blur passes do NOT agree on those:
//   · animatedSampler divides sigma by dpr before the shader
//     (`inspire_child_blur_animated_sampler_pass.dart`), so the shader sees
//     LOGICAL px and 64 meant a 64/3 = 21.33 logical-px ceiling.
//   · imageFilter does not, so the shader sees DEVICE px and 64 meant a
//     64/3 = 21.33 DEVICE-px ceiling — 7.11 logical on a 3x phone, i.e. HALF
//     of a 44/3 = 14.667 logical sigma. At dpr 3 that is 44 device sigma
//     wanting radius ceil(3*44) = 132 and getting 64.
// That truncation is the boxy imageFilter blur that was measured; the other
// half of that defect is the screen-relative deltas, patched in
// `inspire_child_blur_image_filter_pass.dart` (Patch 1).
//
// 192 = ceil(3 * 64), which is the radius the DEVICE-px reading of the
// package's own 64 ceiling implies. Sized to the maximum sigma a caller is
// expected to use (64/3 logical = 64 device px at dpr 3), not to a particular
// default — 132 would cover a 44 device px sigma and leave every sigma between
// it and the ceiling truncated.
//
// Cost at rest is nil: the loop breaks on `x > radiusClamped`, so a sigma of
// 44 still runs 44 iterations. This raises the compile-time bound only.
#define MAX_RADIUS 192
#define MAX_RADIUS_F 192.0

// Minimum sigma below which blur is negligible and skipped.
#define MIN_SIGMA 1.0e-2

// Minimum weight used to avoid division by zero during normalization.
#define MIN_WEIGHT 1.0e-5

out vec4 frag_color;

uniform vec2 u_size;
uniform sampler2D u_texture;

// Gradient map where Red channel controls [0-1] blur strength factor at given pixel.
// Where: 0 — no blur, 1 — full blur.
uniform sampler2D u_blur_texture;

// Blur sigma.
uniform float u_blur_sigma;

// An already normalized (0,1) or (1,0) direction vector.
uniform vec2 u_blur_direction;

// --- Screen position correction ---
uniform vec2 u_delta_left_top;
uniform vec2 u_delta_right_bottom;

// --- Transformation ---
uniform vec2 u_transform_scale;
uniform vec2 u_transform_offset;
uniform float u_transform_rotation;
uniform vec2 u_transform_origin;
uniform float u_transform_inversion;

// --- Color adjustment ---
uniform float u_brightness;
uniform float u_contrast;
uniform float u_exposure;
uniform float u_saturation;
uniform float u_vibrance;
uniform float u_color_adjustment_blur_strength;
uniform float u_color_adjustment_non_blur_strength;

// ── Patch 5 kernel sampling modes · PATCHED vs upstream. ────────────────────
// Observed: on a short list bounced past the bottom the header blur "looks
// pixelated". The whole ramp then sits at a SMALL sigma (the caller scales it
// by scroll progress), and the loop below steps one
// TEXEL per tap. Under the two sampler passes a texel is one LOGICAL px — 3
// device px at dpr 3 — so a sigma of ~1 logical averages a handful of copies
// of the content shifted 3 device px apart: a stepped, ghosted image instead
// of a soft one. These two floats pick an alternative; both default to 0.0,
// and 0.0 runs the pub loop below byte for byte (the `< 0.5` branch).
//
//   u_sample_mode   0 unit       pub: one tap per texel (today)
//                   1 fineStep   step = clamp(sigma / 3, deviceStep, 1) texel
//                   2 denseTaps  one tap per DEVICE px while sigma < 12 dev px
//                   3 minSigma   never below 9 device px; crossfade to bg
//   u_device_step   one device px in texel units: 1/dpr for the sampler
//                   passes (whose texel is logical), 1.0 for imageFilter.
//
// Floats 24 and 25. Unset uniforms are zero, so a caller that never sets them
// gets today's kernel; every Dart caller in this package sets both anyway.
uniform float u_sample_mode;
uniform float u_device_step;

vec2 transformUv(vec2 uv) {
  // Move to origin
  uv -= u_transform_origin;

  // Undo translation
  uv -= u_transform_offset;

  // Undo rotation
  float c = cos(-u_transform_rotation);
  float s = sin(-u_transform_rotation);

  uv = mat2(
    c, -s,
    s, c
  ) * uv;

  // Undo scale
  uv /= sign(u_transform_scale) * max(abs(u_transform_scale), vec2(0.0001));

  // Restore origin
  uv += u_transform_origin;

  return uv;
}

vec3 applyPositiveContrastCurve(vec3 x, float k) {
  vec3 s = 1.0 / (1.0 + exp(-k * (x - 0.5)));

  float lo = 1.0 / (1.0 + exp( k * 0.5));
  float hi = 1.0 / (1.0 + exp(-k * 0.5));

  return (s - vec3(lo)) / (hi - lo);
}

vec3 applyNegativeContrastCurve(vec3 x, float p) {
  // Add 0.01 to cut the lower and upper histogram slightly to prevent artifacts.
  vec3 lower = 0.5 * pow(2.0 * (x + 0.01), vec3(p));
  vec3 upper = 1.0 - 0.5 * pow(2.0 * (1.01 - x), vec3(p));

  return mix(lower, upper, step(vec3(0.5), x));
}

vec3 applySaturation(vec3 color, float saturation) {
  float luminance = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
  return mix(vec3(luminance), color, saturation);
}

vec3 applyVibrance(vec3 color, float vibrance) {
  float luminance = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));

  float maxChannel = max(color.r, max(color.g, color.b));
  float minChannel = min(color.r, min(color.g, color.b));

  float saturation = maxChannel > 1e-5
        ? (maxChannel - minChannel) / maxChannel
        : 0.0;

  float coef = vibrance * (1.0 - saturation);

  return mix(vec3(luminance), color, 1.0 + coef);
}

vec4 applyColorAdjustments(vec4 color, float blurFactor) {
  vec4 original = color;
  float alpha = color.a;

  // Undo premultiplied alpha
  if (alpha > 1e-5) {
    color.rgb /= alpha;
  }

  // 1. Exposure
  if (u_exposure != 0.0) {
    color.rgb *= exp2(u_exposure);
  }

  // 2. Brightness
  if (u_brightness != 0.0) {
    color.rgb += u_brightness * vec3(1.0);
  }

  // 3. Contrast
  if (u_contrast > 1.0) {
    color.rgb = applyPositiveContrastCurve(color.rgb, u_contrast);
  }
  if (u_contrast < 1.0) {
    color.rgb = applyNegativeContrastCurve(clamp(color.rgb, 0.0, 1.0), u_contrast);
  }

  // 4. Saturation
  if (u_saturation != 1.0) {
    color.rgb = applySaturation(color.rgb, u_saturation);
  }

  // 5. Vibrance
  if (u_vibrance != 0.0) {
    color.rgb = applyVibrance(color.rgb, u_vibrance);
  }

  // Premultiply alpha back
  if (alpha > 1e-5) {
    color.rgb *= alpha;
  }

  float nonBlurAreaFactor = (1.0 - blurFactor) * u_color_adjustment_non_blur_strength;
  float blurAreaFactor = blurFactor * u_color_adjustment_blur_strength;
  float adjustmentBlend = clamp(nonBlurAreaFactor + blurAreaFactor, 0.0, 1.0);

  return mix(original, color, adjustmentBlend);
}

// Patch 5 kernel sampling modes · modes 1-3 (see the uniforms). Same edge rule as pub's loop:
// a tap outside [0, 1] is dropped and the rest renormalised. The reach never
// exceeds pub's `ceil(3 * sigma)` texels in modes 1 and 2 (the window the band
// sampler snapshots is sized to that); mode 3 reaches `ceil(3 * sigmaMin)`
// and the band sampler widens its window to match.
vec4 sampledBlur(vec2 uv, vec2 texelStep, float sigma, vec4 bg) {
  float deviceStep = u_device_step > 0.0 ? min(u_device_step, 1.0) : 1.0;

  float kernelSigma = sigma;
  float fade = 1.0;
  float stepTexels = 1.0;
  if (u_sample_mode < 1.5) {
    // 1 · fineStep: about three taps per sigma, never finer than a device px.
    stepTexels = clamp(sigma / 3.0, deviceStep, 1.0);
  } else if (u_sample_mode < 2.5) {
    // 2 · denseTaps: every device px while the kernel is weak (< 12 device px).
    stepTexels = sigma < 12.0 * deviceStep ? deviceStep : 1.0;
  } else {
    // 3 · minSigma: run the kernel at >= 9 device px (3 taps per sigma at the
    // unit step, out of the sparse regime) and fade it in by sigma / sigmaMin.
    float sigmaMin = 9.0 * deviceStep;
    if (sigma < sigmaMin) {
      fade = sigma / sigmaMin;
      kernelSigma = sigmaMin;
    }
  }

  float invTwoSigma2 = 1.0 / (2.0 * kernelSigma * kernelSigma);
  float radiusClamped = min(ceil(3.0 * kernelSigma), MAX_RADIUS_F);
  float taps = floor(radiusClamped / stepTexels + 1.0e-4);

  vec4 totalColor = bg;
  float totalWeight = 1.0;
  for (int i = 1; i <= MAX_RADIUS; i++) {
    float n = float(i);
    if (n > taps) break;
    float x = n * stepTexels;
    float weight = exp(-(x * x) * invTwoSigma2);

    vec2 uvRaw1 = uv + texelStep * x;
    vec2 uvRaw2 = uv - texelStep * x;
    float mask1 =
        step(0.0, uvRaw1.x) * step(uvRaw1.x, 1.0) *
        step(0.0, uvRaw1.y) * step(uvRaw1.y, 1.0);
    float mask2 =
        step(0.0, uvRaw2.x) * step(uvRaw2.x, 1.0) *
        step(0.0, uvRaw2.y) * step(uvRaw2.y, 1.0);
    vec4 c1 = texture(u_texture, clamp(uvRaw1, 0.0, 1.0));
    vec4 c2 = texture(u_texture, clamp(uvRaw2, 0.0, 1.0));
    float w1 = weight * mask1;
    float w2 = weight * mask2;
    totalColor += c1 * w1 + c2 * w2;
    totalWeight += w1 + w2;
  }
  return mix(bg, totalColor / max(totalWeight, MIN_WEIGHT), fade);
}

void main() {
  vec2 xy = FlutterFragCoord().xy;
  vec2 uv = xy / u_size;
  vec2 uv_blur = (xy + u_delta_left_top) / (u_size + u_delta_left_top + u_delta_right_bottom);
  uv_blur = transformUv(uv_blur);

  vec2 texel = 1.0 / u_size;

#if defined(IMPELLER_TARGET_OPENGLES) && !defined(IMPELLER_OPENGLES_UNFLIPPED_DEPRECATED)
    uv.y = 1.0 - uv.y;
  #endif

  vec4 bg = texture(u_texture, uv);
  float blurFactor = texture(u_blur_texture, uv_blur).r;
  blurFactor = mix(
    blurFactor,
    1.0 - blurFactor,
    u_transform_inversion
  );
  blurFactor = clamp(blurFactor, 0.0, 1.0);

  float sigma = u_blur_sigma * blurFactor;

  if (sigma < MIN_SIGMA) {
    if (
      u_color_adjustment_non_blur_strength > 0.0 ||
      u_color_adjustment_blur_strength > 0.0
    ) {
      frag_color = applyColorAdjustments(bg, 0.0);
    } else {
      frag_color = bg;
    }
    return;
  }

  float invTwoSigma2 = 1.0 / (2.0 * sigma * sigma);

  // Blur radius is approximated as 3 * sigma (~99% of Gaussian contribution).
  float radius = ceil(3.0 * sigma);
  float radiusClamped = min(radius, MAX_RADIUS_F);

  vec2 texelStep = texel * u_blur_direction;

  float totalWeight = 0.0;
  vec4 totalColor = vec4(0.0);

  if (u_sample_mode >= 0.5) {
    frag_color = sampledBlur(uv, texelStep, sigma, bg);
  } else {
  for (int i = 0; i <= MAX_RADIUS; i++) {
    float x = float(i);
    if (x > radiusClamped) break;
    
    float weight = exp(-(x * x) * invTwoSigma2);

    if (i == 0) {
      totalColor += bg * weight;
      totalWeight += weight;
    } else {
      vec2 offset = texelStep * x;

      vec2 uvRaw1 = uv + offset;
      vec2 uvRaw2 = uv - offset;

      // Check if inside bounds
      float mask1 =
          step(0.0, uvRaw1.x) * step(uvRaw1.x, 1.0) *
          step(0.0, uvRaw1.y) * step(uvRaw1.y, 1.0);

      float mask2 =
          step(0.0, uvRaw2.x) * step(uvRaw2.x, 1.0) *
          step(0.0, uvRaw2.y) * step(uvRaw2.y, 1.0);

      // Clamp only for safe sampling
      vec2 uv1 = clamp(uvRaw1, 0.0, 1.0);
      vec2 uv2 = clamp(uvRaw2, 0.0, 1.0);

      vec4 c1 = texture(u_texture, uv1);
      vec4 c2 = texture(u_texture, uv2);

      float w1 = weight * mask1;
      float w2 = weight * mask2;

      totalColor += c1 * w1 + c2 * w2;
      totalWeight += w1 + w2;
    }
  }

  frag_color = totalColor / max(totalWeight, MIN_WEIGHT);
  }

  if (
    u_color_adjustment_non_blur_strength > 0.0 ||
    u_color_adjustment_blur_strength > 0.0
  ) {
    frag_color = applyColorAdjustments(frag_color, blurFactor);
  }
}
