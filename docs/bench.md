# Presentation benchmarks

Two programs present the same Chromi frame (the scene of
`examples/scene.bend`, 960x630) for 600 frames:

- `bench/xput.bend`: the official Bend `Window`. Each `Window.frame` expands
  the quadtree into pixels on the CPU and sends them with `XPutImage`; the
  runtime paces frames at 60 Hz.
- `bench/gpu.bend`: Voltra, in a fixed-size window. Arguments choose the
  per-frame work: none (content unchanged: the texture was uploaded once, each
  frame only draws), `upload` (content changes every frame: raster in Bend,
  upload, draw), `leaves` (the quadtree's leaves rebuilt as quads every frame,
  no texture), and `novsync` (IMMEDIATE instead of FIFO).

Both read their own CPU time (user + system, all threads) from
`/proc/self/stat` before and after the 600 frames, so startup and device
creation are excluded. The tick is 10 ms; per-frame values are total ticks
divided by 600. Every GPU run polls window events once per frame.

```sh
bend bench/xput.bend -o build/bench-xput
bend bench/gpu.bend -o build/bench-gpu
for run in "xput" "gpu" "gpu novsync" "gpu upload" "gpu upload novsync" "gpu leaves novsync"; do
  set -- $run; bin=./build/bench-$1; shift
  $bin "$@" --threads 2 --gpu off
done
```

## Results

Machine: NVIDIA GeForce RTX 3050 Laptop GPU, driver 610.57.04, Vulkan 1.4.341,
Hyprland 0.56.2 with XWayland, two 1920x1080 displays at 120 Hz, Bend 2.0.35.
Three runs (2026-10-06):

| Run | 600 frames | CPU ticks | CPU per frame |
| --- | --- | --- | --- |
| xput | 9986 / 9986 / 9986 ms | 75 / 72 / 69 | 1250 / 1200 / 1150 µs |
| gpu (FIFO) | 2947 / 4915 / 4936 ms | 16 / 30 / 17 | 266 / 500 / 283 µs |
| gpu novsync | 152 / 128 / 108 ms | 14 / 11 / 10 | 233 / 183 / 166 µs |
| gpu upload (FIFO) | 2986 / 4967 / 4956 ms | 75 / 138 / 109 | 1250 / 2300 / 1816 µs |
| gpu upload novsync | 695 / 1932 / 716 ms | 44 / 137 / 46 | 733 / 2283 / 766 µs |
| gpu leaves novsync | 3095 / 3121 / 3077 ms | 311 / 314 / 309 | 5183 / 5233 / 5150 µs |

Every GPU run ended with `teardown: 0 native objects left; driver messages:
0 warnings, 0 errors`. The `upload` rows varied between runs; the cause was
not isolated. Earlier runs the same day,
with the same programs, measured 1383–1483 µs per frame for `xput`.

Reading the table:

- With unchanged content, Voltra spends 0.17–0.50 ms of CPU per presented
  frame against 1.15–1.25 ms for the `XPutImage` path, which must expand the
  quadtree and transfer 2.4 MB to the X server every frame.
- New content every frame costs the raster (about 605k array writes in Bend)
  plus a 2.4 MB copy to a staging buffer and a GPU copy; that keeps it near
  the `XPutImage` path's CPU cost while presenting at a much higher rate.
- Rebuilding 21,948 leaf quads in Bend every frame is the slowest path for
  this content. Leaves mode suits frames with few uniform regions, or frames
  whose quads are kept between draws.
- Under FIFO, 600 frames took 2.9–4.9 s (about 120–200 fps): on this XWayland
  setup presentation was not always held to the 120 Hz refresh.

## Idle

With nothing changing, the examples draw only when `pending` and otherwise
wait without a deadline. Over 10 s of idle (`/proc/<pid>/stat` sampled
externally):

- Voltra (`examples/chromi.bend`, `examples/quads.bend`): 0 frames presented,
  1–2 ticks of CPU (at most 20 ms), main thread 0 context switches (parked in
  `poll`). NVIDIA driver threads (`[vkrt]`, `[vkps]` and one unnamed) wake
  about 134 times per second in futex waits, with or without Bend worker
  threads (`--threads 1` or `2`).
- Official `Window` loop with unchanged content (`bench/xput.bend`): 600
  frames per 10 s and 69–89 ticks of CPU per 10 s. The official loop has no
  wait-for-events mode, so it keeps presenting.

## Pixel check

`examples/reference.bend` writes the frame, rasterized exactly as Voltra
uploads it, to `build/reference-960x630.ppm`. Captures of Voltra's window at
960x630 (`grim -T`, the window only) match it in all 604,800 pixels, in
texture mode and in leaves mode (`magick compare -metric AE` reports 0).
