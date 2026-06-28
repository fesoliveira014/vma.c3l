# M4 — Custom pools (design)

Date: 2026-06-28
Status: approved (brainstorming)
Predecessor: [M3 design](2026-06-27-m3-statistics-budget-design.md) · [roadmap](2026-06-26-vma-binding-roadmap-design.md)

Bind VMA's custom-pool surface — create/destroy a `Pool`, allocate from it, query
its statistics, name it, check it for corruption — plus the find-memory-type-index
helpers that are the idiomatic way to choose a pool's memory type. After M4 a
consumer can carve a dedicated `VkDeviceMemory` sub-allocator out of one memory
type and route buffer/image allocations through it.

## Context

M0–M3 shipped the allocator lifecycle, the allocation/buffer/image paths, host
memory access, and the statistics & budget surface. M4 builds directly on M1's
`AllocationCreateInfo`/`try_create_buffer` and **reuses M3's `Statistics` /
`DetailedStatistics`** — pool statistics are reported through those same structs,
so M4 introduces only one new layout-pinned struct (`PoolCreateInfo`).

Custom pools are unusable without two things M1–M3 left open: a way to pick the
pool's `memoryTypeIndex` (the find-memory-type-index helpers), and a typed `pool`
field on `AllocationCreateInfo` so an allocation can name the pool it comes from.
M4 closes both.

## The shape

Mixed fault model, consistent with the rest of the binding:

- Functions returning `VkResult` (`vmaCreatePool`, `vmaCheckPoolCorruption`, the
  three `vmaFindMemoryTypeIndex*`) get `try_*` wrappers routed through M0's
  `check()`.
- Functions returning `void` (`vmaGetPoolStatistics`, `vmaCalculatePoolStatistics`,
  `vmaGetPoolName`) get by-value idiomatic accessors with no fault path — the M3
  statistics pattern.
- `vmaDestroyPool` and `vmaSetPoolName` return `void` and take no out-param, so
  they are used raw with no wrapper.

Raw externs keep the C-mapped verbs (`get_pool_statistics`, `calculate_pool_statistics`);
the by-value accessors take distinct noun names (`pool_statistics`,
`pool_detailed_statistics`) so the two layers don't collide.

## Settled decisions

1. **Scope: roadmap M4 + the find-memory-type-index helpers.** Pools cannot pick a
   memory type without them, so `vmaFindMemoryTypeIndex` /
   `vmaFindMemoryTypeIndexForBufferInfo` / `vmaFindMemoryTypeIndexForImageInfo` are
   folded in (three thin `VkResult` wrappers, no new structs). `vmaSetCurrentFrameIndex`
   stays out (M7).
2. **`AllocationCreateInfo.pool` is retyped `void*` → `Pool`.** ABI-identical
   (both pointers; `$assert` stays 48). This is what makes pools usable through the
   existing allocate paths: set `ai.pool = my_pool` and `try_create_buffer` /
   `try_allocate_*` allocate from the pool.
3. **Pool statistics reuse M3's structs.** `pool_statistics` returns `Statistics`,
   `pool_detailed_statistics` returns `DetailedStatistics`. No new stat structs.
4. **One new granular fault, `CORRUPTION_DETECTED`**, raised by
   `try_check_pool_corruption` when VMA reports `VK_ERROR_UNKNOWN` (VMA 3.3.0
   surfaces detected corruption as `ERROR_UNKNOWN`, not `ERROR_VALIDATION_FAILED_EXT`
   which the header does not use for this purpose). The mapping is handled locally in
   `try_check_pool_corruption` — `ERROR_UNKNOWN` → `CORRUPTION_DETECTED~` — not in
   the shared `check()`. `check_pool_corruption` returns `FEATURE_NOT_PRESENT` when
   the lib lacks corruption detection (ours is built without
   `VMA_DEBUG_DETECT_CORRUPTION`), `SUCCESS` when clean, `CORRUPTION_DETECTED` when
   corruption is found.
5. **`PoolCreateInfo` is layout-pinned** with `$assert(PoolCreateInfo::size == 56)`,
   the `N` from the size probe. `size_t` fields map to C3 `usz`.

## Binding surface

All signatures below are illustrative; exact forms are re-read from
`vk_mem_alloc.h` and verified with `c3-expert` at plan time per `add-binding`.

### New types — layout-pinned (`vma_pool.c3i`)

```
typedef Pool = inline void*;

bitstruct PoolCreateFlags : uint {
    bool ignore_buffer_image_granularity : 1;
    bool linear_algorithm                : 2;
}

struct PoolCreateInfo {
    uint            memory_type_index;
    PoolCreateFlags flags;
    vk::DeviceSize  block_size;
    usz             min_block_count;
    usz             max_block_count;
    float           priority;
    vk::DeviceSize  min_allocation_alignment;
    void*           memory_allocate_next;
}
$assert(PoolCreateInfo::size == 56);
```

`PoolCreateFlagBits` has only two real flags — `IGNORE_BUFFER_IMAGE_GRANULARITY_BIT`
(0x02, bit 1) and `LINEAR_ALGORITHM_BIT` (0x04, bit 2); bit 0 is unused, and the
`ALGORITHM_MASK` / `MAX_ENUM` entries are not flags and are not bound.

### Raw — pool ops (`vma_pool.c3i`)

