import Base
import ./native.bend as N
import ./vk.bend as Vk
import ./words.bend as W
import ./policy.bend as P
import ./commands.bend as C
import ./quads.bend as Q
import ./shaders/spirv.bend as S

# Voltra's GPU context: a Vulkan device drawing instanced 2D quads (flat,
# textured, coverage masks, antialiased rounded boxes and rings; see
# quads.bend) into a swapchain for a native window that Ankra owns, or into
# an offscreen image that can be read back (`open_offscreen`, `read`).
#
# Lifetimes: every native object is a slot recorded in `reg`, newest first.
# Replacing an object (swapchain on resize, texture on size change, a buffer
# that grows) destroys the old slots and forgets them; `close` destroys
# whatever remains in that order, so children always go before their
# device, the device before the instance. The window itself is not Voltra's:
# close Voltra before closing the window. Hard failures (a Vulkan error, no
# usable GPU) end the program with the driver's message, through IO.try /
# IO.die.
#
# Sync policy: FRAMES frames in flight, each with its own command buffer,
# fence, acquire semaphore and instance buffer; one render-finished
# semaphore per swapchain image. Uploads and readbacks wait for the device
# to go idle, so they never race a frame that samples the texture.

def frames_in_flight() -> Nat:
  2n

# Quads per frame before an instance buffer grows (doubles).
def initial_quads() -> U32:
  4096

# Offscreen targets use the format swapchains get on this platform, so the
# same pipeline state and conversions apply to both.
def offscreen_format() -> U32:
  Vk.format_b8g8r8a8_unorm()

# Helpers
# -------

def need(m: Maybe<&2, U32>, why: String) -> IO(U32):
  match m:
    case None{}:
      IO.die(U32, 1, "Voltra: " ++ why)
    case Some{x}:
      IO.pure(U32, x)

def need_gpu(m: Maybe<&2, P.Gpu>) -> IO(P.Gpu):
  match m:
    case None{}:
      IO.die(P.Gpu, 1, "Voltra: no Vulkan 1.3 GPU found")
    case Some{g}:
      IO.pure(P.Gpu, g)

# Unwraps a bridge answer that handed an array back; the array is dropped.
def settle(-A: Data, r: Array<U32> & Result<&1, &1, U32 & String, A>) -> IO(A):
  (a, res) = r
  IO.pass(A, res)

def forget.keep(hit: Bool, +k: U32, rest: List<&2, U32>) -> List<&2, U32>:
  match hit:
    case True{}:
      rest
    case False{}:
      k <> rest

def forget(reg: List<&2, U32>, +slot: U32) -> List<&2, U32>:
  match reg:
    case Nil{}:
      Nil{}
    case Con{s, rest}:
      +k = s
      forget.keep(U32.is_eq(k, slot), k, forget(rest, slot))

# Destroys slots in list order and removes them from the registry.
def release(slots: List<&2, U32>, reg: List<&2, U32>) -> IO(List<&2, U32>):
  match slots:
    case Nil{}:
      IO.pure(List<&2, U32>, reg)
    case Con{s, rest}:
      +k = s
      do IO<List<&2, U32>>:
        IO.try(Unit, N.destroy(k))
        release(rest, forget(reg, k))

def drop_none(slots: List<&2, U32>) -> List<&2, U32>:
  List.filter(~U32, ~(x => U32.is_ne(x, 0)), slots)

# Buffers and images
# ------------------

type Buffer is Data:
  Buffer{buffer: U32, memory: U32, bytes: U32}

def host_buffer.bind(+dev: U32, +types: List<&2, U32>, +bytes: U32,
  +info: List<&2, U32>, reg: List<&2, U32>) -> IO(Buffer & List<&2, U32>):
  +b = W.at(info, 0n)
  do IO<Buffer & List<&2, U32>>:
    +t : U32 <- need(P.memory(types, W.at(info, 3n),
      (Vk.mem_host_visible() .|. Vk.mem_host_coherent() : U32)),
      "no host-visible coherent memory")
    +m : U32 <- IO.try(U32, N.vk_alloc(dev, W.at(info, 1n), t))
    IO.try(Unit, N.vk_bind(dev, b, m, 0))
    IO.try(Unit, N.vk_map(dev, m))
    return (Buffer{b, m, bytes}, m <> b <> reg)

# A buffer in host-visible, coherent memory, mapped for its whole life.
def host_buffer(+dev: U32, +types: List<&2, U32>, +bytes: U32, +usage: U32,
  reg: List<&2, U32>) -> IO(Buffer & List<&2, U32>):
  do IO<Buffer & List<&2, U32>>:
    +info : List<&2, U32> <- IO.try(List<&2, U32>, N.vk_buffer(dev, bytes, usage))
    host_buffer.bind(dev, types, bytes, info, reg)

type Texture is Data:
  Texture{image: U32, memory: U32, view: U32, width: U32, height: U32}

# RGBA8 words 0xRRGGBBAA sit in memory as bytes A, B, G, R; the view's
# swizzle reorders them, so no pixel is converted on the CPU.
def rgba_view(+fmt: U32) -> List<&2, U32>:
  [fmt, Vk.swizzle_a(), Vk.swizzle_b(), Vk.swizzle_g(), Vk.swizzle_r(), Vk.aspect_color()]

def plain_view(+fmt: U32) -> List<&2, U32>:
  [fmt, Vk.swizzle_identity(), Vk.swizzle_identity(), Vk.swizzle_identity(),
    Vk.swizzle_identity(), Vk.aspect_color()]

def image.bind(+dev: U32, +types: List<&2, U32>, +w: U32, +h: U32, +view: List<&2, U32>,
  +info: List<&2, U32>, reg: List<&2, U32>) -> IO(Texture & List<&2, U32>):
  +img = W.at(info, 0n)
  do IO<Texture & List<&2, U32>>:
    +t : U32 <- need(P.memory(types, W.at(info, 3n), Vk.mem_device_local()),
      "no device-local memory for an image")
    +m : U32 <- IO.try(U32, N.vk_alloc(dev, W.at(info, 1n), t))
    IO.try(Unit, N.vk_bind(dev, img, m, 0))
    +v : U32 <- IO.try(U32, N.vk_image_view(dev, img, view))
    return (Texture{img, m, v, w, h}, v <> m <> img <> reg)

# A device-local image with its memory and view.
def image(+dev: U32, +types: List<&2, U32>, +w: U32, +h: U32, +fmt: U32, +usage: U32,
  +view: List<&2, U32>, reg: List<&2, U32>) -> IO(Texture & List<&2, U32>):
  do IO<Texture & List<&2, U32>>:
    +info : List<&2, U32> <- IO.try(List<&2, U32>, N.vk_image(dev,
      [w, h, fmt, usage, Vk.tiling_optimal()]))
    image.bind(dev, types, w, h, view, info, reg)

def texture(+dev: U32, +types: List<&2, U32>, +w: U32, +h: U32,
  reg: List<&2, U32>) -> IO(Texture & List<&2, U32>):
  image(dev, types, w, h, Vk.format_r8g8b8a8_unorm(),
    (Vk.image_transfer_dst() .|. Vk.image_sampled() : U32),
    rgba_view(Vk.format_r8g8b8a8_unorm()), reg)

# Swapchain or offscreen target
# -----------------------------

# The canvas: an image that keeps the last painted picture from one frame
# to the next (see `paint`), and whether it holds it (`kept`). Offscreen,
# the target image is its own canvas (memory 0: the target owns it). A
# swapchain gets a canvas of its own, in its format and size, copied into
# the acquired image every frame; image 0 means none (the surface cannot
# take copies), and every frame is then drawn whole into the image.
#
# `Alias` makes Canvas recursive, so the compiler passes it as one pointer
# instead of four flattened words in every Gpu (the widest record passed
# sets the frame size of every call; see `#define WL_RESW` in the generated
# C). Nothing builds an Alias; the accessors answer for the canvas it wraps.
type Canvas is Data:
  Canvas{image: U32, view: U32, memory: U32, kept: Bool}
  Alias{canvas: Canvas}

# A swapchain target has a swapchain, its images and views, one
# render-finished semaphore per image and a canvas. An offscreen target has
# swapchain 0, one image (owned, with `memory`) and no semaphores.
type Target is Data:
  Target{swapchain: U32, format: U32, width: U32, height: U32,
    images: List<&2, U32>, views: List<&2, U32>, done: List<&2, U32>, memory: U32,
    canvas: Canvas}

def no_canvas() -> Canvas:
  Canvas{0, 0, 0, False{}}

def canvas.image(c: Canvas) -> U32:
  match c:
    case Canvas{i, v, m, k}:
      i
    case Alias{inner}:
      canvas.image(inner)

def canvas.view(c: Canvas) -> U32:
  match c:
    case Canvas{i, v, m, k}:
      v
    case Alias{inner}:
      canvas.view(inner)

def canvas.memory(c: Canvas) -> U32:
  match c:
    case Canvas{i, v, m, k}:
      m
    case Alias{inner}:
      canvas.memory(inner)

