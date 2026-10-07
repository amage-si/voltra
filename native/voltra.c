// Voltra native bridge
// ====================
//
// The only hand-written native code in Voltra. Bend splices this file into
// the generated C program after its runtime (see `bend guide effects`), so
// every runtime helper (Term, Env, io_done, io_fail, io_node, ...) is in
// scope. It is not a renderer: each effect below is one Vulkan call, or a
// fixed, field-by-field translation of Bend words into one Vulkan
// create-info struct. Every decision -- which GPU, queue, format, present
// mode, memory type, image count, barrier, layout, command order, frame
// pacing, resize policy and destruction order -- is made by the Bend caller.
//
// Voltra opens no window. The presentation surface is made from the native
// window that Ankra (the platform layer) hands over as words: the Xlib
// Display* and the X window id. The display stays Ankra's; it must outlive
// the surface.
//
// Objects cross into Bend as U32 slot ids into the table below. Bend owns
// their lifetimes (gpu.bend); the bridge only checks that a slot is alive
// and of the expected kind, so a stale id fails instead of crashing.
//
// Vulkan is reached through `dlopen("libvulkan.so.1")` and
// vkGetInstanceProcAddr, so the build needs no Vulkan headers or link flags.
// The few Vulkan declarations this file uses are written out below and are
// checked against the official Khronos headers by native/abi_check.py.
// <X11/Xlib.h> provides the Display and Window types of the Xlib surface.
//
// Failures answer `Fail{(code, text)}`: code is -VkResult for a Vulkan error,
// 22 (EINVAL) for a bad slot or argument, 95 (ENOTSUP) for a missing loader
// or an unsupported native window kind, 24 (EMFILE) when the slot table is
// full.

#include <dlfcn.h>
#include <X11/Xlib.h>

// Vulkan declarations (subset of vulkan_core.h / vulkan_xlib.h, 64-bit)
// -------------------------------------------------------------------

typedef int32_t  VkResult;
typedef uint32_t VkFlags;
typedef uint32_t VkBool32;
typedef uint64_t VkDeviceSize;
typedef uint32_t VkEnum;  // every Vulkan enum is a 32-bit int

typedef struct VkInstance_T*       VkInstance;
typedef struct VkPhysicalDevice_T* VkPhysicalDevice;
typedef struct VkDevice_T*         VkDevice;
typedef struct VkQueue_T*          VkQueue;
typedef struct VkCommandBuffer_T*  VkCommandBuffer;
typedef uint64_t VkHandle;  // every non-dispatchable handle (64-bit ABI)

typedef void (*PFN_vkVoidFunction)(void);
typedef PFN_vkVoidFunction (*PFN_vkGetInstanceProcAddr)(VkInstance,
  const char*);

typedef struct { uint32_t width, height; } VkExtent2D;
typedef struct { uint32_t width, height, depth; } VkExtent3D;
typedef struct { int32_t x, y; } VkOffset2D;
typedef struct { int32_t x, y, z; } VkOffset3D;
typedef struct { VkOffset2D offset; VkExtent2D extent; } VkRect2D;
typedef struct { float x, y, width, height, minDepth, maxDepth; } VkViewport;
typedef union { float float32[4]; int32_t int32[4]; uint32_t uint32[4]; }
  VkClearValue;

typedef struct {
  VkEnum sType; const void* pNext; const char* pApplicationName;
  uint32_t applicationVersion; const char* pEngineName;
  uint32_t engineVersion; uint32_t apiVersion;
} VkApplicationInfo;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags;
  const VkApplicationInfo* pApplicationInfo; uint32_t enabledLayerCount;
  const char* const* ppEnabledLayerNames; uint32_t enabledExtensionCount;
  const char* const* ppEnabledExtensionNames;
} VkInstanceCreateInfo;

typedef struct {
  char layerName[256]; uint32_t specVersion; uint32_t implementationVersion;
  char description[256];
} VkLayerProperties;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; const char* pMessageIdName;
  int32_t messageIdNumber; const char* pMessage;
  // (label and object arrays follow; unused)
} VkDebugUtilsMessengerCallbackDataEXT;

typedef VkBool32 (*PFN_vkDebugUtilsMessengerCallbackEXT)(VkFlags, VkFlags,
  const VkDebugUtilsMessengerCallbackDataEXT*, void*);

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; VkFlags messageSeverity;
  VkFlags messageType; PFN_vkDebugUtilsMessengerCallbackEXT pfnUserCallback;
  void* pUserData;
} VkDebugUtilsMessengerCreateInfoEXT;

// Only the leading fields are read; `tail` covers VkPhysicalDeviceLimits
// (whose first two words are maxImageDimension1D/2D) and the sparse
// properties, keeping the official size and alignment.
typedef struct {
  uint32_t apiVersion, driverVersion, vendorID, deviceID; VkEnum deviceType;
  char deviceName[256]; uint8_t pipelineCacheUUID[16]; uint64_t tail[66];
} VkPhysicalDeviceProperties;

typedef struct { VkFlags propertyFlags; uint32_t heapIndex; } VkMemoryType;
typedef struct { VkDeviceSize size; VkFlags flags; } VkMemoryHeap;
typedef struct {
  uint32_t memoryTypeCount; VkMemoryType memoryTypes[32];
  uint32_t memoryHeapCount; VkMemoryHeap memoryHeaps[16];
} VkPhysicalDeviceMemoryProperties;

typedef struct {
  VkFlags queueFlags; uint32_t queueCount; uint32_t timestampValidBits;
  VkExtent3D minImageTransferGranularity;
} VkQueueFamilyProperties;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; uint32_t queueFamilyIndex;
  uint32_t queueCount; const float* pQueuePriorities;
} VkDeviceQueueCreateInfo;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags;
  uint32_t queueCreateInfoCount; const VkDeviceQueueCreateInfo* pQueueCreateInfos;
  uint32_t enabledLayerCount; const char* const* ppEnabledLayerNames;
  uint32_t enabledExtensionCount; const char* const* ppEnabledExtensionNames;
  const void* pEnabledFeatures;
} VkDeviceCreateInfo;

typedef struct {
  VkEnum sType; void* pNext; VkBool32 dynamicRendering;
} VkPhysicalDeviceDynamicRenderingFeatures;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; Display* dpy; Window window;
} VkXlibSurfaceCreateInfoKHR;

typedef struct {
  uint32_t minImageCount, maxImageCount; VkExtent2D currentExtent;
  VkExtent2D minImageExtent, maxImageExtent; uint32_t maxImageArrayLayers;
  VkFlags supportedTransforms; VkEnum currentTransform;
  VkFlags supportedCompositeAlpha; VkFlags supportedUsageFlags;
} VkSurfaceCapabilitiesKHR;

typedef struct { VkEnum format; VkEnum colorSpace; } VkSurfaceFormatKHR;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; VkHandle surface;
  uint32_t minImageCount; VkEnum imageFormat; VkEnum imageColorSpace;
  VkExtent2D imageExtent; uint32_t imageArrayLayers; VkFlags imageUsage;
  VkEnum imageSharingMode; uint32_t queueFamilyIndexCount;
  const uint32_t* pQueueFamilyIndices; VkEnum preTransform;
  VkEnum compositeAlpha; VkEnum presentMode; VkBool32 clipped;
  VkHandle oldSwapchain;
} VkSwapchainCreateInfoKHR;

typedef struct { VkEnum r, g, b, a; } VkComponentMapping;
typedef struct {
  VkFlags aspectMask; uint32_t baseMipLevel, levelCount, baseArrayLayer,
    layerCount;
} VkImageSubresourceRange;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; VkHandle image;
  VkEnum viewType; VkEnum format; VkComponentMapping components;
  VkImageSubresourceRange subresourceRange;
} VkImageViewCreateInfo;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; VkDeviceSize size;
  VkFlags usage; VkEnum sharingMode; uint32_t queueFamilyIndexCount;
  const uint32_t* pQueueFamilyIndices;
} VkBufferCreateInfo;

typedef struct {
  VkDeviceSize size; VkDeviceSize alignment; uint32_t memoryTypeBits;
} VkMemoryRequirements;

typedef struct {
  VkEnum sType; const void* pNext; VkDeviceSize allocationSize;
  uint32_t memoryTypeIndex;
} VkMemoryAllocateInfo;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; VkEnum imageType;
  VkEnum format; VkExtent3D extent; uint32_t mipLevels; uint32_t arrayLayers;
  VkEnum samples; VkEnum tiling; VkFlags usage; VkEnum sharingMode;
  uint32_t queueFamilyIndexCount; const uint32_t* pQueueFamilyIndices;
  VkEnum initialLayout;
} VkImageCreateInfo;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; VkEnum magFilter;
  VkEnum minFilter; VkEnum mipmapMode; VkEnum addressModeU, addressModeV,
    addressModeW; float mipLodBias; VkBool32 anisotropyEnable;
  float maxAnisotropy; VkBool32 compareEnable; VkEnum compareOp;
  float minLod, maxLod; VkEnum borderColor; VkBool32 unnormalizedCoordinates;
} VkSamplerCreateInfo;

typedef struct {
  uint32_t binding; VkEnum descriptorType; uint32_t descriptorCount;
  VkFlags stageFlags; const VkHandle* pImmutableSamplers;
} VkDescriptorSetLayoutBinding;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; uint32_t bindingCount;
  const VkDescriptorSetLayoutBinding* pBindings;
} VkDescriptorSetLayoutCreateInfo;

typedef struct { VkEnum type; uint32_t descriptorCount; } VkDescriptorPoolSize;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; uint32_t maxSets;
  uint32_t poolSizeCount; const VkDescriptorPoolSize* pPoolSizes;
} VkDescriptorPoolCreateInfo;

typedef struct {
  VkEnum sType; const void* pNext; VkHandle descriptorPool;
  uint32_t descriptorSetCount; const VkHandle* pSetLayouts;
} VkDescriptorSetAllocateInfo;

typedef struct {
  VkHandle sampler; VkHandle imageView; VkEnum imageLayout;
} VkDescriptorImageInfo;

typedef struct {
  VkEnum sType; const void* pNext; VkHandle dstSet; uint32_t dstBinding;
  uint32_t dstArrayElement; uint32_t descriptorCount; VkEnum descriptorType;
  const VkDescriptorImageInfo* pImageInfo; const void* pBufferInfo;
  const VkHandle* pTexelBufferView;
} VkWriteDescriptorSet;

typedef struct { VkFlags stageFlags; uint32_t offset, size; }
  VkPushConstantRange;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; uint32_t setLayoutCount;
  const VkHandle* pSetLayouts; uint32_t pushConstantRangeCount;
  const VkPushConstantRange* pPushConstantRanges;
} VkPipelineLayoutCreateInfo;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; size_t codeSize;
  const uint32_t* pCode;
} VkShaderModuleCreateInfo;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; VkEnum stage;
  VkHandle module; const char* pName; const void* pSpecializationInfo;
} VkPipelineShaderStageCreateInfo;

typedef struct { uint32_t binding, stride; VkEnum inputRate; }
  VkVertexInputBindingDescription;
