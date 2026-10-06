import Base
import ./native.bend as N
import ./vk.bend as Vk
import ./words.bend as W
import ./policy.bend as P
import ./commands.bend as C
import ./quads.bend as Q
import ./shaders/spirv.bend as S

# Voltra's GPU context: a window with a Vulkan swapchain that draws
# instanced quads, optionally textured from one RGBA8 texture.
#
# Lifetimes: every native object is a slot recorded in `reg`, newest first.
# Replacing an object (swapchain on resize, texture on size change, an
# instance buffer that grows) destroys the old slots and forgets them;
# `close` destroys whatever remains in that order, so children always go
# before their device, the device before the instance, the instance before
# the window. Hard failures (a Vulkan error, no usable GPU) end the program
# with the driver's message, through IO.try / IO.die.
#
# Sync policy: FRAMES frames in flight, each with its own command buffer,
# fence, acquire semaphore and instance buffer; one render-finished
# semaphore per swapchain image. Uploads wait for the device to go idle, so
# they never race a frame that samples the texture.

def frames_in_flight() -> Nat:
  2n

# Quads per frame before an instance buffer grows (doubles).
def initial_quads() -> U32:
  4096

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

# Buffers and textures
# --------------------

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

def texture.bind(+dev: U32, +types: List<&2, U32>, +w: U32, +h: U32,
  +info: List<&2, U32>, reg: List<&2, U32>) -> IO(Texture & List<&2, U32>):
  +img = W.at(info, 0n)
  do IO<Texture & List<&2, U32>>:
    +t : U32 <- need(P.memory(types, W.at(info, 3n), Vk.mem_device_local()),
      "no device-local memory for a texture")
    +m : U32 <- IO.try(U32, N.vk_alloc(dev, W.at(info, 1n), t))
    IO.try(Unit, N.vk_bind(dev, img, m, 0))
    +v : U32 <- IO.try(U32, N.vk_image_view(dev, img, rgba_view(Vk.format_r8g8b8a8_unorm())))
    return (Texture{img, m, v, w, h}, v <> m <> img <> reg)

def texture(+dev: U32, +types: List<&2, U32>, +w: U32, +h: U32,
  reg: List<&2, U32>) -> IO(Texture & List<&2, U32>):
  do IO<Texture & List<&2, U32>>:
    +info : List<&2, U32> <- IO.try(List<&2, U32>, N.vk_image(dev,
      [w, h, Vk.format_r8g8b8a8_unorm(),
        (Vk.image_transfer_dst() .|. Vk.image_sampled() : U32), Vk.tiling_optimal()]))
    texture.bind(dev, types, w, h, info, reg)

# Swapchain target
# ----------------

type Target is Data:
  Target{swapchain: U32, format: U32, width: U32, height: U32,
    images: List<&2, U32>, views: List<&2, U32>, done: List<&2, U32>}

def views(+dev: U32, +fmt: U32, images: List<&2, U32>) -> IO(List<&2, U32>):
  match images:
    case Nil{}:
      IO.pure(List<&2, U32>, Nil{})
    case Con{i, rest}:
      do IO<List<&2, U32>>:
        +v : U32 <- IO.try(U32, N.vk_image_view(dev, i,
          [fmt, Vk.swizzle_identity(), Vk.swizzle_identity(),
            Vk.swizzle_identity(), Vk.swizzle_identity(), Vk.aspect_color()]))
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

def target.made(+sc: U32, +fmt: U32, +w: U32, +h: U32, +dev: U32,
  +images: List<&2, U32>, reg: List<&2, U32>) -> IO(Target & List<&2, U32>):
  do IO<Target & List<&2, U32>>:
    +vs : List<&2, U32> <- views(dev, fmt, images)
    +ds : List<&2, U32> <- semaphores(List.length(&2, U32, images), dev)
    return (Target{sc, fmt, w, h, images, vs, ds},
      List.append(&2, U32, ds, List.append(&2, U32, vs,
        List.append(&2, U32, images, sc <> reg))))