def canvas.kept(c: Canvas) -> Bool:
  match c:
    case Canvas{i, v, m, k}:
      k
    case Alias{inner}:
      canvas.kept(inner)

def canvas.keeping(c: Canvas, +k: Bool) -> Canvas:
  match c:
    case Canvas{i, v, m, old}:
      Canvas{i, v, m, k}
    case Alias{inner}:
      canvas.keeping(inner, k)

def views(+dev: U32, +fmt: U32, images: List<&2, U32>) -> IO(List<&2, U32>):
  match images:
    case Nil{}:
      IO.pure(List<&2, U32>, Nil{})
    case Con{i, rest}:
      do IO<List<&2, U32>>:
        +v : U32 <- IO.try(U32, N.vk_image_view(dev, i, plain_view(fmt)))
        +vs : List<&2, U32> <- views(dev, fmt, rest)
        return v <> vs

def semaphores(n: Nat, +dev: U32) -> IO(List<&2, U32>):
  match n:
    case 0n:
      IO.pure(List<&2, U32>, Nil{})
    case 1n+p:
      do IO<List<&2, U32>>:
        +s : U32 <- IO.try(U32, N.vk_semaphore(dev))
        +ss : List<&2, U32> <- semaphores(p, dev)
        return s <> ss

def target.canvas(+sc: U32, +fmt: U32, +w: U32, +h: U32, +images: List<&2, U32>,
  +vs: List<&2, U32>, +ds: List<&2, U32>, t: Texture & List<&2, U32>) -> Target & List<&2, U32>:
  (tex, reg) = t
  Texture{img, mem, view, tw, th} = tex
  (Target{sc, fmt, w, h, images, vs, ds, 0, Canvas{img, view, mem, False{}}}, reg)

def target.drawn(copies: Bool, +sc: U32, +fmt: U32, +w: U32, +h: U32, +dev: U32,
  +types: List<&2, U32>, +images: List<&2, U32>, +vs: List<&2, U32>, +ds: List<&2, U32>,
  reg: List<&2, U32>) -> IO(Target & List<&2, U32>):
  match copies:
    case False{}:
      IO.pure(Target & List<&2, U32>, (Target{sc, fmt, w, h, images, vs, ds, 0, no_canvas()}, reg))
    case True{}:
      do IO<Target & List<&2, U32>>:
        c : Texture & List<&2, U32> <- image(dev, types, w, h, fmt,
          (Vk.image_color_attachment() .|. Vk.image_transfer_src() : U32), plain_view(fmt), reg)
        return target.canvas(sc, fmt, w, h, images, vs, ds, c)

def target.made(+copies: Bool, +sc: U32, +fmt: U32, +w: U32, +h: U32, +dev: U32,
  +types: List<&2, U32>, +images: List<&2, U32>, reg: List<&2, U32>) -> IO(Target & List<&2, U32>):
  do IO<Target & List<&2, U32>>:
    +vs : List<&2, U32> <- views(dev, fmt, images)
    +ds : List<&2, U32> <- semaphores(List.length(&2, U32, images), dev)
    target.drawn(copies, sc, fmt, w, h, dev, types, images, vs, ds,
      List.append(&2, U32, ds, List.append(&2, U32, vs,
        List.append(&2, U32, images, sc <> reg))))

def target.build(empty: Bool, +copies: Bool, +dev: U32, +types: List<&2, U32>, +surface: U32,
  +desc: List<&2, U32>, +old: U32, +fmt: U32, +w: U32, +h: U32,
  reg: List<&2, U32>) -> IO(Target & List<&2, U32>):
  match empty:
    case True{}:
      # A minimized window has no extent: no swapchain until it returns.
      IO.pure(Target & List<&2, U32>, (Target{0, fmt, 0, 0, [], [], [], 0, no_canvas()}, reg))
    case False{}:
      do IO<Target & List<&2, U32>>:
        +sc : U32 <- IO.try(U32, N.vk_swapchain(dev, surface, desc, old))
        +images : List<&2, U32> <- IO.try(List<&2, U32>, N.vk_swapchain_images(dev, sc))
        target.made(copies, sc, fmt, w, h, dev, types, images, reg)

# Swapchain images take copies from the canvas when the surface allows it.
def target.sized(+dev: U32, +types: List<&2, U32>, +surface: U32, +vsync: Bool, +old: U32,
  s: P.Surface, size: U32 & U32, reg: List<&2, U32>) -> IO(Target & List<&2, U32>):
  P.Surface{+mn, +mx, cw, ch, lw, lh, hw, hh, tr, +cur, +alpha, +us, +fs, +modes} = s
  (+w, +h) = size
  +fmt = P.format(fs)
  +copies = U32.is_ne((us .&. Vk.image_transfer_dst() : U32), 0)
  target.build(U32.is_eq(w, 0) || U32.is_eq(h, 0), copies, dev, types, surface,
    [P.image_count(mn, mx), fmt, Vk.srgb_nonlinear(), w, h,
      (Vk.image_color_attachment() .|. Bool.pick(U32, copies, Vk.image_transfer_dst(), 0) : U32),
      cur, P.alpha(alpha), P.present_mode(modes, vsync), 1], old, fmt, w, h, reg)

def target.info(+dev: U32, +types: List<&2, U32>, +surface: U32, +vsync: Bool, +old: U32,
  +info: List<&2, U32>, +ww: U32, +wh: U32, reg: List<&2, U32>) -> IO(Target & List<&2, U32>):
  +s = P.surface(info)
  target.sized(dev, types, surface, vsync, old, s, P.extent(s, ww, wh), reg)

def target(+dev: U32, +types: List<&2, U32>, +surface: U32, +vsync: Bool, +old: U32, +ww: U32,
  +wh: U32, reg: List<&2, U32>) -> IO(Target & List<&2, U32>):
  do IO<Target & List<&2, U32>>:
    +info : List<&2, U32> <- IO.try(List<&2, U32>, N.vk_surface_info(dev, surface))
    target.info(dev, types, surface, vsync, old, info, ww, wh, reg)

def offscreen.made(t: Texture & List<&2, U32>, +fmt: U32) -> Target & List<&2, U32>:
  (tex, reg) = t
  Texture{+img, mem, +view, w, h} = tex
  (Target{0, fmt, w, h, [img], [view], [], mem, Canvas{img, view, 0, False{}}}, reg)

def offscreen(+dev: U32, +types: List<&2, U32>, +w: U32, +h: U32,
  reg: List<&2, U32>) -> IO(Target & List<&2, U32>):
  do IO<Target & List<&2, U32>>:
    t : Texture & List<&2, U32> <- image(dev, types, w, h, offscreen_format(),
      (Vk.image_color_attachment() .|. Vk.image_transfer_src() : U32),
      plain_view(offscreen_format()), reg)
    return offscreen.made(t, offscreen_format())

# Frames in flight
# ----------------

# A frame's instance buffer also carries the atlas regions a `paint`
# uploads, after the instances (it is a vertex and a transfer source).
type Frame is Data:
  Frame{cmd: U32, fence: U32, acquired: U32, instances: Buffer, quads: U32}

def frame_usage() -> U32:
  (Vk.buffer_vertex() .|. Vk.buffer_transfer_src() : U32)

def instance_bytes(+quads: U32) -> U32:
  (quads * Q.stride_words() * 4 : U32)

def frame.made(+cmd: U32, +fence: U32, +acq: U32, +quads: U32,
  fs: List<&2, Frame>, r: Buffer & List<&2, U32>) -> List<&2, Frame> & List<&2, U32>:
  (b, reg) = r
  (Frame{cmd, fence, acq, b, quads} <> fs, reg)

# One more frame in flight, prepended to the accumulated frames.
def frame(+dev: U32, +types: List<&2, U32>, +pool: U32,
  acc: List<&2, Frame> & List<&2, U32>) -> IO(List<&2, Frame> & List<&2, U32>):
  (fs, reg) = acc
  do IO<List<&2, Frame> & List<&2, U32>>:
    +cmd : U32 <- IO.try(U32, N.vk_command_buffer(dev, pool))
    +fence : U32 <- IO.try(U32, N.vk_fence(dev, True{}))
    +acq : U32 <- IO.try(U32, N.vk_semaphore(dev))
    r : Buffer & List<&2, U32> <- host_buffer(dev, types,
      instance_bytes(initial_quads()), frame_usage(),
      acq <> fence <> cmd <> reg)
    return frame.made(cmd, fence, acq, initial_quads(), fs, r)

def frames(n: Nat, +dev: U32, +types: List<&2, U32>, +pool: U32,
  acc: List<&2, Frame> & List<&2, U32>) -> IO(List<&2, Frame> & List<&2, U32>):
  match n:
    case 0n:
      IO.pure(List<&2, Frame> & List<&2, U32>, acc)
    case 1n+p:
      do IO<List<&2, Frame> & List<&2, U32>>:
        next : List<&2, Frame> & List<&2, U32> <- frame(dev, types, pool, acc)
        frames(p, dev, types, pool, next)

