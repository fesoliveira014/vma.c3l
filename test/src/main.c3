module vma_smoke;

import vma;
import vk;
import std::io;

faultdef
    BUFFER_NULL,
    ALLOCATION_NULL,
    ALLOCATION_TOO_SMALL,
    IMAGE_NULL,
    MAP_MISMATCH;

const ulong BUFFER_SIZE = 65536;

fn int main() {
    if (catch err = run()) {
        io::printfn("vma smoke FAILED: %s", err);
        return 1;
    }
    io::printn("vma smoke OK: buffer + map + image + manual alloc/bind");
    return 0;
}

fn void? run() {
    HeadlessVk h = create_headless_vk()!;
    defer destroy_headless_vk(&h);

    vma::AllocatorCreateInfo info = {
        .physical_device    = h.physical_device,
        .device             = h.device,
        .instance           = h.instance,
        .vulkan_api_version = VK_API_1_0,
    };
    vma::Allocator alloc = vma::try_create_allocator(&info)!;
    defer alloc.destroy();

    map_round_trip(alloc)!;
    image_round_trip(alloc)!;
    manual_alloc_bind(alloc, h.device)!;
}

<* Map a host-visible buffer, write+flush+invalidate+read through the mapped
   slice, then exercise copy-to/from-allocation; assert the bytes survive. *>
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

    char[] mapped = alloc.try_map(ba.allocation)!;
    for (uint i = 0; i < 4; i++) mapped[i] = (char)(0x10 + i);
    alloc.try_flush(ba.allocation, 0, 4)!;
    alloc.unmap_memory(ba.allocation);

    alloc.try_invalidate(ba.allocation, 0, 4)!;
    char[] rb = alloc.try_map(ba.allocation)!;
    bool map_ok = true;
    for (uint i = 0; i < 4; i++) {
        if (rb[i] != (char)(0x10 + i)) map_ok = false;
    }
    alloc.unmap_memory(ba.allocation);
    if (!map_ok) return MAP_MISMATCH~;

    char[4] src = { 0xDE, 0xAD, 0xBE, 0xEF };
    char[4] dst;
    alloc.try_copy_to_allocation((void*)&src, ba.allocation, 0, 4)!;
    alloc.try_copy_from_allocation(ba.allocation, 0, (void*)&dst, 4)!;
    for (uint i = 0; i < 4; i++) {
        if (dst[i] != src[i]) return MAP_MISMATCH~;
    }
}

<* Allocate a small 2D image with its backing memory, assert the handles, free. *>
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
    if (ia.image == null) return IMAGE_NULL~;
    if (ia.allocation == null) return ALLOCATION_NULL~;
}

<* Manual path: create a raw VkBuffer, allocate memory for it, bind, free. *>
fn void? manual_alloc_bind(vma::Allocator alloc, vk::Device device) {
    vk::BufferCreateInfo bi = {
        .s_type       = vk::StructureType.BUFFER_CREATE_INFO,
        .size         = BUFFER_SIZE,
        .usage        = vk::BufferUsageFlagBits.TRANSFER_SRC_BIT,
        .sharing_mode = vk::SharingMode.EXCLUSIVE,
    };
    vk::Buffer buffer;
    if (vk::create_buffer(device, &bi, null, &buffer) != vk::Result.SUCCESS) return BUFFER_NULL~;
    defer vk::destroy_buffer(device, buffer, null);

    // AUTO is invalid with vmaAllocateMemoryForBuffer (VmaBufferImageUsage::UNKNOWN); use GPU_ONLY.
    vma::AllocationCreateInfo ai = { .usage = vma::MemoryUsage.GPU_ONLY };
    vma::MemoryAllocation ma = alloc.try_allocate_memory_for_buffer(buffer, &ai)!;
    defer alloc.free_memory(ma.allocation);

    alloc.try_bind_buffer_memory(ma.allocation, buffer)!;
}