typedef struct { uint32_t location, binding; VkEnum format; uint32_t offset; }
  VkVertexInputAttributeDescription;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags;
  uint32_t vertexBindingDescriptionCount;
  const VkVertexInputBindingDescription* pVertexBindingDescriptions;
  uint32_t vertexAttributeDescriptionCount;
  const VkVertexInputAttributeDescription* pVertexAttributeDescriptions;
} VkPipelineVertexInputStateCreateInfo;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; VkEnum topology;
  VkBool32 primitiveRestartEnable;
} VkPipelineInputAssemblyStateCreateInfo;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; uint32_t viewportCount;
  const VkViewport* pViewports; uint32_t scissorCount;
  const VkRect2D* pScissors;
} VkPipelineViewportStateCreateInfo;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; VkBool32 depthClampEnable;
  VkBool32 rasterizerDiscardEnable; VkEnum polygonMode; VkFlags cullMode;
  VkEnum frontFace; VkBool32 depthBiasEnable; float depthBiasConstantFactor;
  float depthBiasClamp; float depthBiasSlopeFactor; float lineWidth;
} VkPipelineRasterizationStateCreateInfo;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; VkEnum rasterizationSamples;
  VkBool32 sampleShadingEnable; float minSampleShading;
  const uint32_t* pSampleMask; VkBool32 alphaToCoverageEnable;
  VkBool32 alphaToOneEnable;
} VkPipelineMultisampleStateCreateInfo;

typedef struct {
  VkBool32 blendEnable; VkEnum srcColorBlendFactor, dstColorBlendFactor,
    colorBlendOp, srcAlphaBlendFactor, dstAlphaBlendFactor, alphaBlendOp;
  VkFlags colorWriteMask;
} VkPipelineColorBlendAttachmentState;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; VkBool32 logicOpEnable;
  VkEnum logicOp; uint32_t attachmentCount;
  const VkPipelineColorBlendAttachmentState* pAttachments;
  float blendConstants[4];
} VkPipelineColorBlendStateCreateInfo;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; uint32_t dynamicStateCount;
  const VkEnum* pDynamicStates;
} VkPipelineDynamicStateCreateInfo;

typedef struct {
  VkEnum sType; const void* pNext; uint32_t viewMask;
  uint32_t colorAttachmentCount; const VkEnum* pColorAttachmentFormats;
  VkEnum depthAttachmentFormat; VkEnum stencilAttachmentFormat;
} VkPipelineRenderingCreateInfo;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; uint32_t stageCount;
  const VkPipelineShaderStageCreateInfo* pStages;
  const VkPipelineVertexInputStateCreateInfo* pVertexInputState;
  const VkPipelineInputAssemblyStateCreateInfo* pInputAssemblyState;
  const void* pTessellationState;
  const VkPipelineViewportStateCreateInfo* pViewportState;
  const VkPipelineRasterizationStateCreateInfo* pRasterizationState;
  const VkPipelineMultisampleStateCreateInfo* pMultisampleState;
  const void* pDepthStencilState;
  const VkPipelineColorBlendStateCreateInfo* pColorBlendState;
  const VkPipelineDynamicStateCreateInfo* pDynamicState; VkHandle layout;
  VkHandle renderPass; uint32_t subpass; VkHandle basePipelineHandle;
  int32_t basePipelineIndex;
} VkGraphicsPipelineCreateInfo;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; uint32_t queueFamilyIndex;
} VkCommandPoolCreateInfo;

typedef struct {
  VkEnum sType; const void* pNext; VkHandle commandPool; VkEnum level;
  uint32_t commandBufferCount;
} VkCommandBufferAllocateInfo;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; const void* pInheritanceInfo;
} VkCommandBufferBeginInfo;

typedef struct {
  VkEnum sType; const void* pNext; VkHandle imageView; VkEnum imageLayout;
  VkEnum resolveMode; VkHandle resolveImageView; VkEnum resolveImageLayout;
  VkEnum loadOp; VkEnum storeOp; VkClearValue clearValue;
} VkRenderingAttachmentInfo;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags flags; VkRect2D renderArea;
  uint32_t layerCount; uint32_t viewMask; uint32_t colorAttachmentCount;
  const VkRenderingAttachmentInfo* pColorAttachments;
  const VkRenderingAttachmentInfo* pDepthAttachment;
  const VkRenderingAttachmentInfo* pStencilAttachment;
} VkRenderingInfo;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags srcAccessMask, dstAccessMask;
  VkEnum oldLayout, newLayout; uint32_t srcQueueFamilyIndex,
    dstQueueFamilyIndex; VkHandle image;
  VkImageSubresourceRange subresourceRange;
} VkImageMemoryBarrier;

typedef struct {
  VkEnum sType; const void* pNext; VkFlags srcAccessMask, dstAccessMask;
} VkMemoryBarrier;

typedef struct {
  VkFlags aspectMask; uint32_t mipLevel, baseArrayLayer, layerCount;
} VkImageSubresourceLayers;

typedef struct {
  VkDeviceSize bufferOffset; uint32_t bufferRowLength, bufferImageHeight;
  VkImageSubresourceLayers imageSubresource; VkOffset3D imageOffset;
  VkExtent3D imageExtent;
} VkBufferImageCopy;

typedef struct {
  VkImageSubresourceLayers srcSubresource; VkOffset3D srcOffset;
  VkImageSubresourceLayers dstSubresource; VkOffset3D dstOffset;
  VkExtent3D extent;
} VkImageCopy;

typedef struct { VkEnum sType; const void* pNext; VkFlags flags; }
  VkSemaphoreCreateInfo, VkFenceCreateInfo;

typedef struct {
  VkEnum sType; const void* pNext; uint32_t waitSemaphoreCount;
  const VkHandle* pWaitSemaphores; const VkFlags* pWaitDstStageMask;
  uint32_t commandBufferCount; const VkCommandBuffer* pCommandBuffers;
  uint32_t signalSemaphoreCount; const VkHandle* pSignalSemaphores;
} VkSubmitInfo;

typedef struct {
  VkEnum sType; const void* pNext; uint32_t waitSemaphoreCount;
  const VkHandle* pWaitSemaphores; uint32_t swapchainCount;
  const VkHandle* pSwapchains; const uint32_t* pImageIndices;
  VkResult* pResults;
} VkPresentInfoKHR;

