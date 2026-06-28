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

<* Allocate memory satisfying raw VkMemoryRequirements (does not bind it; call a
   bind wrapper after). Free with `free_memory`. *>
fn MemoryAllocation? Allocator.try_allocate_memory(self, vk::MemoryRequirements* reqs, AllocationCreateInfo* ci) {
    MemoryAllocation ma;
    check(self.allocate_memory(reqs, ci, &ma.allocation, &ma.info))!;
    return ma;
}

fn void? Allocator.try_bind_buffer_memory2(self, Allocation allocation, vk::DeviceSize offset, vk::Buffer buffer, void* next) {
    check(self.bind_buffer_memory2(allocation, offset, buffer, next))!;
}

<* Flush a batch of allocations. The three slices must be equal length. *>
fn void? Allocator.try_flush_allocations(self, Allocation[] allocs, vk::DeviceSize[] offsets, vk::DeviceSize[] sizes) {
    if (allocs.len != offsets.len || allocs.len != sizes.len) return BATCH_LENGTH_MISMATCH~;
    if (allocs.len == 0) return;
    check(self.flush_allocations((uint)allocs.len, &allocs[0], &offsets[0], &sizes[0]))!;
}

<* Invalidate a batch of allocations. The three slices must be equal length. *>
fn void? Allocator.try_invalidate_allocations(self, Allocation[] allocs, vk::DeviceSize[] offsets, vk::DeviceSize[] sizes) {
    if (allocs.len != offsets.len || allocs.len != sizes.len) return BATCH_LENGTH_MISMATCH~;
    if (allocs.len == 0) return;
    check(self.invalidate_allocations((uint)allocs.len, &allocs[0], &offsets[0], &sizes[0]))!;
}

fn uint? Allocator.try_find_memory_type_index(self, uint memory_type_bits, AllocationCreateInfo* ci) {
    uint idx;
    check(self.find_memory_type_index(memory_type_bits, ci, &idx))!;
    return idx;
}

fn uint? Allocator.try_find_memory_type_index_for_buffer_info(self, vk::BufferCreateInfo* bi, AllocationCreateInfo* ci) {
    uint idx;
    check(self.find_memory_type_index_for_buffer_info(bi, ci, &idx))!;
    return idx;
}

fn uint? Allocator.try_find_memory_type_index_for_image_info(self, vk::ImageCreateInfo* ii, AllocationCreateInfo* ci) {
    uint idx;
    check(self.find_memory_type_index_for_image_info(ii, ci, &idx))!;
    return idx;
}
