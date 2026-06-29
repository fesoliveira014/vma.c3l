module vma_smoke;

import vma;
import vk;
import std::io;

faultdef
    BUFFER_NULL,
    ALLOCATION_TOO_SMALL,
    MAP_MISMATCH,
    IMAGE_NULL,
    STATS_EMPTY,
    INFO_MISMATCH,
    POOL_NAME_MISMATCH,
    POOL_STATS_EMPTY,
    DEFRAG_RUNAWAY,
    VBLOCK_NOT_EMPTY,
    VBLOCK_NOT_CLEARED,
    VALLOC_BAD_OFFSET,
    VALLOC_INFO_MISMATCH,
    VALLOC_USERDATA_MISMATCH,
    VSTATS_MISMATCH,
    MISC_NAME_MISMATCH,
    MISC_USERDATA_MISMATCH,
    MISC_MEMPROPS,
    MISC_INFO2,
    MISC_ALIGN;

const ulong BUFFER_SIZE = 65536;
const uint MAP_CHECK_BYTES = 4;
const ulong DEFRAG_BLOCK_SIZE = 131072;
const uint DEFRAG_BUFFERS = 16;
const uint MAX_DEFRAG_PASSES = 64;
const ulong VBLOCK_SIZE = 1 << 20;
const uint VALLOC_COUNT = 8;
const ulong VALLOC_SIZE = 1024;
const ulong VALLOC_ALIGN = 256;
const uint PAGE_COUNT = 4;
const ulong PAGE_SIZE = 4096;
const ulong MISC_ALIGN_REQ = 256;

fn int main() {
    if (catch err = run()) {
        io::printfn("vma smoke FAILED: %s", err);
        return 1;
    }
    io::printn("vma smoke OK: virtual + map + image + manual buffer/reqs/image + stats + pool + defrag + misc");
    return 0;
}

fn void? run() {
    virtual_round_trip()!;

    HeadlessVk h = create_headless_vk()!;
    defer destroy_headless_vk(&h);

    vma::AllocatorCreateInfo info = {
        .physical_device    = h.physical_device,
        .device             = h.device,
        .instance           = h.instance,
        .vulkan_api_version = VK_API_1_1,
    };
    vma::Allocator alloc = vma::try_create_allocator(&info)!;
    defer alloc.destroy();

    map_round_trip(alloc)!;
    image_round_trip(alloc)!;
    manual_alloc_bind(alloc, h.device)!;
    manual_reqs_bind(alloc, h.device)!;
    manual_image_bind(alloc, h.device)!;
    stats_round_trip(alloc, h.device)!;
    pool_round_trip(alloc)!;
    defrag_round_trip(alloc)!;
    misc_round_trip(alloc, h.device)!;
}

<* Map a host-visible buffer, write+flush+invalidate+read through the mapped
   slice, then exercise copy-to/from-allocation; assert the bytes survive.
   Also exercises the batch flush/invalidate variants over a one-element set. *>