def target.build(empty: Bool, +dev: U32, +surface: U32, +desc: List<&2, U32>,
  +old: U32, +fmt: U32, +w: U32, +h: U32, reg: List<&2, U32>) -> IO(Target & List<&2, U32>):
  match empty:
    case True{}:
      # A minimized window has no extent: no swapchain until it returns.
      IO.pure(Target & List<&2, U32>, (Target{0, fmt, 0, 0, [], [], []}, reg))
    case False{}:
      do IO<Target & List<&2, U32>>:
        +sc : U32 <- IO.try(U32, N.vk_swapchain(dev, surface, desc, old))
        +images : List<&2, U32> <- IO.try(List<&2, U32>, N.vk_swapchain_images(dev, sc))
        target.made(sc, fmt, w, h, dev, images, reg)

def target.sized(+dev: U32, +surface: U32, +vsync: Bool, +old: U32,
  s: P.Surface, size: U32 & U32, reg: List<&2, U32>) -> IO(Target & List<&2, U32>):
  P.Surface{+mn, +mx, cw, ch, lw, lh, hw, hh, tr, +cur, +alpha, us, +fs, +modes} = s
  (+w, +h) = size
  +fmt = P.format(fs)
  target.build(U32.is_eq(w, 0) || U32.is_eq(h, 0), dev, surface,
    [P.image_count(mn, mx), fmt, Vk.srgb_nonlinear(), w, h,
      Vk.image_color_attachment(), cur, P.alpha(alpha),
      P.present_mode(modes, vsync), 1], old, fmt, w, h, reg)

def target.info(+dev: U32, +surface: U32, +vsync: Bool, +old: U32,
  +info: List<&2, U32>, +ww: U32, +wh: U32, reg: List<&2, U32>) -> IO(Target & List<&2, U32>):
  +s = P.surface(info)
  target.sized(dev, surface, vsync, old, s, P.extent(s, ww, wh), reg)

def target(+dev: U32, +surface: U32, +vsync: Bool, +old: U32, +ww: U32,
  +wh: U32, reg: List<&2, U32>) -> IO(Target & List<&2, U32>):
  do IO<Target & List<&2, U32>>:
    +info : List<&2, U32> <- IO.try(List<&2, U32>, N.vk_surface_info(dev, surface))
    target.info(dev, surface, vsync, old, info, ww, wh, reg)

# Frames in flight
# ----------------

type Frame is Data:
  Frame{cmd: U32, fence: U32, acquired: U32, instances: Buffer, quads: U32}

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
      instance_bytes(initial_quads()), Vk.buffer_vertex(),
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

# Objects fixed for the context's life.
type Core is Data:
  Core{window: U32, instance: U32, layer: U32, gpu: P.Gpu, name: String,
    surface: U32, device: U32, family: U32, types: List<&2, U32>,
    sampler: U32, set_layout: U32, pool: U32, set: U32, layout: U32,
    pipeline: U32, cmd_pool: U32, upload_cmd: U32, upload_fence: U32,
    vsync: Bool}

# The whole context. `pending` means the window shows stale content and the
# next `draw` must happen (resize, expose, upload, a missed frame).
type Gpu is Data:
  Gpu{core: Core, target: Target, frames: List<&2, Frame>, texture: Texture,
    staging: Buffer, reg: List<&2, U32>, width: U32, height: U32,
    pending: Bool, drawn: U32, rebuilds: U32}

# Pipeline description: one instance stream of Q.stride_words() words
# (ivec4 rect, uvec4 source, uvec2 color+flags), straight-alpha
# source-over blending, no culling, triangle list.
def pipeline_desc(+fmt: U32) -> List<&2, U32>:
  [fmt, Vk.topology_triangle_list(), Vk.cull_none(), Vk.front_counter_clockwise(),
    1, Vk.blend_src_alpha(), Vk.blend_one_minus_src_alpha(), Vk.blend_add(),
    Vk.blend_one(), Vk.blend_one_minus_src_alpha(), Vk.blend_add(),
    Vk.color_write_rgba(),
    1, 0, (Q.stride_words() * 4 : U32), Vk.rate_instance(),
    3, 0, 0, Vk.format_r32g32b32a32_sint(), 0,
       1, 0, Vk.format_r32g32b32a32_uint(), 16,
       2, 0, Vk.format_r32g32_uint(), 32]