# Context
# -------

# Objects fixed for the context's life. `surface` is 0 offscreen.
type Core is Data:
  Core{instance: U32, layer: U32, gpu: P.Gpu, name: String,
    surface: U32, device: U32, family: U32, types: List<&2, U32>,
    sampler: U32, set_layout: U32, pool: U32, set: U32, layout: U32,
    pipeline: U32, cmd_pool: U32, upload_cmd: U32, upload_fence: U32,
    vsync: Bool}

# The whole context. `pending` means the target shows stale content and the
# next `draw` must happen (resize, upload, a missed frame). `readback` is
# the host buffer offscreen frames are copied into.
type Gpu is Data:
  Gpu{core: Core, target: Target, frames: List<&2, Frame>, texture: Texture,
    staging: Buffer, readback: Buffer, reg: List<&2, U32>, width: U32,
    height: U32, pending: Bool, drawn: U32, rebuilds: U32}

# Pipeline description: one instance stream of Q.stride_words() words
# (ivec4 rect, ivec4 clip, uvec4 paint, ivec4 shape), straight-alpha
# source-over blending, no culling, triangle list.
def pipeline_desc(+fmt: U32) -> List<&2, U32>:
  [fmt, Vk.topology_triangle_list(), Vk.cull_none(), Vk.front_counter_clockwise(),
    1, Vk.blend_src_alpha(), Vk.blend_one_minus_src_alpha(), Vk.blend_add(),
    Vk.blend_one(), Vk.blend_one_minus_src_alpha(), Vk.blend_add(),
    Vk.color_write_rgba(),
    1, 0, (Q.stride_words() * 4 : U32), Vk.rate_instance(),
    4, 0, 0, Vk.format_r32g32b32a32_sint(), 0,
       1, 0, Vk.format_r32g32b32a32_sint(), 16,
       2, 0, Vk.format_r32g32b32a32_uint(), 32,
       3, 0, Vk.format_r32g32b32a32_sint(), 48]

def shader(+dev: U32, code: Array<U32> & U32) -> IO(U32):
  (a, n) = code
  do IO<U32>:
    r : Array<U32> & Result<&1, &1, U32 & String, U32> <- N.vk_shader(dev, a, n)
    settle(U32, r)

def describe(g: Gpu) -> String:
  Gpu{core, target, fs, tex, st, rb, reg, w, h, p, d, r} = g
  Core{inst, +layer, +gpu, +name, +surf, dev, +family, ty, sa, sl, po, se, la, pi, cp, uc, uf, vs} = core
  Target{sc, +fmt, +tw, +th, +images, vi, dn, mem, +c} = target
  "GPU " ++ U32.show(P.gpu.index(gpu)) ++ ": " ++ name ++ " (" ++ P.kind_name(P.gpu.kind(gpu)) ++
    ", vendor " ++ U32.show(P.gpu.vendor(gpu)) ++ ", device " ++ U32.show(P.gpu.device(gpu)) ++
    ", Vulkan " ++ P.api_show(P.gpu.api(gpu)) ++ ", " ++ U32.show(P.gpu.local_mib(gpu)) ++
    " MiB device-local, max image " ++ U32.show(P.gpu.max_image(gpu)) ++ ")\n" ++
    "queue family " ++ U32.show(family) ++ ", " ++
    Bool.pick(String, U32.is_eq(surf, 0), "offscreen ", "swapchain ") ++
    U32.show(tw) ++ "x" ++ U32.show(th) ++ ", format " ++ U32.show(fmt) ++ ", " ++
    U32.show(W.count(images)) ++ " images, " ++
    Bool.pick(String, U32.is_eq(canvas.image(c), 0), "no canvas", "retained canvas") ++ ", " ++
    U32.show(U32.from_nat(frames_in_flight())) ++ " frames in flight, validation layer " ++
    Bool.pick(String, U32.is_eq(layer, 1), "on", "off (not installed)")

# Points the descriptor set at the current texture.
def bind_texture(g: Gpu) -> IO(Gpu):
  Gpu{+core, target, fs, +texture, st, rb, reg, w, h, p, d, r} = g
  Core{inst, layer, gpu, name, surf, +dev, family, types, +sampler, sl, pool, +set, la, pi, cp, uc, uf, vs} = core
  Texture{img, mem, +view, tw, th} = texture
  do IO<Gpu>:
    IO.try(Unit, N.vk_write_image(dev, set, [0, Vk.descriptor_combined_sampler(),
      view, sampler, Vk.layout_shader_read()]))
    return Gpu{core, target, fs, texture, st, rb, reg, w, h, p, d, r}

# Accessors
# ---------

type Size is Data:
  Size{width: U32, height: U32}

def device(g: Gpu) -> U32:
  Gpu{core, t, fs, tex, st, rb, reg, w, h, p, d, r} = g
  Core{inst, layer, gpu, name, surf, dev, family, types, sa, sl, pool, set, la, pi, cp, uc, uf, vs} = core
  dev

def offscreen_target(g: Gpu) -> Bool:
  Gpu{core, t, fs, tex, st, rb, reg, w, h, p, d, r} = g
  Core{inst, layer, gpu, name, surf, dev, family, types, sa, sl, pool, set, la, pi, cp, uc, uf, vs} = core
  U32.is_eq(surf, 0)

def swapchain(g: Gpu) -> U32:
  Gpu{core, t, fs, tex, st, rb, reg, w, h, p, d, r} = g
  Target{sc, fmt, tw, th, i, v, dn, m, c} = t
  sc

# Whether there is anything to draw into: a swapchain, or an offscreen image.
def drawable(g: Gpu) -> Bool:
  Gpu{core, t, fs, tex, st, rb, reg, w, h, p, d, r} = g
  Target{sc, fmt, +tw, +th, i, v, dn, m, c} = t
  U32.is_ne(tw, 0) && U32.is_ne(th, 0)

def pending(g: Gpu) -> Bool:
  Gpu{core, t, fs, tex, st, rb, reg, w, h, p, d, r} = g
  p

def drawn(g: Gpu) -> U32:
  Gpu{core, t, fs, tex, st, rb, reg, w, h, p, d, r} = g
  d

def rebuilds(g: Gpu) -> U32:
  Gpu{core, t, fs, tex, st, rb, reg, w, h, p, d, r} = g
  r

def target_size(g: Gpu) -> Size:
  Gpu{core, t, fs, tex, st, rb, reg, w, h, p, d, r} = g
  Target{sc, fmt, tw, th, i, v, dn, m, c} = t
  Size{tw, th}

# Whether the canvas holds the last painted picture, so that `paint` may
# redraw only parts of it.
def kept(g: Gpu) -> Bool:
  Gpu{core, t, fs, tex, st, rb, reg, w, h, p, d, r} = g
  Target{sc, fmt, tw, th, i, v, dn, m, +c} = t
  canvas.kept(c) && U32.is_ne(canvas.image(c), 0)

def with_kept(g: Gpu, +k: Bool) -> Gpu:
  Gpu{core, t, fs, tex, st, rb, reg, w, h, p, d, r} = g
  Target{sc, fmt, tw, th, i, v, dn, m, c} = t
  Gpu{core, Target{sc, fmt, tw, th, i, v, dn, m, canvas.keeping(c, k)}, fs, tex, st, rb, reg, w, h,
    p, d, r}

def window_size(g: Gpu) -> Size:
  Gpu{core, t, fs, tex, st, rb, reg, w, h, p, d, r} = g
  Size{w, h}

def texture_size(g: Gpu) -> Size:
  Gpu{core, t, fs, tex, st, rb, reg, w, h, p, d, r} = g
  Texture{img, mem, view, tw, th} = tex
  Size{tw, th}

# Marks the content stale (an expose, or new application content).
def invalidate(g: Gpu) -> Gpu:
  Gpu{core, t, fs, tex, st, rb, reg, w, h, p, d, r} = g
  Gpu{core, t, fs, tex, st, rb, reg, w, h, True{}, d, r}

def first(pair: Array<U32> & U32) -> Array<U32>:
  (a, n) = pair
  a

def record(+cmd: U32, ops: Array<U32> & U32) -> IO(Unit):
  (a, n) = ops
  do IO<Unit>:
    r : Array<U32> & Result<&1, &1, U32 & String, Unit> <- N.vk_record(cmd, a, n)
    settle(Unit, r)

def checked.pick(ok: Bool, cs: List<&2, C.Cmd>) -> IO(Array<U32> & U32):
  match ok:
    case True{}:
      IO.pure(Array<U32> & U32, W.to_array(C.encode(cs)))
    case False{}:
      IO.die(Array<U32> & U32, 1, "Voltra: invalid command sequence")

def checked(+cs: List<&2, C.Cmd>) -> IO(Array<U32> & U32):
  checked.pick(C.valid(cs), cs)