// The Vulkan entry points the bridge calls, loaded after vkCreateInstance.
#define VX_FNS(X) \
  X(void, vkDestroyInstance, (VkInstance, const void*)) \
  X(VkResult, vkEnumeratePhysicalDevices, (VkInstance, uint32_t*, \
    VkPhysicalDevice*)) \
  X(void, vkGetPhysicalDeviceProperties, (VkPhysicalDevice, \
    VkPhysicalDeviceProperties*)) \
  X(void, vkGetPhysicalDeviceMemoryProperties, (VkPhysicalDevice, \
    VkPhysicalDeviceMemoryProperties*)) \
  X(void, vkGetPhysicalDeviceQueueFamilyProperties, (VkPhysicalDevice, \
    uint32_t*, VkQueueFamilyProperties*)) \
  X(VkResult, vkGetPhysicalDeviceSurfaceSupportKHR, (VkPhysicalDevice, \
    uint32_t, VkHandle, VkBool32*)) \
  X(VkResult, vkGetPhysicalDeviceSurfaceCapabilitiesKHR, (VkPhysicalDevice, \
    VkHandle, VkSurfaceCapabilitiesKHR*)) \
  X(VkResult, vkGetPhysicalDeviceSurfaceFormatsKHR, (VkPhysicalDevice, \
    VkHandle, uint32_t*, VkSurfaceFormatKHR*)) \
  X(VkResult, vkGetPhysicalDeviceSurfacePresentModesKHR, (VkPhysicalDevice, \
    VkHandle, uint32_t*, VkEnum*)) \
  X(VkResult, vkCreateXlibSurfaceKHR, (VkInstance, \
    const VkXlibSurfaceCreateInfoKHR*, const void*, VkHandle*)) \
  X(void, vkDestroySurfaceKHR, (VkInstance, VkHandle, const void*)) \
  X(VkResult, vkCreateDebugUtilsMessengerEXT, (VkInstance, \
    const VkDebugUtilsMessengerCreateInfoEXT*, const void*, VkHandle*)) \
  X(void, vkDestroyDebugUtilsMessengerEXT, (VkInstance, VkHandle, \
    const void*)) \
  X(VkResult, vkCreateDevice, (VkPhysicalDevice, const VkDeviceCreateInfo*, \
    const void*, VkDevice*)) \
  X(void, vkDestroyDevice, (VkDevice, const void*)) \
  X(void, vkGetDeviceQueue, (VkDevice, uint32_t, uint32_t, VkQueue*)) \
  X(VkResult, vkDeviceWaitIdle, (VkDevice)) \
  X(VkResult, vkCreateSwapchainKHR, (VkDevice, \
    const VkSwapchainCreateInfoKHR*, const void*, VkHandle*)) \
  X(void, vkDestroySwapchainKHR, (VkDevice, VkHandle, const void*)) \
  X(VkResult, vkGetSwapchainImagesKHR, (VkDevice, VkHandle, uint32_t*, \
    VkHandle*)) \
  X(VkResult, vkAcquireNextImageKHR, (VkDevice, VkHandle, uint64_t, VkHandle, \
    VkHandle, uint32_t*)) \
  X(VkResult, vkQueuePresentKHR, (VkQueue, const VkPresentInfoKHR*)) \
  X(VkResult, vkQueueSubmit, (VkQueue, uint32_t, const VkSubmitInfo*, \
    VkHandle)) \
  X(VkResult, vkCreateImageView, (VkDevice, const VkImageViewCreateInfo*, \
    const void*, VkHandle*)) \
  X(void, vkDestroyImageView, (VkDevice, VkHandle, const void*)) \
  X(VkResult, vkCreateBuffer, (VkDevice, const VkBufferCreateInfo*, \
    const void*, VkHandle*)) \
  X(void, vkDestroyBuffer, (VkDevice, VkHandle, const void*)) \
  X(VkResult, vkCreateImage, (VkDevice, const VkImageCreateInfo*, \
    const void*, VkHandle*)) \
  X(void, vkDestroyImage, (VkDevice, VkHandle, const void*)) \
  X(void, vkGetBufferMemoryRequirements, (VkDevice, VkHandle, \
    VkMemoryRequirements*)) \
  X(void, vkGetImageMemoryRequirements, (VkDevice, VkHandle, \
    VkMemoryRequirements*)) \
  X(VkResult, vkAllocateMemory, (VkDevice, const VkMemoryAllocateInfo*, \
    const void*, VkHandle*)) \
  X(void, vkFreeMemory, (VkDevice, VkHandle, const void*)) \
  X(VkResult, vkBindBufferMemory, (VkDevice, VkHandle, VkHandle, \
    VkDeviceSize)) \
  X(VkResult, vkBindImageMemory, (VkDevice, VkHandle, VkHandle, \
    VkDeviceSize)) \
  X(VkResult, vkMapMemory, (VkDevice, VkHandle, VkDeviceSize, VkDeviceSize, \
    VkFlags, void**)) \
  X(VkResult, vkCreateSampler, (VkDevice, const VkSamplerCreateInfo*, \
    const void*, VkHandle*)) \
  X(void, vkDestroySampler, (VkDevice, VkHandle, const void*)) \
  X(VkResult, vkCreateDescriptorSetLayout, (VkDevice, \
    const VkDescriptorSetLayoutCreateInfo*, const void*, VkHandle*)) \
  X(void, vkDestroyDescriptorSetLayout, (VkDevice, VkHandle, const void*)) \
  X(VkResult, vkCreateDescriptorPool, (VkDevice, \
    const VkDescriptorPoolCreateInfo*, const void*, VkHandle*)) \
  X(void, vkDestroyDescriptorPool, (VkDevice, VkHandle, const void*)) \
  X(VkResult, vkAllocateDescriptorSets, (VkDevice, \
    const VkDescriptorSetAllocateInfo*, VkHandle*)) \
  X(void, vkUpdateDescriptorSets, (VkDevice, uint32_t, \
    const VkWriteDescriptorSet*, uint32_t, const void*)) \
  X(VkResult, vkCreateShaderModule, (VkDevice, \
    const VkShaderModuleCreateInfo*, const void*, VkHandle*)) \
  X(void, vkDestroyShaderModule, (VkDevice, VkHandle, const void*)) \
  X(VkResult, vkCreatePipelineLayout, (VkDevice, \
    const VkPipelineLayoutCreateInfo*, const void*, VkHandle*)) \
  X(void, vkDestroyPipelineLayout, (VkDevice, VkHandle, const void*)) \
  X(VkResult, vkCreateGraphicsPipelines, (VkDevice, VkHandle, uint32_t, \
    const VkGraphicsPipelineCreateInfo*, const void*, VkHandle*)) \
  X(void, vkDestroyPipeline, (VkDevice, VkHandle, const void*)) \
  X(VkResult, vkCreateCommandPool, (VkDevice, const VkCommandPoolCreateInfo*, \
    const void*, VkHandle*)) \
  X(void, vkDestroyCommandPool, (VkDevice, VkHandle, const void*)) \
  X(VkResult, vkAllocateCommandBuffers, (VkDevice, \
    const VkCommandBufferAllocateInfo*, VkCommandBuffer*)) \
  X(VkResult, vkResetCommandBuffer, (VkCommandBuffer, VkFlags)) \
  X(VkResult, vkBeginCommandBuffer, (VkCommandBuffer, \
    const VkCommandBufferBeginInfo*)) \
  X(VkResult, vkEndCommandBuffer, (VkCommandBuffer)) \
  X(VkResult, vkCreateSemaphore, (VkDevice, const VkSemaphoreCreateInfo*, \
    const void*, VkHandle*)) \
  X(void, vkDestroySemaphore, (VkDevice, VkHandle, const void*)) \
  X(VkResult, vkCreateFence, (VkDevice, const VkFenceCreateInfo*, \
    const void*, VkHandle*)) \
  X(void, vkDestroyFence, (VkDevice, VkHandle, const void*)) \
  X(VkResult, vkWaitForFences, (VkDevice, uint32_t, const VkHandle*, \
    VkBool32, uint64_t)) \
  X(VkResult, vkResetFences, (VkDevice, uint32_t, const VkHandle*)) \
  X(void, vkCmdPipelineBarrier, (VkCommandBuffer, VkFlags, VkFlags, VkFlags, \
    uint32_t, const void*, uint32_t, const void*, uint32_t, \
    const VkImageMemoryBarrier*)) \
  X(void, vkCmdBeginRendering, (VkCommandBuffer, const VkRenderingInfo*)) \
  X(void, vkCmdEndRendering, (VkCommandBuffer)) \
  X(void, vkCmdSetViewport, (VkCommandBuffer, uint32_t, uint32_t, \
    const VkViewport*)) \
  X(void, vkCmdSetScissor, (VkCommandBuffer, uint32_t, uint32_t, \
    const VkRect2D*)) \
  X(void, vkCmdBindPipeline, (VkCommandBuffer, VkEnum, VkHandle)) \
  X(void, vkCmdBindDescriptorSets, (VkCommandBuffer, VkEnum, VkHandle, \
    uint32_t, uint32_t, const VkHandle*, uint32_t, const uint32_t*)) \
  X(void, vkCmdPushConstants, (VkCommandBuffer, VkHandle, VkFlags, uint32_t, \
    uint32_t, const void*)) \
  X(void, vkCmdBindVertexBuffers, (VkCommandBuffer, uint32_t, uint32_t, \
    const VkHandle*, const VkDeviceSize*)) \
  X(void, vkCmdDraw, (VkCommandBuffer, uint32_t, uint32_t, uint32_t, \
    uint32_t)) \
  X(void, vkCmdCopyBufferToImage, (VkCommandBuffer, VkHandle, VkHandle, \
    VkEnum, uint32_t, const VkBufferImageCopy*)) \
  X(void, vkCmdCopyImageToBuffer, (VkCommandBuffer, VkHandle, VkEnum, \
    VkHandle, uint32_t, const VkBufferImageCopy*)) \
  X(void, vkCmdCopyImage, (VkCommandBuffer, VkHandle, VkEnum, VkHandle, \
    VkEnum, uint32_t, const VkImageCopy*))

#define VX_DECL(r, n, a) static r (*n) a;
VX_FNS(VX_DECL)

static PFN_vkGetInstanceProcAddr vx_gipa;
static VkResult (*vx_create_instance)(const VkInstanceCreateInfo*,
  const void*, VkInstance*);
static VkResult (*vx_layers)(uint32_t*, VkLayerProperties*);

// Slots
// -----

enum {
  VX_FREE, VX_INSTANCE, VX_SURFACE, VX_DEVICE, VX_SWAPCHAIN,
  VX_SWAP_IMAGE, VX_IMAGE, VX_VIEW, VX_BUFFER, VX_MEMORY, VX_SAMPLER,
  VX_SET_LAYOUT, VX_POOL, VX_SET, VX_SHADER, VX_LAYOUT, VX_PIPELINE,
  VX_CMD_POOL, VX_CMD, VX_SEMAPHORE, VX_FENCE
};

typedef struct {
  u32      kind;
  u32      dev;   // owning device (or instance) slot
  u64      h;     // the handle
  u64      x;     // second word: VkQueue for a device
  u64      size;  // memory size; device: queue family
  void*    map;   // persistent host mapping of a memory slot
} VxSlot;

#define VX_SLOTS 4096
static VxSlot vx_slot[VX_SLOTS];
static u32    vx_live;
static u32    vx_warnings;
static u32    vx_errors;
static u32    vx_layer_on;
static VkHandle vx_messenger;

static u32 vx_new(u32 kind, u32 dev, u64 h, u64 x) {
  for (u32 i = 1; i < VX_SLOTS; i += 1) {
    if (vx_slot[i].kind == VX_FREE) {
      vx_slot[i] = (VxSlot){ kind, dev, h, x, 0, NULL };
      vx_live += 1;
      return i;
    }
  }
  return 0;
}

static VxSlot* vx_get(u32 id, u32 kind) {
  if (id == 0 || id >= VX_SLOTS || vx_slot[id].kind != kind) {
    return NULL;
  }
  return &vx_slot[id];
}

// An image operand: owned images and swapchain images both qualify.
static VxSlot* vx_image(u32 id) {
  VxSlot* s = vx_get(id, VX_IMAGE);
  return s != NULL ? s : vx_get(id, VX_SWAP_IMAGE);
}

static VkDevice vx_dev(VxSlot* s) {
  return (VkDevice)(intptr_t)s->h;
}

// Terms
// -----

static Term vx_err(Env e, u32 code, const char* what, VkResult r) {
  char text[160];
  snprintf(text, sizeof text, "Voltra: %s (%d)", what, (int)r);
  return io_fail(e, code, text);
}

#define VX_BAD(e, what) io_fail(e, 22, "Voltra: invalid " what)
#define VX_TRY(e, call, what) do { \
    VkResult vx_r = (call); \
    if (vx_r < 0) { return vx_err(e, (u32)-vx_r, what, vx_r); } \
  } while (0)

static Term vx_slot_done(Env e, u32 kind, u32 dev, u64 h, u64 x) {
  u32 id = vx_new(kind, dev, h, x);
  if (id == 0) {
    return io_fail(e, 24, "Voltra: slot table full");
  }
  return io_done(e, (Term)id);
}

static Term vx_list(Env e, const u32* w, u32 n) {
  Term xs = term_pak(CID(Nil), 0);
  for (u32 i = n; i > 0; i -= 1) {
    xs = io_node(e, CID(Con), (Term)w[i - 1], xs);
  }
  return xs;
}

// Consumes a List<U32>; answers how many words it held (may exceed max).
static u32 vx_words(Env e, Term s, u32* out, u32 max) {
  u32 n = 0;
  while (term_aux(s) == CID(Con)) {
    Term fb[2];
    spare_free(e, cls_fit(2), ctr_take(e, s, 2, fb));
    if (n < max) {
      out[n] = (u32)fb[0];
    }
    n += 1;
    s = fb[1];
  }
  return n;
}

// The u32 words of an Array<U32> argument, and how many it holds.
static u32* vx_array(Env e, Term a, u64* n) {
  *n = 1ull << blk_cls(a);
  return (u32*)(e.mem + blk_loc(e.mem, a));
}

// Vulkan: instance and devices
// ----------------------------

#ifdef CID(vk_instance)

static VkBool32 vx_debug(VkFlags sev, VkFlags type,
  const VkDebugUtilsMessengerCallbackDataEXT* data, void* user) {
  if (sev >= 0x1000) {
    vx_errors += 1;
  } else if (sev >= 0x100) {
    vx_warnings += 1;
  }
  if (sev >= 0x100) {
    fprintf(stderr, "voltra: vulkan %s: %s\n", sev >= 0x1000 ? "error"
      : "warning", data->pMessage);
  }
  return 0;
}

