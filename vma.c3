module vma;

import vk;

struct BufferAllocation {
    vk::Buffer     buffer;
    Allocation     allocation;
    AllocationInfo info;
}

struct MemoryAllocation {
    Allocation     allocation;
    AllocationInfo info;
}

struct ImageAllocation {
    vk::Image      image;
    Allocation     allocation;
    AllocationInfo info;
}

struct VirtualAllocationResult {
    VirtualAllocation allocation;
    vk::DeviceSize    offset;
}

<* Create a buffer with its backing allocation, returning a vma fault instead of
   a raw VkResult. The returned handles are destroyed with
   `allocator.destroy_buffer(ba.buffer, ba.allocation)`. *>
fn BufferAllocation? Allocator.try_create_buffer(self, vk::BufferCreateInfo* buffer_info, AllocationCreateInfo* alloc_info) {
    BufferAllocation ba;
    check(self.create_buffer(buffer_info, alloc_info, &ba.buffer, &ba.allocation, &ba.info))!;
    return ba;
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

<* Find a memory type index satisfying the given memory-type bitmask and allocation create info. *>
fn uint? Allocator.try_find_memory_type_index(self, uint memory_type_bits, AllocationCreateInfo* ci) {
    uint idx;
    check(self.find_memory_type_index(memory_type_bits, ci, &idx))!;
    return idx;
}

<* Find a memory type index suitable for a buffer with the given create info (VMA creates a temporary buffer internally to query requirements). *>
fn uint? Allocator.try_find_memory_type_index_for_buffer_info(self, vk::BufferCreateInfo* bi, AllocationCreateInfo* ci) {
    uint idx;
    check(self.find_memory_type_index_for_buffer_info(bi, ci, &idx))!;
    return idx;
}

<* Find a memory type index suitable for an image with the given create info (VMA creates a temporary image internally to query requirements). *>
fn uint? Allocator.try_find_memory_type_index_for_image_info(self, vk::ImageCreateInfo* ii, AllocationCreateInfo* ci) {
    uint idx;
    check(self.find_memory_type_index_for_image_info(ii, ci, &idx))!;
    return idx;
}

<* Create an image with its backing allocation. Destroy with
   `allocator.destroy_image(ia.image, ia.allocation)`. *>
fn ImageAllocation? Allocator.try_create_image(self, vk::ImageCreateInfo* image_info, AllocationCreateInfo* alloc_info) {
    ImageAllocation ia;
    check(self.create_image(image_info, alloc_info, &ia.image, &ia.allocation, &ia.info))!;
    return ia;
}

fn void? Allocator.try_bind_image_memory(self, Allocation allocation, vk::Image image) {
    check(self.bind_image_memory(allocation, image))!;
}

<* Allocate memory sized/typed for an existing image (does not bind it; call
   `try_bind_image_memory`/`try_bind_image_memory2` after). Free with `free_memory`. *>
fn MemoryAllocation? Allocator.try_allocate_memory_for_image(self, vk::Image image, AllocationCreateInfo* ci) {
    MemoryAllocation ma;
    check(self.allocate_memory_for_image(image, ci, &ma.allocation, &ma.info))!;
    return ma;
}

fn void? Allocator.try_bind_image_memory2(self, Allocation allocation, vk::DeviceSize offset, vk::Image image, void* next) {
    check(self.bind_image_memory2(allocation, offset, image, next))!;
}

fn AllocatorInfo Allocator.info(self) {
    AllocatorInfo out_info;
    self.get_allocator_info(&out_info);
    return out_info;
}

fn vk::PhysicalDeviceProperties* Allocator.physical_device_properties(self) {
    vk::PhysicalDeviceProperties* out_props;
    self.get_physical_device_properties(&out_props);
    return out_props;
}

fn vk::PhysicalDeviceMemoryProperties* Allocator.memory_properties(self) {
    vk::PhysicalDeviceMemoryProperties* out_props;
    self.get_memory_properties(&out_props);
    return out_props;
}

fn vk::MemoryPropertyFlags Allocator.memory_type_properties(self, uint type_index) {
    vk::MemoryPropertyFlags out_flags;
    self.get_memory_type_properties(type_index, &out_flags);
    return out_flags;
}

fn TotalStatistics Allocator.statistics(self) {
    TotalStatistics out_stats;
    self.calculate_statistics(&out_stats);
    return out_stats;
}

<* Fill `out` with one Budget per memory heap and return the populated prefix.
   `out` must be at least `vk::MAX_MEMORY_HEAPS` long. *>
fn Budget[] Allocator.heap_budgets(self, Budget[] out) {
    uint heap_count = self.memory_properties().memory_heap_count;
    self.get_heap_budgets(&out[0]);
    return out[:heap_count];
}

<* Build VMA's JSON statistics dump as a heap-owned String; the caller frees it
   with `free(s.ptr)`. `detailed` adds per-block detail. *>
fn String Allocator.stats_string(self, bool detailed) {
    ZString raw;
    self.build_stats_string(&raw, (vk::Bool32)detailed);
    defer self.free_stats_string(raw);
    return raw.copy(mem);
}

fn Pool? Allocator.try_create_pool(self, PoolCreateInfo* ci) {
    Pool pool;
    check(self.create_pool(ci, &pool))!;
    return pool;
}

fn Statistics Allocator.pool_statistics(self, Pool pool) {
    Statistics out_stats;
    self.get_pool_statistics(pool, &out_stats);
    return out_stats;
}

fn DetailedStatistics Allocator.pool_detailed_statistics(self, Pool pool) {
    DetailedStatistics out_stats;
    self.calculate_pool_statistics(pool, &out_stats);
    return out_stats;
}

<* Check a pool for corruption. Requires a lib built with corruption detection;
   otherwise returns FEATURE_NOT_PRESENT. Corruption found surfaces as
   CORRUPTION_DETECTED (VMA reports it as VK_ERROR_UNKNOWN). *>
fn void? Allocator.try_check_pool_corruption(self, Pool pool) {
    vk::Result r = self.check_pool_corruption(pool);
    switch (r) {
        case vk::Result.SUCCESS:       return;
        case vk::Result.ERROR_UNKNOWN: return CORRUPTION_DETECTED~;
        default:                       check(r)!;
    }
}

<* Return VMA's internally-owned pool name pointer; may be null if no name was set. *>
fn ZString Allocator.pool_name(self, Pool pool) {
    ZString out_name;
    self.get_pool_name(pool, &out_name);
    return out_name;
}

fn DefragmentationContext? Allocator.try_begin_defragmentation(self, DefragmentationInfo* info) {
    DefragmentationContext ctx;
    check(self.begin_defragmentation(info, &ctx))!;
    return ctx;
}

<* Begin a defragmentation pass. Returns true if there are moves to process
   (VK_INCOMPLETE), false if defragmentation is finished (VK_SUCCESS). *>
fn bool? Allocator.try_begin_defragmentation_pass(self, DefragmentationContext ctx, DefragmentationPassMoveInfo* pass_info) {
    return check_pass(self.begin_defragmentation_pass(ctx, pass_info));
}

<* End a defragmentation pass. Returns true if another pass is needed
   (VK_INCOMPLETE), false if defragmentation is finished (VK_SUCCESS). *>
fn bool? Allocator.try_end_defragmentation_pass(self, DefragmentationContext ctx, DefragmentationPassMoveInfo* pass_info) {
    return check_pass(self.end_defragmentation_pass(ctx, pass_info));
}

<* Map a defragmentation pass result: SUCCESS -> false (done), INCOMPLETE -> true
   (more to do), any other result -> the corresponding vma fault. *>
fn bool? check_pass(vk::Result r) @private {
    switch (r) {
        case vk::Result.SUCCESS:    return false;
        case vk::Result.INCOMPLETE: return true;
        default:                    check(r)!;
    }
    return false;
}

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

<* Allocate a range from the virtual block. Returns the allocation handle and its
   chosen offset. Free with `block.free(result.allocation)`. *>
fn VirtualAllocationResult? VirtualBlock.try_allocate(self, VirtualAllocationCreateInfo* ci) {
    VirtualAllocationResult r;
    check(self.allocate(ci, &r.allocation, &r.offset))!;
    return r;
}

fn VirtualAllocationInfo VirtualBlock.allocation_info(self, VirtualAllocation allocation) {
    VirtualAllocationInfo out_info;
    self.get_allocation_info(allocation, &out_info);
    return out_info;
}

fn Statistics VirtualBlock.statistics(self) {
    Statistics out_stats;
    self.get_statistics(&out_stats);
    return out_stats;
}

fn DetailedStatistics VirtualBlock.detailed_statistics(self) {
    DetailedStatistics out_stats;
    self.calculate_statistics(&out_stats);
    return out_stats;
}

<* Build the virtual block's JSON statistics dump as a heap-owned String; the caller
   frees it with `free(s.ptr)`. `detailed` adds per-allocation detail. *>
fn String VirtualBlock.stats_string(self, bool detailed) {
    ZString raw;
    self.build_stats_string(&raw, (vk::Bool32)detailed);
    defer self.free_stats_string(raw);
    return raw.copy(mem);
}

<* Create an allocator, returning a vma fault instead of a raw VkResult. *>
fn Allocator? try_create_allocator(AllocatorCreateInfo* info) {
    Allocator a;
    check(create_allocator(info, &a))!;
    return a;
}

fn VirtualBlock? try_create_virtual_block(VirtualBlockCreateInfo* info) {
    VirtualBlock block;
    check(create_virtual_block(info, &block))!;
    return block;
}
