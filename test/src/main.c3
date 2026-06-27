module vma_smoke;

import vma;
import vk;
import std::io;

faultdef
    BUFFER_NULL,
    ALLOCATION_NULL,
    ALLOCATION_TOO_SMALL;

const ulong BUFFER_SIZE = 65536;

fn int main() {
    if (catch err = run()) {
        io::printfn("vma smoke FAILED: %s", err);
        return 1;
    }
    io::printn("vma smoke OK: allocator + buffer round-trip");
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

    vk::BufferCreateInfo buffer_info = {
        .s_type       = vk::StructureType.BUFFER_CREATE_INFO,
        .size         = BUFFER_SIZE,
        .usage        = vk::BufferUsageFlagBits.TRANSFER_SRC_BIT | vk::BufferUsageFlagBits.TRANSFER_DST_BIT,
        .sharing_mode = vk::SharingMode.EXCLUSIVE,
    };
    vma::AllocationCreateInfo alloc_info = { .usage = vma::MemoryUsage.AUTO };

    vma::BufferAllocation ba = alloc.try_create_buffer(&buffer_info, &alloc_info)!;
    defer alloc.destroy_buffer(ba.buffer, ba.allocation);

    if (ba.buffer == null) return BUFFER_NULL~;
    if (ba.allocation == null) return ALLOCATION_NULL~;
    if (ba.info.size < BUFFER_SIZE) return ALLOCATION_TOO_SMALL~;
}
