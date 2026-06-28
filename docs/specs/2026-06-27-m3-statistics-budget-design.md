# M3 — Statistics, Budget + closing the M2 leftovers (design)

Date: 2026-06-27
Status: approved (brainstorming)
Predecessor: [M2 design](2026-06-26-m2-memory-images-design.md) · [roadmap](2026-06-26-vma-binding-roadmap-design.md)

Bind VMA's statistics and budget surface, and in the same pass close every
binding gap M2 deliberately deferred. After M3 the consumer can read allocator
totals, per-heap budgets, device/memory properties, and a JSON stats dump; the
manual image-allocation path is complete; and **no compile-checked-only variant
remains** — every M2-deferred function has a runtime test.

## Context

M0–M2 shipped the allocator lifecycle, the `Allocation` handle,
`AllocationCreateInfo`/`AllocationInfo`, buffer + image round-trips, and the
host-memory access path (map / flush / invalidate / copy / bind). M2 left three
things unbound or untested, recorded in its "Out of scope":

- `vmaAllocateMemoryForImage` — never bound, which orphaned `try_bind_image_memory`
  (it had no in-binding allocation source).
- `vmaBindBufferMemory2` / `vmaBindImageMemory2` — bound but compile-checked only.
- `vmaFlushAllocations` / `vmaInvalidateAllocations` (batch) and `vmaAllocateMemory`
  (raw) — bound but compile-checked only.

M3 folds all three into the milestone alongside statistics & budget.

## The shape insight

**Every M3 statistics/budget function returns `void`, not `VkResult`.** So the
M3 statistics surface has *no fault paths* — M0's `check()` is untouched by it.
The idiomatic layer for these functions is pure convenience (return-by-value
accessors) plus one ownership wrapper (the stats-string copy-out), not error
mapping. This is a deliberate departure from the M1/M2 `try_*` shape, which
existed to convert `VkResult`.

The **deferred items**, by contrast, *do* return `VkResult` and route through
`check()` exactly like M1/M2 — they keep the `try_*` shape.

Because raw and idiomatic both live in `module vma;` as methods on `Allocator`,
the two layers need distinct names. The raw externs keep the C-mapped
`get_*`/`calculate_*` verbs (out-param form); the idiomatic accessors use
**nouns** (`info()`, `statistics()`, …). No collision.

## Settled decisions

1. **Scope: M3 = statistics & budget + all three M2 leftovers** (allocate-for-image,
   bind\*2 runtime coverage, batch flush/invalidate + raw allocate runtime coverage).