# Records commands into the upload command buffer, submits them and waits.
def once(+g: Gpu, +cs: List<&2, C.Cmd>) -> IO(Unit):
  Gpu{+core, t, fs, tex, st, rb, reg, w, h, p, d, r} = g
  Core{inst, layer, gpu, name, surf, +dev, family, types, sa, sl, pool, set, la, pi, cp, +ucmd, +ufence, vs} = core
  do IO<Unit>:
    ops : Array<U32> & U32 <- checked(cs)
    record(ucmd, ops)
    IO.try(Unit, N.vk_submit(dev, ucmd, 0, 0, 0, ufence))
    +s : U32 <- IO.try(U32, N.vk_wait(dev, ufence, 10000, True{}))
    return Unit{}

# Swapchain recreation
# --------------------

def retarget.swap(core: Core, t: Target & List<&2, U32>, old: List<&2, U32>,
  fs: List<&2, Frame>, tex: Texture, st: Buffer, rb: Buffer, +w: U32, +h: U32, +d: U32,
  +r: U32) -> IO(Gpu):
  (target, reg) = t
  do IO<Gpu>:
    +reg2 : List<&2, U32> <- release(old, reg)
    return Gpu{core, target, fs, tex, st, rb, reg2, w, h, True{}, d, (r + 1 : U32)}

# Builds a swapchain for the current window size from the old one, then
# destroys the old swapchain and everything made for it (its canvas too:
# the new one does not hold a picture yet).
def retarget(g: Gpu) -> IO(Gpu):
  Gpu{+core, tg, fs, tex, st, rb, reg, +w, +h, p, d, r} = g
  Core{inst, layer, gpu, name, +surf, +dev, family, +types, sa, sl, pool, set, la, pi, cp, uc, uf, +vsync} = core
  Target{+sc, fmt, tw, th, +images, +views, +done, m, +c} = tg
  do IO<Gpu>:
    IO.try(Unit, N.vk_idle(dev))
    t : Target & List<&2, U32> <- target(dev, types, surf, vsync, sc, w, h, reg)
    retarget.swap(core, t, drop_none(canvas.view(c) <> canvas.memory(c) <> canvas.image(c) <>
      List.append(&2, U32, done,
      List.append(&2, U32, views, List.append(&2, U32, images, [sc])))),
      fs, tex, st, rb, w, h, d, r)

def reimage.made(core: Core, t: Target & List<&2, U32>, fs: List<&2, Frame>, tex: Texture,
  st: Buffer, rb: Buffer, +w: U32, +h: U32, +d: U32, +r: U32) -> Gpu:
  (target, reg) = t
  Gpu{core, target, fs, tex, st, rb, reg, w, h, True{}, d, (r + 1 : U32)}

# Makes an offscreen target again at the recorded size; its picture is lost.
def reimage(g: Gpu) -> IO(Gpu):
  Gpu{+core, tg, fs, tex, st, rb, reg, +w, +h, p, d, r} = g
  Core{inst, layer, gpu, name, surf, +dev, family, +types, sa, sl, pool, set, la, pi, cp, uc, uf, vs} = core
  Target{sc, fmt, tw, th, images, views, done, +mem, +c} = tg
  do IO<Gpu>:
    IO.try(Unit, N.vk_idle(dev))
    +reg2 : List<&2, U32> <- release([canvas.view(c), canvas.image(c), mem], reg)
    t : Target & List<&2, U32> <- offscreen(dev, types, w, h, reg2)
    return reimage.made(core, t, fs, tex, st, rb, w, h, d, r)

def resize.pick(differs: Bool, g: Gpu) -> IO(Gpu):
  match differs:
    case True{}:
      retarget(g)
    case False{}:
      IO.pure(Gpu, invalidate(g))

def resize.size(g: Gpu, +w: U32, +h: U32) -> Gpu:
  Gpu{core, t, fs, tex, st, rb, reg, ow, oh, p, d, r} = g
  Gpu{core, t, fs, tex, st, rb, reg, w, h, p, d, r}

def differs(s: Size, +w: U32, +h: U32) -> Bool:
  Size{+tw, +th} = s
  U32.is_ne(tw, w) || U32.is_ne(th, h)

def resize.image(differs: Bool, g: Gpu) -> IO(Gpu):
  match differs:
    case True{}:
      reimage(g)
    case False{}:
      IO.pure(Gpu, invalidate(g))

def resize.offscreen(off: Bool, +g: Gpu, +w: U32, +h: U32) -> IO(Gpu):
  match off:
    case True{}:
      resize.image(differs(target_size(g), w, h), resize.size(g, w, h))
    case False{}:
      resize.pick(differs(target_size(g), w, h), resize.size(g, w, h))

# Records the window's new size (from Ankra's Resized event); recreates
# the swapchain when it differs from the current one. An offscreen target
# is made again at a new size.
def resize(+g: Gpu, +w: U32, +h: U32) -> IO(Gpu):
  resize.offscreen(offscreen_target(g), g, w, h)

# Textures
# --------

def with_texture(g: Gpu, t: Texture & List<&2, U32>) -> Gpu:
  Gpu{core, target, fs, old, st, rb, r0, w, h, p, d, r} = g
  (tex, reg) = t
  Gpu{core, target, fs, tex, st, rb, reg, w, h, p, d, r}

def with_staging(g: Gpu, s: Buffer & List<&2, U32>) -> Gpu:
  Gpu{core, target, fs, tex, old, rb, r0, w, h, p, d, r} = g
  (st, reg) = s
  Gpu{core, target, fs, tex, st, rb, reg, w, h, p, d, r}

def with_readback(g: Gpu, s: Buffer & List<&2, U32>) -> Gpu:
  Gpu{core, target, fs, tex, st, old, r0, w, h, p, d, r} = g
  (rb, reg) = s
  Gpu{core, target, fs, tex, st, rb, reg, w, h, p, d, r}

def texture.new(+g: Gpu, +w: U32, +h: U32) -> IO(Gpu):
  Gpu{core, target, fs, tex, st, rb, reg, gw, gh, p, d, r} = g
  Core{inst, layer, gpu, name, surf, +dev, family, +types, sa, sl, pool, set, la, pi, cp, uc, uf, vs} = core
  Texture{+img, +mem, +view, tw, th} = tex
  do IO<Gpu>:
    +reg2 : List<&2, U32> <- release([view, img, mem], reg)
    t : Texture & List<&2, U32> <- texture(dev, types, w, h, reg2)
    bind_texture(with_texture(g, t))

def texture.ensure(same: Bool, +g: Gpu, +w: U32, +h: U32) -> IO(Gpu):
  match same:
    case True{}:
      IO.pure(Gpu, g)
    case False{}:
      texture.new(g, w, h)

def staging.ensure(enough: Bool, +g: Gpu, +bytes: U32) -> IO(Gpu):
  match enough:
    case True{}:
      IO.pure(Gpu, g)
    case False{}:
      Gpu{core, target, fs, tex, st, rb, reg, gw, gh, p, d, r} = g
      Core{inst, layer, gpu, name, surf, +dev, family, +types, sa, sl, pool, set, la, pi, cp, uc, uf, vs} = core
      Buffer{+b, +m, old} = st
      do IO<Gpu>:
        +reg2 : List<&2, U32> <- release([b, m], reg)
        s : Buffer & List<&2, U32> <- host_buffer(dev, types, bytes, Vk.buffer_transfer_src(), reg2)
        return with_staging(g, s)

def texture_is(g: Gpu, +w: U32, +h: U32) -> Bool:
  Bool.not(differs(texture_size(g), w, h))

def staging_fits(g: Gpu, +bytes: U32) -> Bool:
  Gpu{core, target, fs, tex, st, rb, reg, gw, gh, p, d, r} = g
  Buffer{b, m, +have} = st
  U32.is_ge(have, bytes)

def texture_image(g: Gpu) -> U32:
  Gpu{core, target, fs, tex, st, rb, reg, gw, gh, p, d, r} = g
  Texture{img, mem, view, tw, th} = tex
  img

def staging_slots(g: Gpu) -> List<&2, U32>:
  Gpu{core, target, fs, tex, st, rb, reg, gw, gh, p, d, r} = g
  Buffer{b, m, have} = st
  [b, m]

def write.staging(+g: Gpu, pixels: Array<U32>, +count: U32) -> IO(Unit):
  do IO<Unit>:
    wr : Array<U32> & Result<&1, &1, U32 & String, Unit> <- N.vk_write(
      W.at(staging_slots(g), 1n), 0, pixels, count)
    settle(Unit, wr)

def upload.copy(+g: Gpu, +w: U32, +h: U32, pixels: Array<U32>) -> IO(Gpu):
  do IO<Gpu>:
    write.staging(g, pixels, (w * h : U32))
    once(g, C.upload(texture_image(g), W.at(staging_slots(g), 0n), w, h))
    return invalidate(g)