fn void? map_round_trip(vma::Allocator alloc) {
    vk::BufferCreateInfo bi = {
        .s_type       = vk::StructureType.BUFFER_CREATE_INFO,
        .size         = BUFFER_SIZE,
        .usage        = vk::BufferUsageFlagBits.TRANSFER_SRC_BIT | vk::BufferUsageFlagBits.TRANSFER_DST_BIT,
        .sharing_mode = vk::SharingMode.EXCLUSIVE,
    };
    vma::AllocationCreateInfo ai = {
        .usage = vma::MemoryUsage.AUTO,
        .flags = { .host_access_random = true },
    };
    vma::BufferAllocation ba = alloc.try_create_buffer(&bi, &ai)!;
    defer alloc.destroy_buffer(ba.buffer, ba.allocation);
    if (ba.info.size < BUFFER_SIZE) return ALLOCATION_TOO_SMALL~;

    {
        char[] mapped = alloc.try_map(ba.allocation)!;
        defer alloc.unmap_memory(ba.allocation);
        for (uint i = 0; i < MAP_CHECK_BYTES; i++) mapped[i] = (char)(0x10 + i);
        alloc.try_flush(ba.allocation, 0, MAP_CHECK_BYTES)!;
    }

    vma::Allocation[1] batch_allocs  = { ba.allocation };
    vk::DeviceSize[1]  batch_offsets = { 0 };
    vk::DeviceSize[1]  batch_sizes   = { MAP_CHECK_BYTES };
    alloc.try_flush_allocations(&batch_allocs, &batch_offsets, &batch_sizes)!;

    alloc.try_invalidate(ba.allocation, 0, MAP_CHECK_BYTES)!;
    alloc.try_invalidate_allocations(&batch_allocs, &batch_offsets, &batch_sizes)!;

    bool map_ok = true;
    {
        char[] rb = alloc.try_map(ba.allocation)!;
        defer alloc.unmap_memory(ba.allocation);
        for (uint i = 0; i < MAP_CHECK_BYTES; i++) {
            if (rb[i] != (char)(0x10 + i)) map_ok = false;
        }
    }
    if (!map_ok) return MAP_MISMATCH~;

    char[MAP_CHECK_BYTES] src = { 0xDE, 0xAD, 0xBE, 0xEF };
    char[MAP_CHECK_BYTES] dst;
    alloc.try_copy_to_allocation((void*)&src, ba.allocation, 0, MAP_CHECK_BYTES)!;
    alloc.try_copy_from_allocation(ba.allocation, 0, (void*)&dst, MAP_CHECK_BYTES)!;
    for (uint i = 0; i < MAP_CHECK_BYTES; i++) {
        if (dst[i] != src[i]) return MAP_MISMATCH~;
    }
}

<* Allocate a small 2D image with its backing memory via try_create_image, free. *>
fn void? image_round_trip(vma::Allocator alloc) {
    vk::ImageCreateInfo ici = {
        .s_type         = vk::StructureType.IMAGE_CREATE_INFO,
        .image_type     = vk::ImageType.TYPE_2D,
        .format         = vk::Format.R8G8B8A8_UNORM,
        .extent         = { .width = 64, .height = 64, .depth = 1 },
        .mip_levels     = 1,
        .array_layers   = 1,
        .samples        = vk::SampleCountFlagBits.COUNT_1_BIT,
        .tiling         = vk::ImageTiling.OPTIMAL,
        .usage          = vk::ImageUsageFlagBits.SAMPLED_BIT | vk::ImageUsageFlagBits.TRANSFER_DST_BIT,
        .sharing_mode   = vk::SharingMode.EXCLUSIVE,
        .initial_layout = vk::ImageLayout.UNDEFINED,
    };
    vma::AllocationCreateInfo ai = { .usage = vma::MemoryUsage.AUTO };
    vma::ImageAllocation ia = alloc.try_create_image(&ici, &ai)!;
    defer alloc.destroy_image(ia.image, ia.allocation);
}

<* Manual buffer path: create a raw VkBuffer, allocate memory for it via
   try_allocate_memory_for_buffer, bind via bind_buffer_memory (v1), free.
   Uses GPU_ONLY: AUTO* usage is invalid for vmaAllocateMemoryForBuffer
   (no buffer-usage context — VMA hard-asserts). *>
fn void? manual_alloc_bind(vma::Allocator alloc, vk::Device device) {
    vk::BufferCreateInfo bi = {
        .s_type       = vk::StructureType.BUFFER_CREATE_INFO,
        .size         = BUFFER_SIZE,
        .usage        = vk::BufferUsageFlagBits.TRANSFER_SRC_BIT,
        .sharing_mode = vk::SharingMode.EXCLUSIVE,
    };
    vk::Buffer buffer;
    if (vk::create_buffer(device, &bi, null, &buffer) != vk::Result.SUCCESS) return BUFFER_NULL~;

    vma::AllocationCreateInfo ai = { .usage = vma::MemoryUsage.GPU_ONLY };
    vma::MemoryAllocation? ma_opt = alloc.try_allocate_memory_for_buffer(buffer, &ai);
    if (catch err = ma_opt) {
        vk::destroy_buffer(device, buffer, null);
        return err~;
    }
    vma::MemoryAllocation ma = ma_opt;

    defer alloc.free_memory(ma.allocation);
    defer vk::destroy_buffer(device, buffer, null);

    alloc.try_bind_buffer_memory(ma.allocation, buffer)!;
}

