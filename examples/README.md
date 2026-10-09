# Examples

| File | What it shows |
| --- | --- |
| [hello.bend](hello.bend) | The smallest program: Ankra's window, one rounded quad, a clean teardown after two quiet seconds. |
| [quads.bend](quads.bend) | Flat and textured quads, a checkerboard texture built in Bend, a layout that follows resizes, idle waiting in Ankra's loop. |
| [motion.bend](motion.bend) | A rect sliding for 2 s at constant speed through Ankra's `Loop.animate`, positioned at each frame's `A.frame_time`, then idle (0 frames, 0 wakeups); Space or a click slides it again. Prints the monitor's refresh on start and on moves. `fifo` draws back to back instead and `log` prints the frame times, for the pacing measurements in [docs/bench.md](../docs/bench.md#animation-pacing). |
| [chromi.bend](chromi.bend) | A frame drawn by Chromi on the CPU and presented by Voltra, as one texture or as one quad per quadtree leaf (M toggles; `leaves` argument starts there). Click re-renders. |
| [scene.bend](scene.bend) | The Chromi scene shared by `chromi.bend`, `reference.bend` and the benchmarks. |
| [reference.bend](reference.bend) | Writes the Chromi frame, rasterized as Voltra uploads it, to `build/reference-960x630.ppm` for pixel comparison. |

Every windowed example imports `../../Ankra` (the window and its events):
clone Ankra beside Voltra. `chromi.bend`, `scene.bend` and `reference.bend`
also import `../../Chromi`. Keep the capitalized directory names. Run every
example from the repository root, for example
`bend examples/quads.bend -o build/quads && ./build/quads --threads 2 --gpu off`.
`reference.bend` writes its output relative to the current directory.

Whole UI frames drawn through Voltra's 2D quads (text, a button, a PNG and an
SVG, resizable) are Chromi's integrated demo, `Chromi/examples/eco`.