# Replaces the texture with a row-major w x h RGBA8 image (0xRRGGBBAA words;
# the array may be larger). Synchronous: waits for in-flight frames first,
# then for the copy. Recreates the texture on a size change.
def upload(+g: Gpu, +w: U32, +h: U32, pixels: Array<U32>) -> IO(Gpu):
  +bytes = (w * h * 4 : U32)
  do IO<Gpu>:
    IO.try(Unit, N.vk_idle(device(g)))
    +g1 : Gpu <- texture.ensure(texture_is(g, w, h), g, w, h)
    +g2 : Gpu <- staging.ensure(staging_fits(g1, bytes), g1, bytes)
    upload.copy(g2, w, h, pixels)

# Makes a w x h texture whose contents are undefined until `update` writes
# rectangles of it -- an atlas. Recreates the texture when the size changes.
def blank(+g: Gpu, +w: U32, +h: U32) -> IO(Gpu):
  do IO<Gpu>:
    IO.try(Unit, N.vk_idle(device(g)))
    +g1 : Gpu <- texture.new(g, w, h)
    once(g1, C.texture_init(texture_image(g1)))
    return invalidate(g1)

# A rectangle of texture to replace: row-major RGBA8 words, w x h of them.
type Region is Data:
  Region{x: U32, y: U32, width: U32, height: U32, pixels: List<&2, U32>}

# Texels of the regions, and the quads they occupy after the instances.
def texels(rs: List<&2, Region>, +acc: U32) -> U32:
  match rs:
    case Nil{}:
      acc
    case Con{Region{x, y, +w, +h, px}, rest}:
      texels(rest, (acc + w * h : U32))

def texels.put(rs: List<&2, Region>, a: Array<U32>, +i: U32) -> Array<U32>:
  match rs:
    case Nil{}:
      a
    case Con{Region{x, y, +w, +h, px}, rest}:
      texels.put(rest, W.fill(px, a, i), (i + w * h : U32))

# The regions' texels, one after another, in a new array (zero padded to a
# power of two), with their count.
def region_words(+rs: List<&2, Region>) -> Array<U32> & U32:
  +n = texels(rs, 0)
  (texels.put(rs, Array.new(U32, W.depth(n), 0), 0), n)

def patches(rs: List<&2, Region>, +offset: U32) -> List<&2, C.Patch>:
  match rs:
    case Nil{}:
      Nil{}
    case Con{Region{+x, +y, +w, +h, px}, rest}:
      C.Patch{x, y, w, h, offset} <> patches(rest, (offset + w * h * 4 : U32))

def update.go(+g: Gpu, rs: List<&2, Region>, words: Array<U32> & U32) -> IO(Gpu):
  (a, +n) = words
  +bytes = U32.max((n * 4 : U32), 4)
  do IO<Gpu>:
    IO.try(Unit, N.vk_idle(device(g)))
    +g1 : Gpu <- staging.ensure(staging_fits(g, bytes), g, bytes)
    write.staging(g1, a, n)
    once(g1, C.patch(texture_image(g1), W.at(staging_slots(g1), 0n), patches(rs, 0)))
    return invalidate(g1)

def update.some(any: Bool, +g: Gpu, +rs: List<&2, Region>) -> IO(Gpu):
  match any:
    case False{}:
      IO.pure(Gpu, g)
    case True{}:
      update.go(g, rs, region_words(rs))

# Replaces rectangles of the texture in one transfer and keeps the rest.
# Synchronous, as `upload`. Rectangles must lie inside the texture.
def update(+g: Gpu, +rs: List<&2, Region>) -> IO(Gpu):
  update.some(U32.is_gt(U32.from_nat(List.length(&2, Region, rs)), 0), g, rs)

# Drawing
# -------

def with_frames(g: Gpu, fs: List<&2, Frame>, reg: List<&2, U32>) -> Gpu:
  Gpu{core, t, old, tex, st, rb, r0, w, h, p, d, r} = g
  Gpu{core, t, fs, tex, st, rb, reg, w, h, p, d, r}

def grow.made(+cmd: U32, +fence: U32, +acq: U32, +quads: U32, rest: List<&2, Frame>,
  b: Buffer & List<&2, U32>, g: Gpu) -> Gpu:
  (buf, reg) = b
  with_frames(g, Frame{cmd, fence, acq, buf, quads} <> rest, reg)

def grow.frames(fs: List<&2, Frame>, +g: Gpu, +dev: U32, +types: List<&2, U32>,
  reg: List<&2, U32>, +n: U32) -> IO(Gpu):
  match fs:
    case Nil{}:
      IO.pure(Gpu, g)
    case Con{Frame{+cmd, +fence, +acq, Buffer{+b, +m, bytes}, +cap}, rest}:
      +quads = U32.max(n, (cap * 2 : U32))
      do IO<Gpu>:
        +reg2 : List<&2, U32> <- release([b, m], reg)
        nb : Buffer & List<&2, U32> <- host_buffer(dev, types, instance_bytes(quads),
          frame_usage(), reg2)
        return grow.made(cmd, fence, acq, quads, rest, nb, g)

# Doubles the current frame's instance buffer until `n` quads fit. Called
# after that frame's fence signaled, so the old buffer is idle.
def grow(need: Bool, +g: Gpu, +n: U32) -> IO(Gpu):
  match need:
    case False{}:
      IO.pure(Gpu, g)
    case True{}:
      Gpu{core, t, fs, tex, st, rb, reg, w, h, p, d, r} = g
      Core{inst, layer, gpu, name, surf, +dev, family, +types, sa, sl, pool, set, la, pi, cp, uc, uf, vs} = core
      grow.frames(fs, g, dev, types, reg, n)

def head_capacity(fs: List<&2, Frame>) -> U32:
  match fs:
    case Nil{}:
      0
    case Con{Frame{c, f, a, b, cap}, rest}:
      cap

def rotate(fs: List<&2, Frame>) -> List<&2, Frame>:
  match fs:
    case Nil{}:
      Nil{}
    case Con{f, rest}:
      List.append(&2, Frame, rest, [f])

def presented.pick(stale: Bool, g: Gpu) -> IO(Gpu):
  match stale:
    case True{}:
      retarget(g)
    case False{}:
      IO.pure(Gpu, g)

def presented(+g: Gpu, +status: U32, +acquired: U32) -> IO(Gpu):
  # Suboptimal or out of date: rebuild now so the next frame fits.
  Gpu{core, t, fs, tex, st, rb, reg, w, h, p, d, r} = g
  presented.pick(U32.is_ne(status, 0) || U32.is_ne(acquired, 0),
    Gpu{core, t, rotate(fs), tex, st, rb, reg, w, h, False{}, (d + 1 : U32), r})

def rendered(+g: Gpu) -> Gpu:
  Gpu{core, t, fs, tex, st, rb, reg, w, h, p, d, r} = g
  Gpu{core, t, rotate(fs), tex, st, rb, reg, w, h, False{}, (d + 1 : U32), r}

# Submits the recorded frame: to the swapchain (waiting for the acquired
# image at `stage`, its first use, then presenting) or, offscreen, on its
# own.
def submit.target(off: Bool, +g: Gpu, +dev: U32, +cmd: U32, +acq: U32, +fence: U32,
  +sc: U32, +index: U32, +finished: U32, +acquired: U32, +stage: U32, rects: List<&2, U32>) -> IO(Gpu):
  match off:
    case True{}:
      do IO<Gpu>:
        IO.try(Unit, N.vk_submit(dev, cmd, 0, 0, 0, fence))
        return rendered(g)
    case False{}:
      do IO<Gpu>:
        IO.try(Unit, N.vk_submit(dev, cmd, acq, stage, finished, fence))
        +status : U32 <- IO.try(U32, N.vk_present(dev, sc, index, finished, rects))
        presented(g, status, acquired)

def draw.frame(fs: List<&2, Frame>, +g: Gpu, +dev: U32, +sc: U32, +index: U32,
  +acquired: U32, +image: U32, +view: U32, +finished: U32, +tw: U32, +th: U32,
  +clear: U32, +pipe: U32, +layout: U32, +set: U32, +xw: U32, +xh: U32,
  words: Array<U32> & U32) -> IO(Gpu):
  match fs:
    case Nil{}:
      IO.die(Gpu, 1, "Voltra: no frame in flight")
    case Con{Frame{+cmd, +fence, +acq, Buffer{+b, +m, bytes}, cap}, rest}:
      (a, +n) = words
      +off = offscreen_target(g)
      do IO<Gpu>:
        wr : Array<U32> & Result<&1, &1, U32 & String, Unit> <- N.vk_write(m, 0, a,
          (n * Q.stride_words() : U32))
        settle(Unit, wr)
        ops : Array<U32> & U32 <- checked(C.frame(C.Pass{image, view, tw, th, clear,
          pipe, layout, set, b, n, xw, xh, Bool.not(off)}))
        record(cmd, ops)
        submit.target(off, g, dev, cmd, acq, fence, sc, index, finished, acquired,
          Vk.stage_color_output(), Nil{})