def shader(+dev: U32, code: Array<U32> & U32) -> IO(U32):
  (a, n) = code
  do IO<U32>:
    r : Array<U32> & Result<&1, &1, U32 & String, U32> <- N.vk_shader(dev, a, n)
    settle(U32, r)

def describe(g: Gpu) -> String:
  Gpu{core, target, fs, tex, st, reg, w, h, p, d, r} = g
  Core{win, inst, +layer, gpu, +name, surf, dev, +family, ty, sa, sl, po, se, la, pi, cp, uc, uf, vs} = core
  P.Gpu{+index, +kind, +vendor, +device, +api, driver, +max_image, +local} = gpu
  Target{sc, +fmt, +tw, +th, +images, vi, dn} = target
  "GPU " ++ U32.show(index) ++ ": " ++ name ++ " (" ++ P.kind_name(kind) ++
    ", vendor " ++ U32.show(vendor) ++ ", device " ++ U32.show(device) ++
    ", Vulkan " ++ P.api_show(api) ++ ", " ++ U32.show(local) ++
    " MiB device-local, max image " ++ U32.show(max_image) ++ ")\n" ++
    "queue family " ++ U32.show(family) ++ ", swapchain " ++ U32.show(tw) ++
    "x" ++ U32.show(th) ++ ", format " ++ U32.show(fmt) ++ ", " ++
    U32.show(W.count(images)) ++ " images, " ++
    U32.show(U32.from_nat(frames_in_flight())) ++ " frames in flight, validation layer " ++
    Bool.pick(String, U32.is_eq(layer, 1), "on", "off (not installed)")

# Points the descriptor set at the current texture.
def bind_texture(g: Gpu) -> IO(Gpu):
  Gpu{+core, target, fs, +texture, st, reg, w, h, p, d, r} = g
  Core{win, inst, layer, gpu, name, surf, +dev, family, types, +sampler, sl, pool, +set, la, pi, cp, uc, uf, vs} = core
  Texture{img, mem, +view, tw, th} = texture
  do IO<Gpu>:
    IO.try(Unit, N.vk_write_image(dev, set, [0, Vk.descriptor_combined_sampler(),
      view, sampler, Vk.layout_shader_read()]))
    return Gpu{core, target, fs, texture, st, reg, w, h, p, d, r}

# Events
# ------

type Input is Data:
  Closed{}
  Resized{width: U32, height: U32}
  Exposed{}
  KeyInput{keysym: U32, down: Bool}
  ButtonInput{x: U32, y: U32, button: U32, down: Bool}
  MotionInput{x: U32, y: U32}
  FocusInput{gained: Bool}

def event(+k: U32, +a: U32, +b: U32, +c: U32, +d: U32) -> Maybe<&2, Input>:
  Bool.pick(Maybe<&2, Input>, U32.is_eq(k, 1), Some{Closed{}},
  Bool.pick(Maybe<&2, Input>, U32.is_eq(k, 2), Some{Resized{a, b}},
  Bool.pick(Maybe<&2, Input>, U32.is_eq(k, 3), Some{Exposed{}},
  Bool.pick(Maybe<&2, Input>, U32.is_eq(k, 4), Some{KeyInput{a, U32.is_ne(b, 0)}},
  Bool.pick(Maybe<&2, Input>, U32.is_eq(k, 5), Some{ButtonInput{a, b, c, U32.is_ne(d, 0)}},
  Bool.pick(Maybe<&2, Input>, U32.is_eq(k, 6), Some{MotionInput{a, b}},
  Bool.pick(Maybe<&2, Input>, U32.is_eq(k, 7), Some{FocusInput{U32.is_ne(a, 0)}}, None{})))))))

def events.put(e: Maybe<&2, Input>, rest: List<&2, Input>) -> List<&2, Input>:
  match e:
    case None{}:
      rest
    case Some{x}:
      x <> rest

# Input words from the bridge, five per event: kind, a, b, c, d.
def events(xs: List<&2, U32>) -> List<&2, Input>:
  match xs:
    case Con{k, Con{a, Con{b, Con{c, Con{d, rest}}}}}:
      events.put(event(k, a, b, c, d), events(rest))
    case _:
      Nil{}

