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
