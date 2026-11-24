#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;
uniform float u_fade_start;
uniform float u_fade_end;
uniform sampler2D u_texture;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / u_size;
  float t = clamp((uv.y - u_fade_start) / (u_fade_end - u_fade_start), 0.0, 1.0);
  float blurOpacity = (1.0 - t) * (1.0 - t);
  fragColor = texture(u_texture, uv) * blurOpacity;
}