# Waits up to `ms` for window events (0 polls; 4294967295 waits without a
# deadline). The wait parks on the X connection: no CPU while idle.
def wait(g: Gpu, ms: U32) -> IO(List<&2, Input>):
  Gpu{core, target, fs, tex, st, reg, w, h, p, d, r} = g
  Core{+win, inst, layer, gpu, name, surf, dev, family, types, sa, sl, pool, set, la, pi, cp, uc, uf, vs} = core
  do IO<List<&2, Input>>:
    +ws : List<&2, U32> <- IO.try(List<&2, U32>, N.window_wait(win, ms))
    return events(ws)

def closed(es: List<&2, Input>) -> Bool:
  match es:
    case Nil{}:
      False{}
    case Con{Closed{}, rest}:
      True{}
    case Con{e, rest}:
      closed(rest)

type Size is Data:
  Size{width: U32, height: U32}

# The last size reported in a batch, if any.
def resized(es: List<&2, Input>, last: Maybe<&2, Size>) -> Maybe<&2, Size>:
  match es:
    case Nil{}:
      last
    case Con{Resized{w, h}, rest}:
      resized(rest, Some{Size{w, h}})
    case Con{e, rest}:
      resized(rest, last)

def exposed(es: List<&2, Input>) -> Bool:
  match es:
    case Nil{}:
      False{}
    case Con{Exposed{}, rest}:
      True{}
    case Con{e, rest}:
      exposed(rest)

# Accessors
# ---------

def device(g: Gpu) -> U32:
  Gpu{core, t, fs, tex, st, reg, w, h, p, d, r} = g
  Core{win, inst, layer, gpu, name, surf, dev, family, types, sa, sl, pool, set, la, pi, cp, uc, uf, vs} = core
  dev

def window(g: Gpu) -> U32:
  Gpu{core, t, fs, tex, st, reg, w, h, p, d, r} = g
  Core{win, inst, layer, gpu, name, surf, dev, family, types, sa, sl, pool, set, la, pi, cp, uc, uf, vs} = core
  win

def swapchain(g: Gpu) -> U32:
  Gpu{core, t, fs, tex, st, reg, w, h, p, d, r} = g
  Target{sc, fmt, tw, th, i, v, dn} = t
  sc

def pending(g: Gpu) -> Bool:
  Gpu{core, t, fs, tex, st, reg, w, h, p, d, r} = g
  p

def drawn(g: Gpu) -> U32:
  Gpu{core, t, fs, tex, st, reg, w, h, p, d, r} = g
  d

def rebuilds(g: Gpu) -> U32:
  Gpu{core, t, fs, tex, st, reg, w, h, p, d, r} = g
  r

def target_size(g: Gpu) -> Size:
  Gpu{core, t, fs, tex, st, reg, w, h, p, d, r} = g
  Target{sc, fmt, tw, th, i, v, dn} = t
  Size{tw, th}

def window_size(g: Gpu) -> Size:
  Gpu{core, t, fs, tex, st, reg, w, h, p, d, r} = g
  Size{w, h}

# Marks the window content stale (an Expose, or new application content).
def invalidate(g: Gpu) -> Gpu:
  Gpu{core, t, fs, tex, st, reg, w, h, p, d, r} = g
  Gpu{core, t, fs, tex, st, reg, w, h, True{}, d, r}

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

# Swapchain recreation
# --------------------

def retarget.swap(core: Core, t: Target & List<&2, U32>, old: List<&2, U32>,
  fs: List<&2, Frame>, tex: Texture, st: Buffer, +w: U32, +h: U32, +d: U32,
  +r: U32) -> IO(Gpu):
  (target, reg) = t
  do IO<Gpu>:
    +reg2 : List<&2, U32> <- release(old, reg)
    return Gpu{core, target, fs, tex, st, reg2, w, h, True{}, d, (r + 1 : U32)}