# Records, submits and presents one frame into the acquired image. The
# canvas does not see this frame, so it no longer holds the picture.
def draw.submit(+g: Gpu, +index: U32, +acquired: U32, quads: List<&2, Q.Quad>,
  +clear: U32) -> IO(Gpu):
  Gpu{core, t, fs, tex, st, rb, reg, w, h, p, d, r} = g
  Core{inst, layer, gpu, name, surf, +dev, family, types, sa, sl, pool, +set, +layout, +pipe, cp, uc, uf, vs} = core
  Target{+sc, fmt, +tw, +th, +images, +views, +done, m, c} = t
  Texture{img, mem, view, +xw, +xh} = tex
  +i = U32.to_nat(index)
  draw.frame(fs, with_kept(g, False{}), dev, sc, index, acquired, W.at(images, i), W.at(views, i),
    W.at(done, i), tw, th, clear, pipe, layout, set, xw, xh, Q.words(quads))

def frame_sync(fs: List<&2, Frame>) -> List<&2, U32>:
  match fs:
    case Nil{}:
      [0, 0]
    case Con{Frame{cmd, fence, acq, b, cap}, rest}:
      [fence, acq]

def frames_of(g: Gpu) -> List<&2, Frame>:
  Gpu{core, t, fs, tex, st, rb, reg, w, h, p, d, r} = g
  fs

def draw.acquired(ok: Bool, +g: Gpu, +index: U32, +status: U32,
  +quads: List<&2, Q.Quad>, +clear: U32) -> IO(Gpu):
  match ok:
    case False{}:
      # Out of date or timed out: nothing was acquired; rebuild and retry
      # on the next draw (the content stays pending).
      retarget(g)
    case True{}:
      +n = U32.from_nat(List.length(&2, Q.Quad, quads))
      +fs = frames_of(g)
      do IO<Gpu>:
        +reset : U32 <- IO.try(U32, N.vk_wait(device(g), W.at(frame_sync(fs), 0n), 0, True{}))
        +g2 : Gpu <- grow(U32.is_gt(n, head_capacity(fs)), g, n)
        draw.submit(g2, index, status, quads, clear)

# Waits for the frame's previous use, then (on a swapchain) acquires an image.
def draw.go(off: Bool, +g: Gpu, +sync: List<&2, U32>, quads: List<&2, Q.Quad>, +clear: U32) -> IO(Gpu):
  match off:
    case True{}:
      do IO<Gpu>:
        +waited : U32 <- IO.try(U32, N.vk_wait(device(g), W.at(sync, 0n), 10000, False{}))
        draw.acquired(True{}, g, 0, 0, quads, clear)
    case False{}:
      do IO<Gpu>:
        +waited : U32 <- IO.try(U32, N.vk_wait(device(g), W.at(sync, 0n), 10000, False{}))
        +a : List<&2, U32> <- IO.try(List<&2, U32>, N.vk_acquire(device(g), swapchain(g),
          W.at(sync, 1n), 10000))
        draw.acquired(U32.is_le(W.at(a, 0n), 1), g, W.at(a, 1n), W.at(a, 0n), quads, clear)

def draw.ready(ok: Bool, +g: Gpu, quads: List<&2, Q.Quad>, +clear: U32) -> IO(Gpu):
  match ok:
    case False{}:
      # Minimized (no swapchain): nothing to draw into. The content is not
      # pending; the resize that restores the window makes it pending again.
      Gpu{core, t, fs, tex, st, rb, reg, w, h, p, d, r} = g
      IO.pure(Gpu, Gpu{core, t, fs, tex, st, rb, reg, w, h, False{}, d, r})
    case True{}:
      draw.go(offscreen_target(g), g, frame_sync(frames_of(g)), quads, clear)

# Draws quads in list order (later quads on top) over a target cleared to
# `clear` (0xRRGGBBAA), then presents it (or, offscreen, keeps it for `read`).
def draw(+g: Gpu, quads: List<&2, Q.Quad>, +clear: U32) -> IO(Gpu):
  draw.ready(drawable(g), g, quads, clear)

# Painting the canvas
# -------------------

def settled(g: Gpu) -> Gpu:
  Gpu{core, t, fs, tex, st, rb, reg, w, h, p, d, r} = g
  Gpu{core, t, fs, tex, st, rb, reg, w, h, False{}, d, r}

# Without a canvas the frame is drawn whole into the acquired image, as
# `draw` does; the acquired image is then first used at the color stage.
def paint.commands(direct: Bool, p: C.Paint, pass: C.Pass) -> List<&2, C.Cmd>:
  match direct:
    case True{}:
      C.frame(pass)
    case False{}:
      C.paint(p)

# The rectangles a partial paint changed, for the present (at most 64; past
# that, none: the hint is optional).
def rects.of(rs: List<&2, C.Range>) -> List<&2, U32>:
  match rs:
    case Nil{}:
      Nil{}
    case Con{C.Range{x, y, w, h, first, n}, rest}:
      x <> y <> w <> h <> rects.of(rest)

def rects.pick(on: Bool, +rs: List<&2, C.Range>) -> List<&2, U32>:
  match on:
    case False{}:
      Nil{}
    case True{}:
      +ws = rects.of(rs)
      Bool.pick(List<&2, U32>, U32.is_le(W.count(ws), 256), ws, Nil{})

def paint.texels.write(+m: U32, +offset: U32, ws: Array<U32> & U32) -> IO(Unit):
  (a, n) = ws
  do IO<Unit>:
    wr : Array<U32> & Result<&1, &1, U32 & String, Unit> <- N.vk_write(m, offset, a, n)
    settle(Unit, wr)

# The texels of a paint's atlas regions, written after its n quads.
def paint.texels(any: Bool, +m: U32, +offset: U32, rs: List<&2, Region>) -> IO(Unit):
  match any:
    case False{}:
      IO.pure(Unit, Unit{})
    case True{}:
      paint.texels.write(m, offset, region_words(rs))

# The regions' copies into the atlas texture, recorded before the frame's
# drawing: the texture leaves its sampled layout once earlier frames are
# done reading it (the barrier waits for their fragment stage), so no
# frame in flight sees a region change and the CPU never waits.
def paint.uploads(any: Bool, +texture: U32, +buffer: U32, rs: List<&2, Region>, +offset: U32) ->
  List<&2, C.Cmd>:
  match any:
    case False{}:
      Nil{}
    case True{}:
      C.patch(texture, buffer, patches(rs, offset))

def paint.frame(fs: List<&2, Frame>, +g: Gpu, +dev: U32, +sc: U32, +index: U32,
  +acquired: U32, +image: U32, +view: U32, +finished: U32, +canvas: U32, +cview: U32,
  +tw: U32, +th: U32, +clear: U32, +pipe: U32, +layout: U32, +set: U32, +xw: U32, +xh: U32,
  words: Array<U32>, +n: U32, +ranges: List<&2, C.Range>, +whole: Bool, +hint: Bool,
  +texture: U32, +rs: List<&2, Region>) -> IO(Gpu):
  match fs:
    case Nil{}:
      IO.die(Gpu, 1, "Voltra: no frame in flight")
    case Con{Frame{+cmd, +fence, +acq, Buffer{+b, +m, bytes}, cap}, rest}:
      +off = offscreen_target(g)
      +direct = U32.is_eq(canvas, 0)
      +any = Bool.not(List.is_empty(&2, Region, rs))
      +at = (n * Q.stride_words() * 4 : U32)
      do IO<Gpu>:
        wr : Array<U32> & Result<&1, &1, U32 & String, Unit> <- N.vk_write(m, 0, words,
          (n * Q.stride_words() : U32))
        settle(Unit, wr)
        paint.texels(any, m, at, rs)
        ops : Array<U32> & U32 <- checked(List.append(&2, C.Cmd, paint.uploads(any, texture, b, rs, at),
          paint.commands(direct,
            C.Paint{canvas, cview, image, tw, th, clear, pipe, layout, set, b, xw, xh, ranges, whole,
              Bool.not(off)},
            C.Pass{image, view, tw, th, clear, pipe, layout, set, b, n, xw, xh, Bool.not(off)})))
        record(cmd, ops)
        submit.target(off, with_kept(g, Bool.not(direct)), dev, cmd, acq, fence, sc, index,
          finished, acquired, Bool.pick(U32, direct, Vk.stage_color_output(), Vk.stage_transfer()),
          rects.pick(hint && Bool.not(whole) && Bool.not(direct), ranges))

def paint.submit(+g: Gpu, +index: U32, +acquired: U32, words: Array<U32>, +n: U32,
  +clear: U32, ranges: List<&2, C.Range>, +whole: Bool, rs: List<&2, Region>) -> IO(Gpu):
  Gpu{core, t, fs, tex, st, rb, reg, w, h, p, d, r} = g
  Core{inst, layer, gpu, name, surf, +dev, family, types, sa, sl, pool, +set, +layout, +pipe, cp, uc, uf, vs} = core
  Target{+sc, fmt, +tw, +th, +images, +views, +done, m, +c} = t
  Texture{img, mem, view, +xw, +xh} = tex
  +i = U32.to_nat(index)
  paint.frame(fs, g, dev, sc, index, acquired, W.at(images, i), W.at(views, i), W.at(done, i),
    canvas.image(c), canvas.view(c), tw, th, clear, pipe, layout, set, xw, xh, words, n, ranges, whole,
    P.gpu.regions(gpu), img, rs)

