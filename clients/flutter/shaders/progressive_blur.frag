#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;
uniform float u_fade_start;
uniform float u_fade_end;
uniform sampler2D u_texture;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif

  float blurOpacity = 1.0 - smoothstep(u_fade_start, u_fade_end, uv.y);
  fragColor = texture(u_texture, uv) * blurOpacity;
}