// One instance at a time (Vulkan 1.3, Xlib surface). `flags` bit 0 asks for
// VK_LAYER_KHRONOS_validation when it is installed. Answers [slot, layer_on].
Term vx_vk_instance_run(Env e, Term* f, IoWork* w) {
  u32 flags = (u32)f[0];
  if (vx_gipa == NULL) {
    void* lib = dlopen("libvulkan.so.1", RTLD_NOW | RTLD_LOCAL);
    if (lib == NULL) {
      return io_fail(e, 95, "Voltra: libvulkan.so.1 not found");
    }
    vx_gipa = (PFN_vkGetInstanceProcAddr)dlsym(lib, "vkGetInstanceProcAddr");
    if (vx_gipa == NULL) {
      return io_fail(e, 95, "Voltra: vkGetInstanceProcAddr missing");
    }
    vx_create_instance = (void*)vx_gipa(NULL, "vkCreateInstance");
    vx_layers = (void*)vx_gipa(NULL, "vkEnumerateInstanceLayerProperties");
  }
  const char* want = "VK_LAYER_KHRONOS_validation";
  vx_layer_on = 0;
  if (flags & 1) {
    uint32_t n = 0;
    vx_layers(&n, NULL);
    VkLayerProperties* ls = io_mem(calloc(n + 1, sizeof *ls));
    vx_layers(&n, ls);
    for (uint32_t i = 0; i < n; i += 1) {
      vx_layer_on |= strcmp(ls[i].layerName, want) == 0;
    }
    free(ls);
  }
  const char* exts[] = { "VK_KHR_surface", "VK_KHR_xlib_surface",
    "VK_EXT_debug_utils" };
  VkApplicationInfo app = { 0, NULL, "Voltra", 1, "Voltra", 1,
    (1u << 22) | (3u << 12) };
  VkInstanceCreateInfo ci = { 1, NULL, 0, &app, vx_layer_on, &want, 3, exts };
  VkInstance inst;
  VX_TRY(e, vx_create_instance(&ci, NULL, &inst), "vkCreateInstance");
#define VX_LOAD(r, n, a) n = (void*)vx_gipa(inst, #n);
  VX_FNS(VX_LOAD)
  VkDebugUtilsMessengerCreateInfoEXT dm = { 1000128004, NULL, 0, 0x1111,
    0x7, vx_debug, NULL };
  vkCreateDebugUtilsMessengerEXT(inst, &dm, NULL, &vx_messenger);
  u32 id = vx_new(VX_INSTANCE, 0, (u64)(intptr_t)inst, 0);
  u32 out[2] = { id, vx_layer_on };
  return io_done(e, vx_list(e, out, 2));
}

static void __attribute__((constructor)) vx_vk_instance_use(void) {
  io_eff(CID(vk_instance), vx_vk_instance_run, 0);
}

#endif

static VkPhysicalDevice vx_gpu(VxSlot* inst, u32 index) {
  VkPhysicalDevice gpus[16];
  uint32_t n = 16;
  vkEnumeratePhysicalDevices((VkInstance)(intptr_t)inst->h, &n, gpus);
  return index < n ? gpus[index] : NULL;
}

#ifdef CID(vk_gpus)

// [count, then per GPU: type, vendor, device, api, driver, maxImage2D,
// device-local MiB].
Term vx_vk_gpus_run(Env e, Term* f, IoWork* w) {
  VxSlot* s = vx_get((u32)f[0], VX_INSTANCE);
  if (s == NULL) {
    return VX_BAD(e, "instance");
  }
  VkPhysicalDevice gpus[16];
  uint32_t n = 16;
  vkEnumeratePhysicalDevices((VkInstance)(intptr_t)s->h, &n, gpus);
  u32 out[1 + 16 * 7];
  out[0] = n;
  for (u32 i = 0; i < n; i += 1) {
    VkPhysicalDeviceProperties p;
    VkPhysicalDeviceMemoryProperties m;
    vkGetPhysicalDeviceProperties(gpus[i], &p);
    vkGetPhysicalDeviceMemoryProperties(gpus[i], &m);
    u64 local = 0;
    for (u32 j = 0; j < m.memoryHeapCount; j += 1) {
      local += m.memoryHeaps[j].flags & 1 ? m.memoryHeaps[j].size : 0;
    }
    u32* o = out + 1 + i * 7;
    o[0] = p.deviceType; o[1] = p.vendorID; o[2] = p.deviceID;
    o[3] = p.apiVersion; o[4] = p.driverVersion;
    o[5] = (u32)(p.tail[0] >> 32);  // limits.maxImageDimension2D
    o[6] = (u32)(local >> 20);
  }
  return io_done(e, vx_list(e, out, 1 + n * 7));
}

static void __attribute__((constructor)) vx_vk_gpus_use(void) {
  io_eff(CID(vk_gpus), vx_vk_gpus_run, 0);
}

#endif

#ifdef CID(vk_gpu_name)

Term vx_vk_gpu_name_run(Env e, Term* f, IoWork* w) {
  VxSlot* s = vx_get((u32)f[0], VX_INSTANCE);
  VkPhysicalDevice gpu = s != NULL ? vx_gpu(s, (u32)f[1]) : NULL;
  if (gpu == NULL) {
    return VX_BAD(e, "instance or GPU index");
  }
  VkPhysicalDeviceProperties p;
  vkGetPhysicalDeviceProperties(gpu, &p);
  return io_done(e, io_str(e, p.deviceName, strnlen(p.deviceName, 256)));
}

static void __attribute__((constructor)) vx_vk_gpu_name_use(void) {
  io_eff(CID(vk_gpu_name), vx_vk_gpu_name_run, 0);
}

#endif

#ifdef CID(vk_surface)

// A presentation surface for a native window handed over by the platform
// layer as words: [kind, Display* high word, Display* low word, window id,
// screen]. Kind 1 is Xlib (vkCreateXlibSurfaceKHR); other kinds answer
// ENOTSUP. The display is borrowed: Voltra never closes it.
Term vx_vk_surface_run(Env e, Term* f, IoWork* w) {
  u32 k[5];
  u32 n = vx_words(e, f[1], k, 5);
  VxSlot* s = vx_get((u32)f[0], VX_INSTANCE);
  if (s == NULL || n != 5) {
    return VX_BAD(e, "instance or native window");
  }
  if (k[0] != 1) {
    return io_fail(e, 95, "Voltra: unsupported native window kind");
  }
  Display* dpy = (Display*)(uintptr_t)(((u64)k[1] << 32) | k[2]);
  if (dpy == NULL || k[3] == 0) {
    return VX_BAD(e, "Xlib display or window");
  }
  VkXlibSurfaceCreateInfoKHR ci = { 1000004000, NULL, 0, dpy, (Window)k[3] };
  VkHandle surf;
  VX_TRY(e, vkCreateXlibSurfaceKHR((VkInstance)(intptr_t)s->h, &ci, NULL,
    &surf), "vkCreateXlibSurfaceKHR");
  return vx_slot_done(e, VX_SURFACE, (u32)f[0], surf, 0);
}

static void __attribute__((constructor)) vx_vk_surface_use(void) {
  io_eff(CID(vk_surface), vx_vk_surface_run, 0);
}

#endif

#ifdef CID(vk_queue_families)

// Per family: flags, count, presents-to-surface (surface 0: always 0).
Term vx_vk_queue_families_run(Env e, Term* f, IoWork* w) {
  VxSlot* s = vx_get((u32)f[0], VX_INSTANCE);
  VkPhysicalDevice gpu = s != NULL ? vx_gpu(s, (u32)f[1]) : NULL;
  VxSlot* surf = vx_get((u32)f[2], VX_SURFACE);
  if (gpu == NULL || ((u32)f[2] != 0 && surf == NULL)) {
    return VX_BAD(e, "instance, GPU or surface");
  }
  VkQueueFamilyProperties q[32];
  uint32_t n = 32;
  vkGetPhysicalDeviceQueueFamilyProperties(gpu, &n, q);
  u32 out[96];
  for (u32 i = 0; i < n; i += 1) {
    VkBool32 ok = 0;
    if (surf != NULL) {
      vkGetPhysicalDeviceSurfaceSupportKHR(gpu, i, surf->h, &ok);
    }
    out[i * 3] = q[i].queueFlags;
    out[i * 3 + 1] = q[i].queueCount;
    out[i * 3 + 2] = ok;
  }
  return io_done(e, vx_list(e, out, n * 3));
}

static void __attribute__((constructor)) vx_vk_queue_families_use(void) {
  io_eff(CID(vk_queue_families), vx_vk_queue_families_run, 0);
}

#endif

#ifdef CID(vk_device)

// A logical device with one queue of `family`, VK_KHR_swapchain and the
// dynamicRendering feature (core in 1.3).
Term vx_vk_device_run(Env e, Term* f, IoWork* w) {
  VxSlot* s = vx_get((u32)f[0], VX_INSTANCE);
  VkPhysicalDevice gpu = s != NULL ? vx_gpu(s, (u32)f[1]) : NULL;
  if (gpu == NULL) {
    return VX_BAD(e, "instance or GPU index");
  }
  u32 family = (u32)f[2];
  float prio = 1.0f;
  VkDeviceQueueCreateInfo q = { 2, NULL, 0, family, 1, &prio };
  VkPhysicalDeviceDynamicRenderingFeatures dyn = { 1000044003, NULL, 1 };
  const char* ext = "VK_KHR_swapchain";
  VkDeviceCreateInfo ci = { 3, &dyn, 0, 1, &q, 0, NULL, 1, &ext, NULL };
  VkDevice dev;
  VX_TRY(e, vkCreateDevice(gpu, &ci, NULL, &dev), "vkCreateDevice");
  VkQueue queue;
  vkGetDeviceQueue(dev, family, 0, &queue);
  u32 id = vx_new(VX_DEVICE, (u32)f[0], (u64)(intptr_t)dev,
    (u64)(intptr_t)queue);
  if (id == 0) {
    vkDestroyDevice(dev, NULL);
    return io_fail(e, 24, "Voltra: slot table full");
  }
  vx_slot[id].size = family;
  vx_slot[id].map = (void*)gpu;
  return io_done(e, (Term)id);
}

static void __attribute__((constructor)) vx_vk_device_use(void) {
  io_eff(CID(vk_device), vx_vk_device_run, 0);
}

#endif

#ifdef CID(vk_memory_types)

// [count, (flags, heap)*, heaps, (MiB, flags)*].
Term vx_vk_memory_types_run(Env e, Term* f, IoWork* w) {
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  if (d == NULL) {
    return VX_BAD(e, "device");
  }
  VkPhysicalDeviceMemoryProperties m;
  vkGetPhysicalDeviceMemoryProperties((VkPhysicalDevice)d->map, &m);
  u32 out[1 + 64 + 1 + 32];
  u32 n = 0;
  out[n++] = m.memoryTypeCount;
  for (u32 i = 0; i < m.memoryTypeCount; i += 1) {
    out[n++] = m.memoryTypes[i].propertyFlags;
    out[n++] = m.memoryTypes[i].heapIndex;
  }
  out[n++] = m.memoryHeapCount;
  for (u32 i = 0; i < m.memoryHeapCount; i += 1) {
    out[n++] = (u32)(m.memoryHeaps[i].size >> 20);
    out[n++] = m.memoryHeaps[i].flags;
  }
  return io_done(e, vx_list(e, out, n));
}

static void __attribute__((constructor)) vx_vk_memory_types_use(void) {
  io_eff(CID(vk_memory_types), vx_vk_memory_types_run, 0);
}

#endif

// Vulkan: presentation
// --------------------

#ifdef CID(vk_surface_info)

