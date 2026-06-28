module vma;

import vk;

fn Pool? Allocator.try_create_pool(self, PoolCreateInfo* ci) {
    Pool pool;
    check(self.create_pool(ci, &pool))!;
    return pool;
}

fn Statistics Allocator.pool_statistics(self, Pool pool) {
    Statistics out_stats;
    self.get_pool_statistics(pool, &out_stats);
    return out_stats;
}

fn DetailedStatistics Allocator.pool_detailed_statistics(self, Pool pool) {
    DetailedStatistics out_stats;
    self.calculate_pool_statistics(pool, &out_stats);
    return out_stats;
}

<* Check a pool for corruption. Requires a lib built with corruption detection;
   otherwise returns FEATURE_NOT_PRESENT. Corruption found surfaces as
   CORRUPTION_DETECTED (VMA reports it as VK_ERROR_UNKNOWN). *>
fn void? Allocator.try_check_pool_corruption(self, Pool pool) {
    vk::Result r = self.check_pool_corruption(pool);
    switch (r) {
        case vk::Result.SUCCESS:       return;
        case vk::Result.ERROR_UNKNOWN: return CORRUPTION_DETECTED~;
        default:                       check(r)!;
    }
}

<* Return VMA's internally-owned pool name pointer; may be null if no name was set. *>
fn ZString Allocator.pool_name(self, Pool pool) {
    ZString out_name;
    self.get_pool_name(pool, &out_name);
    return out_name;
}
