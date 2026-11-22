#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform sampler2D uScene;
out vec4 fragColor;
void main() {
  vec2 p = FlutterFragCoord().xy - 0.5 * uSize;
  float radius = 0.5 * min(uSize.x, uSize.y);
  vec2 normal = p - vec2(clamp(p.x, -0.5*uSize.x+radius, 0.5*uSize.x-radius), 0.0);
  float depth = clamp(length(normal) / max(radius, 1.0), 0.0, 1.0);
  // Bend the backdrop only along the curved lip. The lens center stays flat.
  float lip = smoothstep(0.66, 1.0, depth);
  vec2 uv = (p - 0.21 * normal * lip * lip) / uSize + 0.5;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  vec4 color = texture(uScene, clamp(uv, 0.0, 1.0));
  float light = dot(normal / max(length(normal), 1.0), vec2(-0.6,-0.8));
  float rim = smoothstep(0.88, 0.98, depth);
  vec3 shaded = color.rgb * (1.0 - 0.12 * lip * max(0.0, -light));
  fragColor = vec4(mix(shaded, vec3(color.a), rim * max(0.0, light) * 0.56), color.a);
}