def paint.acquired(ok: Bool, +g: Gpu, +index: U32, +status: U32, words: Array<U32>, +n: U32,
  +clear: U32, ranges: List<&2, C.Range>, +whole: Bool, +rs: List<&2, Region>) -> IO(Gpu):
  match ok:
    case False{}:
      # Out of date or timed out: rebuild (the next paint is whole); the
      # atlas regions still go to the texture.
      do IO<Gpu>:
        +g1 : Gpu <- retarget(g)
        update(g1, rs)
    case True{}:
      +fs = frames_of(g)
      +need = (n + (texels(rs, 0) + Q.stride_words() - 1) / Q.stride_words() : U32)
      do IO<Gpu>:
        +reset : U32 <- IO.try(U32, N.vk_wait(device(g), W.at(frame_sync(fs), 0n), 0, True{}))
        +g2 : Gpu <- grow(U32.is_gt(need, head_capacity(fs)), g, need)
        paint.submit(g2, index, status, words, n, clear, ranges, whole, rs)

def paint.go(off: Bool, +g: Gpu, +sync: List<&2, U32>, words: Array<U32>, +n: U32, +clear: U32,
  ranges: List<&2, C.Range>, +whole: Bool, +rs: List<&2, Region>) -> IO(Gpu):
  match off:
    case True{}:
      do IO<Gpu>:
        +waited : U32 <- IO.try(U32, N.vk_wait(device(g), W.at(sync, 0n), 10000, False{}))
        paint.acquired(True{}, g, 0, 0, words, n, clear, ranges, whole, rs)
    case False{}:
      do IO<Gpu>:
        +waited : U32 <- IO.try(U32, N.vk_wait(device(g), W.at(sync, 0n), 10000, False{}))
        +a : List<&2, U32> <- IO.try(List<&2, U32>, N.vk_acquire(device(g), swapchain(g),
          W.at(sync, 1n), 10000))
        paint.acquired(U32.is_le(W.at(a, 0n), 1), g, W.at(a, 1n), W.at(a, 0n), words, n, clear,
          ranges, whole, rs)

def paint.ready(ok: Bool, fits: Bool, +g: Gpu, words: Array<U32>, +n: U32, +clear: U32,
  ranges: List<&2, C.Range>, +whole: Bool, +rs: List<&2, Region>) -> IO(Gpu):
  match ok fits:
    case False{} _:
      # Minimized (no swapchain): nothing to draw into, and the canvas no
      # longer follows the picture; the atlas regions still go to the
      # texture. Nothing is pending until a resize restores the window.
      do IO<Gpu>:
        +g1 : Gpu <- update(with_kept(g, False{}), rs)
        return settled(g1)
    case True{} False{}:
      IO.die(Gpu, 1, "Voltra: paint: a canvas without the last picture must be painted whole")
    case True{} True{}:
      paint.go(offscreen_target(g), g, frame_sync(frames_of(g)), words, n, clear, ranges, whole, rs)

# Paints a frame over the canvas, which keeps the picture between frames:
# `words` holds `n` quads as Q.put writes them (the array may be larger),
# and each range redraws its rectangle with its instances, scissored, so
# the rest of the picture stays as it was; `whole` clears the canvas to
# `clear` first (use one range over the whole target). `rs` are texture
# rectangles to replace first, as `update` does but inside this frame,
# without waiting for the device. The canvas is then copied into the
# acquired swapchain image and presented or, offscreen, kept for `read`. A
# canvas that does not hold the last painted picture (`kept` False: a new
# target or size, a frame drawn with `draw`, a lost frame) must be painted
# whole. Without a canvas every paint draws its quads whole into the
# image, in order.
def paint(+g: Gpu, words: Array<U32>, +n: U32, +clear: U32, ranges: List<&2, C.Range>,
  +whole: Bool, +rs: List<&2, Region>) -> IO(Gpu):
  paint.ready(drawable(g), whole || kept(g), g, words, n, clear, ranges, whole, rs)

# Readback
# --------

# Swapchain-format words (bytes B, G, R, A) to 0xRRGGBBAA, in place.
def bgra_to_rgba(+c: U32) -> U32:
  ((((c >> 16n) .&. 255 : U32) << 24n) .|. (((c >> 8n) .&. 255 : U32) << 16n) .|.
    ((c .&. 255 : U32) << 8n) .|. (c >> 24n) : U32)

def convert(n: Nat, r: Array<U32> & U32, +i: U32) -> Array<U32>:
  match n:
    case 0n:
      (a, c) = r
      a
    case 1n+p:
      (a, +c) = r
      +j = (i + 1 : U32)
      convert(p, Array.get(U32, Array.set(U32, a, i, bgra_to_rgba(c)), j), j)

def read.done(+g: Gpu, +n: U32, got: Array<U32> & Result<&1, &1, U32 & String, Unit>) ->
  IO(Gpu & Array<U32>):
  (a, res) = got
  do IO<Gpu & Array<U32>>:
    ok : Unit <- IO.pass(Unit, res)
    return (g, convert(U32.to_nat(n), Array.get(U32, a, 0), 0))

def read.copy(+g: Gpu, +w: U32, +h: U32) -> IO(Gpu & Array<U32>):
  Gpu{core, t, fs, tex, st, rb, reg, gw, gh, p, d, r} = g
  Target{sc, fmt, tw, th, +images, vi, dn, m, c} = t
  Buffer{+b, +mem, have} = rb
  +n = (w * h : U32)
  do IO<Gpu & Array<U32>>:
    once(g, C.readback(W.at(images, 0n), b, w, h))
    got : Array<U32> & Result<&1, &1, U32 & String, Unit> <- N.vk_read(mem, 0,
      Array.new(U32, W.depth(n), 0), n)
    read.done(g, n, got)

def readback.ensure(enough: Bool, +g: Gpu, +bytes: U32) -> IO(Gpu):
  match enough:
    case True{}:
      IO.pure(Gpu, g)
    case False{}:
      Gpu{core, target, fs, tex, st, rb, reg, gw, gh, p, d, r} = g
      Core{inst, layer, gpu, name, surf, +dev, family, +types, sa, sl, pool, set, la, pi, cp, uc, uf, vs} = core
      Buffer{+b, +m, old} = rb
      do IO<Gpu>:
        +reg2 : List<&2, U32> <- release(drop_none([b, m]), reg)
        s : Buffer & List<&2, U32> <- host_buffer(dev, types, bytes, Vk.buffer_transfer_dst(), reg2)
        return with_readback(g, s)

def readback_fits(g: Gpu, +bytes: U32) -> Bool:
  Gpu{core, target, fs, tex, st, rb, reg, gw, gh, p, d, r} = g
  Buffer{b, m, +have} = rb
  U32.is_ge(have, bytes)

def read.sized(+g: Gpu, s: Size) -> IO(Gpu & Array<U32>):
  Size{+w, +h} = s
  +bytes = (w * h * 4 : U32)
  do IO<Gpu & Array<U32>>:
    IO.try(Unit, N.vk_idle(device(g)))
    +g1 : Gpu <- readback.ensure(readback_fits(g, bytes), g, bytes)
    read.copy(g1, w, h)

def read.offscreen(off: Bool, +g: Gpu) -> IO(Gpu & Array<U32>):
  match off:
    case False{}:
      IO.die(Gpu & Array<U32>, 1, "Voltra: read needs an offscreen target")
    case True{}:
      read.sized(g, target_size(g))

# The last frame drawn offscreen, as row-major 0xRRGGBBAA words (w x h of
# them; the array may be larger). Synchronous: waits for the device.
def read(+g: Gpu) -> IO(Gpu & Array<U32>):
  read.offscreen(offscreen_target(g), g)

# Teardown
# --------

type Report is Data:
  Report{live: U32, warnings: U32, errors: U32}

def report.show(r: Report) -> String:
  Report{live, warnings, errors} = r
  "teardown: " ++ U32.show(live) ++ " native objects left; driver messages: " ++
    U32.show(warnings) ++ " warnings, " ++ U32.show(errors) ++ " errors"

def report.make(+stats: List<&2, U32>, rest: List<&2, U32>) -> Report:
  Report{(W.at(stats, 0n) + W.count(rest) : U32), W.at(stats, 1n), W.at(stats, 2n)}

# Waits for the GPU, destroys every live slot newest first, and reports how
# many slots the bridge still holds (0 when nothing leaked) and how many
# warnings and errors the Vulkan debug messenger saw during the run. Close
# Voltra before the window its surface was made from.
def close(+g: Gpu) -> IO(Report):
  Gpu{core, t, fs, tex, st, rb, +reg, w, h, p, d, r} = g
  do IO<Report>:
    IO.try(Unit, N.vk_idle(device(g)))
    rest : List<&2, U32> <- release(reg, reg)
    +stats : List<&2, U32> <- IO.try(List<&2, U32>, N.stats())
    return report.make(stats, rest)

