import Base
import ./vk.bend as Vk

# Command recording, decided in Bend. A frame is a list of `Cmd`; `encode`
# turns it into the op words that the bridge's vk_record translates one to
# one into vkCmd* calls. Layout transitions and their pipeline stages are
# chosen here (see `to_render`, `to_present`, `upload`); `valid` checks the
# structural rules before anything reaches the driver.

type Cmd is Data:
  Barrier{image: U32, old: U32, new: U32, src_stage: U32, dst_stage: U32,
    src_access: U32, dst_access: U32}
  Render{view: U32, width: U32, height: U32, load: U32, clear: U32}
  EndRender{}
  Viewport{x: U32, y: U32, width: U32, height: U32}
  Scissor{x: U32, y: U32, width: U32, height: U32}
  Pipeline{pipeline: U32}
  Set{layout: U32, set: U32}
  Push{layout: U32, stages: U32, words: List<&2, U32>}
  Vertices{binding: U32, buffer: U32, offset: U32}
  Draw{vertices: U32, instances: U32, first_vertex: U32, first_instance: U32}
  Copy{buffer: U32, image: U32, width: U32, height: U32, offset: U32}
  Region{buffer: U32, image: U32, x: U32, y: U32, width: U32, height: U32, offset: U32}
  Readback{image: U32, buffer: U32, width: U32, height: U32, offset: U32}
  Memory{src_stage: U32, dst_stage: U32, src_access: U32, dst_access: U32}
  CopyImage{src: U32, dst: U32, x: U32, y: U32, width: U32, height: U32}

def op(c: Cmd, rest: List<&2, U32>) -> List<&2, U32>:
  match c:
    case Barrier{i, o, n, ss, ds, sa, da}:
      1 <> i <> o <> n <> ss <> ds <> sa <> da <> rest
    case Render{v, w, h, l, k}:
      2 <> v <> w <> h <> l <> k <> rest
    case EndRender{}:
      3 <> rest
    case Viewport{x, y, w, h}:
      4 <> x <> y <> w <> h <> rest
    case Scissor{x, y, w, h}:
      5 <> x <> y <> w <> h <> rest
    case Pipeline{p}:
      6 <> p <> rest
    case Set{l, s}:
      7 <> l <> s <> rest
    case Push{l, s, +ws}:
      8 <> l <> s <> U32.from_nat(List.length(&2, U32, ws)) <> List.append(&2, U32, ws, rest)
    case Vertices{b, buf, off}:
      9 <> b <> buf <> off <> rest
    case Draw{v, i, fv, fi}:
      10 <> v <> i <> fv <> fi <> rest
    case Copy{b, i, w, h, off}:
      11 <> b <> i <> w <> h <> off <> rest
    case Region{b, i, x, y, w, h, off}:
      12 <> b <> i <> x <> y <> w <> h <> off <> rest
    case Readback{i, b, w, h, off}:
      13 <> i <> b <> w <> h <> off <> rest
    case Memory{ss, ds, sa, da}:
      14 <> ss <> ds <> sa <> da <> rest
    case CopyImage{s, d, x, y, w, h}:
      15 <> s <> d <> x <> y <> w <> h <> rest

def encode(cs: List<&2, Cmd>) -> List<&2, U32>:
  match cs:
    case Nil{}:
      Nil{}
    case Con{c, rest}:
      op(c, encode(rest))

# Structural rules: draws and dynamic state only inside a render scope,
# barriers and copies only outside (region copies not empty), scopes not
# nested and always closed,
# at most 32 push-constant words, a pipeline bound before drawing.
def valid.go(cs: List<&2, Cmd>, inside: Bool, +bound: Bool) -> Bool:
  match cs inside:
    case Nil{} _:
      Bool.not(inside)
    case Con{Render{v, w, h, l, c}, rest} False{}:
      U32.is_gt(w, 0) && U32.is_gt(h, 0) && valid.go(rest, True{}, False{})
    case Con{EndRender{}, rest} True{}:
      valid.go(rest, False{}, False{})
    case Con{Barrier{i, o, n, ss, ds, sa, da}, rest} False{}:
      valid.go(rest, False{}, bound)
    case Con{Copy{b, i, w, h, off}, rest} False{}:
      valid.go(rest, False{}, bound)
    case Con{Region{b, i, x, y, w, h, off}, rest} False{}:
      U32.is_gt(w, 0) && U32.is_gt(h, 0) && valid.go(rest, False{}, bound)
    case Con{Readback{i, b, w, h, off}, rest} False{}:
      valid.go(rest, False{}, bound)
    case Con{Memory{ss, ds, sa, da}, rest} False{}:
      valid.go(rest, False{}, bound)
    case Con{CopyImage{s, d, x, y, w, h}, rest} False{}:
      U32.is_gt(w, 0) && U32.is_gt(h, 0) && valid.go(rest, False{}, bound)
    case Con{Pipeline{p}, rest} True{}:
      valid.go(rest, True{}, True{})
    case Con{Draw{v, i, fv, fi}, rest} True{}:
      bound && valid.go(rest, True{}, bound)
    case Con{Push{l, s, ws}, rest} True{}:
      U32.is_le(U32.from_nat(List.length(&2, U32, ws)), 32) && valid.go(rest, True{}, bound)
    case Con{Viewport{x, y, w, h}, rest} True{}:
      valid.go(rest, True{}, bound)
    case Con{Scissor{x, y, w, h}, rest} True{}:
      valid.go(rest, True{}, bound)
    case Con{Set{l, s}, rest} True{}:
      valid.go(rest, True{}, bound)
    case Con{Vertices{b, buf, off}, rest} True{}:
      valid.go(rest, True{}, bound)
    case _ _:
      False{}

