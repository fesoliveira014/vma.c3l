module vma;

import vk;

faultdef
    OUT_OF_HOST_MEMORY,
    OUT_OF_DEVICE_MEMORY,
    INITIALIZATION_FAILED,
    MEMORY_MAP_FAILED,
    FEATURE_NOT_PRESENT,
    TOO_MANY_OBJECTS,
    INVALID_EXTERNAL_HANDLE,
    BATCH_LENGTH_MISMATCH,
    CORRUPTION_DETECTED,
    UNKNOWN;

<* Map a VkResult to a vma fault. Returns normally on VK_SUCCESS. *>
fn void? check(vk::Result r) {
    switch (r) {
        case vk::Result.SUCCESS:                       return;
        case vk::Result.ERROR_OUT_OF_HOST_MEMORY:      return OUT_OF_HOST_MEMORY~;
        case vk::Result.ERROR_OUT_OF_DEVICE_MEMORY:    return OUT_OF_DEVICE_MEMORY~;
        case vk::Result.ERROR_INITIALIZATION_FAILED:   return INITIALIZATION_FAILED~;
        case vk::Result.ERROR_MEMORY_MAP_FAILED:       return MEMORY_MAP_FAILED~;
        case vk::Result.ERROR_FEATURE_NOT_PRESENT:     return FEATURE_NOT_PRESENT~;
        case vk::Result.ERROR_TOO_MANY_OBJECTS:        return TOO_MANY_OBJECTS~;
        case vk::Result.ERROR_INVALID_EXTERNAL_HANDLE: return INVALID_EXTERNAL_HANDLE~;
        default:                                       return UNKNOWN~;
    }
}

<* Create an allocator, returning a vma fault instead of a raw VkResult. *>
fn Allocator? try_create_allocator(AllocatorCreateInfo* info) {
    Allocator a;
    check(create_allocator(info, &a))!;
    return a;
}
