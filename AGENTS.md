# Voltra: instructions for contributors and agents

Voltra is the GPU layer of the AMAGE UI ecosystem, implemented in **Bend 2**:
devices, presentation surfaces, swapchains, buffers, textures, pipelines,
command submission and synchronization. Read the README for current
capabilities and limits; a roadmap item is not implemented merely because it
appears in the project scope.

## Implementation

- Implement library logic in Bend 2. Do not wrap an existing renderer or
  toolkit (wgpu, SDL, bgfx, raylib, ...).
- The native bridge (`native/voltra.c` and its JS twin) stays thin and
  explicit: one effect per Vulkan call, or a field-by-field translation of
  Bend words into one Vulkan struct. Decisions belong in Bend: device and
  memory selection, formats, present modes, resize policy, barriers and
  layouts, command order, frames in flight, atlas placement, lifetimes and
  destruction order. If a new native call is needed, add the smallest one,
  document it in `docs/bridge.md`, and keep `native/abi_check.py` passing.
- Windows and their events belong to Ankra: Voltra makes its surface from the
  native window Ankra hands over and never opens a window or reads events.
- The shader's integer rules are a contract with Chromi's CPU reference
  (`Chromi/replay.bend`): change both together and keep `gpu_tests.bend`
  and Chromi's `gpu_tests.bend` at 0 differing pixels.
- The official Bend compiler/runtime, the OS, the Vulkan loader and the
  driver remain external dependencies.
- Before writing Bend, run `bend version` and read `bend guide` (and
  `bend guide effects` for the bridge) from the installed toolchain. Verify
  syntax and runtime internals instead of assuming older examples still work.
- Keep source, comments, documentation and commit messages in English.

## Linux first

The initial goal is excellent behavior on the actual Linux development
machine: correctness, stability, measured performance and a finished user
experience. Inspect the effective environment (driver, loader, layers,
compositor) before choosing integrations.

Build compatibility layers as the project progresses, after visible,
well-made Linux results. Do not let speculative platform abstractions delay
local quality. Introduce abstractions from concrete needs.

## Working practice

- Preserve existing work and keep the library's boundary clear: drawing
  belongs to Chromi, windows and input policy to Ankra.
- Favor simple, maintainable code. Back performance claims with measurements.
- Run the native checks after changes, and `gpu_tests.bend` when drawing
  changes. When presentation changes, run an example on a real window,
  capture only that window (its toplevel, never a screen region), check
  resize and normal closure, and confirm the teardown report (0 objects
  left, 0 driver messages).
- Compilation is not visual proof; a passing check is not proof of the whole
  system. State partial support and unverified behavior explicitly.
- Build sequentially and keep compilation units small; the Bend compiler can
  exhaust memory on large import graphs. Do not impose virtual-address limits
  on the Bend runtime or suppress crash reporting. Investigate failures
  before retrying.
- Keep generated binaries, logs, crash dumps, credentials and machine-specific
  evidence out of Git. Stage explicit paths and preserve concurrent changes.

See [CONTRIBUTING.md](CONTRIBUTING.md) for validation commands.
