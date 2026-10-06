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
