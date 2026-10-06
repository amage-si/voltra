import Base

# Quads, the one primitive Voltra's pipeline draws, and the conversions from
# Base.Image quadtrees into GPU-ready data.
#
# Coordinates are physical pixels, origin top left, y down; x and y are
# signed 32-bit values carried in U32 bits. Colors are straight RGBA8 packed
# 0xRRGGBBAA in encoded sRGB, as COORDENACAO.md specifies.
#
# A quad covers the pixels whose centers lie inside it, minus those outside
# its clip box [x0, x1) x [y0, y1). What it paints depends on its kind (see
# shaders/prim.frag, which defines every rule with integer arithmetic):
#   0 flat      its color;
#   1 texels    a texture region mapped onto it by nearest texel, tinted;
#   2 coverage  a texture region's red channel as coverage of its color;
#   3 rounded   a box in 1/8 pixels with rounded corners, 4x4 samples/pixel;
#   4 ring      the border of such a box.

type Quad is Data:
  Quad{x: U32, y: U32, width: U32, height: U32,
    clip_x0: U32, clip_y0: U32, clip_x1: U32, clip_y1: U32,
    color: U32, kind: U32, radius: U32, border: U32,
    a: U32, b: U32, c: U32, d: U32}

def stride_words() -> U32:
  16

# The widest clip: every pixel of any target.
def far_low() -> U32:
  2147483648

def far_high() -> U32:
  2147483647

# A flat colored rectangle.
def fill(x: U32, y: U32, width: U32, height: U32, color: U32) -> Quad:
  Quad{x, y, width, height, far_low(), far_low(), far_high(), far_high(),
    color, 0, 0, 0, 0, 0, 0, 0}

# A rectangle sampling the texel region (u, v, source_width, source_height)
# of the bound texture by nearest texel, each channel tinted as
# (texel * tint + 127) / 255 (0xFFFFFFFF draws the texels unchanged).
def image(x: U32, y: U32, width: U32, height: U32, u: U32, v: U32,
  source_width: U32, source_height: U32, tint: U32) -> Quad:
  Quad{x, y, width, height, far_low(), far_low(), far_high(), far_high(),
    tint, 1, 0, 0, u, v, source_width, source_height}

# A coverage mask: texel (u + dx, v + dy)'s red channel is the coverage c
# of pixel (x + dx, y + dy); the ink's alpha becomes (alpha * c + 127) / 255.
def mask(x: U32, y: U32, +width: U32, +height: U32, u: U32, v: U32, ink: U32) -> Quad:
  Quad{x, y, width, height, far_low(), far_low(), far_high(), far_high(),
    ink, 2, 0, 0, u, v, width, height}

# Signed floor and ceiling of v / 8 on 32-bit two's complement words.
def negative(+v: U32) -> Bool:
  U32.is_ge(v, 2147483648)

def floor8(+v: U32) -> U32:
  Bool.pick(U32, negative(v), (0 - (((0 - v : U32) + 7 : U32) / 8 : U32) : U32), (v / 8 : U32))

def ceil8(+v: U32) -> U32:
  (0 - floor8((0 - v : U32)) : U32)

def rounded.kind(+kind: U32, +x0: U32, +y0: U32, +x1: U32, +y1: U32, +radius: U32,
  +border: U32, color: U32) -> Quad:
  +px = floor8(x0)
  +py = floor8(y0)
  Quad{px, py, (ceil8(x1) - px : U32), (ceil8(y1) - py : U32),
    far_low(), far_low(), far_high(), far_high(), color, kind, radius, border,
    x0, y0, x1, y1}

# A filled box (x0, y0)-(x1, y1) in 1/8 pixels with corner radius `radius`
# (1/8 pixels; at most half the shorter side), antialiased by 4x4 samples.
def rounded(x0: U32, y0: U32, x1: U32, y1: U32, radius: U32, color: U32) -> Quad:
  rounded.kind(3, x0, y0, x1, y1, radius, 0, color)

# The border of such a box: `border` (1/8 pixels) wide, inner radius
# max(radius - border, 0).
def ring(x0: U32, y0: U32, x1: U32, y1: U32, radius: U32, border: U32, color: U32) -> Quad:
  rounded.kind(4, x0, y0, x1, y1, radius, border, color)

