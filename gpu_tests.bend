import Base
import ./gpu.bend as V
import ./quads.bend as Q
import ./words.bend as W
import ./commands.bend as C

# GPU checks, offscreen: every kind of quad is drawn into a 256x256 target,
# read back, and compared pixel by pixel with values computed here in Bend
# by the integer rules of shaders/prim.frag and source-over composition
# (channel = (s * a + d * (255 - a) + 127) / 255). They need a Vulkan 1.3
# GPU but no display. Each check reports how many of the 65,536 pixels
# differ and the largest channel difference.

def size() -> U32:
  256

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ message)
    case False{}:
      IO.die(Unit, 1, "FAIL " ++ message)

# Color arithmetic
# ----------------

def red(+c: U32) -> U32:
  (c >> 24n : U32)

def green(+c: U32) -> U32:
  ((c >> 16n) .&. 255 : U32)

def blue(+c: U32) -> U32:
  ((c >> 8n) .&. 255 : U32)

def alpha(+c: U32) -> U32:
  (c .&. 255 : U32)

def pack(+r: U32, +g: U32, +b: U32, +a: U32) -> U32:
  ((r << 24n) .|. (g << 16n) .|. (b << 8n) .|. a : U32)

def channel(+s: U32, +d: U32, +a: U32) -> U32:
  ((s * a + d * (255 - a) + 127) / 255 : U32)

# Source-over of a straight-alpha color onto an opaque destination.
def over(+src: U32, +dst: U32) -> U32:
  +a = alpha(src)
  pack(channel(red(src), red(dst), a), channel(green(src), green(dst), a),
    channel(blue(src), blue(dst), a), 255)

def tint(+t: U32, +c: U32) -> U32:
  ((t * c + 127) / 255 : U32)

def with_alpha(+c: U32, +a: U32) -> U32:
  ((c .&. 4294967040 : U32) .|. a : U32)

# Comparison
# ----------

type Diff is Data:
  Diff{count: U32, worst: U32}

def absdiff(+a: U32, +b: U32) -> U32:
  (U32.max(a, b) - U32.min(a, b) : U32)

def worst(+a: U32, +b: U32) -> U32:
  U32.max(U32.max(absdiff(red(a), red(b)), absdiff(green(a), green(b))),
    U32.max(absdiff(blue(a), blue(b)), absdiff(alpha(a), alpha(b))))

def tally(d: Diff, +got: U32, +want: U32) -> Diff:
  Diff{n, w} = d
  +off = U32.is_ne(got, want)
  Diff{(n + Bool.to_u32(off) : U32), U32.max(w, worst(got, want))}

# Compares pixel i of the readback with expected(i) for every pixel.
def compare(~expected: U32 -> U32, n: Nat, r: Array<U32> & U32, +i: U32, d: Diff) -> Diff:
  match n:
    case 0n:
      d
    case 1n+p:
      (a, +got) = r
      +j = (i + 1 : U32)
      compare(~expected, p, Array.get(U32, a, j), j, tally(d, got, expected(i)))

def report(d: Diff, name: String) -> IO(Unit):
  Diff{+n, +w} = d
  check(U32.is_eq(n, 0), name ++ ": " ++ U32.show(n) ++ " of 65536 pixels differ, max channel difference " ++ U32.show(w))

# Scenes
# ------

def background() -> U32:
  336860415

def full(+c: U32) -> Q.Quad:
  Q.fill(0, 0, size(), size(), c)

# Flat quads with clips and translucency.
def flat.quads() -> List<&2, Q.Quad>:
  [Q.fill(10, 10, 100, 60, 4278190335),
   Q.clipped(Q.fill(0, 0, 256, 256, 16711808), 40, 20, 200, 90),
   Q.fill(4294967286, 200, 30, 30, 65535),
   Q.clipped(Q.fill(120, 120, 120, 120, 2155905152), 0, 0, 180, 256)]

