import Base
import ./vk.bend as Vk
import ./words.bend as W
import ./policy.bend as P
import ./commands.bend as C
import ./quads.bend as Q
import ./gpu.bend as V
import ./shaders/spirv.bend as S

# Native checks of Voltra's Bend-side logic: word handling, device and
# presentation policies, command encoding and validation, quad packing,
# quadtree conversion, event decoding and slot tracking. They need no
# display and no GPU; the GPU path itself is exercised by the examples.

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ message)
    case False{}:
      IO.die(Unit, 1, "FAIL " ++ message)

def same(xs: List<&2, U32>, ys: List<&2, U32>) -> Bool:
  match xs ys:
    case Nil{} Nil{}:
      True{}
    case Con{a, ra} Con{b, rb}:
      U32.is_eq(a, b) && same(ra, rb)
    case _ _:
      False{}

def maybe_is(m: Maybe<&2, U32>, +v: U32) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{x}:
      U32.is_eq(x, v)

def gpu_index(m: Maybe<&2, P.Gpu>) -> U32:
  match m:
    case None{}:
      99
    case Some{P.Gpu{i, k, v, d, a, dr, mi, l}}:
      i

def array_words.go(n: Nat, r: Array<U32> & U32, +i: U32) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      (a, x) = r
      x <> array_words.go(p, Array.get(U32, a, (i + 1 : U32)), (i + 1 : U32))

def array_words(n: Nat, a: Array<U32>, +i: U32) -> List<&2, U32>:
  array_words.go(n, Array.get(U32, a, i), i)

def pair_words(r: Array<U32> & U32) -> List<&2, U32>:
  (a, +n) = r
  n <> array_words(U32.to_nat(n), a, 0)

# A discrete Vulkan 1.4 GPU, an integrated 1.3 one, a discrete 1.2 one.
def gpu_words() -> List<&2, U32>:
  [3,
   1, 32902, 1, 4206592, 1, 16384, 512,
   2, 4318, 9698, 4211029, 1, 32768, 4096,
   2, 4318, 7, 4202496, 1, 16384, 8192]

def integrated_first() -> List<&2, U32>:
  [2,
   1, 32902, 1, 4206592, 1, 16384, 512,
   1, 32902, 2, 4206592, 1, 16384, 512]

# Families: compute only; graphics without present; graphics + present.
def family_words() -> List<&2, U32>:
  [2, 1, 1, 1, 4, 0, 7, 2, 1]

# Types: device local; host visible+coherent; host visible+coherent+cached.
def memory_words() -> List<&2, U32>:
  [3, 1, 0, 6, 1, 14, 1, 2, 4096, 1, 16000, 0]

def surface_words(+w: U32) -> List<&2, U32>:
  [3, 0, w, 600, 1, 1, 4096, 4096, 1, 1, 9, 31,
   3, 50, 0, 37, 0, 44, 0,
   3, 2, 1, 0]

def pair_list(p: U32 & U32) -> List<&2, U32>:
  (w, h) = p
  [w, h]

def surface_extent(s: P.Surface) -> List<&2, U32>:
  pair_list(P.extent(s, 1000, 9000))

def frame_pass() -> C.Pass:
  C.Pass{11, 12, 800, 600, 255, 13, 14, 15, 16, 3, 64, 64}

def upload_layouts(cs: List<&2, C.Cmd>) -> List<&2, U32>:
  match cs:
    case Con{C.Barrier{i, o1, n1, s1, d1, a1, b1}, Con{C.Copy{b, im, w, h, off}, Con{C.Barrier{j, o2, n2, s2, d2, a2, b2}, Nil{}}}}:
      [o1, n1, o2, n2, i, im, j]
    case _:
      []

def tree() -> Image:
  Qua{Pix{16711680}, Qua{Pix{255}, Pix{255}, Pix{65280}, Pix{255}}, Pix{0}, Pix{16777215}}

