# Examples

| File | What it shows |
| --- | --- |
| [hello.bend](hello.bend) | The smallest program: one quad, then a clean teardown. |
| [quads.bend](quads.bend) | Flat and textured quads, a checkerboard texture built in Bend, a layout that follows resizes, idle waiting. |
| [chromi.bend](chromi.bend) | A frame drawn by Chromi on the CPU and presented by Voltra, as one texture or as one quad per quadtree leaf (M toggles; `leaves` argument starts there). Click re-renders. |
| [scene.bend](scene.bend) | The Chromi scene shared by `chromi.bend`, `reference.bend` and the benchmarks. |
| [reference.bend](reference.bend) | Writes the Chromi frame, rasterized as Voltra uploads it, to `build/reference-960x630.ppm` for pixel comparison. |

`chromi.bend`, `scene.bend` and `reference.bend` import `../../Chromi`: clone
Chromi beside Voltra (see the README for the tested revision). Run every
example from the repository root, for example
`bend examples/quads.bend -o build/quads && ./build/quads --threads 2 --gpu off`.
`reference.bend` writes its output relative to the current directory.
