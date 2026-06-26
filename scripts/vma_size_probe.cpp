#include <cstdio>
#define VMA_EXTERNAL_MEMORY 0
#include <vma/vk_mem_alloc.h>

int main(void) {
    std::printf("%zu\n", sizeof(VmaAllocatorCreateInfo));
    return 0;
}