<* Raw-requirements path: create a VkBuffer, query its memory requirements,
   allocate via try_allocate_memory, bind via bind_buffer_memory2, free.
   Uses GPU_ONLY: AUTO* usage is invalid for vmaAllocateMemory from raw
   requirements (no buffer/image-usage context — VMA hard-asserts). *>
fn void? manual_reqs_bind(vma::Allocator alloc, vk::Device device) {
    vk::BufferCreateInfo bi = {
        .s_type       = vk::StructureType.BUFFER_CREATE_INFO,
        .size         = BUFFER_SIZE,
        .usage        = vk::BufferUsageFlagBits.TRANSFER_SRC_BIT,
        .sharing_mode = vk::SharingMode.EXCLUSIVE,
    };
    vk::Buffer buffer;
    if (vk::create_buffer(device, &bi, null, &buffer) != vk::Result.SUCCESS) return BUFFER_NULL~;

    vk::MemoryRequirements reqs;
    vk::get_buffer_memory_requirements(device, buffer, &reqs);

    vma::AllocationCreateInfo ai = { .usage = vma::MemoryUsage.GPU_ONLY };
    vma::MemoryAllocation? ma_opt = alloc.try_allocate_memory(&reqs, &ai);
    if (catch err = ma_opt) {
        vk::destroy_buffer(device, buffer, null);
        return err~;
    }
    vma::MemoryAllocation ma = ma_opt;

    defer alloc.free_memory(ma.allocation);
    defer vk::destroy_buffer(device, buffer, null);

    alloc.try_bind_buffer_memory2(ma.allocation, 0, buffer, null)!;
}

<* Manual image path: create a raw VkImage, allocate memory for it via
   try_allocate_memory_for_image, bind via bind_image_memory2, free. *>
fn void? manual_image_bind(vma::Allocator alloc, vk::Device device) {
    vk::ImageCreateInfo ici = {
        .s_type         = vk::StructureType.IMAGE_CREATE_INFO,
        .image_type     = vk::ImageType.TYPE_2D,
        .format         = vk::Format.R8G8B8A8_UNORM,
        .extent         = { .width = 64, .height = 64, .depth = 1 },
        .mip_levels     = 1,
        .array_layers   = 1,
        .samples        = vk::SampleCountFlagBits.COUNT_1_BIT,
        .tiling         = vk::ImageTiling.OPTIMAL,
        .usage          = vk::ImageUsageFlagBits.SAMPLED_BIT | vk::ImageUsageFlagBits.TRANSFER_DST_BIT,
        .sharing_mode   = vk::SharingMode.EXCLUSIVE,
        .initial_layout = vk::ImageLayout.UNDEFINED,
    };
    vk::Image image;
    if (vk::create_image(device, &ici, null, &image) != vk::Result.SUCCESS) return IMAGE_NULL~;

    vma::AllocationCreateInfo ai = { .usage = vma::MemoryUsage.GPU_ONLY };
    vma::MemoryAllocation? ma_opt = alloc.try_allocate_memory_for_image(image, &ai);
    if (catch err = ma_opt) {
        vk::destroy_image(device, image, null);
        return err~;
    }
    vma::MemoryAllocation ma = ma_opt;

    defer alloc.free_memory(ma.allocation);
    defer vk::destroy_image(device, image, null);

    alloc.try_bind_image_memory2(ma.allocation, 0, image, null)!;
}

<* With a live allocation present, query statistics, heap budgets, allocator
   info, properties, and the JSON stats string; assert they are populated. *>