// [minImages, maxImages, curW, curH, minW, minH, maxW, maxH, transforms,
// currentTransform, compositeAlpha, usage, nFormats, (format, space)*,
// nModes, mode*].
Term vx_vk_surface_info_run(Env e, Term* f, IoWork* w) {
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  VxSlot* s = vx_get((u32)f[1], VX_SURFACE);
  if (d == NULL || s == NULL) {
    return VX_BAD(e, "device or surface");
  }
  VkPhysicalDevice gpu = (VkPhysicalDevice)d->map;
  VkSurfaceCapabilitiesKHR c;
  VX_TRY(e, vkGetPhysicalDeviceSurfaceCapabilitiesKHR(gpu, s->h, &c),
    "vkGetPhysicalDeviceSurfaceCapabilitiesKHR");
  VkSurfaceFormatKHR fs[64];
  uint32_t nf = 64;
  VkEnum ms[16];
  uint32_t nm = 16;
  vkGetPhysicalDeviceSurfaceFormatsKHR(gpu, s->h, &nf, fs);
  vkGetPhysicalDeviceSurfacePresentModesKHR(gpu, s->h, &nm, ms);
  u32 out[14 + 128 + 16];
  u32 n = 0;
  u32 head[12] = { c.minImageCount, c.maxImageCount, c.currentExtent.width,
    c.currentExtent.height, c.minImageExtent.width, c.minImageExtent.height,
    c.maxImageExtent.width, c.maxImageExtent.height, c.supportedTransforms,
    c.currentTransform, c.supportedCompositeAlpha, c.supportedUsageFlags };
  memcpy(out, head, sizeof head);
  n = 12;
  out[n++] = nf;
  for (u32 i = 0; i < nf; i += 1) {
    out[n++] = fs[i].format;
    out[n++] = fs[i].colorSpace;
  }
  out[n++] = nm;
  for (u32 i = 0; i < nm; i += 1) {
    out[n++] = ms[i];
  }
  return io_done(e, vx_list(e, out, n));
}

static void __attribute__((constructor)) vx_vk_surface_info_use(void) {
  io_eff(CID(vk_surface_info), vx_vk_surface_info_run, 0);
}

#endif

#ifdef CID(vk_swapchain)

// desc: [minImageCount, format, colorSpace, width, height, usage,
// preTransform, compositeAlpha, presentMode, clipped]; old may be 0.
Term vx_vk_swapchain_run(Env e, Term* f, IoWork* w) {
  u32 k[10];
  u32 n = vx_words(e, f[2], k, 10);
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  VxSlot* s = vx_get((u32)f[1], VX_SURFACE);
  VxSlot* old = vx_get((u32)f[3], VX_SWAPCHAIN);
  if (d == NULL || s == NULL || n != 10 || ((u32)f[3] != 0 && old == NULL)) {
    return VX_BAD(e, "swapchain arguments");
  }
  VkSwapchainCreateInfoKHR ci = { 1000001000, NULL, 0, s->h, k[0], k[1], k[2],
    { k[3], k[4] }, 1, k[5], 0, 0, NULL, k[6], k[7], k[8], k[9],
    old != NULL ? old->h : 0 };
  VkHandle sc;
  VX_TRY(e, vkCreateSwapchainKHR(vx_dev(d), &ci, NULL, &sc),
    "vkCreateSwapchainKHR");
  return vx_slot_done(e, VX_SWAPCHAIN, (u32)f[0], sc, 0);
}

static void __attribute__((constructor)) vx_vk_swapchain_use(void) {
  io_eff(CID(vk_swapchain), vx_vk_swapchain_run, 0);
}

#endif

#ifdef CID(vk_swapchain_images)

// New slots for the swapchain's images; they die with the swapchain, so
// destroying one only releases its slot.
Term vx_vk_swapchain_images_run(Env e, Term* f, IoWork* w) {
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  VxSlot* sc = vx_get((u32)f[1], VX_SWAPCHAIN);
  if (d == NULL || sc == NULL) {
    return VX_BAD(e, "device or swapchain");
  }
  VkHandle img[16];
  uint32_t n = 16;
  VX_TRY(e, vkGetSwapchainImagesKHR(vx_dev(d), sc->h, &n, img),
    "vkGetSwapchainImagesKHR");
  u32 out[16];
  for (u32 i = 0; i < n; i += 1) {
    out[i] = vx_new(VX_SWAP_IMAGE, (u32)f[0], img[i], 0);
  }
  return io_done(e, vx_list(e, out, n));
}

static void __attribute__((constructor)) vx_vk_swapchain_images_use(void) {
  io_eff(CID(vk_swapchain_images), vx_vk_swapchain_images_run, 0);
}

#endif

#ifdef CID(vk_acquire)

// [status, index]: status 0 ready, 1 suboptimal, 2 out of date, 3 timeout.
Term vx_vk_acquire_run(Env e, Term* f, IoWork* w) {
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  VxSlot* sc = vx_get((u32)f[1], VX_SWAPCHAIN);
  VxSlot* sem = vx_get((u32)f[2], VX_SEMAPHORE);
  if (d == NULL || sc == NULL || sem == NULL) {
    return VX_BAD(e, "acquire arguments");
  }
  uint32_t index = 0;
  VkResult r = vkAcquireNextImageKHR(vx_dev(d), sc->h,
    (uint64_t)(u32)f[3] * 1000000ull, sem->h, 0, &index);
  u32 out[2] = { r == 0 ? 0 : r == 1000001003 ? 1 : r == -1000001004 ? 2
    : 3, index };
  if (r < 0 && r != -1000001004) {
    return vx_err(e, (u32)-r, "vkAcquireNextImageKHR", r);
  }
  return io_done(e, vx_list(e, out, 2));
}

static void __attribute__((constructor)) vx_vk_acquire_use(void) {
  io_eff(CID(vk_acquire), vx_vk_acquire_run, 0);
}

#endif

#ifdef CID(vk_present)

// Status as vk_acquire: 0 presented, 1 suboptimal, 2 out of date.
Term vx_vk_present_run(Env e, Term* f, IoWork* w) {
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  VxSlot* sc = vx_get((u32)f[1], VX_SWAPCHAIN);
  VxSlot* sem = vx_get((u32)f[3], VX_SEMAPHORE);
  if (d == NULL || sc == NULL || sem == NULL) {
    return VX_BAD(e, "present arguments");
  }
  uint32_t index = (u32)f[2];
  VkPresentInfoKHR pi = { 1000001001, NULL, 1, &sem->h, 1, &sc->h, &index,
    NULL };
  VkResult r = vkQueuePresentKHR((VkQueue)(intptr_t)d->x, &pi);
  if (r < 0 && r != -1000001004) {
    return vx_err(e, (u32)-r, "vkQueuePresentKHR", r);
  }
  return io_done(e, (Term)(u32)(r == 0 ? 0 : r == 1000001003 ? 1 : 2));
}

static void __attribute__((constructor)) vx_vk_present_use(void) {
  io_eff(CID(vk_present), vx_vk_present_run, 0);
}

#endif

// Vulkan: resources
// -----------------

#ifdef CID(vk_buffer)

// Answers [slot, requiredSize, alignment, memoryTypeBits].
Term vx_vk_buffer_run(Env e, Term* f, IoWork* w) {
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  if (d == NULL || (u32)f[1] == 0) {
    return VX_BAD(e, "device or buffer size");
  }
  VkBufferCreateInfo ci = { 12, NULL, 0, (u32)f[1], (u32)f[2], 0, 0, NULL };
  VkHandle b;
  VX_TRY(e, vkCreateBuffer(vx_dev(d), &ci, NULL, &b), "vkCreateBuffer");
  VkMemoryRequirements r;
  vkGetBufferMemoryRequirements(vx_dev(d), b, &r);
  u32 out[4] = { vx_new(VX_BUFFER, (u32)f[0], b, 0), (u32)r.size,
    (u32)r.alignment, r.memoryTypeBits };
  return io_done(e, vx_list(e, out, 4));
}

static void __attribute__((constructor)) vx_vk_buffer_use(void) {
  io_eff(CID(vk_buffer), vx_vk_buffer_run, 0);
}

#endif

#ifdef CID(vk_image)

// desc: [width, height, format, usage, tiling]; a 2D, single-mip,
// single-sample image in UNDEFINED layout. Answers as vk_buffer.
Term vx_vk_image_run(Env e, Term* f, IoWork* w) {
  u32 k[5];
  u32 n = vx_words(e, f[1], k, 5);
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  if (d == NULL || n != 5) {
    return VX_BAD(e, "device or image description");
  }
  VkImageCreateInfo ci = { 14, NULL, 0, 1, k[2], { k[0], k[1], 1 }, 1, 1, 1,
    k[4], k[3], 0, 0, NULL, 0 };
  VkHandle img;
  VX_TRY(e, vkCreateImage(vx_dev(d), &ci, NULL, &img), "vkCreateImage");
  VkMemoryRequirements r;
  vkGetImageMemoryRequirements(vx_dev(d), img, &r);
  u32 out[4] = { vx_new(VX_IMAGE, (u32)f[0], img, 0), (u32)r.size,
    (u32)r.alignment, r.memoryTypeBits };
  return io_done(e, vx_list(e, out, 4));
}

static void __attribute__((constructor)) vx_vk_image_use(void) {
  io_eff(CID(vk_image), vx_vk_image_run, 0);
}

#endif

#ifdef CID(vk_alloc)

Term vx_vk_alloc_run(Env e, Term* f, IoWork* w) {
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  if (d == NULL) {
    return VX_BAD(e, "device");
  }
  VkMemoryAllocateInfo ai = { 5, NULL, (u32)f[1], (u32)f[2] };
  VkHandle m;
  VX_TRY(e, vkAllocateMemory(vx_dev(d), &ai, NULL, &m), "vkAllocateMemory");
  u32 id = vx_new(VX_MEMORY, (u32)f[0], m, 0);
  if (id == 0) {
    vkFreeMemory(vx_dev(d), m, NULL);
    return io_fail(e, 24, "Voltra: slot table full");
  }
  vx_slot[id].size = (u32)f[1];
  return io_done(e, (Term)id);
}

static void __attribute__((constructor)) vx_vk_alloc_use(void) {
  io_eff(CID(vk_alloc), vx_vk_alloc_run, 0);
}

#endif

#ifdef CID(vk_bind)

// Binds a buffer or image to memory at a byte offset.
Term vx_vk_bind_run(Env e, Term* f, IoWork* w) {
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  VxSlot* b = vx_get((u32)f[1], VX_BUFFER);
  VxSlot* i = vx_get((u32)f[1], VX_IMAGE);
  VxSlot* m = vx_get((u32)f[2], VX_MEMORY);
  if (d == NULL || m == NULL || (b == NULL && i == NULL)) {
    return VX_BAD(e, "bind arguments");
  }
  VX_TRY(e, b != NULL ? vkBindBufferMemory(vx_dev(d), b->h, m->h, (u32)f[3])
    : vkBindImageMemory(vx_dev(d), i->h, m->h, (u32)f[3]), "vkBind*Memory");
  return io_done(e, term_pak(CID(Unit), 0));
}

static void __attribute__((constructor)) vx_vk_bind_use(void) {
  io_eff(CID(vk_bind), vx_vk_bind_run, 0);
}

#endif

#ifdef CID(vk_map)

// Maps the whole allocation, persistently, until the memory is freed.
Term vx_vk_map_run(Env e, Term* f, IoWork* w) {
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  VxSlot* m = vx_get((u32)f[1], VX_MEMORY);
  if (d == NULL || m == NULL || m->map != NULL) {
    return VX_BAD(e, "device or unmapped memory");
  }
  VX_TRY(e, vkMapMemory(vx_dev(d), m->h, 0, m->size, 0, &m->map),
    "vkMapMemory");
  return io_done(e, term_pak(CID(Unit), 0));
}

