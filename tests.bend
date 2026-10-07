import Base
import ./vk.bend as Vk
import ./words.bend as W
import ./policy.bend as P
import ./commands.bend as C
import ./quads.bend as Q
import ./gpu.bend as V
import ./atlas.bend as At
import ./shaders/spirv.bend as S

# Native checks of Voltra's Bend-side logic: word handling, device and
# presentation policies, command encoding and validation, quad packing,
# quadtree conversion, atlas packing, readback conversion and slot
# tracking. They need no display and no GPU; the GPU path itself is checked
# by gpu_tests.bend (offscreen, against CPU references) and the examples.

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
    case Some{g}:
      P.gpu.index(g)

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
  C.Pass{11, 12, 800, 600, 255, 13, 14, 15, 16, 3, 64, 64, True{}}

def offscreen_pass() -> C.Pass:
  C.Pass{11, 12, 800, 600, 255, 13, 14, 15, 16, 3, 64, 64, False{}}

def last_layout(cs: List<&2, C.Cmd>, +found: U32) -> U32:
  match cs:
    case Nil{}:
      found
    case Con{C.Barrier{i, o, n, ss, ds, sa, da}, rest}:
      last_layout(rest, n)
    case Con{c, rest}:
      last_layout(rest, found)

def entry_words(r: At.Atlas & Maybe<&2, At.Entry>) -> List<&2, U32>:
  (a, m) = r
  match m:
    case None{}:
      []
    case Some{At.Entry{k, x, y, w, h}}:
      [k, x, y, w, h]

def atlas_of(r: At.Atlas & Maybe<&2, At.Entry>) -> At.Atlas:
  (a, m) = r
  a

def three() -> At.Atlas:
  atlas_of(At.place(atlas_of(At.place(atlas_of(At.place(At.new(64, 32), 1, 10, 12)), 2, 20, 12)), 3, 8, 20))

def found_words(m: Maybe<&2, At.Entry>) -> List<&2, U32>:
  match m:
    case None{}:
      []
    case Some{At.Entry{k, x, y, w, h}}:
      [k, x, y, w, h]

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

def frame_ids(fs: List<&2, V.Frame>) -> List<&2, U32>:
  match fs:
    case Nil{}:
      Nil{}
    case Con{V.Frame{c, f, a, b, q}, rest}:
      c <> frame_ids(rest)

def frames3() -> List<&2, V.Frame>:
  [V.Frame{1, 0, 0, V.Buffer{0, 0, 0}, 0}, V.Frame{2, 0, 0, V.Buffer{0, 0, 0}, 0},
   V.Frame{3, 0, 0, V.Buffer{0, 0, 0}, 0}]

def paint_of(rs: List<&2, C.Range>, +whole: Bool, +present: Bool) -> C.Paint:
  C.Paint{21, 22, 23, 800, 600, 255, 13, 14, 15, 16, 64, 64, rs, whole, present}

def two_ranges() -> List<&2, C.Range>:
  [C.Range{10, 20, 30, 40, 0, 3}, C.Range{100, 0, 8, 8, 3, 2}]

# The load op of the first render scope (9: none).
def render_load(cs: List<&2, C.Cmd>) -> U32:
  match cs:
    case Nil{}:
      9
    case Con{C.Render{v, w, h, l, k}, rest}:
      l
    case Con{c, rest}:
      render_load(rest)

def first_old_layout(cs: List<&2, C.Cmd>) -> U32:
  match cs:
    case Nil{}:
      9
    case Con{C.Barrier{i, o, n, ss, ds, sa, da}, rest}:
      o
    case Con{c, rest}:
      first_old_layout(rest)

# Scissors and draws, in order, as [x, y, w, h] and [count, first] words.
def scissored(cs: List<&2, C.Cmd>) -> List<&2, U32>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{C.Scissor{x, y, w, h}, rest}:
      x <> y <> w <> h <> scissored(rest)
    case Con{C.Draw{v, n, fv, fi}, rest}:
      n <> fi <> scissored(rest)
    case Con{c, rest}:
      scissored(rest)