# Opening
# -------

def pixels(pair: Array<U32> & U32) -> Array<U32>:
  (a, n) = pair
  a

def open.ready(core: Core, tg: Target, fs: List<&2, Frame>, tex: Texture, +w: U32, +h: U32,
  s: Buffer & List<&2, U32>) -> IO(Gpu):
  (st, reg) = s
  do IO<Gpu>:
    +g : Gpu <- bind_texture(Gpu{core, tg, fs, tex, st, Buffer{0, 0, 0}, reg, w, h, True{}, 0, 0})
    # A white texel, so the descriptor is valid before the first upload.
    upload(g, 1, 1, pixels(W.to_array([4294967295])))

def open.staging(core: Core, +dev: U32, +types: List<&2, U32>, +w: U32, +h: U32,
  tg: Target, fs: List<&2, Frame>, t: Texture & List<&2, U32>) -> IO(Gpu):
  (tex, reg) = t
  do IO<Gpu>:
    st : Buffer & List<&2, U32> <- host_buffer(dev, types, 4, Vk.buffer_transfer_src(), reg)
    open.ready(core, tg, fs, tex, w, h, st)

def open.texture(core: Core, +dev: U32, +types: List<&2, U32>, +w: U32, +h: U32,
  tg: Target, fr: List<&2, Frame> & List<&2, U32>) -> IO(Gpu):
  (fs, reg) = fr
  do IO<Gpu>:
    tex : Texture & List<&2, U32> <- texture(dev, types, 1, 1, reg)
    open.staging(core, dev, types, w, h, tg, fs, tex)

def open.finish(core: Core, +dev: U32, +types: List<&2, U32>, +cpool: U32, +w: U32, +h: U32,
  t: Target & List<&2, U32>, extra: List<&2, U32>) -> IO(Gpu):
  (tg, treg) = t
  do IO<Gpu>:
    fr : List<&2, Frame> & List<&2, U32> <- frames(frames_in_flight(), dev, types, cpool,
      ([], List.append(&2, U32, extra, treg)))
    open.texture(core, dev, types, w, h, tg, fr)

# The pipeline and the objects that never change while the context lives.
def open.pipeline(+inst: U32, +layer: U32, +gpu: P.Gpu, +name: String,
  +surface: U32, +dev: U32, +family: U32, +types: List<&2, U32>,
  +vsync: Bool, +w: U32, +h: U32, t: Target & List<&2, U32>) -> IO(Gpu):
  (tg, treg) = t
  Target{sc, +fmt, tw, th, i, v, dn, mem, c} = tg
  do IO<Gpu>:
    +sampler : U32 <- IO.try(U32, N.vk_sampler(dev,
      [Vk.filter_nearest(), Vk.filter_nearest(), Vk.address_clamp_to_edge()]))
    +sl : U32 <- IO.try(U32, N.vk_set_layout(dev,
      [0, Vk.descriptor_combined_sampler(), 1, Vk.shader_fragment()]))
    +pool : U32 <- IO.try(U32, N.vk_descriptor_pool(dev, 1,
      [Vk.descriptor_combined_sampler(), 1]))
    +set : U32 <- IO.try(U32, N.vk_descriptor_set(dev, pool, sl))
    +layout : U32 <- IO.try(U32, N.vk_pipeline_layout(dev, sl, 16, Vk.shader_vertex()))
    +vert : U32 <- shader(dev, W.to_array(S.prim_vert()))
    +frag : U32 <- shader(dev, W.to_array(S.prim_frag()))
    +pipe : U32 <- IO.try(U32, N.vk_pipeline(dev, layout, vert, frag, pipeline_desc(fmt)))
    IO.try(Unit, N.destroy(vert))
    IO.try(Unit, N.destroy(frag))
    +cpool : U32 <- IO.try(U32, N.vk_command_pool(dev, Vk.pool_reset_buffer()))
    +ucmd : U32 <- IO.try(U32, N.vk_command_buffer(dev, cpool))
    +ufence : U32 <- IO.try(U32, N.vk_fence(dev, False{}))
    open.finish(Core{inst, layer, gpu, name, surface, dev, family, types,
      sampler, sl, pool, set, layout, pipe, cpool, ucmd, ufence, vsync},
      dev, types, cpool, w, h, (Target{sc, fmt, tw, th, i, v, dn, mem, c}, treg),
      [ufence, ucmd, cpool, pipe, layout, set, pool, sl, sampler])

def open.objects(+inst: U32, +layer: U32, +gpu: P.Gpu, +name: String,
  +surface: U32, +dev: U32, +family: U32, +types: List<&2, U32>,
  +vsync: Bool, +w: U32, +h: U32, reg: List<&2, U32>) -> IO(Gpu):
  do IO<Gpu>:
    t : Target & List<&2, U32> <- target(dev, types, surface, vsync, 0, w, h, reg)
    open.pipeline(inst, layer, gpu, name, surface, dev, family, types, vsync, w, h, t)

def open.device(+native: List<&2, U32>, +inst: U32, +layer: U32, +gpu: P.Gpu, +vsync: Bool,
  +w: U32, +h: U32) -> IO(Gpu):
  +index = P.gpu.index(gpu)
  do IO<Gpu>:
    +name : String <- IO.try(String, N.vk_gpu_name(inst, index))
    +surface : U32 <- IO.try(U32, N.vk_surface(inst, native))
    +fams : List<&2, U32> <- IO.try(List<&2, U32>, N.vk_queue_families(inst, index, surface))
    +family : U32 <- need(P.family(fams), "no queue family draws and presents to this window")
    +made : List<&2, U32> <- IO.try(List<&2, U32>, N.vk_device(inst, index, family, P.device_flags()))
    +dev : U32 = W.at(made, 0n)
    +types : List<&2, U32> <- IO.try(List<&2, U32>, N.vk_memory_types(dev))
    open.objects(inst, layer, P.gpu.with_regions(gpu, U32.is_eq(W.at(made, 1n), 1)), name, surface,
      dev, family, types, vsync, w, h, [dev, surface, inst])

def instance() -> IO(List<&2, U32>):
  IO.try(List<&2, U32>, N.vk_instance(1))

# Picks the best Vulkan 1.3 GPU that presents to the native window Ankra
# hands over (`native`: Ankra's window.native words), builds a w x h
# swapchain for it and the 2D pipeline. vsync True presents with FIFO;
# False prefers IMMEDIATE/MAILBOX (for measurement). The window stays
# Ankra's: close Voltra first, then the window.
def open(+native: List<&2, U32>, +w: U32, +h: U32, +vsync: Bool) -> IO(Gpu):
  do IO<Gpu>:
    +iw : List<&2, U32> <- instance()
    +inst : U32 = W.at(iw, 0n)
    +gl : List<&2, U32> <- IO.try(List<&2, U32>, N.vk_gpus(inst))
    +gpu : P.Gpu <- need_gpu(P.best(P.gpus(gl)))
    open.device(native, inst, W.at(iw, 1n), gpu, vsync, w, h)

def open.offscreen_target(+inst: U32, +layer: U32, +gpu: P.Gpu, +name: String,
  +dev: U32, +family: U32, +types: List<&2, U32>, +w: U32, +h: U32,
  reg: List<&2, U32>) -> IO(Gpu):
  do IO<Gpu>:
    t : Target & List<&2, U32> <- offscreen(dev, types, w, h, reg)
    open.pipeline(inst, layer, gpu, name, 0, dev, family, types, True{}, w, h, t)

def open.offscreen_device(+inst: U32, +layer: U32, +gpu: P.Gpu, +w: U32, +h: U32) -> IO(Gpu):
  +index = P.gpu.index(gpu)
  do IO<Gpu>:
    +name : String <- IO.try(String, N.vk_gpu_name(inst, index))
    +fams : List<&2, U32> <- IO.try(List<&2, U32>, N.vk_queue_families(inst, index, 0))
    +family : U32 <- need(P.graphics(fams), "no queue family draws")
    +made : List<&2, U32> <- IO.try(List<&2, U32>, N.vk_device(inst, index, family, 0))
    +dev : U32 = W.at(made, 0n)
    +types : List<&2, U32> <- IO.try(List<&2, U32>, N.vk_memory_types(dev))
    open.offscreen_target(inst, layer, gpu, name, dev, family, types, w, h, [dev, inst])

# A context without a window: frames are drawn into a w x h offscreen image
# (in the swapchain format), and `read` copies the last one back. Used to
# compare GPU output with CPU references, pixel by pixel.
def open_offscreen(+w: U32, +h: U32) -> IO(Gpu):
  do IO<Gpu>:
    +iw : List<&2, U32> <- instance()
    +inst : U32 = W.at(iw, 0n)
    +gl : List<&2, U32> <- IO.try(List<&2, U32>, N.vk_gpus(inst))
    +gpu : P.Gpu <- need_gpu(P.best(P.gpus(gl)))
    open.offscreen_device(inst, W.at(iw, 1n), gpu, w, h)
