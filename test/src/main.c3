module vma_smoke;

import vma;
import vk;
import std::io;

fn int main() {
    if (catch err = run()) {
        io::printn("vma smoke FAILED");
        return 1;
    }
    io::printn("vma smoke OK: allocator create/destroy");
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
    alloc.destroy();
}
