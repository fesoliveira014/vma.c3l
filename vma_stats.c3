module vma;

import vk;

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