def copies(cs: List<&2, C.Cmd>) -> List<&2, U32>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{C.CopyImage{a, b, x, y, w, h}, rest}:
      a <> b <> x <> y <> w <> h <> copies(rest)
    case Con{c, rest}:
      copies(rest)

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
    check(same(W.take(S.prim_vert(), 1n), [119734787]) && same(W.take(S.prim_frag(), 1n), [119734787]),
      "shaders: embedded SPIR-V starts with the magic number")
    check(U32.is_gt(W.count(S.prim_vert()), 100) && U32.is_gt(W.count(S.prim_frag()), 500), "shaders: embedded word counts")
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
    check(Bool.not(C.valid([C.Render{1, 8, 8, 1, 0}, C.Push{1, 1, W.take(S.prim_vert(), 33n)}, C.EndRender{}])),
      "commands: more than 32 push words is rejected")
    check(same(upload_layouts(C.upload(5, 6, 8, 8)), [0, 7, 7, 5, 5, 5, 5]),
      "commands: upload goes UNDEFINED -> TRANSFER_DST -> SHADER_READ")
    # quads.bend
    check(same(Q.pack([Q.fill(1, 2, 3, 4, 5)]), [1, 2, 3, 4, 2147483648, 2147483648, 2147483647, 2147483647,
      5, 0, 0, 0, 0, 0, 0, 0]), "quads: flat quad words, unclipped")
    check(same(Q.pack([Q.image(1, 2, 3, 4, 5, 6, 7, 8, 9)]), [1, 2, 3, 4, 2147483648, 2147483648, 2147483647,
      2147483647, 9, 1, 0, 0, 5, 6, 7, 8]), "quads: textured quad words")
    check(same(W.drop(Q.pack([Q.mask(1, 2, 3, 4, 5, 6, 7)]), 8n), [7, 2, 0, 0, 5, 6, 3, 4]), "quads: coverage quad words")
    check(same(W.take(W.drop(Q.pack([Q.clipped(Q.fill(0, 0, 9, 9, 1), 2, 3, 4, 5)]), 4n), 4n), [2, 3, 4, 5]),
      "quads: clip box")
    check(same(W.take(Q.pack([Q.rounded(4294967284, 9, 17, 24, 4, 1)]), 4n), [4294967294, 1, 5, 2]),
      "quads: rounded box covers its pixels, also left of the origin")
    check(same(W.drop(Q.pack([Q.ring(0, 0, 80, 40, 16, 8, 1)]), 8n), [1, 4, 16, 8, 0, 0, 80, 40]),
      "quads: ring words")
    check(U32.is_eq(Q.floor8(4294967295), 4294967295) && U32.is_eq(Q.ceil8(4294967295), 0) &&
      U32.is_eq(Q.floor8(15), 1) && U32.is_eq(Q.ceil8(15), 2) && U32.is_eq(Q.ceil8(16), 2), "quads: signed eighths")
    check(U32.is_eq(Q.opaque(1122867), 287454207), "quads: RGB leaf to opaque RGBA8")
    check(U32.is_eq(Q.span(2, 4, 5), 3) && U32.is_eq(Q.span(6, 4, 5), 0), "quads: span clips to the surface")
    check(U32.is_eq(Q.side(960, 630), 1024) && U32.is_eq(Q.side(1, 1), 1), "quads: quadtree side")
    check(U32.is_eq((W.count(leaf_words(4, 4)) / 16 : U32), 7), "quads: one quad per visible leaf")
    check(same(W.take(leaf_words(4, 4), 9n), [0, 0, 2, 2, 2147483648, 2147483648, 2147483647, 2147483647,
      4278190335]), "quads: leaf geometry and color")
    check(U32.is_eq((W.count(leaf_words(3, 1)) / 16 : U32), 2), "quads: leaves outside the surface are dropped")
    check(same(raster_words(4, 2), [4278190335, 4278190335, 65535, 65535, 4278190335, 4278190335, 16711935, 65535]),
      "quads: raster of a quadtree, row-major RGBA8")
    check(same(raster_words(3, 1), [4278190335, 4278190335, 65535]), "quads: raster clips to width")
    # commands.bend (textures and readback)
    check(U32.is_eq(last_layout(C.frame(offscreen_pass()), 0), 6) && U32.is_eq(last_layout(C.frame(frame_pass()), 0), 1000001002),
      "commands: offscreen frames end ready for readback, swapchain frames for present")
    check(C.valid(C.patch(1, 2, [C.Patch{0, 0, 4, 4, 0}, C.Patch{4, 0, 2, 2, 64}])), "commands: a patch is valid")
    check(same(W.drop(C.encode(C.patch(1, 2, [C.Patch{3, 4, 5, 6, 64}])), 8n), [12, 2, 1, 3, 4, 5, 6, 64, 1, 1, 7, 5, 4096, 128, 4096, 32]),
      "commands: a patch keeps the texture and copies a region")
    check(Bool.not(C.valid(C.patch(1, 2, [C.Patch{0, 0, 0, 4, 0}]))), "commands: an empty region is rejected")
    check(C.valid(C.readback(1, 2, 8, 8)) && same(C.encode(C.readback(1, 2, 8, 8)), [13, 1, 2, 8, 8, 0, 14, 4096, 16384, 4096, 8192]),
      "commands: readback copies, then makes the bytes visible to the host")
    check(same(W.take(C.encode(C.texture_init(9)), 3n), [1, 9, 0]) && U32.is_eq(last_layout(C.texture_init(9), 0), 5),
      "commands: a blank texture starts readable")
    # atlas.bend
    check(same(entry_words(At.place(At.new(64, 32), 7, 10, 12)), [7, 0, 0, 10, 12]), "atlas: first entry at the origin")
    check(same(found_words(At.lookup(three(), 2)), [2, 10, 0, 20, 12]), "atlas: same-height entry shares the shelf")
    check(same(found_words(At.lookup(three(), 3)), [3, 0, 12, 8, 20]), "atlas: a taller entry opens a new shelf")
    check(same(entry_words(At.place(three(), 4, 64, 1)), []), "atlas: full atlas refuses an entry")
    check(U32.is_eq(At.count(three()), 3) && U32.is_eq(At.count(At.reset(three())), 0), "atlas: count and reset")
    # gpu.bend (pure parts)
    check(U32.is_eq(V.bgra_to_rgba(4278255360), 16711935) && U32.is_eq(V.bgra_to_rgba(4286513152), 2130706687),
      "readback: B,G,R,A bytes to 0xRRGGBBAA")
    check(maybe_is(P.graphics([4, 1, 0, 3, 1, 0]), 1) && Maybe.is_none(&2, U32, P.graphics([2, 1, 0])),
      "policy: offscreen needs only a graphics family")
    check(same(V.forget([9, 7, 5], 7), [9, 5]) && same(V.forget([9], 4), [9]), "slots: forget removes only that slot")
    check(same(frame_ids(V.rotate(frames3())), [2, 3, 1]), "frames: rotation after a present")
    check(desc_ok(V.pipeline_desc(44)), "pipeline: description has the bridge's exact length")
    # commands.bend (painting a retained canvas)
    check(same(C.encode([C.CopyImage{1, 2, 3, 4, 5, 6}]), [15, 1, 2, 3, 4, 5, 6]) &&
      Bool.not(C.valid([C.Render{1, 8, 8, 1, 0}, C.CopyImage{1, 2, 0, 0, 8, 8}, C.EndRender{}])),
      "commands: an image copy is op 15, outside render scopes")
    check(C.valid(C.paint(paint_of(two_ranges(), False{}, True{}))) &&
      U32.is_eq(render_load(C.paint(paint_of(two_ranges(), False{}, True{}))), 0) &&
      U32.is_eq(first_old_layout(C.paint(paint_of(two_ranges(), False{}, True{}))), 6) &&
      same(scissored(C.paint(paint_of(two_ranges(), False{}, True{}))), [10, 20, 30, 40, 3, 0, 100, 0, 8, 8, 2, 3]) &&
      same(copies(C.paint(paint_of(two_ranges(), False{}, True{}))), [21, 23, 0, 0, 800, 600]) &&
      U32.is_eq(last_layout(C.paint(paint_of(two_ranges(), False{}, True{})), 0), 1000001002),
      "commands: a partial paint loads the kept canvas, scissors each range, copies it out and presents")
    check(C.valid(C.paint(paint_of([C.Range{0, 0, 800, 600, 0, 5}], True{}, True{}))) &&
      U32.is_eq(render_load(C.paint(paint_of([C.Range{0, 0, 800, 600, 0, 5}], True{}, True{}))), 1) &&
      U32.is_eq(first_old_layout(C.paint(paint_of([C.Range{0, 0, 800, 600, 0, 5}], True{}, True{}))), 0),
      "commands: a whole paint clears the canvas, discarding its old picture")
    check(C.valid(C.paint(paint_of([], False{}, True{}))) &&
      U32.is_eq(render_load(C.paint(paint_of([], False{}, True{}))), 9) &&
      U32.is_eq(W.count(C.encode(C.paint(paint_of([], False{}, True{})))), 23),
      "commands: nothing to redraw: the kept canvas is only copied out and presented")
    check(C.valid(C.paint(paint_of(two_ranges(), False{}, False{}))) &&
      U32.is_eq(last_layout(C.paint(paint_of(two_ranges(), False{}, False{})), 0), 6) &&
      same(copies(C.paint(paint_of(two_ranges(), False{}, False{}))), []),
      "commands: an offscreen canvas ends ready for readback, with nothing copied")
    check(same(V.rgba_view(37), [37, 6, 5, 4, 3, 1]), "texture: 0xRRGGBBAA words read through an A,B,G,R swizzle")
    IO.print("76 Voltra checks passed (Bend-side logic; the GPU path is checked by gpu_tests.bend and the examples)")
