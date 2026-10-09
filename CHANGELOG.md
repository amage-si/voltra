# Changelog

All notable changes to Voltra are recorded here. Voltra follows
[semantic versioning](https://semver.org) in its 0.x form: while the API is
experimental, a minor version (0.2.0) may change it in breaking ways and a
patch version (0.1.1) only fixes. Voltra is built from source together with its
sibling AMAGE libraries; the set of versions tested together is listed in
[eco-build's releases](https://github.com/amage-si/eco-build/tree/main/releases).

## [0.1.1] - 2026-10-09

### Changed

- Build with Bend 2.0.36: the native bridge registers its 38 effects as
  `io_eff(CID(name), run)`, the form 2.0.36 requires (upstream #1281 removed
  the third `need` argument). No effect parks, so behaviour is unchanged. No
  API change.

## [0.1.0] - 2026-10-09

First tagged release, tested with Bend 2.0.35 on Linux (X11/XWayland) as part
of AMAGE Eco 0.1.0.

### Included

- Vulkan device selection, Xlib surface from Ankra's window, swapchain
  rebuilt on resize and out-of-date presents.
- One instanced 2D pipeline of 16-word quads (flat, image, coverage mask,
  rounded box, ring) with integer coverage rules shared with Chromi's CPU path.
- Retained canvas with partial redraws and incremental present
  (`VK_KHR_incremental_present`).
- A persistent GPU quad store, so kept parts are drawn without re-uploading
  their words; quads and texels are written straight into arrays.
- Textures, atlas (`atlas.bend`), the persistent key map `keys.bend`,
  offscreen targets and readback.
- 79 native checks plus GPU checks, pixel-identical to the CPU reference.

[0.1.1]: https://github.com/amage-si/voltra/releases/tag/v0.1.1
[0.1.0]: https://github.com/amage-si/voltra/releases/tag/v0.1.0
