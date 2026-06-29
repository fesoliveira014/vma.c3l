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
    std::printf("PoolCreateInfo %zu\n", sizeof(VmaPoolCreateInfo));
    std::printf("DefragmentationInfo %zu\n", sizeof(VmaDefragmentationInfo));
    std::printf("DefragmentationMove %zu\n", sizeof(VmaDefragmentationMove));
    std::printf("DefragmentationPassMoveInfo %zu\n", sizeof(VmaDefragmentationPassMoveInfo));
    std::printf("DefragmentationStats %zu\n", sizeof(VmaDefragmentationStats));
    std::printf("VirtualBlockCreateInfo %zu\n", sizeof(VmaVirtualBlockCreateInfo));
    std::printf("VirtualAllocationCreateInfo %zu\n", sizeof(VmaVirtualAllocationCreateInfo));
    std::printf("VirtualAllocationInfo %zu\n", sizeof(VmaVirtualAllocationInfo));
    std::printf("AllocationInfo2 %zu\n", sizeof(VmaAllocationInfo2));
    return 0;
}
