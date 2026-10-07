import Base

# Vulkan enum and flag values used by Voltra, named in Bend. The bridge
# passes them through untouched; every choice of value is made here or by
# the policies in policy.bend. Values are from the Vulkan 1.3 registry.

# VkPhysicalDeviceType
def gpu_other() -> U32: 0
def gpu_integrated() -> U32: 1
def gpu_discrete() -> U32: 2
def gpu_virtual() -> U32: 3
def gpu_cpu() -> U32: 4

# VkQueueFlags
def queue_graphics() -> U32: 1
def queue_compute() -> U32: 2
def queue_transfer() -> U32: 4

# VkMemoryPropertyFlags
def mem_device_local() -> U32: 1
def mem_host_visible() -> U32: 2
def mem_host_coherent() -> U32: 4

# VkFormat
def format_r8g8b8a8_unorm() -> U32: 37
def format_b8g8r8a8_unorm() -> U32: 44
def format_r32g32_uint() -> U32: 101
def format_r32g32b32a32_uint() -> U32: 107
def format_r32g32b32a32_sint() -> U32: 108

# VkColorSpaceKHR, VkPresentModeKHR
def srgb_nonlinear() -> U32: 0
def present_immediate() -> U32: 0
def present_mailbox() -> U32: 1
def present_fifo() -> U32: 2
def present_fifo_relaxed() -> U32: 3

# VkImageUsageFlags, VkBufferUsageFlags
def image_transfer_src() -> U32: 1
def image_transfer_dst() -> U32: 2
def image_sampled() -> U32: 4
def image_color_attachment() -> U32: 16
def buffer_transfer_src() -> U32: 1
def buffer_transfer_dst() -> U32: 2
def buffer_vertex() -> U32: 128

# VkImageLayout
def layout_undefined() -> U32: 0
def layout_color_attachment() -> U32: 2
def layout_shader_read() -> U32: 5
def layout_transfer_src() -> U32: 6
def layout_transfer_dst() -> U32: 7
def layout_present() -> U32: 1000001002

# VkPipelineStageFlags
def stage_top() -> U32: 1
def stage_vertex_shader() -> U32: 8
def stage_fragment_shader() -> U32: 128
def stage_color_output() -> U32: 1024
def stage_transfer() -> U32: 4096
def stage_bottom() -> U32: 8192
def stage_host() -> U32: 16384

# VkAccessFlags
def access_none() -> U32: 0
def access_shader_read() -> U32: 32
def access_color_read() -> U32: 128
def access_color_write() -> U32: 256
def access_transfer_read() -> U32: 2048
def access_transfer_write() -> U32: 4096
def access_host_read() -> U32: 8192

# VkComponentSwizzle, VkImageAspectFlags, VkFilter, VkSamplerAddressMode
def swizzle_identity() -> U32: 0
def swizzle_r() -> U32: 3
def swizzle_g() -> U32: 4
def swizzle_b() -> U32: 5
def swizzle_a() -> U32: 6
def aspect_color() -> U32: 1
def filter_nearest() -> U32: 0
def filter_linear() -> U32: 1
def address_clamp_to_edge() -> U32: 2

# VkImageTiling, VkDescriptorType, VkShaderStageFlags
def tiling_optimal() -> U32: 0
def descriptor_combined_sampler() -> U32: 1
def shader_vertex() -> U32: 1
def shader_fragment() -> U32: 16

# Pipeline state: topology, cull, front face, blend factors and ops
def topology_triangle_list() -> U32: 3
def cull_none() -> U32: 0
def front_counter_clockwise() -> U32: 0
def blend_zero() -> U32: 0
def blend_one() -> U32: 1
def blend_src_alpha() -> U32: 6
def blend_one_minus_src_alpha() -> U32: 7
def blend_add() -> U32: 0
def color_write_rgba() -> U32: 15
def rate_vertex() -> U32: 0
def rate_instance() -> U32: 1

# VkAttachmentLoadOp, VkCompositeAlphaFlags, VkSurfaceTransformFlags
def load_load() -> U32: 0
def load_clear() -> U32: 1
def composite_opaque() -> U32: 1
def transform_identity() -> U32: 1

# VkCommandPoolCreateFlags: command buffers may be reset one by one
def pool_reset_buffer() -> U32: 2
