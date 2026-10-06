# Voltra

**GPU access and presentation for Bend 2, on Vulkan.**

Voltra is the GPU layer of the AMAGE UI ecosystem. It opens a window, picks
a Vulkan device, builds a swapchain, uploads textures and draws colored and
textured quads, then presents, resizes and tears down cleanly. The library is
written in Bend 2; the only native code is a thin, documented bridge of Xlib
and Vulkan calls exposed as Bend effects.

**Status:** early Linux implementation, tested with **Bend 2.0.35** on an
NVIDIA GeForce RTX 3050 Laptop GPU (driver 610.57.04, Vulkan 1.4.341) under
Hyprland/XWayland. The first priority is a polished, measured experience on
the development Linux machine. Compatibility layers will follow proven progress.

![A Chromi frame presented by Voltra on the GPU, captured from its window.](docs/preview.png)

The capture above is a frame rendered by [Chromi](https://github.com/amageweb/chromi)
on the CPU and presented by Voltra on the GPU. It is identical, pixel for
pixel, to Chromi's own output (all 604,800 pixels).

## What works today

- Device selection: every Vulkan GPU is reported (type, vendor, device, API
  and driver versions, device-local memory, maximum image size), and the best
  Vulkan 1.3+ device that can present to the window is chosen.
- A window owned by Voltra, with close, resize, expose, key, button, motion
  and focus events. Waiting for events parks on the X connection: an idle
  application uses no CPU and presents no frames.
- A swapchain with explicit format, present mode (FIFO by default),
  image-count and composition choices, rebuilt on every real resize and on
  out-of-date or suboptimal presentation.
- Host-visible buffers, device-local textures, an RGBA8 upload path with
  explicit layout transitions, and a quad pipeline: instanced, straight-alpha
  source-over blending, encoded-sRGB values like Chromi's CPU composition.
- Two frames in flight with per-frame fences, semaphores, command buffers and
  growable instance buffers.
- Ordered teardown of every native object, reporting leaked objects and the
  driver warnings and errors seen during the run.

How it was verified on the development machine:

- **57 native checks** (`tests.bend`) of the Bend-side logic: policies,
  command encoding and validation, quad packing, quadtree conversion, event
  decoding and slot tracking. They need no display or GPU.
- **Visual:** both examples captured from their own windows at 941x1030
  (tiled), 960x630, 500x760, 1280x480 and 720x450; the content follows each size.
- **Pixel-exact:** the GPU-presented Chromi frame equals the CPU reference
  written by `examples/reference.bend`, in texture mode and in leaves mode.
- **Teardown:** every run ended with 0 native objects left and 0 driver
  warnings or errors. The Khronos validation layer is not installed on the
  development machine, so validation-layer coverage is still pending.
- **ABI:** `native/abi_check.py` compares 483 sizes and offsets of the bridge's
  Vulkan declarations with the official Khronos headers.

## Measurements

The same Chromi frame at 960x630, 600 frames per run, CPU time of the whole
process from `/proc/self/stat` (10 ms ticks), three runs each. Method and raw
output: [docs/bench.md](docs/bench.md).

| Path | Wall time per frame | CPU per frame |
| --- | --- | --- |
| Official `Window` (CPU quadtree fill + `XPutImage`, runtime paced at 60 Hz) | 16.6 ms | 1.15–1.25 ms |
| Voltra, unchanged content, FIFO | 4.9–8.2 ms | 0.27–0.50 ms |
| Voltra, unchanged content, IMMEDIATE | 0.18–0.25 ms | 0.17–0.23 ms |
| Voltra, new content every frame (raster in Bend + 2.4 MB upload), IMMEDIATE | 1.2–3.2 ms | 0.73–2.28 ms |
| Voltra, 21,948 quadtree leaves rebuilt as quads every frame, IMMEDIATE | 5.1–5.2 ms | 5.15–5.23 ms |

Idle, nothing changing, 10 s: Voltra presents **0 frames** and uses 1–2 ticks
(at most 20 ms, ≤ 0.2 % of one core); its main thread makes 0 wakeups. The
official loop keeps presenting 60 frames per second and uses 69–89 ticks per
10 s. NVIDIA driver threads inside the process wake about 134 times per second
while idle; they are present with `--threads 1` as well.

## Quick start

Requirements: the [Bend 2 toolchain](https://bend-lang.com), Clang 14 or newer,
X11 development headers/libraries, a Vulkan 1.3 driver with its loader
(`libvulkan.so.1`), and an X11 or XWayland display. No Vulkan SDK or headers
are needed to build.

```sh
git clone https://github.com/amageweb/voltra.git Voltra
cd Voltra
export BEND_NO_TELEMETRY=1
bend version
mkdir -p build
bend tests.bend -o build/tests
./build/tests --threads 2 --gpu off
```

Open the quad example (colored quads and a texture made in Bend):

```sh
bend examples/quads.bend -o build/quads
./build/quads --threads 2 --gpu off
```

![The quad example at 960x630: flat quads and two textured quads.](docs/quads.png)

Resize the window to watch the layout follow; close it normally. The program
prints the device report, frames presented, swapchain rebuilds and the
teardown result.

The Chromi example needs Chromi beside Voltra, keeping the capitalized
directory names because Bend imports are case-sensitive:

```sh
git clone https://github.com/amageweb/chromi.git ../Chromi
git -C ../Chromi checkout --detach 665a18b84900cfe533df87155e77b4e49dd1f92b
bend examples/chromi.bend -o build/chromi
./build/chromi --threads 2 --gpu off          # texture mode
./build/chromi leaves --threads 2 --gpu off   # one quad per quadtree leaf
```

Click to change the accent color, press M to switch modes, and press Escape
or close the window to exit. `--gpu off` refers to Bend's `!` compute offload,
which Voltra does not use.

## Using it

```bend
import Base
import ./Voltra/gpu.bend as V
import ./Voltra/quads.bend as Q

def main() -> IO(Unit):
  do IO<Unit>:
    +g : V.Gpu <- V.open("Hello", 640, 400, True{}, True{})
    +g1 : V.Gpu <- V.draw(g, [Q.fill(40, 40, 200, 120, 4282664191)], 255)
    +es : List<&2, V.Input> <- V.wait(g1, 2000)
    +report : V.Report <- V.close(g1)
    IO.print(V.report.show(report))
```

The context is a value: every call returns the next `Gpu`. Colors are
straight RGBA8 packed `0xRRGGBBAA`; coordinates are physical pixels from the
top left. Read the [API reference](docs/api.md), the
[bridge reference](docs/bridge.md) and the [examples](examples/).

## The native bridge

`native/voltra.c`, with the JS twin Bend requires (`native/voltra.js`, which
answers ENOTSUP), exposes 40 effects. Each one is a single Xlib or Vulkan call,
or a field-by-field translation of Bend words into one Vulkan create-info
struct. Objects cross into Bend as `U32` slot ids. Bend decides everything
else: which GPU, queue family, memory type, format, present mode and image
count; when to rebuild the swapchain; barriers, layouts and command order;
frames in flight; and the order in which objects are destroyed.

Vulkan is loaded with `dlopen("libvulkan.so.1")`, and the bridge declares the
Vulkan types it uses, checked against the Khronos headers by
`native/abi_check.py`. Shaders are GLSL compiled to SPIR-V by
`shaders/build.sh`; the SPIR-V and its Bend embedding are checked in.

## Current boundaries

- Linux with an Xlib surface (XWayland under Wayland compositors). Native
  Wayland surfaces, other platforms and multiple windows are not implemented.
- One Vulkan instance per process and one RGBA8 texture per context. There
  is no texture atlas, mipmapping, partial upload, depth buffer, MSAA, custom
  shader or user pipeline yet; the quad is the only primitive.
- Uploads are synchronous: they wait for the GPU to finish in-flight frames.
- Hard failures (a Vulkan error, no usable GPU) end the program with the
  driver's message instead of returning an error value.
- Under FIFO the frame rate on XWayland reached about 200 fps in some runs on
  this 120 Hz machine; frame pacing is left to the compositor and was not tuned.
- The Khronos validation layer was not installed during development; only
  driver messages through `VK_EXT_debug_utils` were observed (none).
- Bend's checker reports `SOME PROOFS FAIL` for every def that reaches the
  foreign effects. That is expected: foreign code is outside Bend's proofs.

## Repository map

| Path | Purpose |
| --- | --- |
| [gpu.bend](gpu.bend) | Context, swapchain, frames, upload, draw, events, teardown. |
| [policy.bend](policy.bend) | GPU, queue, memory, format, present-mode and extent choices. |
| [commands.bend](commands.bend) | Command list, encoding, validation and barrier policy. |
| [quads.bend](quads.bend) | Quads, instance packing, quadtree leaves and rasterization. |
| [words.bend](words.bend), [vk.bend](vk.bend) | Word helpers and named Vulkan values. |
| [native.bend](native.bend) | The bridge's effect declarations. |
| [native/](native/) | The native bridge, its JS twin and the ABI check. |
| [shaders/](shaders/) | GLSL sources, SPIR-V and the reproducible build script. |
| [tests.bend](tests.bend) | Native checks that run without a display or GPU. |
| [examples/](examples/) | Hello, quads, the Chromi frame on the GPU, the CPU reference. |
| [bench/](bench/) | The `XPutImage` and GPU presentation benchmarks. |
| [docs/](docs/) | API, bridge and benchmark references. |

## Direction

Next: a texture atlas and partial uploads for glyphs and images, damage-aware
redraw, native Wayland surfaces, validation-layer runs, and integration with
Chromi and Ankra so the ecosystem's windows present through the GPU. These
are goals, not supported features.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development rules. The API is
experimental and may change. A distribution license has not yet been selected.