def leaf_words(+w: U32, +h: U32) -> List<&2, U32>:
  Q.pack(Q.leaves(tree(), 0, 0, 4, w, h, []))

def raster_words(+w: U32, +h: U32) -> List<&2, U32>:
  array_words(U32.to_nat((w * h : U32)), Q.raster(tree(), Array.new(U32, 4n, 0), 0, 0, 4, w, h), 0)

def size_words(m: Maybe<&2, V.Size>) -> List<&2, U32>:
  match m:
    case None{}:
      []
    case Some{V.Size{w, h}}:
      [w, h]

def input_kinds(es: List<&2, V.Input>) -> List<&2, U32>:
  match es:
    case Nil{}:
      Nil{}
    case Con{V.Closed{}, rest}:
      1 <> input_kinds(rest)
    case Con{V.Resized{w, h}, rest}:
      2 <> input_kinds(rest)
    case Con{V.Exposed{}, rest}:
      3 <> input_kinds(rest)
    case Con{V.KeyInput{k, d}, rest}:
      4 <> input_kinds(rest)
    case Con{V.ButtonInput{x, y, b, d}, rest}:
      5 <> input_kinds(rest)
    case Con{V.MotionInput{x, y}, rest}:
      6 <> input_kinds(rest)
    case Con{V.FocusInput{g}, rest}:
      7 <> input_kinds(rest)

def event_words() -> List<&2, U32>:
  [2, 640, 480, 0, 0,
   9, 1, 2, 3, 4,
   4, 65307, 1, 0, 0,
   5, 10, 20, 1, 1,
   2, 800, 600, 0, 0,
   3, 0, 0, 0, 0,
   6, 7, 8, 0, 0,
   7, 1, 0, 0, 0,
   1, 0, 0, 0, 0,
   6, 1]

def frame_ids(fs: List<&2, V.Frame>) -> List<&2, U32>:
  match fs:
    case Nil{}:
      Nil{}
    case Con{V.Frame{c, f, a, b, q}, rest}:
      c <> frame_ids(rest)

def frames3() -> List<&2, V.Frame>:
  [V.Frame{1, 0, 0, V.Buffer{0, 0, 0}, 0}, V.Frame{2, 0, 0, V.Buffer{0, 0, 0}, 0},
   V.Frame{3, 0, 0, V.Buffer{0, 0, 0}, 0}]

# The bridge accepts a pipeline description of exactly 13 + 3b + 1 + 4a words.
def desc_ok(+d: List<&2, U32>) -> Bool:
  +nb = W.at(d, 12n)
  +at = (13 + nb * 3 : U32)
  +na = W.at(d, U32.to_nat(at))
  U32.is_eq(W.count(d), (at + 1 + na * 4 : U32))