# Builds a swapchain for the current window size from the old one, then
# destroys the old swapchain and everything made for it.
def retarget(g: Gpu) -> IO(Gpu):
  Gpu{+core, tg, fs, tex, st, reg, +w, +h, p, d, r} = g
  Core{win, inst, layer, gpu, name, +surf, +dev, family, types, sa, sl, pool, set, la, pi, cp, uc, uf, +vsync} = core
  Target{+sc, fmt, tw, th, +images, +views, +done} = tg
  do IO<Gpu>:
    IO.try(Unit, N.vk_idle(dev))
    t : Target & List<&2, U32> <- target(dev, surf, vsync, sc, w, h, reg)
    retarget.swap(core, t, drop_none(List.append(&2, U32, done,
      List.append(&2, U32, views, List.append(&2, U32, images, [sc])))),
      fs, tex, st, w, h, d, r)

def resize.pick(differs: Bool, g: Gpu) -> IO(Gpu):
  match differs:
    case True{}:
      retarget(g)
    case False{}:
      IO.pure(Gpu, invalidate(g))

# Records the window's new size; recreates the swapchain when it differs.
def resize(g: Gpu, +w: U32, +h: U32) -> IO(Gpu):
  Gpu{core, t, fs, tex, st, reg, ow, oh, p, d, r} = g
  Target{+sc, +fmt, +tw, +th, +i, +v, +dn} = t
  resize.pick(U32.is_ne(tw, w) || U32.is_ne(th, h),
    Gpu{core, Target{sc, fmt, tw, th, i, v, dn}, fs, tex, st, reg, w, h, p, d, r})

# Texture upload
# --------------

def with_texture(g: Gpu, t: Texture & List<&2, U32>) -> Gpu:
  Gpu{core, target, fs, old, st, r0, w, h, p, d, r} = g
  (tex, reg) = t
  Gpu{core, target, fs, tex, st, reg, w, h, p, d, r}

def with_staging(g: Gpu, s: Buffer & List<&2, U32>) -> Gpu:
  Gpu{core, target, fs, tex, old, r0, w, h, p, d, r} = g
  (st, reg) = s
  Gpu{core, target, fs, tex, st, reg, w, h, p, d, r}

def upload.texture(same: Bool, +g: Gpu, +w: U32, +h: U32) -> IO(Gpu):
  match same:
    case True{}:
      IO.pure(Gpu, g)
    case False{}:
      Gpu{core, target, fs, tex, st, reg, gw, gh, p, d, r} = g
      Core{win, inst, layer, gpu, name, surf, +dev, family, +types, sa, sl, pool, set, la, pi, cp, uc, uf, vs} = core
      Texture{+img, +mem, +view, tw, th} = tex
      do IO<Gpu>:
        +reg2 : List<&2, U32> <- release([view, img, mem], reg)
        t : Texture & List<&2, U32> <- texture(dev, types, w, h, reg2)
        bind_texture(with_texture(g, t))

def upload.staging(enough: Bool, +g: Gpu, +bytes: U32) -> IO(Gpu):
  match enough:
    case True{}:
      IO.pure(Gpu, g)
    case False{}:
      Gpu{core, target, fs, tex, st, reg, gw, gh, p, d, r} = g
      Core{win, inst, layer, gpu, name, surf, +dev, family, +types, sa, sl, pool, set, la, pi, cp, uc, uf, vs} = core
      Buffer{+b, +m, old} = st
      do IO<Gpu>:
        +reg2 : List<&2, U32> <- release([b, m], reg)
        s : Buffer & List<&2, U32> <- host_buffer(dev, types, bytes, Vk.buffer_transfer_src(), reg2)
        return with_staging(g, s)

def texture_is(g: Gpu, +w: U32, +h: U32) -> Bool:
  Gpu{core, target, fs, tex, st, reg, gw, gh, p, d, r} = g
  Texture{img, mem, view, +tw, +th} = tex
  U32.is_eq(tw, w) && U32.is_eq(th, h)

def staging_fits(g: Gpu, +bytes: U32) -> Bool:
  Gpu{core, target, fs, tex, st, reg, gw, gh, p, d, r} = g
  Buffer{b, m, +have} = st
  U32.is_ge(have, bytes)

