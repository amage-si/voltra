#version 450
// Voltra 2D primitive, vertex stage: one instance per quad, six vertices from
// gl_VertexIndex. Positions are physical pixels with the origin at the top
// left; the quad covers exactly the pixels whose centers lie inside it.
// Everything the fragment stage needs passes through unchanged, flat.

layout(location = 0) in ivec4 rect;    // quad x, y, width, height (pixels)
layout(location = 1) in ivec4 clip;    // pixels outside [x0,x1) x [y0,y1) are dropped
layout(location = 2) in uvec4 paint;   // color 0xRRGGBBAA, kind, radius, border
layout(location = 3) in ivec4 shape;   // texel region u v w h, or box x0 y0 x1 y1 (1/8 px)

layout(push_constant) uniform Frame {
  uvec4 size;  // target width, height; texture width, height
} frame;

layout(location = 0) flat out ivec4 o_rect;
layout(location = 1) flat out ivec4 o_clip;
layout(location = 2) flat out uvec4 o_paint;
layout(location = 3) flat out ivec4 o_shape;

const vec2 corners[6] = vec2[](
  vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(0.0, 1.0),
  vec2(1.0, 0.0), vec2(1.0, 1.0), vec2(0.0, 1.0));

void main() {
  vec2 c = corners[gl_VertexIndex];
  vec2 p = vec2(rect.xy) + c * vec2(rect.zw);
  gl_Position = vec4(p / vec2(frame.size.xy) * 2.0 - 1.0, 0.0, 1.0);
  o_rect = rect;
  o_clip = clip;
  o_paint = paint;
  o_shape = shape;
}