fn void? stats_round_trip(vma::Allocator alloc, vk::Device device) {
    vk::BufferCreateInfo bi = {
        .s_type       = vk::StructureType.BUFFER_CREATE_INFO,
        .size         = BUFFER_SIZE,
        .usage        = vk::BufferUsageFlagBits.TRANSFER_DST_BIT,
        .sharing_mode = vk::SharingMode.EXCLUSIVE,
    };
    vma::AllocationCreateInfo ai = { .usage = vma::MemoryUsage.AUTO };
    vma::BufferAllocation ba = alloc.try_create_buffer(&bi, &ai)!;
    defer alloc.destroy_buffer(ba.buffer, ba.allocation);

    vma::TotalStatistics stats = alloc.statistics();
    if (stats.total.statistics.allocation_bytes == 0) return STATS_EMPTY~;
    if (stats.total.statistics.block_count == 0) return STATS_EMPTY~;

    vma::Budget[vk::MAX_MEMORY_HEAPS] budget_buf;
    vma::Budget[] budgets = alloc.heap_budgets(&budget_buf);
    if (budgets.len == 0) return STATS_EMPTY~;
    bool any_budget = false;
    foreach (b : budgets) {
        if (b.budget > 0) any_budget = true;
    }
    if (!any_budget) return STATS_EMPTY~;

    vma::AllocatorInfo ainfo = alloc.info();
    if (ainfo.device != device) return INFO_MISMATCH~;

    if (alloc.physical_device_properties() == null) return STATS_EMPTY~;
    vk::PhysicalDeviceMemoryProperties* mp = alloc.memory_properties();
    if (mp == null) return STATS_EMPTY~;

    uint combined = 0;
    for (uint i = 0; i < mp.memory_type_count; i++) {
        combined |= (uint)alloc.memory_type_properties(i);
    }
    if (combined == 0) return STATS_EMPTY~;

    String js = alloc.stats_string(true);
    defer free(js.ptr);
    if (js.len == 0) return STATS_EMPTY~;
}

<* Custom pool: find a memory type for a buffer, create a pool on it, name it,
   allocate a buffer from the pool, query pool statistics, check corruption. *>
fn void? pool_round_trip(vma::Allocator alloc) {
    vk::BufferCreateInfo bi = {
        .s_type       = vk::StructureType.BUFFER_CREATE_INFO,
        .size         = BUFFER_SIZE,
        .usage        = vk::BufferUsageFlagBits.TRANSFER_DST_BIT,
        .sharing_mode = vk::SharingMode.EXCLUSIVE,
    };
    vma::AllocationCreateInfo find_ai = { .usage = vma::MemoryUsage.AUTO };
    uint mem_type = alloc.try_find_memory_type_index_for_buffer_info(&bi, &find_ai)!;

    vma::PoolCreateInfo pci = { .memory_type_index = mem_type };
    vma::Pool pool = alloc.try_create_pool(&pci)!;
    defer alloc.destroy_pool(pool);

    alloc.set_pool_name(pool, "smoke_pool");
    if (alloc.pool_name(pool).str_view() != "smoke_pool") return POOL_NAME_MISMATCH~;

    vma::AllocationCreateInfo pool_ai = { .pool = pool };
    vma::BufferAllocation ba = alloc.try_create_buffer(&bi, &pool_ai)!;
    defer alloc.destroy_buffer(ba.buffer, ba.allocation);

    vma::Statistics ps = alloc.pool_statistics(pool);
    if (ps.allocation_bytes == 0 || ps.block_count == 0) return POOL_STATS_EMPTY~;
    vma::DetailedStatistics pds = alloc.pool_detailed_statistics(pool);
    if (pds.statistics.allocation_bytes == 0) return POOL_STATS_EMPTY~;

    if (catch err = alloc.try_check_pool_corruption(pool)) {
        if (err != vma::FEATURE_NOT_PRESENT) return err~;
    }
}

<* Fragment a small-block custom pool, then drive the full defragmentation
   begin->pass-loop->end lifecycle with operation=IGNORE (no GPU copy needed).
   Move count is best-effort (lavapipe-dependent); the loop handles zero moves. *>
