module vma;

import vk;

struct ImageAllocation {
    vk::Image      image;
    Allocation     allocation;
    AllocationInfo info;
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