static void __attribute__((constructor)) vx_vk_map_use(void) {
  io_eff(CID(vk_map), vx_vk_map_run, 0);
}

#endif

#ifdef CID(vk_write)

// Copies `count` words of a Bend Array<U32> into mapped memory at a byte
// offset, then hands the array back. Bend chose coherent memory, so no
// flush is needed.
Term vx_vk_write_run(Env e, Term* f, IoWork* w) {
  VxSlot* m = vx_get((u32)f[0], VX_MEMORY);
  u64 offset = (u32)f[1];
  u64 cap = 0;
  u32* src = vx_array(e, f[2], &cap);
  u64 count = (u32)f[3];
  Term r;
  if (m == NULL || m->map == NULL || count > cap
    || offset + count * 4 > m->size) {
    r = VX_BAD(e, "write: memory unmapped or range out of bounds");
  } else {
    memcpy((char*)m->map + offset, src, count * 4);
    r = io_done(e, term_pak(CID(Unit), 0));
  }
  return io_tup(e, f[2], r);
}

static void __attribute__((constructor)) vx_vk_write_use(void) {
  io_eff(CID(vk_write), vx_vk_write_run, 0);
}

#endif

#ifdef CID(vk_read)

// Copies `count` words from mapped memory at a byte offset into a Bend
// Array<U32>, in place, then hands the array back: the read side of
// vk_write, for readbacks. Bend made the device writes visible to the host
// (a HOST_READ barrier, then a fence wait) before calling it.
Term vx_vk_read_run(Env e, Term* f, IoWork* w) {
  VxSlot* m = vx_get((u32)f[0], VX_MEMORY);
  u64 offset = (u32)f[1];
  u64 cap = 0;
  u32* dst = vx_array(e, f[2], &cap);
  u64 count = (u32)f[3];
  Term r;
  if (m == NULL || m->map == NULL || count > cap
    || offset + count * 4 > m->size) {
    r = VX_BAD(e, "read: memory unmapped or range out of bounds");
  } else {
    memcpy(dst, (char*)m->map + offset, count * 4);
    r = io_done(e, term_pak(CID(Unit), 0));
  }
  return io_tup(e, f[2], r);
}

static void __attribute__((constructor)) vx_vk_read_use(void) {
  io_eff(CID(vk_read), vx_vk_read_run, 0);
}

#endif

#ifdef CID(vk_image_view)

// desc: [format, swizzleR, swizzleG, swizzleB, swizzleA, aspect].
Term vx_vk_image_view_run(Env e, Term* f, IoWork* w) {
  u32 k[6];
  u32 n = vx_words(e, f[2], k, 6);
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  VxSlot* img = vx_image((u32)f[1]);
  if (d == NULL || img == NULL || n != 6) {
    return VX_BAD(e, "image view arguments");
  }
  VkImageViewCreateInfo ci = { 15, NULL, 0, img->h, 1, k[0],
    { k[1], k[2], k[3], k[4] }, { k[5], 0, 1, 0, 1 } };
  VkHandle v;
  VX_TRY(e, vkCreateImageView(vx_dev(d), &ci, NULL, &v), "vkCreateImageView");
  return vx_slot_done(e, VX_VIEW, (u32)f[0], v, 0);
}

static void __attribute__((constructor)) vx_vk_image_view_use(void) {
  io_eff(CID(vk_image_view), vx_vk_image_view_run, 0);
}

#endif

#ifdef CID(vk_sampler)

// desc: [magFilter, minFilter, addressMode].
Term vx_vk_sampler_run(Env e, Term* f, IoWork* w) {
  u32 k[3];
  u32 n = vx_words(e, f[1], k, 3);
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  if (d == NULL || n != 3) {
    return VX_BAD(e, "sampler arguments");
  }
  VkSamplerCreateInfo ci = { 31, NULL, 0, k[0], k[1], 0, k[2], k[2], k[2],
    0.0f, 0, 1.0f, 0, 0, 0.0f, 0.0f, 0, 0 };
  VkHandle s;
  VX_TRY(e, vkCreateSampler(vx_dev(d), &ci, NULL, &s), "vkCreateSampler");
  return vx_slot_done(e, VX_SAMPLER, (u32)f[0], s, 0);
}

static void __attribute__((constructor)) vx_vk_sampler_use(void) {
  io_eff(CID(vk_sampler), vx_vk_sampler_run, 0);
}

#endif

// Vulkan: descriptors, shaders, pipelines
// ---------------------------------------

#ifdef CID(vk_set_layout)

// desc: (binding, type, count, stages)*, at most 8 bindings.
Term vx_vk_set_layout_run(Env e, Term* f, IoWork* w) {
  u32 k[32];
  u32 n = vx_words(e, f[1], k, 32);
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  if (d == NULL || n % 4 != 0 || n > 32) {
    return VX_BAD(e, "set layout arguments");
  }
  VkDescriptorSetLayoutBinding b[8];
  for (u32 i = 0; i < n / 4; i += 1) {
    b[i] = (VkDescriptorSetLayoutBinding){ k[i * 4], k[i * 4 + 1],
      k[i * 4 + 2], k[i * 4 + 3], NULL };
  }
  VkDescriptorSetLayoutCreateInfo ci = { 32, NULL, 0, n / 4, b };
  VkHandle l;
  VX_TRY(e, vkCreateDescriptorSetLayout(vx_dev(d), &ci, NULL, &l),
    "vkCreateDescriptorSetLayout");
  return vx_slot_done(e, VX_SET_LAYOUT, (u32)f[0], l, 0);
}

static void __attribute__((constructor)) vx_vk_set_layout_use(void) {
  io_eff(CID(vk_set_layout), vx_vk_set_layout_run, 0);
}

#endif

#ifdef CID(vk_descriptor_pool)

// desc: (type, count)*, at most 8 sizes; maxSets in f[1].
Term vx_vk_descriptor_pool_run(Env e, Term* f, IoWork* w) {
  u32 k[16];
  u32 n = vx_words(e, f[2], k, 16);
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  if (d == NULL || n % 2 != 0 || n > 16) {
    return VX_BAD(e, "descriptor pool arguments");
  }
  VkDescriptorPoolSize sz[8];
  for (u32 i = 0; i < n / 2; i += 1) {
    sz[i] = (VkDescriptorPoolSize){ k[i * 2], k[i * 2 + 1] };
  }
  VkDescriptorPoolCreateInfo ci = { 33, NULL, 0, (u32)f[1], n / 2, sz };
  VkHandle p;
  VX_TRY(e, vkCreateDescriptorPool(vx_dev(d), &ci, NULL, &p),
    "vkCreateDescriptorPool");
  return vx_slot_done(e, VX_POOL, (u32)f[0], p, 0);
}

static void __attribute__((constructor)) vx_vk_descriptor_pool_use(void) {
  io_eff(CID(vk_descriptor_pool), vx_vk_descriptor_pool_run, 0);
}

#endif

#ifdef CID(vk_descriptor_set)

// A set from a pool; it dies with the pool, so destroying it only
// releases its slot.
Term vx_vk_descriptor_set_run(Env e, Term* f, IoWork* w) {
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  VxSlot* p = vx_get((u32)f[1], VX_POOL);
  VxSlot* l = vx_get((u32)f[2], VX_SET_LAYOUT);
  if (d == NULL || p == NULL || l == NULL) {
    return VX_BAD(e, "descriptor set arguments");
  }
  VkDescriptorSetAllocateInfo ai = { 34, NULL, p->h, 1, &l->h };
  VkHandle s;
  VX_TRY(e, vkAllocateDescriptorSets(vx_dev(d), &ai, &s),
    "vkAllocateDescriptorSets");
  return vx_slot_done(e, VX_SET, (u32)f[0], s, 0);
}

static void __attribute__((constructor)) vx_vk_descriptor_set_use(void) {
  io_eff(CID(vk_descriptor_set), vx_vk_descriptor_set_run, 0);
}

#endif

#ifdef CID(vk_write_image)

// desc: [binding, descriptorType, view, sampler, imageLayout].
Term vx_vk_write_image_run(Env e, Term* f, IoWork* w) {
  u32 k[5];
  u32 n = vx_words(e, f[2], k, 5);
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  VxSlot* s = vx_get((u32)f[1], VX_SET);
  VxSlot* v = n == 5 ? vx_get(k[2], VX_VIEW) : NULL;
  VxSlot* sm = n == 5 ? vx_get(k[3], VX_SAMPLER) : NULL;
  if (d == NULL || s == NULL || v == NULL || sm == NULL) {
    return VX_BAD(e, "image descriptor arguments");
  }
  VkDescriptorImageInfo ii = { sm->h, v->h, k[4] };
  VkWriteDescriptorSet wr = { 35, NULL, s->h, k[0], 0, 1, k[1], &ii, NULL,
    NULL };
  vkUpdateDescriptorSets(vx_dev(d), 1, &wr, 0, NULL);
  return io_done(e, term_pak(CID(Unit), 0));
}

static void __attribute__((constructor)) vx_vk_write_image_use(void) {
  io_eff(CID(vk_write_image), vx_vk_write_image_run, 0);
}

#endif

#ifdef CID(vk_shader)

// A shader module from the first `count` SPIR-V words of an array.
Term vx_vk_shader_run(Env e, Term* f, IoWork* w) {
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  u64 cap = 0;
  u32* code = vx_array(e, f[1], &cap);
  u64 count = (u32)f[2];
  Term r;
  if (d == NULL || count == 0 || count > cap) {
    r = VX_BAD(e, "shader arguments");
  } else {
    VkShaderModuleCreateInfo ci = { 16, NULL, 0, count * 4, code };
    VkHandle m;
    VkResult vr = vkCreateShaderModule(vx_dev(d), &ci, NULL, &m);
    r = vr < 0 ? vx_err(e, (u32)-vr, "vkCreateShaderModule", vr)
      : vx_slot_done(e, VX_SHADER, (u32)f[0], m, 0);
  }
  return io_tup(e, f[1], r);
}

static void __attribute__((constructor)) vx_vk_shader_use(void) {
  io_eff(CID(vk_shader), vx_vk_shader_run, 0);
}

#endif

#ifdef CID(vk_pipeline_layout)

// One optional set layout (0: none) and one push-constant range.
Term vx_vk_pipeline_layout_run(Env e, Term* f, IoWork* w) {
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  VxSlot* l = vx_get((u32)f[1], VX_SET_LAYOUT);
  if (d == NULL || ((u32)f[1] != 0 && l == NULL)) {
    return VX_BAD(e, "pipeline layout arguments");
  }
  VkPushConstantRange pc = { (u32)f[3], 0, (u32)f[2] };
  VkPipelineLayoutCreateInfo ci = { 30, NULL, 0, l != NULL, l != NULL
    ? &l->h : NULL, (u32)f[2] != 0, &pc };
  VkHandle p;
  VX_TRY(e, vkCreatePipelineLayout(vx_dev(d), &ci, NULL, &p),
    "vkCreatePipelineLayout");
  return vx_slot_done(e, VX_LAYOUT, (u32)f[0], p, 0);
}