def main() -> IO(Unit):
  do IO<Unit>:
    # words.bend
    check(U32.is_eq(W.at([5, 6, 7], 2n), 7) && U32.is_eq(W.at([5], 3n), 0), "words: at, with 0 past the end")
    check(same(W.drop([1, 2, 3, 4], 2n), [3, 4]) && same(W.take([1, 2, 3], 5n), [1, 2, 3]), "words: drop and take")
    check(W.contains([4, 9, 2], 9) && Bool.not(W.contains([4, 9, 2], 3)), "words: contains")
    check(same([U32.from_nat(W.depth(0)), U32.from_nat(W.depth(1)), U32.from_nat(W.depth(2)),
      U32.from_nat(W.depth(3)), U32.from_nat(W.depth(4)), U32.from_nat(W.depth(5)),
      U32.from_nat(W.depth(604800))], [0, 0, 1, 2, 2, 3, 20]), "words: array depth fits n words")
    check(same(pair_words(W.to_array([7, 8, 9])), [3, 7, 8, 9]), "words: list to array keeps count and order")
    check(same(W.take(S.quad_vert(), 1n), [119734787]) && same(W.take(S.quad_frag(), 1n), [119734787]),
      "shaders: embedded SPIR-V starts with the magic number")
    check(U32.is_gt(W.count(S.quad_vert()), 100) && U32.is_gt(W.count(S.quad_frag()), 50), "shaders: embedded word counts")
    # policy.bend
    check(U32.is_eq(gpu_index(P.best(P.gpus(gpu_words()))), 1), "policy: prefers a discrete Vulkan 1.3+ GPU")
    check(U32.is_eq(gpu_index(P.best(P.gpus([1, 2, 4318, 7, 4202496, 1, 16384, 8192]))), 99),
      "policy: rejects a GPU below Vulkan 1.3")
    check(U32.is_eq(gpu_index(P.best(P.gpus(integrated_first()))), 0), "policy: earlier GPU wins a tie")
    check(U32.is_eq(gpu_index(P.best(P.gpus([0]))), 99), "policy: no GPU, no choice")
    check(String.eq(P.api_show(4211029), "1.4.341"), "policy: Vulkan version text")
    check(maybe_is(P.family(family_words()), 2), "policy: first family that draws and presents")
    check(Maybe.is_none(&2, U32, P.family([1, 1, 0, 7, 1, 0])), "policy: no presenting graphics family")
    check(maybe_is(P.memory(memory_words(), 7, 6), 1), "policy: first host-visible coherent type")
    check(maybe_is(P.memory(memory_words(), 5, 6), 2), "policy: memory type bits are respected")
    check(maybe_is(P.memory(memory_words(), 7, 1), 0), "policy: device-local type")
    check(Maybe.is_none(&2, U32, P.memory(memory_words(), 1, 2)), "policy: no allowed type has the flags")
    check(U32.is_eq(P.format([50, 0, 37, 0, 44, 0]), 44), "policy: prefers B8G8R8A8 UNORM")
    check(U32.is_eq(P.format([50, 0, 37, 0]), 37), "policy: then R8G8B8A8 UNORM")
    check(U32.is_eq(P.format([44, 1000104002, 50, 0]), 50), "policy: needs the sRGB-nonlinear color space")
    check(U32.is_eq(P.present_mode([0, 1, 2], True{}), 2), "policy: vsync is FIFO")
    check(U32.is_eq(P.present_mode([2, 1, 0], False{}), 0) && U32.is_eq(P.present_mode([2, 1], False{}), 1)
      && U32.is_eq(P.present_mode([2], False{}), 2), "policy: uncapped prefers IMMEDIATE, then MAILBOX")
    check(U32.is_eq(P.image_count(2, 0), 3) && U32.is_eq(P.image_count(3, 3), 3), "policy: image count within limits")
    check(same(surface_extent(P.surface(surface_words(800))), [800, 600]), "policy: surface extent wins")
    check(same(surface_extent(P.surface(surface_words(4294967295))), [1000, 4096]),
      "policy: free extent clamps the window size")
    check(U32.is_eq(P.alpha(9), 1) && U32.is_eq(P.alpha(12), 4), "policy: opaque composition, else lowest mode")
    # commands.bend
    check(same(C.encode([C.Draw{6, 2, 0, 1}, C.EndRender{}]), [10, 6, 2, 0, 1, 3]), "commands: fixed-arity encoding")
    check(same(C.encode([C.Push{4, 1, [9, 8]}]), [8, 4, 1, 2, 9, 8]), "commands: push carries its word count")
    check(U32.is_eq(W.count(C.encode(C.frame(frame_pass()))), 55), "commands: a frame encodes to 55 words")
    check(C.valid(C.frame(frame_pass())), "commands: a frame is valid")
    check(C.valid(C.upload(1, 2, 64, 64)), "commands: an upload is valid")
    check(Bool.not(C.valid([C.Draw{6, 1, 0, 0}])), "commands: draw outside a render scope is rejected")
    check(Bool.not(C.valid([C.Render{1, 8, 8, 1, 0}, C.Draw{6, 1, 0, 0}, C.EndRender{}])),
      "commands: draw before binding a pipeline is rejected")
    check(Bool.not(C.valid([C.Render{1, 8, 8, 1, 0}, C.Pipeline{2}])), "commands: unclosed render scope is rejected")
    check(Bool.not(C.valid([C.Render{1, 8, 8, 1, 0}, C.Copy{1, 2, 3, 4, 0}, C.EndRender{}])),
      "commands: copy inside a render scope is rejected")
    check(Bool.not(C.valid([C.Render{1, 0, 8, 1, 0}, C.EndRender{}])), "commands: empty render area is rejected")
    check(Bool.not(C.valid([C.Render{1, 8, 8, 1, 0}, C.Push{1, 1, W.take(S.quad_vert(), 33n)}, C.EndRender{}])),
      "commands: more than 32 push words is rejected")
    check(same(upload_layouts(C.upload(5, 6, 8, 8)), [0, 7, 7, 5, 5, 5, 5]),
      "commands: upload goes UNDEFINED -> TRANSFER_DST -> SHADER_READ")
    # quads.bend
    check(same(Q.pack([Q.fill(1, 2, 3, 4, 5)]), [1, 2, 3, 4, 0, 0, 0, 0, 5, 0]), "quads: flat quad words")
    check(same(Q.pack([Q.image(1, 2, 3, 4, 5, 6, 7, 8, 9)]), [1, 2, 3, 4, 5, 6, 7, 8, 9, 1]), "quads: textured quad words")
    check(U32.is_eq(Q.opaque(1122867), 287454207), "quads: RGB leaf to opaque RGBA8")
    check(U32.is_eq(Q.span(2, 4, 5), 3) && U32.is_eq(Q.span(6, 4, 5), 0), "quads: span clips to the surface")
    check(U32.is_eq(Q.side(960, 630), 1024) && U32.is_eq(Q.side(1, 1), 1), "quads: quadtree side")
    check(U32.is_eq((W.count(leaf_words(4, 4)) / 10 : U32), 7), "quads: one quad per visible leaf")
    check(same(W.take(leaf_words(4, 4), 10n), [0, 0, 2, 2, 0, 0, 0, 0, 4278190335, 0]), "quads: leaf geometry and color")
    check(U32.is_eq((W.count(leaf_words(3, 1)) / 10 : U32), 2), "quads: leaves outside the surface are dropped")
    check(same(raster_words(4, 2), [4278190335, 4278190335, 65535, 65535, 4278190335, 4278190335, 16711935, 65535]),
      "quads: raster of a quadtree, row-major RGBA8")
    check(same(raster_words(3, 1), [4278190335, 4278190335, 65535]), "quads: raster clips to width")
    # gpu.bend (pure parts)
    check(same(input_kinds(V.events(event_words())), [2, 4, 5, 2, 3, 6, 7, 1]),
      "events: decoded in order, unknown kinds and partial words dropped")
    check(V.closed(V.events(event_words())) && Bool.not(V.closed(V.events([2, 1, 1, 0, 0]))), "events: close detection")
    check(same(size_words(V.resized(V.events(event_words()), None{})), [800, 600]), "events: last size wins")
    check(V.exposed(V.events(event_words())), "events: expose detection")
    check(same(V.forget([9, 7, 5], 7), [9, 5]) && same(V.forget([9], 4), [9]), "slots: forget removes only that slot")
    check(same(frame_ids(V.rotate(frames3())), [2, 3, 1]), "frames: rotation after a present")
    check(desc_ok(V.pipeline_desc(44)), "pipeline: description has the bridge's exact length")
    check(same(V.rgba_view(37), [37, 6, 5, 4, 3, 1]), "texture: 0xRRGGBBAA words read through an A,B,G,R swizzle")
    IO.print("57 Voltra checks passed (Bend-side logic; the GPU path is verified by the examples)")
