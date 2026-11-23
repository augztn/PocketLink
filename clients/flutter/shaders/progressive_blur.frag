#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;
uniform float u_max_sigma;
uniform float u_min_sigma;
uniform sampler2D u_texture;

out vec4 fragColor;

vec4 sampleBackdrop(vec2 uv) {
  return texture(u_texture, clamp(uv, vec2(0.0), vec2(1.0)));
}

void main() {
  vec2 uv = FlutterFragCoord().xy / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif

  float sigma = mix(u_max_sigma, u_min_sigma, smoothstep(0.0, 1.0, uv.y));
  vec2 offset = (sigma * 1.35) / u_size;

  vec4 color = sampleBackdrop(uv) * 0.25;
  color += sampleBackdrop(uv + vec2(offset.x, 0.0)) * 0.125;
  color += sampleBackdrop(uv - vec2(offset.x, 0.0)) * 0.125;
  color += sampleBackdrop(uv + vec2(0.0, offset.y)) * 0.125;
  color += sampleBackdrop(uv - vec2(0.0, offset.y)) * 0.125;
  color += sampleBackdrop(uv + offset) * 0.0625;
  color += sampleBackdrop(uv - offset) * 0.0625;
  color += sampleBackdrop(uv + vec2(offset.x, -offset.y)) * 0.0625;
  color += sampleBackdrop(uv + vec2(-offset.x, offset.y)) * 0.0625;

  fragColor = color;
}