static void __attribute__((constructor)) vx_vk_pipeline_layout_use(void) {
  io_eff(CID(vk_pipeline_layout), vx_vk_pipeline_layout_run, 0);
}

#endif

#ifdef CID(vk_pipeline)

// desc: [colorFormat, topology, cullMode, frontFace, blendEnable,
// srcColor, dstColor, colorOp, srcAlpha, dstAlpha, alphaOp, writeMask,
// nBindings, (binding, stride, rate)*, nAttributes,
// (location, binding, format, offset)*]. One color attachment, dynamic
// rendering, dynamic viewport and scissor, entry points "main".
Term vx_vk_pipeline_run(Env e, Term* f, IoWork* w) {
  u32 k[128];
  u32 n = vx_words(e, f[4], k, 128);
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  VxSlot* l = vx_get((u32)f[1], VX_LAYOUT);
  VxSlot* vs = vx_get((u32)f[2], VX_SHADER);
  VxSlot* fs = vx_get((u32)f[3], VX_SHADER);
  u32 nb = n > 12 ? k[12] : 99;
  u32 at = 13 + nb * 3;
  u32 na = n > at && nb <= 8 ? k[at] : 99;
  if (d == NULL || l == NULL || vs == NULL || fs == NULL || na > 16
    || n != at + 1 + na * 4) {
    return VX_BAD(e, "pipeline arguments");
  }
  VkVertexInputBindingDescription vb[8];
  VkVertexInputAttributeDescription va[16];
  for (u32 i = 0; i < nb; i += 1) {
    vb[i] = (VkVertexInputBindingDescription){ k[13 + i * 3],
      k[14 + i * 3], k[15 + i * 3] };
  }
  for (u32 i = 0; i < na; i += 1) {
    u32* a = k + at + 1 + i * 4;
    va[i] = (VkVertexInputAttributeDescription){ a[0], a[1], a[2], a[3] };
  }
  VkPipelineShaderStageCreateInfo st[2] = {
    { 18, NULL, 0, 0x1, vs->h, "main", NULL },
    { 18, NULL, 0, 0x10, fs->h, "main", NULL } };
  VkPipelineVertexInputStateCreateInfo vi = { 19, NULL, 0, nb, vb, na, va };
  VkPipelineInputAssemblyStateCreateInfo ia = { 20, NULL, 0, k[1], 0 };
  VkPipelineViewportStateCreateInfo vp = { 22, NULL, 0, 1, NULL, 1, NULL };
  VkPipelineRasterizationStateCreateInfo rs = { 23, NULL, 0, 0, 0, 0, k[2],
    k[3], 0, 0.0f, 0.0f, 0.0f, 1.0f };
  VkPipelineMultisampleStateCreateInfo ms = { 24, NULL, 0, 1, 0, 0.0f, NULL,
    0, 0 };
  VkPipelineColorBlendAttachmentState cb = { k[4], k[5], k[6], k[7], k[8],
    k[9], k[10], k[11] };
  VkPipelineColorBlendStateCreateInfo bs = { 26, NULL, 0, 0, 0, 1, &cb,
    { 0, 0, 0, 0 } };
  VkEnum dyn_states[2] = { 0, 1 };
  VkPipelineDynamicStateCreateInfo ds = { 27, NULL, 0, 2, dyn_states };
  VkEnum fmt = k[0];
  VkPipelineRenderingCreateInfo ri = { 1000044002, NULL, 0, 1, &fmt, 0, 0 };
  VkGraphicsPipelineCreateInfo ci = { 28, &ri, 0, 2, st, &vi, &ia, NULL, &vp,
    &rs, &ms, NULL, &bs, &ds, l->h, 0, 0, 0, -1 };
  VkHandle p;
  VX_TRY(e, vkCreateGraphicsPipelines(vx_dev(d), 0, 1, &ci, NULL, &p),
    "vkCreateGraphicsPipelines");
  return vx_slot_done(e, VX_PIPELINE, (u32)f[0], p, 0);
}

static void __attribute__((constructor)) vx_vk_pipeline_use(void) {
  io_eff(CID(vk_pipeline), vx_vk_pipeline_run, 0);
}

#endif

// Vulkan: commands and synchronization
// ------------------------------------

#ifdef CID(vk_command_pool)

// A pool on the device's queue family; flags as VkCommandPoolCreateFlags.
Term vx_vk_command_pool_run(Env e, Term* f, IoWork* w) {
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  if (d == NULL) {
    return VX_BAD(e, "device");
  }
  VkCommandPoolCreateInfo ci = { 39, NULL, (u32)f[1], (u32)d->size };
  VkHandle p;
  VX_TRY(e, vkCreateCommandPool(vx_dev(d), &ci, NULL, &p),
    "vkCreateCommandPool");
  return vx_slot_done(e, VX_CMD_POOL, (u32)f[0], p, 0);
}

static void __attribute__((constructor)) vx_vk_command_pool_use(void) {
  io_eff(CID(vk_command_pool), vx_vk_command_pool_run, 0);
}

#endif

#ifdef CID(vk_command_buffer)

// A primary command buffer; it dies with its pool.
Term vx_vk_command_buffer_run(Env e, Term* f, IoWork* w) {
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  VxSlot* p = vx_get((u32)f[1], VX_CMD_POOL);
  if (d == NULL || p == NULL) {
    return VX_BAD(e, "device or command pool");
  }
  VkCommandBufferAllocateInfo ai = { 40, NULL, p->h, 0, 1 };
  VkCommandBuffer cb;
  VX_TRY(e, vkAllocateCommandBuffers(vx_dev(d), &ai, &cb),
    "vkAllocateCommandBuffers");
  return vx_slot_done(e, VX_CMD, (u32)f[0], (u64)(intptr_t)cb, 0);
}

static void __attribute__((constructor)) vx_vk_command_buffer_use(void) {
  io_eff(CID(vk_command_buffer), vx_vk_command_buffer_run, 0);
}

#endif

#ifdef CID(vk_record)

// Resets and records a command buffer from op words that Bend encoded
// (commands.bend). Each op is a fixed translation to one vkCmd* call:
//  1 barrier   image oldLayout newLayout srcStage dstStage srcAccess dstAccess
//  2 render    view width height loadOp clearRGBA8
//  3 end render
//  4 viewport  x y width height
//  5 scissor   x y width height
//  6 pipeline  pipeline
//  7 set       layout set
//  8 push      layout stages count word*
//  9 vertices  binding buffer offset
// 10 draw      vertexCount instanceCount firstVertex firstInstance
// 11 copy      buffer image width height bufferOffset
// 12 region    buffer image x y width height bufferOffset
// 13 readback  image buffer width height bufferOffset
// 14 memory    srcStage dstStage srcAccess dstAccess
// 15 imgcopy   srcImage dstImage x y width height
static const u8 vx_arity[16] = { 0, 7, 5, 0, 4, 4, 1, 2, 3, 3, 4, 5, 7, 5, 4, 6 };

static Term vx_record(Env e, u32 dev, VkCommandBuffer cb, const u32* k,
  u64 n) {
  VkCommandBufferBeginInfo bi = { 42, NULL, 1, NULL };
  VX_TRY(e, vkResetCommandBuffer(cb, 0), "vkResetCommandBuffer");
  VX_TRY(e, vkBeginCommandBuffer(cb, &bi), "vkBeginCommandBuffer");
  for (u64 i = 0; i < n;) {
    u32 op = k[i];
    if (op == 0 || op > 15 || i + 1 + vx_arity[op] > n) {
      return VX_BAD(e, "command word");
    }
    const u32* a = k + i + 1;
    i += 1 + vx_arity[op];
    if (op == 1) {
      VxSlot* img = vx_image(a[0]);
      if (img == NULL) {
        return VX_BAD(e, "barrier image");
      }
      VkImageMemoryBarrier b = { 45, NULL, a[5], a[6], a[1], a[2], ~0u, ~0u,
        img->h, { 1, 0, 1, 0, 1 } };
      vkCmdPipelineBarrier(cb, a[3], a[4], 0, 0, NULL, 0, NULL, 1, &b);
    } else if (op == 2) {
      VxSlot* v = vx_get(a[0], VX_VIEW);
      if (v == NULL) {
        return VX_BAD(e, "render target view");
      }
      u32 c = a[4];
      VkRenderingAttachmentInfo at = { 1000044001, NULL, v->h, 2, 0, 0, 0,
        a[3], 0, { .float32 = { (c >> 24) / 255.0f, (c >> 16 & 255) / 255.0f,
        (c >> 8 & 255) / 255.0f, (c & 255) / 255.0f } } };
      VkRenderingInfo ri = { 1000044000, NULL, 0, { { 0, 0 }, { a[1], a[2] } },
        1, 0, 1, &at, NULL, NULL };
      vkCmdBeginRendering(cb, &ri);
    } else if (op == 3) {
      vkCmdEndRendering(cb);
    } else if (op == 4) {
      VkViewport vp = { (float)(int32_t)a[0], (float)(int32_t)a[1],
        (float)a[2], (float)a[3], 0.0f, 1.0f };
      vkCmdSetViewport(cb, 0, 1, &vp);
    } else if (op == 5) {
      VkRect2D sc = { { (int32_t)a[0], (int32_t)a[1] }, { a[2], a[3] } };
      vkCmdSetScissor(cb, 0, 1, &sc);
    } else if (op == 6) {
      VxSlot* p = vx_get(a[0], VX_PIPELINE);
      if (p == NULL) {
        return VX_BAD(e, "pipeline");
      }
      vkCmdBindPipeline(cb, 0, p->h);
    } else if (op == 7) {
      VxSlot* l = vx_get(a[0], VX_LAYOUT);
      VxSlot* s = vx_get(a[1], VX_SET);
      if (l == NULL || s == NULL) {
        return VX_BAD(e, "descriptor binding");
      }
      vkCmdBindDescriptorSets(cb, 0, l->h, 0, 1, &s->h, 0, NULL);
    } else if (op == 8) {
      VxSlot* l = vx_get(a[0], VX_LAYOUT);
      if (l == NULL || a[2] > 32 || i + a[2] > n) {
        return VX_BAD(e, "push constants");
      }
      vkCmdPushConstants(cb, l->h, a[1], 0, a[2] * 4, a + 3);
      i += a[2];
    } else if (op == 9) {
      VxSlot* b = vx_get(a[1], VX_BUFFER);
      if (b == NULL) {
        return VX_BAD(e, "vertex buffer");
      }
      VkDeviceSize off = a[2];
      vkCmdBindVertexBuffers(cb, a[0], 1, &b->h, &off);
    } else if (op == 10) {
      vkCmdDraw(cb, a[0], a[1], a[2], a[3]);
    } else if (op == 11) {
      VxSlot* b = vx_get(a[0], VX_BUFFER);
      VxSlot* img = vx_get(a[1], VX_IMAGE);
      if (b == NULL || img == NULL) {
        return VX_BAD(e, "copy operands");
      }
      VkBufferImageCopy c = { a[4], 0, 0, { 1, 0, 0, 1 }, { 0, 0, 0 },
        { a[2], a[3], 1 } };
      vkCmdCopyBufferToImage(cb, b->h, img->h, 7, 1, &c);
    } else if (op == 12) {
      VxSlot* b = vx_get(a[0], VX_BUFFER);
      VxSlot* img = vx_get(a[1], VX_IMAGE);
      if (b == NULL || img == NULL) {
        return VX_BAD(e, "region copy operands");
      }
      VkBufferImageCopy c = { a[6], 0, 0, { 1, 0, 0, 1 },
        { (int32_t)a[2], (int32_t)a[3], 0 }, { a[4], a[5], 1 } };
      vkCmdCopyBufferToImage(cb, b->h, img->h, 7, 1, &c);
    } else if (op == 13) {
      VxSlot* img = vx_image(a[0]);
      VxSlot* b = vx_get(a[1], VX_BUFFER);
      if (img == NULL || b == NULL) {
        return VX_BAD(e, "readback operands");
      }
      VkBufferImageCopy c = { a[4], 0, 0, { 1, 0, 0, 1 }, { 0, 0, 0 },
        { a[2], a[3], 1 } };
      vkCmdCopyImageToBuffer(cb, img->h, 6, b->h, 1, &c);
    } else if (op == 14) {
      VkMemoryBarrier m = { 46, NULL, a[2], a[3] };
      vkCmdPipelineBarrier(cb, a[0], a[1], 0, 1, &m, 0, NULL, 0, NULL);
    } else if (op == 15) {
      VxSlot* src = vx_image(a[0]);
      VxSlot* dst = vx_image(a[1]);
      if (src == NULL || dst == NULL) {
        return VX_BAD(e, "image copy operands");
      }
      VkImageCopy c = { { 1, 0, 0, 1 }, { (int32_t)a[2], (int32_t)a[3], 0 },
        { 1, 0, 0, 1 }, { (int32_t)a[2], (int32_t)a[3], 0 }, { a[4], a[5], 1 } };
      vkCmdCopyImage(cb, src->h, 6, dst->h, 7, 1, &c);
    }
  }
  VX_TRY(e, vkEndCommandBuffer(cb), "vkEndCommandBuffer");
  return io_done(e, term_pak(CID(Unit), 0));
}