def valid(cs: List<&2, Cmd>) -> Bool:
  valid.go(cs, False{}, False{})

# Sync policy for a swapchain image: its acquire semaphore is waited at the
# color-output stage, so the transition starts there; the contents are
# discarded (UNDEFINED) because every frame clears the whole target.
def to_render(image: U32) -> Cmd:
  Barrier{image, Vk.layout_undefined(), Vk.layout_color_attachment(),
    Vk.stage_color_output(), Vk.stage_color_output(), Vk.access_none(),
    Vk.access_color_write()}

def to_present(image: U32) -> Cmd:
  Barrier{image, Vk.layout_color_attachment(), Vk.layout_present(),
    Vk.stage_color_output(), Vk.stage_bottom(), Vk.access_color_write(),
    Vk.access_none()}

# An offscreen target ends its frame ready to be copied out.
def to_readback(image: U32) -> Cmd:
  Barrier{image, Vk.layout_color_attachment(), Vk.layout_transfer_src(),
    Vk.stage_color_output(), Vk.stage_transfer(), Vk.access_color_write(),
    Vk.access_transfer_read()}

def finish(present: Bool, image: U32) -> Cmd:
  match present:
    case True{}:
      to_present(image)
    case False{}:
      to_readback(image)

# A texture's first layout: readable by fragment shaders, contents
# undefined until a region is uploaded.
def texture_init(image: U32) -> List<&2, Cmd>:
  [Barrier{image, Vk.layout_undefined(), Vk.layout_shader_read(),
     Vk.stage_top(), Vk.stage_fragment_shader(), Vk.access_none(),
     Vk.access_shader_read()}]

type Patch is Data:
  Patch{x: U32, y: U32, width: U32, height: U32, offset: U32}

def regions(+image: U32, +buffer: U32, ps: List<&2, Patch>, tail: List<&2, Cmd>) -> List<&2, Cmd>:
  match ps:
    case Nil{}:
      tail
    case Con{Patch{x, y, w, h, off}, rest}:
      Region{buffer, image, x, y, w, h, off} <> regions(image, buffer, rest, tail)

# Rectangles of a texture replaced from a staging buffer (rows tightly
# packed, each patch at its byte offset); the rest of the texture is kept.
# Frames that sampled it finished before (uploads wait for the device).
def patch(+image: U32, +buffer: U32, ps: List<&2, Patch>) -> List<&2, Cmd>:
  Barrier{image, Vk.layout_shader_read(), Vk.layout_transfer_dst(),
    Vk.stage_fragment_shader(), Vk.stage_transfer(), Vk.access_shader_read(),
    Vk.access_transfer_write()} <>
  regions(image, buffer, ps,
    [Barrier{image, Vk.layout_transfer_dst(), Vk.layout_shader_read(),
      Vk.stage_transfer(), Vk.stage_fragment_shader(),
      Vk.access_transfer_write(), Vk.access_shader_read()}])

# Copies an offscreen target (already in TRANSFER_SRC, see to_readback)
# into a host-visible buffer and makes the bytes visible to the host.
def readback(+image: U32, +buffer: U32, +width: U32, +height: U32) -> List<&2, Cmd>:
  [Readback{image, buffer, width, height, 0},
   Memory{Vk.stage_transfer(), Vk.stage_host(), Vk.access_transfer_write(),
     Vk.access_host_read()}]

# A whole-image upload from a staging buffer, ending readable by fragment
# shaders. The previous contents are discarded.
def upload(+image: U32, buffer: U32, width: U32, height: U32) -> List<&2, Cmd>:
  [Barrier{image, Vk.layout_undefined(), Vk.layout_transfer_dst(),
     Vk.stage_top(), Vk.stage_transfer(), Vk.access_none(),
     Vk.access_transfer_write()},
   Copy{buffer, image, width, height, 0},
   Barrier{image, Vk.layout_transfer_dst(), Vk.layout_shader_read(),
     Vk.stage_transfer(), Vk.stage_fragment_shader(),
     Vk.access_transfer_write(), Vk.access_shader_read()}]

# One frame of instanced quads into a swapchain image or offscreen target.
# `present` False ends the frame ready for a readback instead.
type Pass is Data:
  Pass{image: U32, view: U32, width: U32, height: U32, clear: U32,
    pipeline: U32, layout: U32, set: U32, instances: U32, quads: U32,
    texture_width: U32, texture_height: U32, present: Bool}