def inside(+x: U32, +y: U32, +x0: U32, +y0: U32, +x1: U32, +y1: U32) -> Bool:
  U32.is_ge(x, x0) && U32.is_lt(x, x1) && U32.is_ge(y, y0) && U32.is_lt(y, y1)

def layer(on: Bool, +src: U32, +dst: U32) -> U32:
  Bool.pick(U32, on, over(src, dst), dst)

def flat.expected(at: U32) -> U32:
  +i = at
  +x = (i % 256 : U32)
  +y = (i / 256 : U32)
  +c0 = background()
  +c1 = layer(inside(x, y, 10, 10, 110, 70), 4278190335, c0)
  +c2 = layer(inside(x, y, 40, 20, 200, 90), 16711808, c1)
  +c3 = layer(inside(x, y, 0, 200, 20, 230), 65535, c2)
  layer(inside(x, y, 120, 120, 180, 240), 2155905152, c3)

# Texels: texel (x, y) holds red x, green 255 - x, blue (x + y) % 256 and
# alpha y, so one image covers every source value with every alpha.
def texel(+x: U32, +y: U32) -> U32:
  pack(x, (255 - x : U32), ((x + y) % 256 : U32), y)

def texels.go(n: Nat, a: Array<U32>, +i: U32) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+p:
      texels.go(p, Array.set(U32, a, i, texel((i % 256 : U32), (i / 256 : U32))), (i + 1 : U32))

def texels() -> Array<U32>:
  texels.go(65536n, Array.new(U32, 16n, 0), 0)

def tinted(+t: U32, +c: U32) -> U32:
  pack(tint(red(t), red(c)), tint(green(t), green(c)), tint(blue(t), blue(c)), tint(alpha(t), alpha(c)))

def image.expected(~bg: U32, ~tint_color: U32, +i: U32) -> U32:
  over(tinted(texel((i % 256 : U32), (i / 256 : U32)), tint_color), bg)

def bg_a() -> U32:
  336860415

def bg_b() -> U32:
  2139062271

def bg_c() -> U32:
  4294967295

def white() -> U32:
  4294967295

def ink_tint() -> U32:
  2550118520

def image.a(at: U32) -> U32:
  +i = at
  image.expected(~bg_a(), ~white(), i)

def image.b(at: U32) -> U32:
  +i = at
  image.expected(~bg_b(), ~white(), i)

def image.c(at: U32) -> U32:
  +i = at
  image.expected(~bg_c(), ~ink_tint(), i)

# Coverage: the texture's red channel is x; quad row y has ink alpha y.
def mask.quads(n: Nat, +y: U32) -> List<&2, Q.Quad>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Q.mask(0, y, 256, 1, 0, y, with_alpha(4286595072, y)) <> mask.quads(p, (y + 1 : U32))

def mask.expected(at: U32) -> U32:
  +i = at
  +x = (i % 256 : U32)
  +y = (i / 256 : U32)
  over(with_alpha(4286595072, ((y * x + 127) / 255 : U32)), bg_b())

# Rounded boxes: the reference counts 4x4 samples exactly as prim.frag.
def corner(+s: U32, +lo: U32, +hi: U32, +r: U32) -> U32:
  Bool.pick(U32, U32.is_lt(s, (lo + r : U32)), (lo + r - s : U32),
    Bool.pick(U32, U32.is_ge(s, (hi - r : U32)), (s - (hi - r) : U32), 0))

def in_box(+sx: U32, +sy: U32, +x0: U32, +y0: U32, +x1: U32, +y1: U32, +r: U32) -> Bool:
  +dx = corner(sx, x0, x1, r)
  +dy = corner(sy, y0, y1, r)
  U32.is_ge(sx, x0) && U32.is_ge(sy, y0) && U32.is_lt(sx, x1) && U32.is_lt(sy, y1) &&
    (U32.is_eq(dx, 0) || U32.is_eq(dy, 0) || U32.is_le((dx * dx + dy * dy : U32), (r * r : U32)))

