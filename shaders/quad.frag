#version 450
// Flat color, or the texture tinted by the color when flags bit 0 is set.
// Values stay in encoded sRGB, matching Chromi's CPU composition.

layout(set = 0, binding = 0) uniform sampler2D image;

layout(location = 0) in vec2 uv;
layout(location = 1) flat in vec4 color;
layout(location = 2) flat in uint flags;

layout(location = 0) out vec4 target;

void main() {
  vec4 c = color;
  if ((flags & 1u) != 0u) {
    c *= texture(image, uv);
  }
  target = c;
}
