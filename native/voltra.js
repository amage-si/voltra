// Voltra native bridge: JavaScript twin
// =====================================
//
// Bend requires a JS file beside every effect's C file; it serves
// `bend file.bend` (checked and run in JS) and `-o file.js`. Voltra talks to
// Vulkan and Xlib, which the JS lane cannot reach, so every effect answers
// Fail with ENOTSUP (95). Effects that borrow an array hand it back first.

function voltra_unsupported() {
  return io_fail(95);
}

function voltra_unsupported_with(array) {
  return io_tup(array, io_fail(95));
}

for (const id of [
  CID(window_open), CID(window_wait), CID(window_title),
  CID(vk_instance), CID(vk_gpus), CID(vk_gpu_name),
  CID(vk_surface), CID(vk_queue_families),
  CID(vk_device), CID(vk_memory_types),
  CID(vk_surface_info), CID(vk_swapchain),
  CID(vk_swapchain_images), CID(vk_acquire),
  CID(vk_present), CID(vk_buffer), CID(vk_image),
  CID(vk_alloc), CID(vk_bind), CID(vk_map),
  CID(vk_image_view), CID(vk_sampler),
  CID(vk_set_layout), CID(vk_descriptor_pool),
  CID(vk_descriptor_set), CID(vk_write_image),
  CID(vk_pipeline_layout), CID(vk_pipeline),
  CID(vk_command_pool), CID(vk_command_buffer),
  CID(vk_semaphore), CID(vk_fence), CID(vk_wait),
  CID(vk_submit), CID(vk_idle), CID(destroy),
  CID(stats),
]) {
  io_eff(id, voltra_unsupported);
}

io_eff(CID(vk_write), (memory, offset, array) =>
  voltra_unsupported_with(array));
io_eff(CID(vk_shader), (device, array) =>
  voltra_unsupported_with(array));
io_eff(CID(vk_record), (cmd, array) =>
  voltra_unsupported_with(array));
