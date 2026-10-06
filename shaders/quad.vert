#version 450
// Voltra quad shader: one instance per quad, six vertices from gl_VertexIndex.
// All positions are physical pixels with the origin at the top left.

layout(location = 0) in ivec4 rect;     // x, y, width, height
layout(location = 1) in uvec4 source;   // texture texels: x, y, width, height
layout(location = 2) in uvec2 paint;    // 0xRRGGBBAA straight color, flags

layout(push_constant) uniform Frame {
  uvec4 size;  // target width, height; texture width, height
} frame;

layout(location = 0) out vec2 uv;
layout(location = 1) flat out vec4 color;
layout(location = 2) flat out uint flags;

const vec2 corners[6] = vec2[](
  vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(0.0, 1.0),
  vec2(1.0, 0.0), vec2(1.0, 1.0), vec2(0.0, 1.0));

void main() {
  vec2 c = corners[gl_VertexIndex];
  vec2 p = vec2(rect.xy) + c * vec2(rect.zw);
  gl_Position = vec4(p / vec2(frame.size.xy) * 2.0 - 1.0, 0.0, 1.0);
  vec2 texels = vec2(max(frame.size.zw, uvec2(1u)));
  uv = (vec2(source.xy) + c * vec2(source.zw)) / texels;
  uint k = paint.x;
  color = vec4(float(k >> 24), float((k >> 16) & 255u),
    float((k >> 8) & 255u), float(k & 255u)) / 255.0;
  flags = paint.y;
}
