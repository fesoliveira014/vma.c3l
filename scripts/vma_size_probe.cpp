#include <cstdio>
#define VMA_STATIC_VULKAN_FUNCTIONS  1
#define VMA_DYNAMIC_VULKAN_FUNCTIONS 0
#define VMA_EXTERNAL_MEMORY          0
#include <vma/vk_mem_alloc.h>

int main(void) {
    std::printf("AllocatorCreateInfo %zu\n", sizeof(VmaAllocatorCreateInfo));
    std::printf("Statistics %zu\n", sizeof(VmaStatistics));
    std::printf("DetailedStatistics %zu\n", sizeof(VmaDetailedStatistics));
    std::printf("TotalStatistics %zu\n", sizeof(VmaTotalStatistics));
    std::printf("Budget %zu\n", sizeof(VmaBudget));
    std::printf("AllocatorInfo %zu\n", sizeof(VmaAllocatorInfo));
    return 0;
}
