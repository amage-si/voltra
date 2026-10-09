# Voltra API

Voltra depends only on `Base` from the official Bend toolchain and on its own
modules; windows come from [Ankra](https://github.com/amage-si/ankra). Import
paths are relative to the calling file; an application next to the `Voltra`
and `Ankra` directories uses:

```bend
import Base
import ./Voltra/gpu.bend as V
import ./Voltra/quads.bend as Q
import ./Voltra/atlas.bend as At
import ./Ankra/window.bend as A
```

## The context

`V.Gpu` is `Data`: a value holding slot ids, the swapchain or offscreen target,
the frames in flight, the texture, the registry of live native objects and a
few counters. Every operation takes a context and returns the next one; keep
using the returned value. Mark bindings `+g` when you read a context more than
once.

| Function | Contract |
| --- | --- |
| `open(native, w, h, vsync)` | `IO(Gpu)`. `native` is Ankra's `A.native(win)` words (`[1, Display* high, Display* low, window id, screen]`). Makes the Xlib surface, picks the best Vulkan 1.3+ GPU that presents to it, and builds a `w` x `h` swapchain, the 2D pipeline, two frames in flight and a 1x1 white texture. `vsync` True presents with FIFO; False prefers IMMEDIATE, then MAILBOX. The window stays Ankra's. |
| `open_offscreen(w, h)` | `IO(Gpu)`. No window: frames are drawn into a `w` x `h` image in the swapchain format (B8G8R8A8), kept for `read`. `resize` makes it again at a new size. |
| `describe(g)` | Device and target report as a `String`. |
| `draw(g, quads, clear)` | `IO(Gpu)`. Clears to `clear` (`0xRRGGBBAA`), draws the quads in list order (later quads on top) in one instanced draw, and presents (offscreen: keeps the image). Rebuilds the swapchain when presentation is out of date or suboptimal. Does nothing while the window has no extent (minimized). The canvas does not see the frame: `kept` becomes False. |
| `paint(g, words, n, clear, ranges, whole, regions)` | `IO(Gpu)`. Paints a frame on the canvas (see below): `words` holds `n` quads as `Q.put` writes them (an `Array<U32>`, which may be larger); each `C.Range{x, y, width, height, first, count}` redraws its rectangle with the instances `[first, first + count)`, scissored. `whole` clears the canvas to `clear` first; otherwise the canvas must be `kept`. `regions` (as for `update`) replace texture rectangles first, recorded in this frame's commands: the CPU does not wait for the device. The canvas is then copied into the acquired image and presented, naming the ranges' rectangles when the device enabled `VK_KHR_incremental_present` (offscreen: kept for `read`). |
| `upload(g, w, h, pixels)` | `IO(Gpu)`. Replaces the texture with a row-major `w` x `h` RGBA8 image (`Array<U32>` of `0xRRGGBBAA` words; the array may be larger). Recreates the texture when the size changes. Synchronous. |
| `blank(g, w, h)` | `IO(Gpu)`. A new `w` x `h` texture whose contents are undefined until `update` writes rectangles of it: an atlas. |
| `update(g, regions)` | `IO(Gpu)`. Replaces rectangles of the texture in one transfer and keeps the rest. `Region{x, y, width, height, pixels}`, pixels row-major `0xRRGGBBAA`. Synchronous. |
| `read(g)` | `IO(Gpu & Array<U32>)`. Offscreen only: the last frame as row-major `0xRRGGBBAA` words (`w` x `h` of them). Synchronous. |
| `resize(g, w, h)` | `IO(Gpu)`. Records a new window size (Ankra's `Resized`); rebuilds the swapchain (and its canvas) when it differs from the current one. An offscreen target is made again at the new size. |
| `invalidate(g)` | Marks the content stale: `pending(g)` becomes True. |
| `close(g)` | `IO(Report)`. Waits for the GPU, destroys every live native object newest first (children before devices, devices before the instance), and reports. Close Voltra before the window. |

Accessors: `pending(g)` (the target shows stale content; draw again before
waiting indefinitely), `kept(g)` (the canvas holds the last painted picture,
so `paint` may redraw only part of it), `target_size(g)`, `window_size(g)` and
`texture_size(g)` (`Size{width, height}`), `drawn(g)` (frames drawn),
`rebuilds(g)` (swapchains rebuilt), `device(g)`, `swapchain(g)` (slot ids; 0
means none), `drawable(g)`, `offscreen_target(g)`.

`Report{live, warnings, errors}`: native objects left after teardown (0 when
nothing leaked) and the warnings and errors reported by the Vulkan debug
messenger during the run. `report.show(r)` formats it.

Hard failures, such as a Vulkan error or the absence of a usable GPU, end
the program with the driver's message (through `IO.try`/`IO.die`).

## A typical loop

Ankra's application loop (`Ankra/app.bend`) does the waiting; the app draws
when its content is stale and resizes on `Resized`:

```bend
def update(win: A.Win, batch: List<&2, A.Input>, g: V.Gpu) -> IO(Loop.Step<V.Gpu>):
  +es = batch
  do IO<Loop.Step<V.Gpu>>:
    +g1 : V.Gpu <- resized(A.resized(es, None{}), g)       # V.resize on a new size
    return Bool.pick(Loop.Step<V.Gpu>, A.exposed(es) || V.pending(g1),
      Loop.Redraw{g1}, Loop.Keep{g1})

def draw(win: A.Win, g: V.Gpu) -> IO(Loop.Step<V.Gpu>):
  ...   # V.draw at V.target_size(g); Redraw again while V.pending
```

`examples/quads.bend` and `examples/chromi.bend` contain complete loops.
Drawing only when stale and otherwise waiting without a deadline is what
keeps an idle window at zero frames and zero CPU.

## Painting only what changed

Every target has a canvas: an image that keeps the picture from one frame to
the next. Offscreen, the target image is its own canvas; a swapchain gets a
canvas in its format and size (when its images can receive copies), which
every `paint` copies into the acquired image whole. Because the canvas
keeps its picture, a frame needs to redraw only the rectangles where it
differs from the last one:

1. Write (`Q.put`), for each changed rectangle, the quads that cover it in
   drawing order, starting with an opaque background fill of the rectangle
   (a partial paint loads the canvas, so nothing is cleared for it).
2. `paint(g, words, n, clear, ranges, False{}, regions)` with one `C.Range`
   per rectangle and the atlas regions the frame needs (often none). Each range is drawn with the scissor on its rectangle, so
   pixels outside the ranges keep their last value, and a pixel inside one
   gets exactly what a whole redraw would give it.
3. When the canvas does not hold the last picture (`kept(g)` False: a first
   frame, a new swapchain or size, a minimized window, a frame drawn with
   `draw`), paint whole: `paint(g, words, n, clear, [C.Range{0, 0, w, h, 0,
   n}], True{}, regions)`.

The present names the ranges' rectangles (`VK_KHR_incremental_present`),
so the presentation engine may update only those; the whole image is still
presented and correct. Chromi's `render` (Chromi `gpu.bend`) does all of
this for retained frames. Frames in flight share the canvas and the
texture: each frame's first barrier waits for the previous frame's copy
out of the canvas, and a frame's texture copies wait for earlier frames to
finish sampling. The texels travel in the frame's own instance buffer,
after the instances.

## Quads

`Q.Quad{x, y, width, height, clip_x0, clip_y0, clip_x1, clip_y1, color, kind,
radius, border, a, b, c, d}`: sixteen words per instance. `x` and `y` and
the clip are signed 32-bit values carried in `U32` bits. A quad covers the
pixels whose centers lie inside it, minus those outside its clip box
`[x0, x1) x [y0, y1)`. The rules below are the shader's
(`shaders/prim.frag`), all in integer arithmetic.

| Function | Contract |
| --- | --- |
| `Q.fill(x, y, w, h, rgba)` | A flat rectangle. |
| `Q.image(x, y, w, h, u, v, sw, sh, tint)` | The texel region `(u, v, sw, sh)` mapped onto the quad by nearest texel (`u + dx * sw / w`), each channel tinted `(texel * tint + 127) / 255`; `0xFFFFFFFF` keeps the texels. |
| `Q.mask(x, y, w, h, u, v, ink)` | Texel `(u + dx, v + dy)`'s red channel is the coverage `c` of pixel `(x + dx, y + dy)`; the ink's alpha becomes `(alpha * c + 127) / 255`. |
| `Q.rounded(x0, y0, x1, y1, r, rgba)` | A box in 1/8 pixels with corner radius `r` (1/8 pixels, at most half the shorter side). Coverage: 4x4 samples per pixel at 1/8, 3/8, 5/8, 7/8; a sample is inside when it is inside the box and, in a corner zone, within `r` of the corner's center. `h` hits give `c = (255 h + 8) / 16`, then alpha as for masks. |
| `Q.ring(x0, y0, x1, y1, r, b, rgba)` | The same box minus the box inset by `b` with radius `max(r - b, 0)`. |
| `Q.clipped(q, x0, y0, x1, y1)` | The quad with that clip box (the constructors' clip is unlimited). |
| `Q.put(quads, array, i)` | Writes the quads' instance words, 16 per quad, into the array from word `i` on (what `paint` takes). |
| `Q.words(quads)` | The quads' instance words in a new array (zero padded to a power of two), with the number of quads; what `draw` uploads. |
| `Q.leaves(image, x, y, side, w, h, acc)` | Every leaf of a `Base.Image` quadtree as one opaque quad, clipped to `w` x `h`. |
| `Q.raster(image, array, x, y, side, w, h)` | The quadtree as a row-major `w` x `h` RGBA8 array, ready for `upload`. |
| `Q.side(w, h)` | The power-of-two side of the quadtree covering `w` x `h`. |
| `Q.opaque(rgb)` | `0xRRGGBB` to `0xRRGGBBFF`. |
| `Q.floor8(v)`, `Q.ceil8(v)` | Signed floor and ceiling of `v / 8`. |

Blending is straight-alpha source-over in encoded sRGB, matching Chromi:
`channel = round(s a / 255 + d (255 - a) / 255)`, verified bit-exact against
`(s a + d (255 - a) + 127) / 255` on the development GPU (see
`gpu_tests.bend`).

## Atlas

`At.new(w, h)`, `At.place(atlas, key, w, h) -> At.Atlas & Maybe<At.Entry>`
(a shelf that fits, else a new shelf; None when full), `At.lookup(atlas, key)`,
`At.count(atlas)`, `At.reset(atlas)`. `Entry{key, x, y, width, height}`.
Placement is bookkeeping only; the texels travel with `V.update`.

## Lower layers

`policy.bend` holds the selection rules (`best`, `family`, `graphics`,
`memory`, `format`, `present_mode`, `image_count`, `extent`, `alpha`),
`commands.bend` the command list (`Cmd`, `encode`, `valid`, `frame`,
`paint` with `Range` and `Paint`, `upload`, `patch`, `texture_init`,
`readback`, `to_render`, `to_present`, `to_readback`) and `native.bend` the raw effects documented in
[bridge.md](bridge.md). Applications should prefer `gpu.bend`; the lower
layers are public because Bend modules have no export boundary, and they may
change.
