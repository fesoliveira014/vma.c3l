module vma;

import vk;

<* Check default-pool corruption for the given memory types. Returns normally on
   SUCCESS; raises FEATURE_NOT_PRESENT when corruption detection is disabled (callers
   typically accept it) and CORRUPTION_DETECTED when corruption is found (VMA reports
   it as VK_ERROR_UNKNOWN). *>
fn void? Allocator.try_check_corruption(self, uint memory_type_bits) {
    vk::Result r = self.check_corruption(memory_type_bits);
    switch (r) {
        case vk::Result.SUCCESS:       return;
        case vk::Result.ERROR_UNKNOWN: return CORRUPTION_DETECTED~;
        default:                       check(r)!;
    }
}

fn vk::MemoryPropertyFlags Allocator.allocation_memory_properties(self, Allocation allocation) {
    vk::MemoryPropertyFlags out_flags;
    self.get_allocation_memory_properties(allocation, &out_flags);
    return out_flags;
}

fn AllocationInfo2 Allocator.allocation_info2(self, Allocation allocation) {
    AllocationInfo2 out_info;
    self.get_allocation_info2(allocation, &out_info);
    return out_info;
}

fn vk::Buffer? Allocator.try_create_aliasing_buffer(self, Allocation allocation, vk::BufferCreateInfo* bi) {
    vk::Buffer out_buffer;
    check(self.create_aliasing_buffer(allocation, bi, &out_buffer))!;
    return out_buffer;
}

fn vk::Image? Allocator.try_create_aliasing_image(self, Allocation allocation, vk::ImageCreateInfo* ii) {
    vk::Image out_image;
    check(self.create_aliasing_image(allocation, ii, &out_image))!;
    return out_image;
}

fn BufferAllocation? Allocator.try_create_buffer_with_alignment(self, vk::BufferCreateInfo* bi, AllocationCreateInfo* ci, vk::DeviceSize min_alignment) {
    BufferAllocation ba;
    check(self.create_buffer_with_alignment(bi, ci, min_alignment, &ba.buffer, &ba.allocation, &ba.info))!;
    return ba;
}

<* Allocate a batch of pages, one per (reqs, cis) pair. The three slices must be the
   same length (an empty batch is a no-op); results land in out_allocs. Free with
   free_memory_pages. *>
fn void? Allocator.try_allocate_memory_pages(self, vk::MemoryRequirements[] reqs, AllocationCreateInfo[] cis, Allocation[] out_allocs) {
    if (reqs.len != cis.len || reqs.len != out_allocs.len) return BATCH_LENGTH_MISMATCH~;
    if (out_allocs.len == 0) return;
    check(self.allocate_memory_pages(&reqs[0], &cis[0], (usz)out_allocs.len, &out_allocs[0], null))!;
}
