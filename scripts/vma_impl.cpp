// Single translation unit that compiles the VMA implementation into a static
// library. Defines are fixed here so any rebuild reproduces the same ABI.
#define VMA_IMPLEMENTATION
#define VMA_STATIC_VULKAN_FUNCTIONS 1
#define VMA_DYNAMIC_VULKAN_FUNCTIONS 0
#define VMA_EXTERNAL_MEMORY 0
#include <vma/vk_mem_alloc.h>
