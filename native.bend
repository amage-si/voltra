import Base

# The native bridge: one Bend effect per thin Vulkan call, implemented in
# native/voltra.c (native builds) and native/voltra.js (JS lane, always
# ENOTSUP). Voltra opens no window: surfaces are made from the native
# window words that Ankra hands over (see vk_surface). Objects are U32 slot
# ids; 0 means "none". Word layouts are documented beside each effect in
# native/voltra.c and in docs/bridge.md. Prefer the typed API in gpu.bend;
# these are the raw calls it composes.

# Instance, GPUs and devices

def vk_instance(flags: U32) ->
  IO(Result<&1, &1, U32 & String, List<&2, U32>>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_gpus(instance: U32) ->
  IO(Result<&1, &1, U32 & String, List<&2, U32>>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_gpu_name(instance: U32, gpu: U32) ->
  IO(Result<&1, &1, U32 & String, String>):
  import "./native/voltra.c"
  import "./native/voltra.js"

# native: [kind (1 = Xlib), Display* high word, Display* low word, window
# id, screen], as Ankra's `native` answers.
def vk_surface(instance: U32, native: List<&2, U32>) ->
  IO(Result<&1, &1, U32 & String, U32>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_queue_families(instance: U32, gpu: U32, surface: U32) ->
  IO(Result<&1, &1, U32 & String, List<&2, U32>>):
  import "./native/voltra.c"
  import "./native/voltra.js"

# flags bit 0: VK_KHR_incremental_present when offered. Answers [slot,
# incremental_present_on].
def vk_device(instance: U32, gpu: U32, family: U32, flags: U32) ->
  IO(Result<&1, &1, U32 & String, List<&2, U32>>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_memory_types(device: U32) ->
  IO(Result<&1, &1, U32 & String, List<&2, U32>>):
  import "./native/voltra.c"
  import "./native/voltra.js"

# Presentation

def vk_surface_info(device: U32, surface: U32) ->
  IO(Result<&1, &1, U32 & String, List<&2, U32>>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_swapchain(device: U32, surface: U32, desc: List<&2, U32>, old: U32) ->
  IO(Result<&1, &1, U32 & String, U32>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_swapchain_images(device: U32, swapchain: U32) ->
  IO(Result<&1, &1, U32 & String, List<&2, U32>>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_acquire(device: U32, swapchain: U32, semaphore: U32, ms: U32) ->
  IO(Result<&1, &1, U32 & String, List<&2, U32>>):
  import "./native/voltra.c"
  import "./native/voltra.js"

# rects: (x, y, width, height) words of the regions that changed, at most
# 64 of them, or Nil (VK_KHR_incremental_present).
def vk_present(device: U32, swapchain: U32, index: U32, semaphore: U32,
  rects: List<&2, U32>) -> IO(Result<&1, &1, U32 & String, U32>):
  import "./native/voltra.c"
  import "./native/voltra.js"

# Resources

def vk_buffer(device: U32, size: U32, usage: U32) ->
  IO(Result<&1, &1, U32 & String, List<&2, U32>>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_image(device: U32, desc: List<&2, U32>) ->
  IO(Result<&1, &1, U32 & String, List<&2, U32>>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_alloc(device: U32, size: U32, memory_type: U32) ->
  IO(Result<&1, &1, U32 & String, U32>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_bind(device: U32, object: U32, memory: U32, offset: U32) ->
  IO(Result<&1, &1, U32 & String, Unit>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_map(device: U32, memory: U32) ->
  IO(Result<&1, &1, U32 & String, Unit>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_write(memory: U32, offset: U32, data: Array<U32>, count: U32) ->
  IO(Array<U32> & Result<&1, &1, U32 & String, Unit>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_read(memory: U32, offset: U32, data: Array<U32>, count: U32) ->
  IO(Array<U32> & Result<&1, &1, U32 & String, Unit>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_image_view(device: U32, image: U32, desc: List<&2, U32>) ->
  IO(Result<&1, &1, U32 & String, U32>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_sampler(device: U32, desc: List<&2, U32>) ->
  IO(Result<&1, &1, U32 & String, U32>):
  import "./native/voltra.c"
  import "./native/voltra.js"

# Descriptors, shaders, pipelines

def vk_set_layout(device: U32, desc: List<&2, U32>) ->
  IO(Result<&1, &1, U32 & String, U32>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_descriptor_pool(device: U32, sets: U32, desc: List<&2, U32>) ->
  IO(Result<&1, &1, U32 & String, U32>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_descriptor_set(device: U32, pool: U32, layout: U32) ->
  IO(Result<&1, &1, U32 & String, U32>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_write_image(device: U32, set: U32, desc: List<&2, U32>) ->
  IO(Result<&1, &1, U32 & String, Unit>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_shader(device: U32, code: Array<U32>, count: U32) ->
  IO(Array<U32> & Result<&1, &1, U32 & String, U32>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_pipeline_layout(device: U32, set_layout: U32, push_bytes: U32,
  push_stages: U32) -> IO(Result<&1, &1, U32 & String, U32>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_pipeline(device: U32, layout: U32, vertex: U32, fragment: U32,
  desc: List<&2, U32>) -> IO(Result<&1, &1, U32 & String, U32>):
  import "./native/voltra.c"
  import "./native/voltra.js"

# Commands and synchronization

def vk_command_pool(device: U32, flags: U32) ->
  IO(Result<&1, &1, U32 & String, U32>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_command_buffer(device: U32, pool: U32) ->
  IO(Result<&1, &1, U32 & String, U32>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_record(command: U32, ops: Array<U32>, count: U32) ->
  IO(Array<U32> & Result<&1, &1, U32 & String, Unit>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_semaphore(device: U32) -> IO(Result<&1, &1, U32 & String, U32>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_fence(device: U32, signaled: Bool) ->
  IO(Result<&1, &1, U32 & String, U32>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_wait(device: U32, fence: U32, ms: U32, reset: Bool) ->
  IO(Result<&1, &1, U32 & String, U32>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_submit(device: U32, command: U32, wait: U32, stage: U32,
  signal: U32, fence: U32) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def vk_idle(device: U32) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./native/voltra.c"
  import "./native/voltra.js"

# Lifetimes and counters

def destroy(slot: U32) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./native/voltra.c"
  import "./native/voltra.js"

def stats() -> IO(Result<&1, &1, U32 & String, List<&2, U32>>):
  import "./native/voltra.c"
  import "./native/voltra.js"