```
fn vk::Result Allocator.create_pool(self, PoolCreateInfo* ci, Pool* out_pool) @cname("vmaCreatePool");
fn void       Allocator.destroy_pool(self, Pool pool) @cname("vmaDestroyPool");
fn void       Allocator.get_pool_statistics(self, Pool pool, Statistics* out_stats) @cname("vmaGetPoolStatistics");
fn void       Allocator.calculate_pool_statistics(self, Pool pool, DetailedStatistics* out_stats) @cname("vmaCalculatePoolStatistics");
fn vk::Result Allocator.check_pool_corruption(self, Pool pool) @cname("vmaCheckPoolCorruption");
fn void       Allocator.get_pool_name(self, Pool pool, ZString* out_name) @cname("vmaGetPoolName");
fn void       Allocator.set_pool_name(self, Pool pool, ZString name) @cname("vmaSetPoolName");
```

### Idiomatic — pool ops (`vma_pool.c3`)

```
fn Pool?              Allocator.try_create_pool(self, PoolCreateInfo* ci);
fn Statistics         Allocator.pool_statistics(self, Pool pool);
fn DetailedStatistics Allocator.pool_detailed_statistics(self, Pool pool);
fn void?              Allocator.try_check_pool_corruption(self, Pool pool);
fn ZString            Allocator.pool_name(self, Pool pool);
```

`destroy_pool` and `set_pool_name` are used raw. `pool_name` returns VMA's
internally-owned name pointer, which may be null when no name was set.

### Find-memory-type-index helpers (`vma_memory.c3i` / `.c3`)

```
// raw
fn vk::Result Allocator.find_memory_type_index(self, uint memory_type_bits, AllocationCreateInfo* ci, uint* out_index) @cname("vmaFindMemoryTypeIndex");
fn vk::Result Allocator.find_memory_type_index_for_buffer_info(self, vk::BufferCreateInfo* bi, AllocationCreateInfo* ci, uint* out_index) @cname("vmaFindMemoryTypeIndexForBufferInfo");
fn vk::Result Allocator.find_memory_type_index_for_image_info(self, vk::ImageCreateInfo* ii, AllocationCreateInfo* ci, uint* out_index) @cname("vmaFindMemoryTypeIndexForImageInfo");

// idiomatic
fn uint? Allocator.try_find_memory_type_index(self, uint memory_type_bits, AllocationCreateInfo* ci);
fn uint? Allocator.try_find_memory_type_index_for_buffer_info(self, vk::BufferCreateInfo* bi, AllocationCreateInfo* ci);
fn uint? Allocator.try_find_memory_type_index_for_image_info(self, vk::ImageCreateInfo* ii, AllocationCreateInfo* ci);
```

### `AllocationCreateInfo.pool` retype (`vma_memory.c3i`)

The M1 field `void* pool;` becomes `Pool pool;`. Pointer-width-identical, so the
existing `$assert(AllocationCreateInfo::size == 48)` is unchanged.

### `check()` extension (`vma.c3`)

Add `CORRUPTION_DETECTED` to the `faultdef` block (one fault per line). No new case
is added to `check()` — the fault is raised locally in `try_check_pool_corruption`
(see decision #4).

## Testing

Extend the headless smoke (`test/src/main.c3`) with one path, `pool_round_trip`,
exit 0 on lavapipe:

1. Build a `BufferCreateInfo` (64 KB, `TRANSFER_DST`) and `AllocationCreateInfo{ usage = AUTO }`.
2. `idx = try_find_memory_type_index_for_buffer_info(&bi, &ai)` — the pool's memory type.
3. `pool = try_create_pool({ .memory_type_index = idx })`; defer `destroy_pool(pool)`
   (declared first → runs last).
4. `set_pool_name(pool, "smoke_pool")`; assert `pool_name(pool).str_view() == "smoke_pool"`.
5. Allocate from the pool: `try_create_buffer(&bi, { .pool = pool })`; defer
   `destroy_buffer` (declared after the pool defer → runs first, before the pool is
   destroyed).
6. `pool_statistics(pool)` → assert `allocation_bytes > 0` and `block_count > 0`;
   `pool_detailed_statistics(pool)` → assert `.statistics.allocation_bytes > 0`.
7. `try_check_pool_corruption(pool)` — accept `SUCCESS`; catch and accept
   `FEATURE_NOT_PRESENT` (the lib has no corruption detection); any other fault fails
   the test.

New smoke faults: `POOL_NAME_MISMATCH`, `POOL_STATS_EMPTY`.

When allocating from a custom pool, VMA ignores the `usage`/`required`/`preferred`
fields of `AllocationCreateInfo` — the pool dictates the memory type — so the
allocation's create-info is just `{ .pool = pool }`.

## File layout

```
vma_pool.c3i   (new)  Pool, PoolCreateFlags, PoolCreateInfo + $assert, 7 raw externs
vma_pool.c3    (new)  5 idiomatic wrappers (try_create_pool, pool_statistics, pool_detailed_statistics, try_check_pool_corruption, pool_name)
vma_memory.c3i (+)    retype AllocationCreateInfo.pool -> Pool; + 3 find-memtype raw externs
vma_memory.c3  (+)    + 3 find-memtype idiomatic wrappers
vma.c3         (+)    CORRUPTION_DETECTED fault + check() case
test/src/main.c3 (+)  pool_round_trip path; updated success message
```

## Out of scope (later milestones)

- Defragmentation (M5), virtual allocator (M6).
- M7 misc: `vmaSetCurrentFrameIndex`, aliasing buffers/images,
  `vmaCreateBufferWithAlignment`, `vmaAllocateMemoryPages`/`vmaFreeMemoryPages`,
  `vmaSetAllocationName`/`vmaSetAllocationUserData`,
  `vmaGetAllocationMemoryProperties`, cross-target `linked-libs/` population.
- Non-default pool flags (`linear_algorithm`, `ignore_buffer_image_granularity`)
  are bound but not runtime-exercised.
- True corruption detection (needs a lib built with `VMA_DEBUG_DETECT_CORRUPTION`);
  the test only confirms the call path and accepts `FEATURE_NOT_PRESENT`.