def sample(+sx: U32, +sy: U32, +x0: U32, +y0: U32, +x1: U32, +y1: U32, +r: U32, +b: U32) -> U32:
  +ix0 = (x0 + b : U32)
  +iy0 = (y0 + b : U32)
  +ix1 = (x1 - b : U32)
  +iy1 = (y1 - b : U32)
  +ring = U32.is_eq(b, 0) || U32.is_ge(ix0, ix1) || U32.is_ge(iy0, iy1) ||
    Bool.not(in_box(sx, sy, ix0, iy0, ix1, iy1, (r - U32.min(r, b) : U32)))
  Bool.to_u32(in_box(sx, sy, x0, y0, x1, y1, r) && ring)

def hits.go(n: Nat, +k: U32, +px: U32, +py: U32, +x0: U32, +y0: U32, +x1: U32, +y1: U32, +r: U32, +b: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      +sx = (px * 8 + 1 + 2 * (k % 4) : U32)
      +sy = (py * 8 + 1 + 2 * (k / 4) : U32)
      hits.go(p, (k + 1 : U32), px, py, x0, y0, x1, y1, r, b, (acc + sample(sx, sy, x0, y0, x1, y1, r, b) : U32))

def coverage(+px: U32, +py: U32, +x0: U32, +y0: U32, +x1: U32, +y1: U32, +r: U32, +b: U32) -> U32:
  ((255 * hits.go(16n, 0, px, py, x0, y0, x1, y1, r, b, 0) + 8) / 16 : U32)

def shaped(+c: U32, +cov: U32) -> U32:
  with_alpha(c, ((alpha(c) * cov + 127) / 255 : U32))

def round.quads() -> List<&2, Q.Quad>:
  [Q.rounded(83, 77, 1003, 621, 101, 4053246207),
   Q.ring(1101, 85, 1957, 1931, 200, 37, 2868903935),
   Q.rounded(300, 1300, 1900, 1900, 300, 1086374016),
   Q.ring(20, 1500, 400, 2030, 9, 50, 4294902015)]

def round.expected(at: U32) -> U32:
  +i = at
  +x = (i % 256 : U32)
  +y = (i / 256 : U32)
  +c1 = over(shaped(4053246207, coverage(x, y, 83, 77, 1003, 621, 101, 0)), bg_a())
  +c2 = over(shaped(2868903935, coverage(x, y, 1101, 85, 1957, 1931, 200, 37)), c1)
  +c3 = over(shaped(1086374016, coverage(x, y, 300, 1300, 1900, 1900, 300, 0)), c2)
  over(shaped(4294902015, coverage(x, y, 20, 1500, 400, 2030, 9, 50)), c3)

def frame(+g: V.Gpu, qs: List<&2, Q.Quad>, +clear: U32) -> IO(V.Gpu & Array<U32>):
  do IO<V.Gpu & Array<U32>>:
    +g1 : V.Gpu <- V.draw(g, qs, clear)
    V.read(g1)

# Every destination value: 86 frames of the texel image over the colors
# (3k, 3k + 1, 3k + 2), k = 0..85, so each of red, green and blue meets
# every destination byte with every source byte at every alpha.
def sweep.color(+k: U32) -> U32:
  pack(U32.min((3 * k : U32), 255), U32.min((3 * k + 1 : U32), 255), U32.min((3 * k + 2 : U32), 255), 255)

def compare.over(n: Nat, r: Array<U32> & U32, +i: U32, +bg: U32, d: Diff) -> Diff:
  match n:
    case 0n:
      d
    case 1n+p:
      (a, +got) = r
      +j = (i + 1 : U32)
      compare.over(p, Array.get(U32, a, j), j, bg,
        tally(d, got, over(texel((i % 256 : U32), (i / 256 : U32)), bg)))

def sweep.add(a: Diff, b: Diff) -> Diff:
  Diff{n1, w1} = a
  Diff{n2, w2} = b
  Diff{(n1 + n2 : U32), U32.max(w1, w2)}

def sweep.one(r: V.Gpu & Array<U32>, +bg: U32, d: Diff) -> V.Gpu & Diff:
  (g, a) = r
  (g, sweep.add(d, compare.over(65536n, Array.get(U32, a, 0), 0, bg, Diff{0, 0})))

def sweep(n: Nat, +k: U32, st: V.Gpu & Diff) -> IO(V.Gpu & Diff):
  match n:
    case 0n:
      IO.pure(V.Gpu & Diff, st)
    case 1n+p:
      (+g, d) = st
      +bg = sweep.color(k)
      do IO<V.Gpu & Diff>:
        r : V.Gpu & Array<U32> <- frame(g, [Q.image(0, 0, 256, 256, 0, 0, 256, 256, white())], bg)
        sweep(p, (k + 1 : U32), sweep.one(r, bg, d))

def swept(r: V.Gpu & Diff) -> IO(V.Gpu):
  (+g, d) = r
  Diff{+n, +w} = d
  do IO<V.Gpu>:
    check(U32.is_eq(n, 0), "texels over all 256 destination values (86 frames, 5,636,096 pixels): " ++
      U32.show(n) ++ " differ, max channel difference " ++ U32.show(w))
    return g

# Running
# -------

def diffed(~expected: U32 -> U32, r: V.Gpu & Array<U32>, name: String) -> IO(V.Gpu):
  (+g, a) = r
  do IO<V.Gpu>:
    report(compare(~expected, 65536n, Array.get(U32, a, 0), 0, Diff{0, 0}), name)
    return g

# Painting the canvas
# -------------------

# Scene B: scene A (flat.quads) with its first quad in another color.
def flat.b() -> List<&2, Q.Quad>:
  [Q.fill(10, 10, 100, 60, 65535),
   Q.clipped(Q.fill(0, 0, 256, 256, 16711808), 40, 20, 200, 90),
   Q.fill(4294967286, 200, 30, 30, 65535),
   Q.clipped(Q.fill(120, 120, 120, 120, 2155905152), 0, 0, 180, 256)]

def flat.b.expected(at: U32) -> U32:
  +i = at
  +x = (i % 256 : U32)
  +y = (i / 256 : U32)
  +c0 = background()
  +c1 = layer(inside(x, y, 10, 10, 110, 70), 65535, c0)
  +c2 = layer(inside(x, y, 40, 20, 200, 90), 16711808, c1)
  +c3 = layer(inside(x, y, 0, 200, 20, 230), 65535, c2)
  layer(inside(x, y, 120, 120, 180, 240), 2155905152, c3)

# Scene A on a 128x96 target.
def small.expected(at: U32) -> U32:
  +i = at
  flat.expected(((i % 128 : U32) + (i / 128 : U32) * 256 : U32))

def painted.words(+g: V.Gpu, ws: Array<U32> & U32, ranges: List<&2, C.Range>, +whole: Bool,
  rs: List<&2, V.Region>) -> IO(V.Gpu & Array<U32>):
  (a, +n) = ws
  do IO<V.Gpu & Array<U32>>:
    +g1 : V.Gpu <- V.paint(g, a, n, background(), ranges, whole, rs)
    V.read(g1)

def painted(+g: V.Gpu, +qs: List<&2, Q.Quad>, ranges: List<&2, C.Range>, +whole: Bool) ->
  IO(V.Gpu & Array<U32>):
  painted.words(g, Q.words(qs), ranges, whole, Nil{})

# A 16x16 texture region of one color, uploaded inside a partial paint and
# drawn there by an image quad at (40, 40) over scene B.
def stamp_color() -> U32:
  2864434431

def stamp.texels(n: Nat) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      stamp_color() <> stamp.texels(p)

def uploaded.expected(at: U32) -> U32:
  +i = at
  Bool.pick(U32, inside((i % 256 : U32), (i / 256 : U32), 40, 40, 56, 56), stamp_color(), flat.b.expected(i))

def painted.with(+g: V.Gpu, +qs: List<&2, Q.Quad>, ranges: List<&2, C.Range>, +whole: Bool,
  rs: List<&2, V.Region>) -> IO(V.Gpu & Array<U32>):
  painted.words(g, Q.words(qs), ranges, whole, rs)

def stored.of(+g: V.Gpu, ws: Array<U32> & U32) -> IO(V.Gpu & U32):
  (a, +n) = ws
  V.store(g, a, n)

# Quads written to the store once, then drawn from it by later paints.
def stored(+g: V.Gpu, +qs: List<&2, Q.Quad>) -> IO(V.Gpu & U32):
  stored.of(g, Q.words(qs))

def stored.paint(r: V.Gpu & U32, +bg: List<&2, Q.Quad>, +x: U32, +y: U32, +w: U32, +h: U32,
  +whole: Bool) -> IO(V.Gpu & Array<U32>):
  (+g, +first) = r
  +n = U32.from_nat(List.length(&2, Q.Quad, bg))
  painted(g, bg, [C.Spans{x, y, w, h, List.append(&2, C.Run, Bool.pick(List<&2, C.Run>, U32.is_eq(n, 0), [],
    [C.Run{False{}, 0, n}]), [C.Run{True{}, first, 4}])}], whole)

# The store: scene A stored and painted whole from it, then B stored after
# it and painted over the changed box with a background quad from the
# frame's buffer; each equals the frame drawn whole.
def store(+g0: V.Gpu) -> IO(V.Gpu):
  do IO<V.Gpu>:
    +g1 : V.Gpu <- V.store_restart(g0, 8)
    check(V.store_room(g1, 4096) && Bool.not(V.store_room(g1, 4097)), "store: room after a restart")
    sa : V.Gpu & U32 <- stored(g1, flat.quads())
    r1 : V.Gpu & Array<U32> <- stored.paint(sa, [], 0, 0, 256, 256, True{})
    +g2 : V.Gpu <- diffed(~flat.expected, r1, "store: a whole paint of stored quads equals the drawn frame")
    sb : V.Gpu & U32 <- stored(g2, flat.b())
    r2 : V.Gpu & Array<U32> <- stored.paint(sb, [Q.fill(10, 10, 100, 60, background())], 10, 10, 100, 60, False{})
    +g3 : V.Gpu <- diffed(~flat.b.expected, r2,
      "store: stored quads redrawing a box over the kept picture equal the new frame drawn whole")
    check(U32.is_eq(V.stored(g3), 8), "store: quads are appended")
    +g4 : V.Gpu <- V.store_restart(g3, 8)
    check(U32.is_eq(V.stored(g4), 0) && U32.is_eq(V.store_generation(g4), 2), "store: a restart empties it")
    return g4

def report.of(d: Diff, +total: U32, name: String) -> IO(Unit):
  Diff{+n, +w} = d
  check(U32.is_eq(n, 0), name ++ ": " ++ U32.show(n) ++ " of " ++ U32.show(total) ++
    " pixels differ, max channel difference " ++ U32.show(w))

def diffed.of(~expected: U32 -> U32, r: V.Gpu & Array<U32>, +n: Nat, name: String) -> IO(V.Gpu):
  (+g, a) = r
  do IO<V.Gpu>:
    report.of(compare(~expected, n, Array.get(U32, a, 0), 0, Diff{0, 0}), U32.from_nat(n), name)
    return g

# Scene A painted whole, then B painted only where it differs (the first
# quad's box: the background, then every quad of B, scissored), then
# nothing at all: each readback must equal B drawn whole. Last, a new size.
def canvas(+g0: V.Gpu) -> IO(V.Gpu):
  do IO<V.Gpu>:
    r1 : V.Gpu & Array<U32> <- painted(g0, flat.quads(), [C.Range{0, 0, 256, 256, 0, 4}], True{})
    +g1 : V.Gpu <- diffed(~flat.expected, r1, "paint: a whole paint equals the drawn frame")
    check(V.kept(g1), "paint: the canvas keeps the painted picture")
    r2 : V.Gpu & Array<U32> <- painted(g1, Q.fill(10, 10, 100, 60, background()) <> flat.b(),
      [C.Range{10, 10, 100, 60, 0, 5}], False{})
    +g2 : V.Gpu <- diffed(~flat.b.expected, r2,
      "paint: redrawing only the changed box over the kept picture equals the new frame drawn whole")
    r3 : V.Gpu & Array<U32> <- painted(g2, [], [], False{})
    +g3a : V.Gpu <- diffed(~flat.b.expected, r3, "paint: with nothing to redraw the picture stays")
    r3b : V.Gpu & Array<U32> <- painted.with(g3a, [Q.fill(40, 40, 16, 16, background()),
      Q.image(40, 40, 16, 16, 0, 0, 16, 16, white())], [C.Range{40, 40, 16, 16, 0, 2}], False{},
      [V.Region{0, 0, 16, 16, stamp.texels(256n)}])
    +g3b : V.Gpu <- diffed(~uploaded.expected, r3b,
      "paint: a texture region uploaded inside a partial paint is drawn by that paint")
    +g3 : V.Gpu <- store(g3b)
    +g4 : V.Gpu <- V.resize(g3, 128, 96)
    check(Bool.not(V.kept(g4)), "resize: an offscreen target made again at a new size holds no picture")
    r4 : V.Gpu & Array<U32> <- painted(g4, flat.quads(), [C.Range{0, 0, 128, 96, 0, 4}], True{})
    diffed.of(~small.expected, r4, 12288n, "resize: a whole paint at 128x96")

def run(+g0: V.Gpu) -> IO(V.Gpu):
  do IO<V.Gpu>:
    r1 : V.Gpu & Array<U32> <- frame(g0, flat.quads(), background())
    +g1 : V.Gpu <- diffed(~flat.expected, r1, "flat quads, clips, translucency, negative x")
    +g2 : V.Gpu <- V.upload(g1, 256, 256, texels())
    r2 : V.Gpu & Array<U32> <- frame(g2, [Q.image(0, 0, 256, 256, 0, 0, 256, 256, white())], bg_a())
    +g3 : V.Gpu <- diffed(~image.a, r2, "texels: every source value at every alpha over a dark color")
    r3 : V.Gpu & Array<U32> <- frame(g3, [Q.image(0, 0, 256, 256, 0, 0, 256, 256, white())], bg_b())
    +g4 : V.Gpu <- diffed(~image.b, r3, "texels over a mid color")
    r4 : V.Gpu & Array<U32> <- frame(g4, [Q.image(0, 0, 256, 256, 0, 0, 256, 256, ink_tint())], bg_c())
    +g5 : V.Gpu <- diffed(~image.c, r4, "tinted texels over white")
    r5 : V.Gpu & Array<U32> <- frame(g5, mask.quads(256n, 0), bg_b())
    +g6 : V.Gpu <- diffed(~mask.expected, r5, "coverage: every coverage at every ink alpha")
    r6 : V.Gpu & Array<U32> <- frame(g6, round.quads(), bg_a())
    +g7 : V.Gpu <- diffed(~round.expected, r6, "rounded boxes and rings, 4x4 samples")
    r7 : V.Gpu & Diff <- sweep(86n, 0, (g7, Diff{0, 0}))
    +g8 : V.Gpu <- swept(r7)
    canvas(g8)

def main() -> IO(Unit):
  do IO<Unit>:
    +g : V.Gpu <- V.open_offscreen(size(), size())
    IO.print(V.describe(g))
    +g1 : V.Gpu <- run(g)
    +report : V.Report <- V.close(g1)
    IO.print(V.report.show(report))
