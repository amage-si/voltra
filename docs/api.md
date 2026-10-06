# Voltra API

Voltra depends only on `Base` from the official Bend toolchain and on its own
modules. Import paths are relative to the calling file; an application next to
the `Voltra` directory uses:

```bend
import Base
import ./Voltra/gpu.bend as V
import ./Voltra/quads.bend as Q
```

## The context

`V.Gpu` is `Data`: a value holding slot ids, the swapchain, the frames in
flight, the texture, the registry of live native objects and a few counters.
Every operation takes a context and returns the next one; keep using the
returned value. Mark bindings `+g` when you read a context more than once.

| Function | Contract |
| --- | --- |
| `open(title, w, h, vsync, resizable)` | `IO(Gpu)`. Opens a `w` x `h` window, picks the best Vulkan 1.3+ GPU that presents to it, and builds the swapchain, pipeline, two frames in flight and a 1x1 white texture. `vsync` True presents with FIFO; False prefers IMMEDIATE, then MAILBOX. A window that is not `resizable` asks for a fixed size. |
| `describe(g)` | Device and swapchain report as a `String`. |
| `draw(g, quads, clear)` | `IO(Gpu)`. Clears to `clear` (`0xRRGGBBAA`), draws the quads in list order (later quads on top) and presents. Rebuilds the swapchain when presentation is out of date or suboptimal. Does nothing while the window has no extent (minimized). |
| `upload(g, w, h, pixels)` | `IO(Gpu)`. Replaces the texture with a row-major `w` x `h` RGBA8 image (`Array<U32>` of `0xRRGGBBAA` words; the array may be larger). Recreates the texture when the size changes. Synchronous: waits for in-flight frames, then for the copy. |
| `wait(g, ms)` | `IO(List<&2, Input>)`. Waits up to `ms` for window events: 0 polls, 4294967295 waits without a deadline. The wait parks on the X connection, without busy polling. |
| `resize(g, w, h)` | `IO(Gpu)`. Records a new window size; rebuilds the swapchain when it differs from the current one. |
| `invalidate(g)` | Marks the content stale: `pending(g)` becomes True. |
| `close(g)` | `IO(Report)`. Waits for the GPU, destroys every live native object newest first (children before devices, devices before the instance, the instance before the window), and reports. |

Accessors: `pending(g)` (the window shows stale content; draw before waiting
indefinitely), `target_size(g)` and `window_size(g)` (`Size{width, height}`),
`drawn(g)` (frames presented), `rebuilds(g)` (swapchains rebuilt),
`device(g)`, `window(g)`, `swapchain(g)` (slot ids; 0 means none).

`Report{live, warnings, errors}`: native objects left after teardown (0 when
nothing leaked) and the warnings and errors reported by the Vulkan debug
messenger during the run. `report.show(r)` formats it.

Hard failures, such as a Vulkan error or the absence of a usable GPU, end
the program with the driver's message (through `IO.try`/`IO.die`).

## A typical loop

```bend
def loop(n: Nat, stop: Bool, +g: V.Gpu) -> IO(V.Gpu):
  match n stop:
    case _ True{}:
      IO.pure(V.Gpu, g)
    case 0n _:
      IO.pure(V.Gpu, g)
    case 1n+p False{}:
      do IO<V.Gpu>:
        +g1 : V.Gpu <- paint(V.pending(g), g)      # draw only when stale
        +es : List<&2, V.Input> <- V.wait(g1, Bool.pick(U32, V.pending(g1), 0, 4294967295))
        +g2 : V.Gpu <- apply(g1, es)                # resize, input, invalidate
        loop(p, V.closed(es), g2)
```

`examples/quads.bend` and `examples/chromi.bend` contain complete loops.
Drawing only while `pending` and otherwise waiting without a deadline is what
keeps an idle window at zero frames and zero CPU.

## Events

`Input` constructors: `Closed{}`, `Resized{width, height}`, `Exposed{}`,
`KeyInput{keysym, down}` (X11 keysym, e.g. 65307 for Escape),
`ButtonInput{x, y, button, down}` (1 left, 2 middle, 3 right, 4/5 wheel),
`MotionInput{x, y}`, `FocusInput{gained}`. Helpers: `closed(es)`,
`exposed(es)`, `resized(es, None{})` (the last size in the batch). Window
coordinates are physical pixels.

## Quads

`Q.Quad{x, y, width, height, u, v, source_width, source_height, color, textured}`.
`x` and `y` are signed 32-bit values carried in `U32` bits.

| Function | Contract |
| --- | --- |
| `Q.fill(x, y, w, h, rgba)` | A flat rectangle. |
| `Q.image(x, y, w, h, u, v, sw, sh, rgba)` | A rectangle sampling the texel region `(u, v, sw, sh)` of the texture, multiplied by `rgba` (`0xFFFFFFFF` leaves the texels unchanged). Sampling is nearest-neighbor. |
| `Q.pack(quads)` | Instance words, 10 per quad; what `draw` uploads. |
| `Q.leaves(image, x, y, side, w, h, acc)` | Every leaf of a `Base.Image` quadtree as one opaque quad, clipped to `w` x `h`. |
| `Q.raster(image, array, x, y, side, w, h)` | The quadtree as a row-major `w` x `h` RGBA8 array, ready for `upload`. |
| `Q.side(w, h)` | The power-of-two side of the quadtree covering `w` x `h`. |
| `Q.opaque(rgb)` | `0xRRGGBB` to `0xRRGGBBFF`. |

`Base.Image` leaves are `0xRRGGBB`, the format Chromi's `finish` produces.
Blending is straight-alpha source-over in encoded sRGB, matching Chromi.

## Lower layers

`policy.bend` holds the selection rules (`best`, `family`, `memory`, `format`,
`present_mode`, `image_count`, `extent`, `alpha`), `commands.bend` the
command list (`Cmd`, `encode`, `valid`, `frame`, `upload`, `to_render`,
`to_present`) and `native.bend` the raw effects documented in
[bridge.md](bridge.md). Applications should prefer `gpu.bend`; the lower
layers are public because Bend modules have no export boundary, and they may
change.