# The quad restricted to the pixels of [x0, x1) x [y0, y1).
def clipped(q: Quad, x0: U32, y0: U32, x1: U32, y1: U32) -> Quad:
  Quad{x, y, w, h, a0, b0, a1, b1, color, kind, r, br, a, b, c, d} = q
  Quad{x, y, w, h, x0, y0, x1, y1, color, kind, r, br, a, b, c, d}

# Instance words, matching the pipeline's vertex input in gpu.bend:
# ivec4 rect, ivec4 clip, uvec4 (color, kind, radius, border), ivec4 shape.
def pack(qs: List<&2, Quad>) -> List<&2, U32>:
  match qs:
    case Nil{}:
      Nil{}
    case Con{Quad{x, y, w, h, a0, b0, a1, b1, color, kind, r, br, a, b, c, d}, rest}:
      x <> y <> w <> h <> a0 <> b0 <> a1 <> b1 <> color <> kind <> r <> br <>
        a <> b <> c <> d <> pack(rest)

# Base.Image leaves hold 0xRRGGBB (Chromi's `finish` output); the GPU path
# takes opaque RGBA8.
def opaque(+rgb: U32) -> U32:
  ((rgb << 8n) .|. 255 : U32)

# The visible part of a side-long square at (x, y) on a w x h surface.
def span(+pos: U32, +side: U32, +limit: U32) -> U32:
  Bool.pick(U32, U32.is_ge(pos, limit), 0, (U32.min((pos + side : U32), limit) - pos : U32))

def keep(empty: Bool, q: Quad, acc: List<&2, Quad>) -> List<&2, Quad>:
  match empty:
    case True{}:
      acc
    case False{}:
      q <> acc

# Every quadtree leaf as one opaque quad, clipped to w x h. Uniform regions
# stay single quads, so a mostly flat UI frame is a few thousand instances.
def leaves(img: Image, +x: U32, +y: U32, +side: U32, +w: U32, +h: U32,
  acc: List<&2, Quad>) -> List<&2, Quad>:
  match img:
    case Pix{rgb}:
      +qw = span(x, side, w)
      +qh = span(y, side, h)
      keep(U32.is_eq(qw, 0) || U32.is_eq(qh, 0), fill(x, y, qw, qh, opaque(rgb)), acc)
    case Qua{a, b, c, d}:
      +half = (side / 2 : U32)
      +right = (x + half : U32)
      +bottom = (y + half : U32)
      leaves(a, x, y, half, w, h,
        leaves(b, right, y, half, w, h,
          leaves(c, x, bottom, half, w, h,
            leaves(d, right, bottom, half, w, h, acc))))

# The side of the square quadtree that covers w x h (a power of two).
def side.go(n: Nat, +s: U32, +need: U32) -> U32:
  match n:
    case 0n:
      s
    case 1n+p:
      Bool.pick(U32, U32.is_ge(s, need), s, side.go(p, (s * 2 : U32), need))

def side(+w: U32, +h: U32) -> U32:
  side.go(16n, 1, U32.max(w, h))

def row(n: Nat, a: Array<U32>, +i: U32, +c: U32) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+p:
      row(p, Array.set(U32, a, i, c), (i + 1 : U32), c)

def rows(n: Nat, a: Array<U32>, +i: U32, +stride: U32, +cols: Nat, +c: U32) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+p:
      rows(p, row(cols, a, i, c), (i + stride : U32), stride, cols, c)

# The quadtree as a row-major w x h RGBA8 array (power-of-two capacity),
# ready for a texture upload. Each pixel is written once.
def raster(img: Image, a: Array<U32>, +x: U32, +y: U32, +side: U32, +w: U32, +h: U32) -> Array<U32>:
  match img:
    case Pix{rgb}:
      rows(U32.to_nat(span(y, side, h)), a, (y * w + x : U32), w,
        U32.to_nat(span(x, side, w)), opaque(rgb))
    case Qua{q0, q1, q2, q3}:
      +half = (side / 2 : U32)
      +right = (x + half : U32)
      +bottom = (y + half : U32)
      raster(q3, raster(q2, raster(q1, raster(q0, a, x, y, half, w, h),
        right, y, half, w, h), x, bottom, half, w, h), right, bottom, half, w, h)
