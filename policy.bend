import Base
import ./vk.bend as Vk
import ./words.bend as W

# Pure selection policies. The bridge reports what the driver offers as
# words; these functions decide what Voltra uses. Native tests cover them.

type Gpu is Data:
  Gpu{index: U32, kind: U32, vendor: U32, device: U32, api: U32,
    driver: U32, max_image: U32, local_mib: U32}

# Words from vk_gpus: [count, (kind, vendor, device, api, driver,
# max_image, local_mib)*].
def gpus.go(n: Nat, +i: U32, xs: List<&2, U32>) -> List<&2, Gpu>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +ws = xs
      Gpu{i, W.at(ws, 0n), W.at(ws, 1n), W.at(ws, 2n), W.at(ws, 3n),
        W.at(ws, 4n), W.at(ws, 5n), W.at(ws, 6n)}
        <> gpus.go(p, (i + 1 : U32), W.drop(ws, 7n))

def gpus(+xs: List<&2, U32>) -> List<&2, Gpu>:
  gpus.go(U32.to_nat(W.at(xs, 0n)), 0, W.drop(xs, 1n))

def api_major(+v: U32) -> U32:
  ((v >> 22n) .&. 127 : U32)

def api_minor(+v: U32) -> U32:
  ((v >> 12n) .&. 1023 : U32)

def api_show(+v: U32) -> String:
  U32.show(api_major(v)) ++ "." ++ U32.show(api_minor(v)) ++ "." ++
    U32.show((v .&. 4095 : U32))

# Voltra uses dynamic rendering, core in Vulkan 1.3.
def api_ok(+v: U32) -> Bool:
  U32.is_gt(api_major(v), 1) || (U32.is_eq(api_major(v), 1) && U32.is_ge(api_minor(v), 3))

def kind_score(+k: U32) -> U32:
  Bool.pick(U32, U32.is_eq(k, Vk.gpu_discrete()), 4,
    Bool.pick(U32, U32.is_eq(k, Vk.gpu_integrated()), 3,
      Bool.pick(U32, U32.is_eq(k, Vk.gpu_virtual()), 2, 1)))

# 0 rejects the device; otherwise higher is better.
def score(g: Gpu) -> U32:
  Gpu{index, +kind, vendor, device, +api, driver, max_image, local_mib} = g
  Bool.pick(U32, api_ok(api), kind_score(kind), 0)

def kind_name(+k: U32) -> String:
  Bool.pick(String, U32.is_eq(k, Vk.gpu_discrete()), "discrete",
    Bool.pick(String, U32.is_eq(k, Vk.gpu_integrated()), "integrated",
      Bool.pick(String, U32.is_eq(k, Vk.gpu_virtual()), "virtual",
        Bool.pick(String, U32.is_eq(k, Vk.gpu_cpu()), "cpu", "other"))))

def best.go(gs: List<&2, Gpu>, best: Maybe<&2, Gpu>, +top: U32) -> Maybe<&2, Gpu>:
  match gs:
    case Nil{}:
      best
    case Con{g, rest}:
      +h = g
      +s = score(h)
      +better = U32.is_gt(s, top)
      best.go(rest, Bool.pick(Maybe<&2, Gpu>, better, Some{h}, best),
        Bool.pick(U32, better, s, top))

# The highest-scoring usable GPU; earlier devices win ties.
def best(gs: List<&2, Gpu>) -> Maybe<&2, Gpu>:
  best.go(gs, None{}, 0)

