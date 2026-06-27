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

struct MemoryAllocation {
    Allocation     allocation;
    AllocationInfo info;
}

<* Map an allocation's memory and return it as a bounded slice. The length is the
   allocation size from `get_allocation_info`. Pair with `unmap_memory`. *>
fn char[]? Allocator.try_map(self, Allocation allocation) {
    void* p;
    check(self.map_memory(allocation, &p))!;
    AllocationInfo info;
    self.get_allocation_info(allocation, &info);
    return ((char*)p)[:info.size];
}

fn void? Allocator.try_flush(self, Allocation allocation, vk::DeviceSize offset, vk::DeviceSize size) {
    check(self.flush_allocation(allocation, offset, size))!;
}

fn void? Allocator.try_invalidate(self, Allocation allocation, vk::DeviceSize offset, vk::DeviceSize size) {
    check(self.invalidate_allocation(allocation, offset, size))!;
}

fn void? Allocator.try_copy_to_allocation(self, void* src, Allocation allocation, vk::DeviceSize dst_offset, vk::DeviceSize size) {
    check(self.copy_memory_to_allocation(src, allocation, dst_offset, size))!;
}

fn void? Allocator.try_copy_from_allocation(self, Allocation allocation, vk::DeviceSize src_offset, void* dst, vk::DeviceSize size) {
    check(self.copy_allocation_to_memory(allocation, src_offset, dst, size))!;
}

<* Allocate memory sized/typed for an existing buffer (does not bind it; call
   `try_bind_buffer_memory` after). Free with `free_memory`. *>
fn MemoryAllocation? Allocator.try_allocate_memory_for_buffer(self, vk::Buffer buffer, AllocationCreateInfo* ci) {
    MemoryAllocation ma;
    check(self.allocate_memory_for_buffer(buffer, ci, &ma.allocation, &ma.info))!;
    return ma;
}

fn void? Allocator.try_bind_buffer_memory(self, Allocation allocation, vk::Buffer buffer) {
    check(self.bind_buffer_memory(allocation, buffer))!;
}
