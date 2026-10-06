# The native bridge

`native/voltra.c` is Voltra's only hand-written native code. Bend splices it
into the generated C program after the runtime (see `bend guide effects`);
`native/voltra.js` is the JavaScript twin every Bend effect needs, and it
answers `Fail` with ENOTSUP (95) for every call, so `bend file.bend` (the JS
lane) fails cleanly. The effects are declared in [native.bend](../native.bend).

## Shape of the bridge

- **One call per effect.** Each effect performs one Xlib or Vulkan call, or a
  fixed translation of Bend words into one Vulkan create-info struct and the
  call that consumes it. `vk_record` translates each command word into one
  `vkCmd*` call; it does not choose or reorder anything.
- **Slots.** Native objects live in a 4096-entry table and cross into Bend as
  `U32` slot ids (0 means none). The bridge checks that a slot is alive and of
  the expected kind, so a stale id fails instead of crashing. Lifetimes,
  ownership and destruction order are tracked in Bend (`gpu.bend`).
- **No SDK.** Vulkan is reached through `dlopen("libvulkan.so.1")` and
  `vkGetInstanceProcAddr`; no headers or link flags are needed. The bridge
  declares the Vulkan structs it uses (64-bit Linux ABI);
  `native/abi_check.py` compares their 483 sizes and offsets with the
  Khronos headers. Including `<X11/Xlib.h>` makes `bend` link libX11, the
  same rule the official Window effect relies on.
- **Arrays without copies.** Effects that take an `Array<U32>` (`vk_write`,
  `vk_shader`, `vk_record`) read its words in place and hand the array back.
  This uses runtime internals (`blk_loc`, `blk_cls`) that carry no ABI
  promise: rebuild and retest the bridge with every Bend update.
- **Failures** answer `Fail{(code, text)}`: `-VkResult` for a Vulkan error,
  22 (EINVAL) for a bad slot or argument, 24 (EMFILE) when the slot table is
  full, 95 (ENOTSUP) for a missing loader or display.

Size: 1,969 lines (1,594 non-blank, non-comment). About 490 of them are the
Vulkan declarations and the entry-point table, about 140 the slot table and
term helpers, and the rest the 40 effects (each with its `#ifdef` guard and
registration).

## Effects

All answer `IO(Result<&1, &1, U32 & String, T>)`; `vk_write`, `vk_shader`
and `vk_record` answer `IO(Array<U32> & Result<...>)`. Word lists are
`List<&2, U32>`.

### Window (Xlib)

| Effect | Native call | Arguments → answer |
| --- | --- | --- |
| `window_open(title, w, h, flags)` | `XOpenDisplay`, `XCreateSimpleWindow`, WM protocols, `XMapWindow` | Flags bit 0: fixed size. Background `None`, class `Voltra`. → window slot |
| `window_wait(win, ms)` | `XPending`/`XNextEvent`; parks on the X socket with `io_wait_on` | 0 polls, 4294967295 no deadline. → event words, 5 per event: `1` close; `2` configure w h; `3` expose; `4` key keysym down; `5` button x y button down; `6` motion x y; `7` focus in |
| `window_title(win, title)` | `XStoreName`, `_NET_WM_NAME` | → Unit |

### Instance, GPUs, device

| Effect | Native call | Arguments → answer |
| --- | --- | --- |
| `vk_instance(flags)` | `dlopen`, `vkCreateInstance` (1.3; `VK_KHR_surface`, `VK_KHR_xlib_surface`, `VK_EXT_debug_utils`), debug messenger | Flags bit 0: enable `VK_LAYER_KHRONOS_validation` if installed. → `[slot, layer_on]` |
| `vk_gpus(inst)` | `vkEnumeratePhysicalDevices`, properties, memory properties | → `[count, (type, vendor, device, api, driver, maxImage2D, deviceLocalMiB)*]` |
| `vk_gpu_name(inst, gpu)` | `vkGetPhysicalDeviceProperties` | → name |
| `vk_surface(inst, win)` | `vkCreateXlibSurfaceKHR` | → surface slot |
| `vk_queue_families(inst, gpu, surface)` | queue family properties, `vkGetPhysicalDeviceSurfaceSupportKHR` | → `(flags, count, presents)*` |
| `vk_device(inst, gpu, family)` | `vkCreateDevice` (one queue, `VK_KHR_swapchain`, dynamic rendering), `vkGetDeviceQueue` | → device slot |
| `vk_memory_types(dev)` | `vkGetPhysicalDeviceMemoryProperties` | → `[count, (flags, heap)*, heaps, (MiB, flags)*]` |

### Presentation

| Effect | Native call | Arguments → answer |
| --- | --- | --- |
| `vk_surface_info(dev, surface)` | surface capabilities, formats, present modes | → `[minImages, maxImages, curW, curH, minW, minH, maxW, maxH, transforms, currentTransform, compositeAlpha, usage, nFormats, (format, colorSpace)*, nModes, mode*]` |
| `vk_swapchain(dev, surface, desc, old)` | `vkCreateSwapchainKHR` | desc `[minImageCount, format, colorSpace, w, h, usage, preTransform, compositeAlpha, presentMode, clipped]`; `old` may be 0. → swapchain slot |
| `vk_swapchain_images(dev, sc)` | `vkGetSwapchainImagesKHR` | → image slots (owned by the swapchain) |
| `vk_acquire(dev, sc, semaphore, ms)` | `vkAcquireNextImageKHR` | → `[status, index]`; status 0 ready, 1 suboptimal, 2 out of date, 3 timeout |
| `vk_present(dev, sc, index, semaphore)` | `vkQueuePresentKHR` | → status 0 presented, 1 suboptimal, 2 out of date |