def upload.copy(+g: Gpu, +w: U32, +h: U32, pixels: Array<U32>) -> IO(Gpu):
  Gpu{+core, target, fs, +tex, +st, reg, gw, gh, p, d, r} = g
  Core{win, inst, layer, gpu, name, surf, +dev, family, types, sa, sl, pool, set, la, pi, cp, +ucmd, +ufence, vs} = core
  Texture{+img, mem, view, tw, th} = tex
  Buffer{+b, +m, have} = st
  do IO<Gpu>:
    wr : Array<U32> & Result<&1, &1, U32 & String, Unit> <- N.vk_write(m, 0, pixels, (w * h : U32))
    settle(Unit, wr)
    ops : Array<U32> & U32 <- checked(C.upload(img, b, w, h))
    record(ucmd, ops)
    IO.try(Unit, N.vk_submit(dev, ucmd, 0, 0, 0, ufence))
    +s : U32 <- IO.try(U32, N.vk_wait(dev, ufence, 10000, True{}))
    return invalidate(g)

# Uploads a row-major w x h RGBA8 image (0xRRGGBBAA words; the array may be
# larger) as the texture quads sample. Synchronous: waits for in-flight
# frames first, then for the copy. Recreates the texture on a size change.
def upload(+g: Gpu, +w: U32, +h: U32, pixels: Array<U32>) -> IO(Gpu):
  +bytes = (w * h * 4 : U32)
  do IO<Gpu>:
    IO.try(Unit, N.vk_idle(device(g)))
    +g1 : Gpu <- upload.texture(texture_is(g, w, h), g, w, h)
    +g2 : Gpu <- upload.staging(staging_fits(g1, bytes), g1, bytes)
    upload.copy(g2, w, h, pixels)

# Drawing
# -------

def with_frames(g: Gpu, fs: List<&2, Frame>, reg: List<&2, U32>) -> Gpu:
  Gpu{core, t, old, tex, st, r0, w, h, p, d, r} = g
  Gpu{core, t, fs, tex, st, reg, w, h, p, d, r}

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
          Vk.buffer_vertex(), reg2)
        return grow.made(cmd, fence, acq, quads, rest, nb, g)

# Doubles the current frame's instance buffer until `n` quads fit. Called
# after that frame's fence signaled, so the old buffer is idle.
def grow(need: Bool, +g: Gpu, +n: U32) -> IO(Gpu):
  match need:
    case False{}:
      IO.pure(Gpu, g)
    case True{}:
      Gpu{core, t, fs, tex, st, reg, w, h, p, d, r} = g
      Core{win, inst, layer, gpu, name, surf, +dev, family, +types, sa, sl, pool, set, la, pi, cp, uc, uf, vs} = core
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
  Gpu{core, t, fs, tex, st, reg, w, h, p, d, r} = g
  presented.pick(U32.is_ne(status, 0) || U32.is_ne(acquired, 0),
    Gpu{core, t, rotate(fs), tex, st, reg, w, h, False{}, (d + 1 : U32), r})

def draw.frame(fs: List<&2, Frame>, +g: Gpu, +dev: U32, +sc: U32, +index: U32,
  +acquired: U32, +image: U32, +view: U32, +finished: U32, +tw: U32, +th: U32,
  +clear: U32, +pipe: U32, +layout: U32, +set: U32, +xw: U32, +xh: U32,
  words: List<&2, U32>, +n: U32) -> IO(Gpu):
  match fs:
    case Nil{}:
      IO.die(Gpu, 1, "Voltra: no frame in flight")
    case Con{Frame{+cmd, +fence, +acq, Buffer{+b, +m, bytes}, cap}, rest}:
      do IO<Gpu>:
        wr : Array<U32> & Result<&1, &1, U32 & String, Unit> <- N.vk_write(m, 0,
          first(W.to_array(words)), (n * Q.stride_words() : U32))
        settle(Unit, wr)
        ops : Array<U32> & U32 <- checked(C.frame(C.Pass{image, view, tw, th, clear,
          pipe, layout, set, b, n, xw, xh}))
        record(cmd, ops)
        IO.try(Unit, N.vk_submit(dev, cmd, acq, Vk.stage_color_output(), finished, fence))
        +status : U32 <- IO.try(U32, N.vk_present(dev, sc, index, finished))
        presented(g, status, acquired)

