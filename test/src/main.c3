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
    POOL_STATS_EMPTY;

const ulong BUFFER_SIZE = 65536;
const uint MAP_CHECK_BYTES = 4;

fn int main() {
    if (catch err = run()) {
        io::printfn("vma smoke FAILED: %s", err);
        return 1;
    }
    io::printn("vma smoke OK: map + image + manual buffer/reqs/image + stats + pool");
    return 0;
}

fn void? run() {
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
