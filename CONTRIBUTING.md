# Contributing to Voltra

Use Bend 2.0.35 for the current baseline. Read `bend guide` and
`bend guide effects` before editing Bend or the bridge, and keep project text
in English. Library logic belongs in Bend; the native bridge stays a thin
layer of Xlib and Vulkan calls.

## Validation

From the repository root:

```sh
export BEND_NO_TELEMETRY=1
mkdir -p build
bend tests.bend -o build/tests
./build/tests --threads 2 --gpu off
bend examples/quads.bend -o build/quads
```

The native checks run without a display or GPU. When a change affects
presentation, run `build/quads` (and `examples/chromi.bend` with Chromi beside
Voltra) on a real window: resize it, close it normally, and confirm the last
line reads `teardown: 0 native objects left; driver messages: 0 warnings,
0 errors`. A successful build alone does not validate the experience.

When the bridge's Vulkan declarations change, compare them with the Khronos
headers (Vulkan-Headers 1.3 or newer; any directory containing
`vulkan/vulkan.h`):

```sh
python3 native/abi_check.py /path/to/include
```

When a shader changes, rebuild the SPIR-V and its Bend embedding with
`sh shaders/build.sh` (needs `glslc` and `spirv-val`) and commit all three.

Build one target at a time. The Bend runtime reserves substantial virtual
address space; a virtual-memory limit is not a resident-memory limit. Preserve
crash evidence and investigate before repeating a failed compiler invocation.

## Measurements

Performance claims need numbers. `bench/xput.bend` and `bench/gpu.bend`
present the same frame through the official window and through Voltra; see
[docs/bench.md](docs/bench.md) for the method. Report ranges over repeated
runs and distinguish presentation cost from content rendering.

## Changes

Keep the API small and ownership explicit. Add a focused native check when
Bend-side behavior changes, update the affected documents, and report what was
actually validated.

Use English commit messages that explain the result. Do not commit `build/`,
generated C, logs, captures that show anything but Voltra's own window, crash
dumps, credentials or machine-specific paths. Do not publish BendHub packages
or create releases as a side effect of validation.