### Resources

| Effect | Native call | Arguments → answer |
| --- | --- | --- |
| `vk_buffer(dev, size, usage)` | `vkCreateBuffer`, `vkGetBufferMemoryRequirements` | → `[slot, size, alignment, typeBits]` |
| `vk_image(dev, desc)` | `vkCreateImage`, `vkGetImageMemoryRequirements` | desc `[w, h, format, usage, tiling]` (2D, one mip, one sample, UNDEFINED). → as `vk_buffer` |
| `vk_alloc(dev, size, type)` | `vkAllocateMemory` | → memory slot |
| `vk_bind(dev, object, memory, offset)` | `vkBindBufferMemory` / `vkBindImageMemory` | → Unit |
| `vk_map(dev, memory)` | `vkMapMemory` (whole allocation, persistent) | → Unit |
| `vk_write(memory, offset, array, count)` | `memcpy` into the mapping | Bounds-checked against the allocation and the array. → (array, Unit) |
| `vk_image_view(dev, image, desc)` | `vkCreateImageView` | desc `[format, swizzleR, swizzleG, swizzleB, swizzleA, aspect]`. → view slot |
| `vk_sampler(dev, desc)` | `vkCreateSampler` | desc `[magFilter, minFilter, addressMode]`. → sampler slot |

### Descriptors, shaders, pipelines

| Effect | Native call | Arguments → answer |
| --- | --- | --- |
| `vk_set_layout(dev, desc)` | `vkCreateDescriptorSetLayout` | desc `(binding, type, count, stages)*`, at most 8. → slot |
| `vk_descriptor_pool(dev, sets, desc)` | `vkCreateDescriptorPool` | desc `(type, count)*`, at most 8. → slot |
| `vk_descriptor_set(dev, pool, layout)` | `vkAllocateDescriptorSets` | → set slot (owned by the pool) |
| `vk_write_image(dev, set, desc)` | `vkUpdateDescriptorSets` | desc `[binding, type, view, sampler, layout]`. → Unit |
| `vk_shader(dev, code, count)` | `vkCreateShaderModule` | First `count` SPIR-V words of the array. → (array, slot) |
| `vk_pipeline_layout(dev, setLayout, pushBytes, pushStages)` | `vkCreatePipelineLayout` | One optional set layout (0: none), one push range. → slot |
| `vk_pipeline(dev, layout, vert, frag, desc)` | `vkCreateGraphicsPipelines` | desc `[colorFormat, topology, cullMode, frontFace, blendEnable, srcColor, dstColor, colorOp, srcAlpha, dstAlpha, alphaOp, writeMask, nBindings, (binding, stride, rate)*, nAttributes, (location, binding, format, offset)*]`; dynamic rendering, dynamic viewport and scissor, entry points `main`. → slot |

### Commands and synchronization

| Effect | Native call | Arguments → answer |
| --- | --- | --- |
| `vk_command_pool(dev, flags)` | `vkCreateCommandPool` on the device's family | → slot |
| `vk_command_buffer(dev, pool)` | `vkAllocateCommandBuffers` (primary) | → slot (owned by the pool) |
| `vk_record(cmd, ops, count)` | reset, begin (one-time submit), one `vkCmd*` per op, end | See below. → (array, Unit) |
| `vk_semaphore(dev)` | `vkCreateSemaphore` | → slot |
| `vk_fence(dev, signaled)` | `vkCreateFence` | → slot |
| `vk_wait(dev, fence, ms, reset)` | `vkWaitForFences`, then `vkResetFences` if `reset` | → 0 signaled, 1 timed out |
| `vk_submit(dev, cmd, wait, stage, signal, fence)` | `vkQueueSubmit` | Semaphores and fence may be 0. → Unit |
| `vk_idle(dev)` | `vkDeviceWaitIdle` | → Unit |
| `destroy(slot)` | the matching `vkDestroy*`/`vkFree*`, or `XDestroyWindow` + `XCloseDisplay` | Swapchain images, descriptor sets and command buffers only release their slot. → Unit |
| `stats()` | none | → `[liveSlots, warnings, errors, layerOn]` |

### Command words (`vk_record`)

| Op | Words | Call |
| --- | --- | --- |
| 1 | image oldLayout newLayout srcStage dstStage srcAccess dstAccess | `vkCmdPipelineBarrier` (one image barrier, color aspect) |
| 2 | view width height loadOp clearRGBA8 | `vkCmdBeginRendering` (one color attachment, store) |
| 3 | — | `vkCmdEndRendering` |
| 4 | x y width height | `vkCmdSetViewport` |
| 5 | x y width height | `vkCmdSetScissor` |
| 6 | pipeline | `vkCmdBindPipeline` (graphics) |
| 7 | layout set | `vkCmdBindDescriptorSets` (set 0) |
| 8 | layout stages count word* | `vkCmdPushConstants` (offset 0, at most 32 words) |
| 9 | binding buffer offset | `vkCmdBindVertexBuffers` |
| 10 | vertexCount instanceCount firstVertex firstInstance | `vkCmdDraw` |
| 11 | buffer image width height bufferOffset | `vkCmdCopyBufferToImage` (to TRANSFER_DST layout) |

`commands.bend` builds these words from `Cmd` values and checks the
structural rules (`valid`) before they reach the bridge.

## Why Voltra owns its window

The official `Window` effect does not expose its native handle, and it
presents with `XPutImage` from a fixed-size buffer. A Vulkan surface needs the
`Display*` and `Window`, so the bridge opens its own X11 window, handles its
events and lets the swapchain present into it.