fn void? defrag_round_trip(vma::Allocator alloc) {
    vk::BufferCreateInfo bi = {
        .s_type       = vk::StructureType.BUFFER_CREATE_INFO,
        .size         = BUFFER_SIZE,
        .usage        = vk::BufferUsageFlagBits.TRANSFER_SRC_BIT | vk::BufferUsageFlagBits.TRANSFER_DST_BIT,
        .sharing_mode = vk::SharingMode.EXCLUSIVE,
    };
    vma::AllocationCreateInfo find_ai = { .usage = vma::MemoryUsage.AUTO };
    uint mem_type = alloc.try_find_memory_type_index_for_buffer_info(&bi, &find_ai)!;

    vma::PoolCreateInfo pci = { .memory_type_index = mem_type, .block_size = DEFRAG_BLOCK_SIZE };
    vma::Pool pool = alloc.try_create_pool(&pci)!;
    defer alloc.destroy_pool(pool);

    vma::BufferAllocation[DEFRAG_BUFFERS] bufs;
    bool[DEFRAG_BUFFERS] live;
    defer {
        for (uint i = 0; i < DEFRAG_BUFFERS; i++) {
            if (live[i]) alloc.destroy_buffer(bufs[i].buffer, bufs[i].allocation);
        }
    }

    vma::AllocationCreateInfo pool_ai = { .pool = pool };
    for (uint i = 0; i < DEFRAG_BUFFERS; i++) {
        bufs[i] = alloc.try_create_buffer(&bi, &pool_ai)!;
        live[i] = true;
    }
    for (uint i = 0; i < DEFRAG_BUFFERS; i += 2) {
        alloc.destroy_buffer(bufs[i].buffer, bufs[i].allocation);
        live[i] = false;
    }

    vma::DefragmentationInfo info = {
        .flags = { .algorithm_balanced = true },
        .pool  = pool,
    };
    vma::DefragmentationContext ctx = alloc.try_begin_defragmentation(&info)!;
    vma::DefragmentationStats stats;
    defer alloc.end_defragmentation(ctx, &stats);

    vma::DefragmentationPassMoveInfo pass;
    uint passes = 0;
    while (alloc.try_begin_defragmentation_pass(ctx, &pass)!) {
        foreach (&m : pass.moves[:pass.move_count]) {
            m.operation = vma::DefragmentationMoveOperation.IGNORE;
        }
        passes++;
        if (passes > MAX_DEFRAG_PASSES) return DEFRAG_RUNAWAY~;
        if (!alloc.try_end_defragmentation_pass(ctx, &pass)!) break;
    }
}

<* Device-free: create a virtual block, sub-allocate ranges, check offsets/info/
   user-data/statistics round-trip, free and clear. Needs no Vulkan device. *>
fn void? virtual_round_trip() {
    vma::VirtualBlockCreateInfo bci = { .size = VBLOCK_SIZE };
    vma::VirtualBlock block = vma::try_create_virtual_block(&bci)!;
    defer block.destroy();

    if (block.is_empty() == 0) return VBLOCK_NOT_EMPTY~;

    vma::VirtualAllocation[VALLOC_COUNT] allocs;
    for (uint i = 0; i < VALLOC_COUNT; i++) {
        vma::VirtualAllocationCreateInfo aci = { .size = VALLOC_SIZE, .alignment = VALLOC_ALIGN };
        vma::VirtualAllocationResult r = block.try_allocate(&aci)!;
        allocs[i] = r.allocation;
        if (i == 0 && r.offset != 0) return VALLOC_BAD_OFFSET~;
        if (r.offset % VALLOC_ALIGN != 0) return VALLOC_BAD_OFFSET~;
    }

    if (block.is_empty() != 0) return VBLOCK_NOT_EMPTY~;

    vma::VirtualAllocationInfo info = block.allocation_info(allocs[0]);
    if (info.size != VALLOC_SIZE) return VALLOC_INFO_MISMATCH~;

    int marker = 42;
    block.set_allocation_user_data(allocs[0], &marker);
    vma::VirtualAllocationInfo info2 = block.allocation_info(allocs[0]);
    if (info2.user_data != (void*)&marker) return VALLOC_USERDATA_MISMATCH~;

    vma::Statistics stats = block.statistics();
    if (stats.allocation_count != VALLOC_COUNT) return VSTATS_MISMATCH~;
    if (stats.allocation_bytes < VALLOC_SIZE * VALLOC_COUNT) return VSTATS_MISMATCH~;
    vma::DetailedStatistics dstats = block.detailed_statistics();
    if (dstats.statistics.allocation_count != VALLOC_COUNT) return VSTATS_MISMATCH~;

    String js = block.stats_string(true);
    defer free(js.ptr);
    if (js.len == 0) return VSTATS_MISMATCH~;

    for (uint i = 0; i < VALLOC_COUNT; i++) block.free(allocs[i]);
    if (block.is_empty() == 0) return VBLOCK_NOT_EMPTY~;

    vma::VirtualAllocationCreateInfo aci2 = { .size = VALLOC_SIZE };
    block.try_allocate(&aci2)!;
    block.clear();
    if (block.is_empty() == 0) return VBLOCK_NOT_CLEARED~;
}