2. **Full by-value idiomatic accessors** for the void getters, in addition to the
   faithful raw out-param externs (roadmap decision #2). The one exception is
   `heap_budgets`, which is variable-length and returns a bounded slice over a
   caller buffer (the `try_map` precedent), and `try_build_stats_string`, which
   copies out (see #3).
3. **`vmaBuildStatsString` → copy-out to an owned `String`.** The idiomatic
   `stats_string` calls the raw builder, copies the VMA-owned JSON into a
   `mem`-allocated C3 `String` (`ZString.copy(mem)`), frees the VMA buffer immediately
   (`vmaFreeStatsString`), and returns the owned copy. The caller frees it with
   `free(s.ptr)` — no VMA-free juggling. Costs one copy. It returns a **plain
   `String`, not an optional**: `ZString.copy` returns a plain `String` and panics on
   OOM like any C3 heap allocation, so there is no fault to surface — consistent with
   the rest of the M3 statistics surface having no fault paths. The raw
   `build_stats_string`/`free_stats_string` pair stays reachable.
4. **bind\*2 runtime coverage via a Vulkan 1.1 device.** The headless bootstrap and
   the allocator are bumped to Vulkan 1.1 (`VK_API_1_1 = (1<<22)|(1<<12)`) so
   `vmaBindBufferMemory2`/`vmaBindImageMemory2` resolve as core entry points.
   `pNext` stays null (a non-null `pNext` would additionally need the
   `khr_bind_memory2` allocator flag; out of scope here). lavapipe supports 1.1.
5. **New layout-pinned structs get `$assert` size pins**, with `N` from the size
   probe (per-binding workflow). M3 introduces five.

## Binding surface

All signatures below are illustrative; exact forms are re-read from
`vk_mem_alloc.h` and verified with `c3-expert` at plan time per the `add-binding`
workflow.

### New structs — layout-pinned (`vma_stats.c3i`)

| C3 struct | composition | expected size |
| --- | --- | --- |
| `Statistics` | 2×`uint` + 2×`vk::DeviceSize` | 24 |
| `DetailedStatistics` | `Statistics` + `uint`(+pad) + 4×`vk::DeviceSize` | 64 |
| `TotalStatistics` | `DetailedStatistics[32]` + `[16]` + `[1]` | 3136 |
| `Budget` | `Statistics` + 2×`vk::DeviceSize` | 40 |
| `AllocatorInfo` | `vk::Instance` + `vk::PhysicalDevice` + `vk::Device` | 24 |

Array bounds come from `vk::MAX_MEMORY_TYPES` (32) and `vk::MAX_MEMORY_HEAPS`
(16). Sizes are deterministic (no platform-variant fields) but still
probe-verified.

### Raw externs (`vma_stats.c3i`)

```
fn void Allocator.get_allocator_info(self, AllocatorInfo* out) @cname("vmaGetAllocatorInfo");
fn void Allocator.get_physical_device_properties(self, vk::PhysicalDeviceProperties** out) @cname("vmaGetPhysicalDeviceProperties");
fn void Allocator.get_memory_properties(self, vk::PhysicalDeviceMemoryProperties** out) @cname("vmaGetMemoryProperties");
fn void Allocator.get_memory_type_properties(self, uint type_index, vk::MemoryPropertyFlags* out) @cname("vmaGetMemoryTypeProperties");
fn void Allocator.calculate_statistics(self, TotalStatistics* out) @cname("vmaCalculateStatistics");
fn void Allocator.get_heap_budgets(self, Budget* out) @cname("vmaGetHeapBudgets");
fn void Allocator.build_stats_string(self, ZString* out, vk::Bool32 detailed) @cname("vmaBuildStatsString");
fn void Allocator.free_stats_string(self, ZString s) @cname("vmaFreeStatsString");
```

`get_heap_budgets` writes `memoryHeapCount` entries into the caller array.
`get_physical_device_properties`/`get_memory_properties` write VMA's internally
cached pointer into the caller's pointer slot.

### Idiomatic accessors (`vma_stats.c3`)

```
fn AllocatorInfo                       Allocator.info(self);
fn vk::PhysicalDeviceProperties*       Allocator.physical_device_properties(self);
fn vk::PhysicalDeviceMemoryProperties* Allocator.memory_properties(self);
fn vk::MemoryPropertyFlags             Allocator.memory_type_properties(self, uint type_index);
fn TotalStatistics                     Allocator.statistics(self);
fn Budget[]                            Allocator.heap_budgets(self, Budget[] out);
fn String                              Allocator.stats_string(self, bool detailed);
```

- `statistics()` returns the ~3KB `TotalStatistics` by value (accepted cost).
- `heap_budgets(out)` reads the live heap count from `memory_properties()`
  internally, calls the raw getter, and returns `out[:heap_count]`. The caller
  buffer must be at least `vk::MAX_MEMORY_HEAPS` long.
- `physical_device_properties()`/`memory_properties()` return VMA's cached pointer
  directly (no copy — the pointer is owned by the allocator).
- `stats_string(detailed)` returns an owned `String` the caller frees with
  `free(s.ptr)`; no fault (see decision #3). None of the accessors fault.

### Deferred items — all return `VkResult`, route through `check()`

**(a) allocate-for-image** (`vma_image.c3i`/`.c3`) — completes the manual image path:

```
fn vk::Result        Allocator.allocate_memory_for_image(self, vk::Image, AllocationCreateInfo*, Allocation*, AllocationInfo*) @cname("vmaAllocateMemoryForImage");
fn MemoryAllocation? Allocator.try_allocate_memory_for_image(self, vk::Image, AllocationCreateInfo*);
```

**(b) bind\*2 idiomatic wrappers** over M2's raw externs:

```
fn void? Allocator.try_bind_buffer_memory2(self, Allocation, vk::DeviceSize offset, vk::Buffer, void* next);   // vma_memory.c3
fn void? Allocator.try_bind_image_memory2(self, Allocation, vk::DeviceSize offset, vk::Image, void* next);     // vma_image.c3
```

**(c) raw allocate + batch flush/invalidate idiomatic wrappers** (`vma_memory.c3`):

```
fn MemoryAllocation? Allocator.try_allocate_memory(self, vk::MemoryRequirements*, AllocationCreateInfo*);
fn void?             Allocator.try_flush_allocations(self, Allocation[] allocs, vk::DeviceSize[] offsets, vk::DeviceSize[] sizes);
fn void?             Allocator.try_invalidate_allocations(self, Allocation[] allocs, vk::DeviceSize[] offsets, vk::DeviceSize[] sizes);
```

The batch wrappers derive `count` from the slice length and return a specific
fault on a length mismatch between the three slices — a genuine precondition, so
it earns a fault (unlike the void getters in §"Idiomatic accessors").

## Testing

Extend the headless smoke (`test/src/main.c3`), exit 0 on lavapipe. Bootstrap and
allocator move to Vulkan 1.1.

1. **`stats_round_trip`** — with a live allocation present: `statistics()` asserts
   `total.statistics.allocation_bytes > 0` and `block_count > 0`; `heap_budgets(buf)`
   asserts `len > 0` and at least one heap `budget > 0`; `info()` asserts
   `device == h.device`; `memory_type_properties(0)` returns; the two property
   getters are non-null; `stats_string(true)` asserts a non-empty string, then
   frees it with `free(s.ptr)`.
2. **`manual_image_bind`** — raw `vk::create_image` → `try_allocate_memory_for_image`
   (`MemoryUsage.GPU_ONLY`) → `try_bind_image_memory2` (offset 0, null next) →
   teardown destroys the image before `free_memory`. Covers leftover (a) and the
   image bind2 path.
3. **`manual_reqs_bind`** (new) — create a `VkBuffer`, pull `vk::MemoryRequirements`
   from `vk::get_buffer_memory_requirements`, allocate via `try_allocate_memory`, bind
   via `try_bind_buffer_memory2`, free. Covers the raw allocate and buffer bind2. The
   M2 `manual_alloc_bind` (`try_allocate_memory_for_buffer` + v1 `try_bind_buffer_memory`)
   is kept unchanged so its paths keep their runtime coverage.
4. **`map_round_trip`** (modify) — add a single-element `try_flush_allocations`
   batch alongside the existing scalar flush. Covers the batch flush/invalidate
   variants.

After M3 the only unexercised-at-runtime path is a non-null `pNext` on bind\*2,
which needs the `khr_bind_memory2` flag and is explicitly out of scope.

## File layout

```
vma_stats.c3i    (new)  5 stat structs + $assert + 8 raw externs
vma_stats.c3     (new)  7 idiomatic accessors (info/statistics/budgets/props/stats-string)
vma_image.c3i    (+)    allocate_memory_for_image raw extern
vma_image.c3     (+)    try_allocate_memory_for_image, try_bind_image_memory2
vma_memory.c3    (+)    try_allocate_memory, try_flush_allocations, try_invalidate_allocations, try_bind_buffer_memory2
scripts/vma_size_probe.cpp  (+)  five stat-struct sizeof lines (probe table)
scripts/build-vma.sh        (+)  size guard generalized to a (name,expected) table
test/src/vk_bootstrap.c3    (+)  VK_API_1_1 const; app api_version -> 1.1
test/src/main.c3            (+)  stats_round_trip, manual_image_bind; modify manual_alloc_bind + map_round_trip; allocator api_version -> 1.1
```

No change to `vma_memory.c3i` externs (the M2 raw bind\*2 / batch / allocate
externs are already present); M3 only adds their idiomatic wrappers in the `.c3`.

## Out of scope (later milestones)

- Custom pools (M4), defragmentation (M5), virtual allocator (M6).
- Misc leftovers (M7): `vmaCreateBufferWithAlignment`, aliasing buffers/images,
  `vmaAllocateMemoryPages`/`vmaFreeMemoryPages`, `vmaSetCurrentFrameIndex`,
  `vmaCheckCorruption`, `vmaSetAllocationName`/`vmaSetAllocationUserData`,
  `vmaGetAllocationMemoryProperties`.
- Non-null `pNext` on bind\*2 (needs the `khr_bind_memory2` allocator flag).
- Cross-target `linked-libs/` population (M7).