def frame(p: Pass) -> List<&2, Cmd>:
  Pass{+image, view, +w, +h, clear, pipeline, +layout, set, buffer, quads, tw, th, present} = p
  [to_render(image),
   Render{view, w, h, Vk.load_clear(), clear},
   Viewport{0, 0, w, h},
   Scissor{0, 0, w, h},
   Pipeline{pipeline},
   Set{layout, set},
   Push{layout, Vk.shader_vertex(), [w, h, tw, th]},
   Vertices{0, buffer, 0},
   Draw{6, quads, 0, 0},
   EndRender{},
   finish(present, image)]

# Painting a retained canvas
# --------------------------

# A rectangle of the target to redraw and the quads that redraw it: the
# instances [first, first + count) of the frame's buffer, drawn with the
# scissor set to the rectangle, so nothing outside it changes.
type Range is Data:
  Range{x: U32, y: U32, width: U32, height: U32, first: U32, count: U32}

# A frame painted on a canvas: an image that keeps its picture from one
# frame to the next. `whole` clears the canvas to `clear` before the ranges
# are drawn (a first frame, a new size, a lost picture); otherwise the
# canvas is loaded as the last frame left it and only the ranges'
# rectangles change. A swapchain frame then copies the canvas into the
# acquired `image` and presents it; an offscreen canvas (`present` False,
# `image` unused) ends ready for a readback, as `frame` leaves it.
type Paint is Data:
  Paint{canvas: U32, view: U32, image: U32, width: U32, height: U32, clear: U32,
    pipeline: U32, layout: U32, set: U32, instances: U32, texture_width: U32,
    texture_height: U32, ranges: List<&2, Range>, whole: Bool, present: Bool}

def ranges(rs: List<&2, Range>, tail: List<&2, Cmd>) -> List<&2, Cmd>:
  match rs:
    case Nil{}:
      tail
    case Con{Range{x, y, w, h, first, count}, rest}:
      Scissor{x, y, w, h} <> Draw{6, count, 0, first} <> ranges(rest, tail)

# Every frame ends with the canvas in the transfer-source layout (copied
# into the swapchain image, or read back), so a kept picture is loaded from
# there; a cleared one is discarded. The previous frame's copy out of the
# canvas finishes before anything is drawn into it.
def canvas.open(+whole: Bool, +canvas: U32) -> Cmd:
  Barrier{canvas, Bool.pick(U32, whole, Vk.layout_undefined(), Vk.layout_transfer_src()),
    Vk.layout_color_attachment(), Vk.stage_transfer(), Vk.stage_color_output(),
    Vk.access_none(), (Vk.access_color_read() .|. Vk.access_color_write() : U32)}

def canvas.close(+canvas: U32) -> Cmd:
  Barrier{canvas, Vk.layout_color_attachment(), Vk.layout_transfer_src(),
    Vk.stage_color_output(), Vk.stage_transfer(), Vk.access_color_write(),
    Vk.access_transfer_read()}

# The acquired image receives the whole canvas and goes to presentation.
# Its acquire semaphore is waited at the transfer stage (see gpu.bend).
def shown(present: Bool, +canvas: U32, +image: U32, +w: U32, +h: U32) -> List<&2, Cmd>:
  match present:
    case False{}:
      Nil{}
    case True{}:
      [Barrier{image, Vk.layout_undefined(), Vk.layout_transfer_dst(), Vk.stage_transfer(),
         Vk.stage_transfer(), Vk.access_none(), Vk.access_transfer_write()},
       CopyImage{canvas, image, 0, 0, w, h},
       Barrier{image, Vk.layout_transfer_dst(), Vk.layout_present(), Vk.stage_transfer(),
         Vk.stage_bottom(), Vk.access_transfer_write(), Vk.access_none()}]

# Nothing to redraw on a kept canvas: no render scope at all.
def painted(draws: Bool, p: Paint, tail: List<&2, Cmd>) -> List<&2, Cmd>:
  match draws:
    case False{}:
      tail
    case True{}:
      Paint{+canvas, view, image, +w, +h, clear, pipeline, +layout, set, buffer, tw, th, rs, +whole,
        present} = p
      canvas.open(whole, canvas) <>
      Render{view, w, h, Bool.pick(U32, whole, Vk.load_clear(), Vk.load_load()), clear} <>
      Viewport{0, 0, w, h} <>
      Pipeline{pipeline} <>
      Set{layout, set} <>
      Push{layout, Vk.shader_vertex(), [w, h, tw, th]} <>
      Vertices{0, buffer, 0} <>
      ranges(rs, EndRender{} <> canvas.close(canvas) <> tail)

def has_ranges(rs: List<&2, Range>) -> Bool:
  match rs:
    case Nil{}:
      False{}
    case Con{r, rest}:
      True{}

def paint(+p: Paint) -> List<&2, Cmd>:
  Paint{+canvas, view, +image, +w, +h, clear, pipeline, layout, set, buffer, tw, th, +rs, +whole,
    present} = p
  painted(whole || has_ranges(rs), p, shown(present, canvas, image, w, h))
