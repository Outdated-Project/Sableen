#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform sampler2D uScene;
out vec4 fragColor;
void main() {
  vec2 p = FlutterFragCoord().xy - 0.5 * uSize;
  float radius = 0.5 * min(uSize.x, uSize.y);
  vec2 normal = p - vec2(clamp(p.x, -0.5*uSize.x+radius, 0.5*uSize.x-radius), 0.0);
  float depth = clamp(length(normal) / max(radius, 1.0), 0.0, 1.0);
  vec2 uv = (p - 0.18 * normal * depth * depth) / uSize + 0.5;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  vec4 color = texture(uScene, clamp(uv, 0.0, 1.0));
  float glint = smoothstep(0.76, 1.0, depth) * max(0.0, dot(normal / max(length(normal), 1.0), vec2(-0.6,-0.8)));
  fragColor = vec4(mix(color.rgb, vec3(color.a), glint * 0.54), color.a);
}
