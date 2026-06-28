module vma_smoke;

import vk;

faultdef
    NO_PHYSICAL_DEVICE,
    NO_USABLE_DEVICE;

const uint VK_API_1_0 = 1 << 22;
const uint VK_API_1_1 = (1 << 22) | (1 << 12);

struct HeadlessVk {
    vk::Instance       instance;
    vk::PhysicalDevice physical_device;
    vk::Device         device;
}

<* Create a headless Vulkan instance + logical device (no window/surface).
   Picks the first physical device whose logical-device creation succeeds,
   which selects a working ICD (e.g. lavapipe) under WSL's multi-ICD setup. *>
fn HeadlessVk? create_headless_vk() {
    HeadlessVk h;

    vk::ApplicationInfo app = {
        .s_type      = vk::StructureType.APPLICATION_INFO,
        .api_version = VK_API_1_1,
    };
    vk::InstanceCreateInfo ici = {
        .s_type             = vk::StructureType.INSTANCE_CREATE_INFO,
        .p_application_info = &app,
    };
    vk::try_create_instance(&ici, null, &h.instance)!;
    defer catch vk::destroy_instance(h.instance, null);

    uint count = 0;
    vk::try_enumerate_physical_devices(h.instance, &count, null)!;
    if (count == 0) return NO_PHYSICAL_DEVICE~;
    if (count > 32) count = 32;
    vk::PhysicalDevice[32] devices;
    vk::try_enumerate_physical_devices(h.instance, &count, &devices[0])!;

    float priority = 1.0;
    vk::DeviceQueueCreateInfo qci = {
        .s_type             = vk::StructureType.DEVICE_QUEUE_CREATE_INFO,
        .queue_family_index = 0,
        .queue_count        = 1,
        .p_queue_priorities = &priority,
    };
    vk::DeviceCreateInfo dci = {
        .s_type                  = vk::StructureType.DEVICE_CREATE_INFO,
        .queue_create_info_count = 1,
        .p_queue_create_infos    = &qci,
    };

    for (uint i = 0; i < count; i++) {
        vk::PhysicalDevice pd = devices[i];
        if (catch err = vk::try_create_device(pd, &dci, null, &h.device)) {
            continue;
        }
        h.physical_device = pd;
        return h;
    }
    return NO_USABLE_DEVICE~;
}

fn void destroy_headless_vk(HeadlessVk* h) {
    vk::destroy_device(h.device, null);
    vk::destroy_instance(h.instance, null);
}
