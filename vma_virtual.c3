module vma;

import vk;

struct VirtualAllocationResult {
    VirtualAllocation allocation;
    vk::DeviceSize    offset;
}

fn VirtualBlock? try_create_virtual_block(VirtualBlockCreateInfo* info) {
    VirtualBlock block;
    check(create_virtual_block(info, &block))!;
    return block;
}

<* Allocate a range from the virtual block. Returns the allocation handle and its
   chosen offset. Free with `block.free(result.allocation)`. *>
fn VirtualAllocationResult? VirtualBlock.try_allocate(self, VirtualAllocationCreateInfo* ci) {
    VirtualAllocationResult r;
    check(self.allocate(ci, &r.allocation, &r.offset))!;
    return r;
}

fn VirtualAllocationInfo VirtualBlock.allocation_info(self, VirtualAllocation allocation) {
    VirtualAllocationInfo out_info;
    self.get_allocation_info(allocation, &out_info);
    return out_info;
}

fn Statistics VirtualBlock.statistics(self) {
    Statistics out_stats;
    self.get_statistics(&out_stats);
    return out_stats;
}

fn DetailedStatistics VirtualBlock.detailed_statistics(self) {
    DetailedStatistics out_stats;
    self.calculate_statistics(&out_stats);
    return out_stats;
}

<* Build the virtual block's JSON statistics dump as a heap-owned String; the caller
   frees it with `free(s.ptr)`. `detailed` adds per-allocation detail. *>
fn String VirtualBlock.stats_string(self, bool detailed) {
    ZString raw;
    self.build_stats_string(&raw, (vk::Bool32)detailed);
    defer self.free_stats_string(raw);
    return raw.copy(mem);
}