# Records, submits and presents one frame into the acquired image.
def draw.submit(+g: Gpu, +index: U32, +acquired: U32, quads: List<&2, Q.Quad>,
  +clear: U32) -> IO(Gpu):
  Gpu{core, t, fs, tex, st, reg, w, h, p, d, r} = g
  Core{win, inst, layer, gpu, name, surf, +dev, family, types, sa, sl, pool, +set, +layout, +pipe, cp, uc, uf, vs} = core
  Target{+sc, fmt, +tw, +th, +images, +views, +done} = t
  Texture{img, mem, view, +xw, +xh} = tex
  +i = U32.to_nat(index)
  +words = Q.pack(quads)
  +n = (W.count(words) / Q.stride_words() : U32)
  draw.frame(fs, g, dev, sc, index, acquired, W.at(images, i), W.at(views, i), W.at(done, i),
    tw, th, clear, pipe, layout, set, xw, xh, words, n)

def frame_sync(fs: List<&2, Frame>) -> List<&2, U32>:
  match fs:
    case Nil{}:
      [0, 0]
    case Con{Frame{cmd, fence, acq, b, cap}, rest}:
      [fence, acq]

def frames_of(g: Gpu) -> List<&2, Frame>:
  Gpu{core, t, fs, tex, st, reg, w, h, p, d, r} = g
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

def draw.go(+g: Gpu, quads: List<&2, Q.Quad>, +clear: U32) -> IO(Gpu):
  +sync = frame_sync(frames_of(g))
  +dev = device(g)
  do IO<Gpu>:
    +waited : U32 <- IO.try(U32, N.vk_wait(dev, W.at(sync, 0n), 10000, False{}))
    +a : List<&2, U32> <- IO.try(List<&2, U32>, N.vk_acquire(dev, swapchain(g),
      W.at(sync, 1n), 10000))
    draw.acquired(U32.is_le(W.at(a, 0n), 1), g, W.at(a, 1n), W.at(a, 0n), quads, clear)

def draw.ready(ok: Bool, +g: Gpu, quads: List<&2, Q.Quad>, +clear: U32) -> IO(Gpu):
  match ok:
    case False{}:
      # Minimized (no swapchain): nothing to draw into. The content is not
      # pending; the resize that restores the window makes it pending again.
      Gpu{core, t, fs, tex, st, reg, w, h, p, d, r} = g
      IO.pure(Gpu, Gpu{core, t, fs, tex, st, reg, w, h, False{}, d, r})
    case True{}:
      draw.go(g, quads, clear)

