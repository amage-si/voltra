#version 450
// Voltra 2D primitive, fragment stage. Every coverage and color value is
// computed with integer arithmetic, so a CPU renderer that follows the same
// rules (Chromi's reference) produces the same bytes. Values stay in encoded
// sRGB with straight alpha; fixed-function blending composes source-over.
//
// Kinds (paint.y):
//   0 flat      the color;
//   1 texels    the texture region shape (u, v, w, h) mapped onto the quad
//               by nearest texel (integer division), each channel tinted
//               as (texel * color + 127) / 255 -- 0xFFFFFFFF keeps texels;
//   2 coverage  texel red (u + dx, v + dy) is coverage c: alpha becomes
//               (alpha * c + 127) / 255;
//   3 rounded   box shape (x0, y0, x1, y1) in 1/8 pixels with corner
//               radius paint.z, sampled 4x4 per pixel;
//   4 ring      the same box minus the box inset by paint.w with radius
//               max(radius - border, 0).
// Rounded coverage: samples at 8p + 1, 3, 5, 7 (1/8 px) on both axes; hits
// h (0..16) give c = (255 h + 8) / 16, then alpha as for coverage.

layout(set = 0, binding = 0) uniform sampler2D atlas;

layout(location = 0) flat in ivec4 rect;
layout(location = 1) flat in ivec4 clip;
layout(location = 2) flat in uvec4 paint;
layout(location = 3) flat in ivec4 shape;

layout(location = 0) out vec4 target;

bool inside(ivec2 s, ivec4 box, int r) {
  if (s.x < box.x || s.y < box.y || s.x >= box.z || s.y >= box.w) {
    return false;
  }
  int dx = s.x < box.x + r ? box.x + r - s.x : (s.x >= box.z - r ? s.x - (box.z - r) : 0);
  int dy = s.y < box.y + r ? box.y + r - s.y : (s.y >= box.w - r ? s.y - (box.w - r) : 0);
  return dx == 0 || dy == 0 || dx * dx + dy * dy <= r * r;
}

uint hits(ivec2 p, ivec4 box, int r, int b) {
  ivec4 inner = box + ivec4(b, b, -b, -b);
  int ir = max(r - b, 0);
  uint n = 0u;
  for (int j = 0; j < 4; j++) {
    for (int i = 0; i < 4; i++) {
      ivec2 s = p * 8 + ivec2(1 + 2 * i, 1 + 2 * j);
      bool in_ring = b == 0 || inner.x >= inner.z || inner.y >= inner.w || !inside(s, inner, ir);
      n += uint(inside(s, box, r) && in_ring);
    }
  }
  return n;
}

uint byte_of(float v) {
  return uint(v * 255.0 + 0.5);
}

void main() {
  ivec2 p = ivec2(gl_FragCoord.xy);
  if (p.x < clip.x || p.y < clip.y || p.x >= clip.z || p.y >= clip.w) {
    discard;
  }
  uint k = paint.x;
  uvec4 c = uvec4(k >> 24, (k >> 16) & 255u, (k >> 8) & 255u, k & 255u);
  uint kind = paint.y;
  uvec4 o = c;
  if (kind == 1u) {
    ivec2 t = shape.xy + ((p - rect.xy) * shape.zw) / max(rect.zw, ivec2(1));
    vec4 f = texelFetch(atlas, t, 0);
    uvec4 x = uvec4(byte_of(f.r), byte_of(f.g), byte_of(f.b), byte_of(f.a));
    o = (x * c + 127u) / 255u;
  } else if (kind == 2u) {
    uint cov = byte_of(texelFetch(atlas, shape.xy + (p - rect.xy), 0).r);
    o.a = (c.a * cov + 127u) / 255u;
  } else if (kind >= 3u) {
    int border = kind == 4u ? int(paint.w) : 0;
    uint cov = (255u * hits(p, shape, int(paint.z), border) + 8u) / 16u;
    o.a = (c.a * cov + 127u) / 255u;
  }
  target = vec4(o) / 255.0;
}