Term vx_vk_record_run(Env e, Term* f, IoWork* w) {
  VxSlot* c = vx_get((u32)f[0], VX_CMD);
  u64 cap = 0;
  u32* ops = vx_array(e, f[1], &cap);
  u64 count = (u32)f[2];
  Term r = c == NULL || count > cap ? VX_BAD(e, "record arguments")
    : vx_record(e, c->dev, (VkCommandBuffer)(intptr_t)c->h, ops, count);
  return io_tup(e, f[1], r);
}

static void __attribute__((constructor)) vx_vk_record_use(void) {
  io_eff(CID(vk_record), vx_vk_record_run, 0);
}

#endif

#ifdef CID(vk_semaphore)

Term vx_vk_semaphore_run(Env e, Term* f, IoWork* w) {
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  if (d == NULL) {
    return VX_BAD(e, "device");
  }
  VkSemaphoreCreateInfo ci = { 9, NULL, 0 };
  VkHandle s;
  VX_TRY(e, vkCreateSemaphore(vx_dev(d), &ci, NULL, &s), "vkCreateSemaphore");
  return vx_slot_done(e, VX_SEMAPHORE, (u32)f[0], s, 0);
}

static void __attribute__((constructor)) vx_vk_semaphore_use(void) {
  io_eff(CID(vk_semaphore), vx_vk_semaphore_run, 0);
}

#endif

#ifdef CID(vk_fence)

Term vx_vk_fence_run(Env e, Term* f, IoWork* w) {
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  if (d == NULL) {
    return VX_BAD(e, "device");
  }
  VkFenceCreateInfo ci = { 8, NULL, term_aux(f[1]) == CID(True) ? 1u : 0u };
  VkHandle s;
  VX_TRY(e, vkCreateFence(vx_dev(d), &ci, NULL, &s), "vkCreateFence");
  return vx_slot_done(e, VX_FENCE, (u32)f[0], s, 0);
}

static void __attribute__((constructor)) vx_vk_fence_use(void) {
  io_eff(CID(vk_fence), vx_vk_fence_run, 0);
}

#endif

#ifdef CID(vk_wait)

// Waits for a fence up to `ms`; then resets it when `reset` is True.
// Answers 0 signaled, 1 timed out (left unreset).
Term vx_vk_wait_run(Env e, Term* f, IoWork* w) {
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  VxSlot* fe = vx_get((u32)f[1], VX_FENCE);
  if (d == NULL || fe == NULL) {
    return VX_BAD(e, "device or fence");
  }
  VkResult r = vkWaitForFences(vx_dev(d), 1, &fe->h, 1,
    (uint64_t)(u32)f[2] * 1000000ull);
  if (r < 0) {
    return vx_err(e, (u32)-r, "vkWaitForFences", r);
  }
  if (r == 0 && term_aux(f[3]) == CID(True)) {
    VX_TRY(e, vkResetFences(vx_dev(d), 1, &fe->h), "vkResetFences");
  }
  return io_done(e, (Term)(u32)(r == 0 ? 0 : 1));
}

static void __attribute__((constructor)) vx_vk_wait_use(void) {
  io_eff(CID(vk_wait), vx_vk_wait_run, 0);
}

#endif

#ifdef CID(vk_submit)

// One command buffer; wait semaphore (0: none) at waitStage; signal
// semaphore (0: none); fence (0: none).
Term vx_vk_submit_run(Env e, Term* f, IoWork* w) {
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  VxSlot* c = vx_get((u32)f[1], VX_CMD);
  VxSlot* ws = vx_get((u32)f[2], VX_SEMAPHORE);
  VxSlot* ss = vx_get((u32)f[4], VX_SEMAPHORE);
  VxSlot* fe = vx_get((u32)f[5], VX_FENCE);
  if (d == NULL || c == NULL || ((u32)f[2] != 0 && ws == NULL)
    || ((u32)f[4] != 0 && ss == NULL) || ((u32)f[5] != 0 && fe == NULL)) {
    return VX_BAD(e, "submit arguments");
  }
  VkFlags stage = (u32)f[3];
  VkCommandBuffer cb = (VkCommandBuffer)(intptr_t)c->h;
  VkSubmitInfo si = { 4, NULL, ws != NULL, ws != NULL ? &ws->h : NULL,
    &stage, 1, &cb, ss != NULL, ss != NULL ? &ss->h : NULL };
  VX_TRY(e, vkQueueSubmit((VkQueue)(intptr_t)d->x, 1, &si,
    fe != NULL ? fe->h : 0), "vkQueueSubmit");
  return io_done(e, term_pak(CID(Unit), 0));
}

static void __attribute__((constructor)) vx_vk_submit_use(void) {
  io_eff(CID(vk_submit), vx_vk_submit_run, 0);
}

#endif

#ifdef CID(vk_idle)

Term vx_vk_idle_run(Env e, Term* f, IoWork* w) {
  VxSlot* d = vx_get((u32)f[0], VX_DEVICE);
  if (d == NULL) {
    return VX_BAD(e, "device");
  }
  VX_TRY(e, vkDeviceWaitIdle(vx_dev(d)), "vkDeviceWaitIdle");
  return io_done(e, term_pak(CID(Unit), 0));
}

static void __attribute__((constructor)) vx_vk_idle_use(void) {
  io_eff(CID(vk_idle), vx_vk_idle_run, 0);
}

#endif

// Lifetimes
// ---------

#ifdef CID(destroy)

// Destroys the object in a slot and frees the slot. Order is the caller's
// responsibility (children before their device, device before instance,
// surfaces before the window that Ankra closes).
Term vx_destroy_run(Env e, Term* f, IoWork* w) {
  u32 id = (u32)f[0];
  if (id == 0 || id >= VX_SLOTS || vx_slot[id].kind == VX_FREE) {
    return VX_BAD(e, "slot");
  }
  VxSlot* s = &vx_slot[id];
  VkDevice d = s->dev != 0 && vx_slot[s->dev].kind == VX_DEVICE
    ? vx_dev(&vx_slot[s->dev]) : NULL;
  VkInstance inst = s->dev != 0 && vx_slot[s->dev].kind == VX_INSTANCE
    ? (VkInstance)(intptr_t)vx_slot[s->dev].h : NULL;
  switch (s->kind) {
    case VX_INSTANCE:
      if (vx_messenger != 0) {
        vkDestroyDebugUtilsMessengerEXT((VkInstance)(intptr_t)s->h,
          vx_messenger, NULL);
        vx_messenger = 0;
      }
      vkDestroyInstance((VkInstance)(intptr_t)s->h, NULL);
      break;
    case VX_SURFACE:   vkDestroySurfaceKHR(inst, s->h, NULL); break;
    case VX_DEVICE:    vkDestroyDevice(vx_dev(s), NULL); break;
    case VX_SWAPCHAIN: vkDestroySwapchainKHR(d, s->h, NULL); break;
    case VX_IMAGE:     vkDestroyImage(d, s->h, NULL); break;
    case VX_VIEW:      vkDestroyImageView(d, s->h, NULL); break;
    case VX_BUFFER:    vkDestroyBuffer(d, s->h, NULL); break;
    case VX_MEMORY:    vkFreeMemory(d, s->h, NULL); break;
    case VX_SAMPLER:   vkDestroySampler(d, s->h, NULL); break;
    case VX_SET_LAYOUT: vkDestroyDescriptorSetLayout(d, s->h, NULL); break;
    case VX_POOL:      vkDestroyDescriptorPool(d, s->h, NULL); break;
    case VX_SHADER:    vkDestroyShaderModule(d, s->h, NULL); break;
    case VX_LAYOUT:    vkDestroyPipelineLayout(d, s->h, NULL); break;
    case VX_PIPELINE:  vkDestroyPipeline(d, s->h, NULL); break;
    case VX_CMD_POOL:  vkDestroyCommandPool(d, s->h, NULL); break;
    case VX_SEMAPHORE: vkDestroySemaphore(d, s->h, NULL); break;
    case VX_FENCE:     vkDestroyFence(d, s->h, NULL); break;
    default: break;  // swapchain images, sets, command buffers: owned above
  }
  *s = (VxSlot){ 0 };
  vx_live -= 1;
  return io_done(e, term_pak(CID(Unit), 0));
}

static void __attribute__((constructor)) vx_destroy_use(void) {
  io_eff(CID(destroy), vx_destroy_run, 0);
}

#endif

#ifdef CID(stats)

// [live slots, validation warnings, validation errors, layer enabled].
Term vx_stats_run(Env e, Term* f, IoWork* w) {
  u32 out[4] = { vx_live, vx_warnings, vx_errors, vx_layer_on };
  return io_done(e, vx_list(e, out, 4));
}

static void __attribute__((constructor)) vx_stats_use(void) {
  io_eff(CID(stats), vx_stats_run, 0);
}

#endif