# Draws quads over a cleared target and presents. `clear` is 0xRRGGBBAA.
def draw(+g: Gpu, quads: List<&2, Q.Quad>, +clear: U32) -> IO(Gpu):
  draw.ready(U32.is_ne(swapchain(g), 0), g, quads, clear)

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
# warnings and errors the Vulkan debug messenger saw during the run.
def close(g: Gpu) -> IO(Report):
  Gpu{core, t, fs, tex, st, +reg, w, h, p, d, r} = g
  do IO<Report>:
    IO.try(Unit, N.vk_idle(device(Gpu{core, t, fs, tex, st, reg, w, h, p, d, r})))
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
    +g : Gpu <- bind_texture(Gpu{core, tg, fs, tex, st, reg, w, h, True{}, 0, 0})
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
def open.pipeline(+win: U32, +inst: U32, +layer: U32, +gpu: P.Gpu, +name: String,
  +surface: U32, +dev: U32, +family: U32, +types: List<&2, U32>,
  +vsync: Bool, +w: U32, +h: U32, t: Target & List<&2, U32>) -> IO(Gpu):
  (tg, treg) = t
  Target{sc, +fmt, tw, th, i, v, dn} = tg
  do IO<Gpu>:
    +sampler : U32 <- IO.try(U32, N.vk_sampler(dev,
      [Vk.filter_nearest(), Vk.filter_nearest(), Vk.address_clamp_to_edge()]))
    +sl : U32 <- IO.try(U32, N.vk_set_layout(dev,
      [0, Vk.descriptor_combined_sampler(), 1, Vk.shader_fragment()]))
    +pool : U32 <- IO.try(U32, N.vk_descriptor_pool(dev, 1,
      [Vk.descriptor_combined_sampler(), 1]))
    +set : U32 <- IO.try(U32, N.vk_descriptor_set(dev, pool, sl))
    +layout : U32 <- IO.try(U32, N.vk_pipeline_layout(dev, sl, 16, Vk.shader_vertex()))
    +vert : U32 <- shader(dev, W.to_array(S.quad_vert()))
    +frag : U32 <- shader(dev, W.to_array(S.quad_frag()))
    +pipe : U32 <- IO.try(U32, N.vk_pipeline(dev, layout, vert, frag, pipeline_desc(fmt)))
    IO.try(Unit, N.destroy(vert))
    IO.try(Unit, N.destroy(frag))
    +cpool : U32 <- IO.try(U32, N.vk_command_pool(dev, Vk.pool_reset_buffer()))
    +ucmd : U32 <- IO.try(U32, N.vk_command_buffer(dev, cpool))
    +ufence : U32 <- IO.try(U32, N.vk_fence(dev, False{}))
    open.finish(Core{win, inst, layer, gpu, name, surface, dev, family, types,
      sampler, sl, pool, set, layout, pipe, cpool, ucmd, ufence, vsync},
      dev, types, cpool, w, h, (Target{sc, fmt, tw, th, i, v, dn}, treg),
      [ufence, ucmd, cpool, pipe, layout, set, pool, sl, sampler])

def open.objects(+win: U32, +inst: U32, +layer: U32, +gpu: P.Gpu, +name: String,
  +surface: U32, +dev: U32, +family: U32, +types: List<&2, U32>,
  +vsync: Bool, +w: U32, +h: U32, reg: List<&2, U32>) -> IO(Gpu):
  do IO<Gpu>:
    t : Target & List<&2, U32> <- target(dev, surface, vsync, 0, w, h, reg)
    open.pipeline(win, inst, layer, gpu, name, surface, dev, family, types, vsync, w, h, t)

def open.device(+win: U32, +inst: U32, +layer: U32, +gpu: P.Gpu, +vsync: Bool,
  +w: U32, +h: U32) -> IO(Gpu):
  P.Gpu{+index, kind, vendor, device, api, driver, max_image, local} = gpu
  do IO<Gpu>:
    +name : String <- IO.try(String, N.vk_gpu_name(inst, index))
    +surface : U32 <- IO.try(U32, N.vk_surface(inst, win))
    +fams : List<&2, U32> <- IO.try(List<&2, U32>, N.vk_queue_families(inst, index, surface))
    +family : U32 <- need(P.family(fams), "no queue family draws and presents to this window")
    +dev : U32 <- IO.try(U32, N.vk_device(inst, index, family))
    +types : List<&2, U32> <- IO.try(List<&2, U32>, N.vk_memory_types(dev))
    open.objects(win, inst, layer, gpu, name, surface, dev, family, types, vsync, w, h,
      [dev, surface, inst, win])

# Opens a w x h window owned by Voltra, picks the best Vulkan 1.3 GPU that
# presents to it and builds the quad pipeline. vsync True presents with FIFO;
# False prefers IMMEDIATE/MAILBOX (for measurement). A window that is not
# resizable asks the window manager for a fixed size.
def open(title: String, +w: U32, +h: U32, +vsync: Bool, resizable: Bool) -> IO(Gpu):
  do IO<Gpu>:
    +win : U32 <- IO.try(U32, N.window_open(title, w, h, Bool.pick(U32, resizable, 0, 1)))
    +iw : List<&2, U32> <- IO.try(List<&2, U32>, N.vk_instance(1))
    +inst : U32 = W.at(iw, 0n)
    +gl : List<&2, U32> <- IO.try(List<&2, U32>, N.vk_gpus(inst))
    +gpu : P.Gpu <- need_gpu(P.best(P.gpus(gl)))
    open.device(win, inst, W.at(iw, 1n), gpu, vsync, w, h)
