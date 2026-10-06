# Presentation benchmarks

Two programs present the same Chromi frame (the scene of
`examples/scene.bend`, 960x630) for 600 frames:

- `bench/xput.bend`: the official Bend `Window`. Each `Window.frame` expands
  the quadtree into pixels on the CPU and sends them with `XPutImage`; the
  runtime paces frames at 60 Hz.
- `bench/gpu.bend`: Voltra, in a fixed-size Ankra window. Arguments choose the
  per-frame work: none (content unchanged: the texture was uploaded once, each
  frame only draws), `upload` (content changes every frame: raster in Bend,
  upload, draw), `leaves` (the quadtree's leaves rebuilt as quads every frame,
  no texture), and `novsync` (IMMEDIATE instead of FIFO).

Both read their own CPU time (user + system, all threads) from
`/proc/self/stat` before and after the 600 frames, so startup and device
creation are excluded. The tick is 10 ms; per-frame values are total ticks
divided by 600. Every GPU run polls Ankra's window events once per frame.

```sh
bend bench/xput.bend -o build/bench-xput
bend bench/gpu.bend -o build/bench-gpu
for run in "xput" "gpu" "gpu novsync" "gpu upload" "gpu upload novsync" "gpu leaves novsync"; do
  set -- $run; bin=./build/bench-$1; shift
  $bin "$@" --threads 2 --gpu off
done
```

The windows were opened through the window manager on a workspace of the
laptop display, floating and without taking keyboard focus.

## Results

Machine: NVIDIA GeForce RTX 3050 Laptop GPU, driver 610.57.04, Vulkan 1.4.341,
Hyprland 0.56.2 with XWayland, two 1920x1080 displays at 120 Hz, Bend 2.0.35.
Three runs (2026-10-06, after the window moved to Ankra and the pipeline to
16-word quads):

| Run | 600 frames | CPU ticks | CPU per frame |
| --- | --- | --- | --- |
| xput | 9987 / 9986 / 9987 ms | 72 / 70 / 75 | 1200 / 1166 / 1250 µs |
| gpu (FIFO) | 4546 / 4527 / 4534 ms | 18 / 19 / 19 | 300 / 316 / 316 µs |
| gpu novsync | 101 / 104 / 111 ms | 10 / 9 / 10 | 166 / 150 / 166 µs |
| gpu upload (FIFO) | 4556 / 4558 / 4561 ms | 73 / 76 / 72 | 1216 / 1266 / 1200 µs |
| gpu upload novsync | 712 / 685 / 710 ms | 45 / 42 / 45 | 750 / 700 / 750 µs |
| gpu leaves novsync | 4776 / 4721 / 4681 ms | 479 / 475 / 470 | 7983 / 7916 / 7833 µs |

Every GPU run ended with `teardown: 0 native objects left; driver messages:
0 warnings, 0 errors` and `window objects left: 0`.

Reading the table:

- With unchanged content, Voltra spends 0.15–0.32 ms of CPU per presented
  frame against 1.17–1.25 ms for the `XPutImage` path, which must expand the
  quadtree and transfer 2.4 MB to the X server every frame.
- New content every frame costs the raster (about 605k array writes in Bend)
  plus a 2.4 MB copy to a staging buffer and a GPU copy.
- Rebuilding 21,948 leaf quads in Bend every frame is the slowest path for
  this content, and slower than before the pipeline's quads grew from 10 to
  16 words (5.15–5.23 ms earlier the same day). Leaves suit frames with few
  uniform regions; whole UI frames go through Chromi's draw list instead.
- Under FIFO, 600 frames took 4.5 s (about 132 fps on this 120 Hz machine).

Earlier runs the same day, with Voltra still opening its own window,
measured 2.9–4.9 s under FIFO and 1150–1250 µs per frame for `xput`.

## Idle

With nothing changing, the examples draw only when content is stale and
otherwise wait without a deadline in Ankra's loop. Sampled externally
(`/proc/<pid>/stat` and each thread's context switches) over 10 s of idle
for Chromi's integrated demo (`examples/eco` in Chromi): 0 frames presented,
2–3 ticks of CPU, main thread 0–3 context switches. NVIDIA driver threads
inside the process wake on their own: `[vkrt]` about 10 times per second,
`[vkps]` about 4, and one unnamed thread about 100. The official loop with
unchanged content keeps presenting about 58 frames per second (75–97 ticks
per 10 s for that demo's scene).

## Pixel check

`examples/reference.bend` writes the frame, rasterized exactly as Voltra
uploads it, to `build/reference-960x630.ppm`. Captures of Voltra's window at
960x630 (`grim -T`, the window only) match it in all 604,800 pixels
(`magick compare -metric AE` reports 0). `gpu_tests.bend` checks every quad
kind offscreen against values computed in Bend, without a display.