<* Exercise the misc leftovers: frame index, allocation name/user-data round-trip,
   memory properties, info2, corruption check, buffer-with-alignment, memory pages,
   and an aliasing buffer. *>
fn void? misc_round_trip(vma::Allocator alloc, vk::Device device) {
    alloc.set_current_frame_index(0);

    vk::BufferCreateInfo bi = {
        .s_type       = vk::StructureType.BUFFER_CREATE_INFO,
        .size         = BUFFER_SIZE,
        .usage        = vk::BufferUsageFlagBits.TRANSFER_DST_BIT,
        .sharing_mode = vk::SharingMode.EXCLUSIVE,
    };
    vma::AllocationCreateInfo ai = {
        .usage = vma::MemoryUsage.AUTO,
        .flags = { .host_access_random = true },
    };
    vma::BufferAllocation ba = alloc.try_create_buffer(&bi, &ai)!;
    defer alloc.destroy_buffer(ba.buffer, ba.allocation);

    alloc.set_allocation_name(ba.allocation, "smoke_alloc");
    vma::AllocationInfo ni;
    alloc.get_allocation_info(ba.allocation, &ni);
    if (ni.name.str_view() != "smoke_alloc") return MISC_NAME_MISMATCH~;

    int marker = 7;
    alloc.set_allocation_user_data(ba.allocation, &marker);
    vma::AllocationInfo ui;
    alloc.get_allocation_info(ba.allocation, &ui);
    if (ui.user_data != (void*)&marker) return MISC_USERDATA_MISMATCH~;

    vk::MemoryPropertyFlags mp = alloc.allocation_memory_properties(ba.allocation);
    if (((uint)mp & (uint)vk::MemoryPropertyFlagBits.HOST_VISIBLE_BIT) == 0) return MISC_MEMPROPS~;

    vma::AllocationInfo2 i2 = alloc.allocation_info2(ba.allocation);
    if (i2.allocation_info.size < BUFFER_SIZE) return MISC_INFO2~;
    if (i2.block_size < i2.allocation_info.size) return MISC_INFO2~;

    if (catch err = alloc.try_check_corruption(0xFFFFFFFF)) {
        if (err != vma::FEATURE_NOT_PRESENT) return err~;
    }

    vma::BufferAllocation aba = alloc.try_create_buffer_with_alignment(&bi, &ai, MISC_ALIGN_REQ)!;
    defer alloc.destroy_buffer(aba.buffer, aba.allocation);
    if (aba.info.offset % MISC_ALIGN_REQ != 0) return MISC_ALIGN~;

    vk::BufferCreateInfo pbi = {
        .s_type       = vk::StructureType.BUFFER_CREATE_INFO,
        .size         = PAGE_SIZE,
        .usage        = vk::BufferUsageFlagBits.TRANSFER_SRC_BIT,
        .sharing_mode = vk::SharingMode.EXCLUSIVE,
    };
    vk::Buffer probe;
    if (vk::create_buffer(device, &pbi, null, &probe) != vk::Result.SUCCESS) return BUFFER_NULL~;
    vk::MemoryRequirements one;
    vk::get_buffer_memory_requirements(device, probe, &one);
    vk::destroy_buffer(device, probe, null);

    vk::MemoryRequirements[PAGE_COUNT]   reqs;
    vma::AllocationCreateInfo[PAGE_COUNT] cis;
    vma::Allocation[PAGE_COUNT]          pages;
    for (uint i = 0; i < PAGE_COUNT; i++) {
        reqs[i] = one;
        cis[i] = { .usage = vma::MemoryUsage.GPU_ONLY };
    }
    alloc.try_allocate_memory_pages(&reqs, &cis, &pages)!;
    alloc.free_memory_pages(PAGE_COUNT, &pages[0]);

    vk::Buffer alias_buf = alloc.try_create_aliasing_buffer(ba.allocation, &bi)!;
    vk::destroy_buffer(device, alias_buf, null);
}
