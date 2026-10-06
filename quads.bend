import Base

# Quads, the one primitive Voltra's pipeline draws, and the conversions from
# Base.Image quadtrees (as produced by Chromi) into GPU-ready data.
#
# Coordinates are physical pixels, origin top left, y down; x and y are
# signed 32-bit values carried in U32 bits. Colors are straight RGBA8 packed
# 0xRRGGBBAA in encoded sRGB, as COORDENACAO.md specifies.

type Quad is Data:
  Quad{x: U32, y: U32, width: U32, height: U32, u: U32, v: U32,
    source_width: U32, source_height: U32, color: U32, textured: Bool}

def stride_words() -> U32:
  10

# A flat colored rectangle.
def fill(x: U32, y: U32, width: U32, height: U32, color: U32) -> Quad:
  Quad{x, y, width, height, 0, 0, 0, 0, color, False{}}

# A rectangle sampling a texel region of the bound texture, tinted by color
# (0xFFFFFFFF draws the texels unchanged).
def image(x: U32, y: U32, width: U32, height: U32, u: U32, v: U32,
  source_width: U32, source_height: U32, color: U32) -> Quad:
  Quad{x, y, width, height, u, v, source_width, source_height, color, True{}}

# Instance words, matching the pipeline's vertex input in gpu.bend:
# ivec4 rect, uvec4 source, uvec2 (color, flags).
def pack(qs: List<&2, Quad>) -> List<&2, U32>:
  match qs:
    case Nil{}:
      Nil{}
    case Con{Quad{x, y, w, h, u, v, sw, sh, c, t}, rest}:
      x <> y <> w <> h <> u <> v <> sw <> sh <> c <> Bool.to_u32(t) <> pack(rest)

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