# Queue families from vk_queue_families: (flags, count, present)*.
# The first family that both draws and presents to the surface.
def family.go(n: Nat, xs: List<&2, U32>, +i: U32, found: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match n:
    case 0n:
      found
    case 1n+p:
      +ws = xs
      +f = found
      +ok = U32.is_ne((W.at(ws, 0n) .&. Vk.queue_graphics() : U32), 0)
        && U32.is_ne(W.at(ws, 2n), 0) && Maybe.is_none(&2, U32, f)
      family.go(p, W.drop(ws, 3n), (i + 1 : U32), Bool.pick(Maybe<&2, U32>, ok, Some{i}, f))

def family(+xs: List<&2, U32>) -> Maybe<&2, U32>:
  family.go(U32.to_nat((W.count(xs) / 3 : U32)), xs, 0, None{})

# Memory types from vk_memory_types: [count, (flags, heap)*, ...]. The first
# type allowed by `bits` whose flags include every flag in `want`.
def memory.go(n: Nat, xs: List<&2, U32>, +i: U32, +bits: U32, +want: U32, found: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match n:
    case 0n:
      found
    case 1n+p:
      +ws = xs
      +f = found
      +flags = W.at(ws, 0n)
      +ok = U32.is_ne(((bits >> U32.to_nat(i)) .&. 1 : U32), 0)
        && U32.is_eq((flags .&. want : U32), want) && Maybe.is_none(&2, U32, f)
      memory.go(p, W.drop(ws, 2n), (i + 1 : U32), bits, want, Bool.pick(Maybe<&2, U32>, ok, Some{i}, f))

def memory(+types: List<&2, U32>, +bits: U32, +want: U32) -> Maybe<&2, U32>:
  memory.go(U32.to_nat(W.at(types, 0n)), W.drop(types, 1n), 0, bits, want, None{})

# Surface report from vk_surface_info.
type Surface is Data:
  Surface{min_images: U32, max_images: U32, width: U32, height: U32,
    min_width: U32, min_height: U32, max_width: U32, max_height: U32,
    transforms: U32, transform: U32, alpha: U32, usage: U32,
    formats: List<&2, U32>, modes: List<&2, U32>}

def surface(+xs: List<&2, U32>) -> Surface:
  +nf = W.at(xs, 12n)
  +rest = W.drop(xs, 13n)
  +nfw = U32.to_nat((nf * 2 : U32))
  Surface{W.at(xs, 0n), W.at(xs, 1n), W.at(xs, 2n), W.at(xs, 3n),
    W.at(xs, 4n), W.at(xs, 5n), W.at(xs, 6n), W.at(xs, 7n), W.at(xs, 8n),
    W.at(xs, 9n), W.at(xs, 10n), W.at(xs, 11n), W.take(rest, nfw),
    W.take(W.drop(rest, 1n+nfw), U32.to_nat(W.at(rest, nfw)))}

def has_format(fs: List<&2, U32>, +format: U32) -> Bool:
  match fs:
    case Nil{}:
      False{}
    case Con{f, Nil{}}:
      False{}
    case Con{f, Con{space, rest}}:
      (U32.is_eq(f, format) && U32.is_eq(space, Vk.srgb_nonlinear())) || has_format(rest, format)

# The first format offered with the sRGB-nonlinear color space (0 if none).
def first_srgb(fs: List<&2, U32>) -> U32:
  match fs:
    case Nil{}:
      0
    case Con{f, Nil{}}:
      0
    case Con{+f, Con{space, rest}}:
      Bool.pick(U32, U32.is_eq(space, Vk.srgb_nonlinear()), f, first_srgb(rest))

# Encoded-sRGB (UNORM) targets keep the values Chromi composites on the CPU.
# Voltra always asks for the sRGB-nonlinear color space.
def format(+fs: List<&2, U32>) -> U32:
  Bool.pick(U32, has_format(fs, Vk.format_b8g8r8a8_unorm()), Vk.format_b8g8r8a8_unorm(),
    Bool.pick(U32, has_format(fs, Vk.format_r8g8b8a8_unorm()), Vk.format_r8g8b8a8_unorm(),
      first_srgb(fs)))

# FIFO (vsync) is always available and is the default. Uncapped presentation,
# for measurement, prefers IMMEDIATE, then MAILBOX.
def present_mode(+modes: List<&2, U32>, vsync: Bool) -> U32:
  match vsync:
    case True{}:
      Vk.present_fifo()
    case False{}:
      Bool.pick(U32, W.contains(modes, Vk.present_immediate()), Vk.present_immediate(),
        Bool.pick(U32, W.contains(modes, Vk.present_mailbox()), Vk.present_mailbox(),
          Vk.present_fifo()))

# One image more than the minimum, within the maximum (0: no maximum).
def image_count(+min: U32, +max: U32) -> U32:
  Bool.pick(U32, U32.is_eq(max, 0), (min + 1 : U32), U32.min((min + 1 : U32), max))

def clamp(+v: U32, +lo: U32, +hi: U32) -> U32:
  U32.max(lo, U32.min(v, hi))

# The swapchain extent: the surface's current extent when it states one,
# otherwise the window size within the surface limits.
def extent(s: Surface, +window_w: U32, +window_h: U32) -> U32 & U32:
  Surface{n0, n1, +w, +h, +lw, +lh, +hw, +hh, t0, t1, a, u, f, m} = s
  +free = U32.is_eq(w, 4294967295)
  (Bool.pick(U32, free, clamp(window_w, lw, hw), w),
    Bool.pick(U32, free, clamp(window_h, lh, hh), h))

# Opaque composition when the surface offers it, else its lowest mode.
def alpha(+supported: U32) -> U32:
  Bool.pick(U32, U32.is_ne((supported .&. Vk.composite_opaque() : U32), 0),
    Vk.composite_opaque(), (supported .&. (0 - supported : U32) : U32))
