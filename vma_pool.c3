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

fn void? Allocator.try_check_pool_corruption(self, Pool pool) {
    check(self.check_pool_corruption(pool))!;
}

<* Return VMA's internally-owned pool name pointer; may be null if no name was set. *>
fn ZString Allocator.pool_name(self, Pool pool) {
    ZString out_name;
    self.get_pool_name(pool, &out_name);
    return out_name;
}
