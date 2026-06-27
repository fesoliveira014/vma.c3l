module vma;

import vk;

struct BufferAllocation {
    vk::Buffer     buffer;
    Allocation     allocation;
    AllocationInfo info;
}

<* Create a buffer with its backing allocation, returning a vma fault instead of
   a raw VkResult. The returned handles are destroyed with
   `allocator.destroy_buffer(ba.buffer, ba.allocation)`. *>
fn BufferAllocation? Allocator.try_create_buffer(self, vk::BufferCreateInfo* buffer_info, AllocationCreateInfo* alloc_info) {
    BufferAllocation ba;
    check(self.create_buffer(buffer_info, alloc_info, &ba.buffer, &ba.allocation, &ba.info))!;
    return ba;
}
