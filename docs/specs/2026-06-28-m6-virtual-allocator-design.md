# M6 — Virtual allocator (design)

Date: 2026-06-28
Status: approved (brainstorming)
Predecessor: [M5 design](2026-06-28-m5-defragmentation-design.md) · [roadmap](2026-06-26-vma-binding-roadmap-design.md)

Bind VMA's virtual allocator — a pure-CPU offset sub-allocator that has nothing to
do with a Vulkan device or `VkDeviceMemory`. You create a `VirtualBlock` of some
size (in bytes or any unit), sub-allocate ranges out of it, and VMA tracks the
offsets and free space. After M6 a consumer can use VMA's allocation algorithm for
arbitrary CPU-side range bookkeeping, and the binding gains its first
device-independent surface.

## Context

M0–M5 bound the device-backed allocator and its pools, statistics, and
defragmentation. M6 is independent of all of it: the virtual allocator needs no
`Allocator`, no `VkDevice`, no `vk` runtime at all beyond a couple of plain types
(`vk::DeviceSize`, `vk::Bool32`, `vk::AllocationCallbacks`, `vk::Result`). It is the
roadmap's reorderable, device-free milestone.

It **reuses M3's `Statistics`/`DetailedStatistics`** (the virtual-block statistics
functions report through those same structs) and M0's `check()` (for the two
`VkResult`-returning functions). It introduces two handles, two flags bitstructs,
and three layout-pinned structs.

## The shape

**Functions are methods on `VirtualBlock`, not `Allocator`.** This is the first
milestone whose surface does not hang off the device allocator. `create_virtual_block`
is a free function (block is an out-parameter); everything else is a method on the
`VirtualBlock` handle (receiver `self` by value, since the handle is `inline void*`).
Method names **strip the `Virtual`/`VirtualBlock` prefix** — the receiver type carries
it: `block.allocate(...)`, `block.free(a)`, `block.clear()`, `block.statistics()`.

The two-layer rule holds: faithful raw externs plus a thin idiomatic layer. The two
`VkResult` functions (`vmaCreateVirtualBlock`, `vmaVirtualAllocate`) get `try_*`
wrappers via `check()`; the `void` getters get by-value accessors; `void` mutators
(`destroy`, `free`, `clear`, `set_allocation_user_data`) are used raw;
`vmaIsVirtualBlockEmpty` returns `VkBool32` and is bound raw (caller compares `!= 0`).
`stats_string` copies VMA's JSON into an owned `String` (the M3 pattern).

## Settled decisions

1. **Methods strip the `Virtual` prefix** — the `VirtualBlock` receiver supplies the
   context (`block.allocate`, not `block.virtual_allocate`). `vmaVirtualFree` →
   `VirtualBlock.free`, `vmaClearVirtualBlock` → `VirtualBlock.clear`, etc.
2. **`VirtualAllocation` is `inline void*`** — it is a non-dispatchable handle
   (pointer-sized on the built linux-x64 target), bound the same way `vk.c3l` binds
   `vk::Buffer`/`vk::Image`. (32-bit targets, where non-dispatchable handles are
   `uint64`, are M7's cross-target concern and follow vk's existing convention.)
3. **Statistics reuse M3's structs.** `statistics()` returns `Statistics`,
   `detailed_statistics()` returns `DetailedStatistics`. No new stat structs.
4. **`try_allocate` returns a result struct** `VirtualAllocationResult { VirtualAllocation allocation; vk::DeviceSize offset; }`
   (mirrors M1's `BufferAllocation`) — the raw `vmaVirtualAllocate` yields both the
   handle and the chosen offset.
5. **`stats_string` copies out to an owned `String`** (`ZString.copy(mem)`, VMA buffer
   freed immediately), the same decision as M3's `Allocator.stats_string`. Returns a
   plain `String` (no fault). The raw `build_stats_string`/`free_stats_string` pair
   stays reachable.
6. **`is_empty` is bound raw, returning `vk::Bool32`** — no bool wrapper; the caller
   compares `!= 0`. (`Bool32` nonzero = empty.)
7. **Three new layout-pinned structs**, each `$assert`-pinned with `N` from the size
   probe.
8. **The test is device-free** and runs first in the smoke, before any Vulkan device
   is created — proving the virtual allocator needs no device.

## Binding surface

All signatures below are illustrative; exact forms are re-read from
`vk_mem_alloc.h` and verified with `c3-expert` at plan time per `add-binding`.

### New types — layout-pinned (`vma_virtual.c3i`)

```
typedef VirtualBlock      = inline void*;
typedef VirtualAllocation = inline void*;

bitstruct VirtualBlockCreateFlags : uint {
    bool linear_algorithm : 0;       // 0x1
}

bitstruct VirtualAllocationCreateFlags : uint {
    bool upper_address       : 6;    // 0x40
    bool strategy_min_memory : 16;   // 0x10000
    bool strategy_min_time   : 17;   // 0x20000
    bool strategy_min_offset : 18;   // 0x40000
}

struct VirtualBlockCreateInfo {
    vk::DeviceSize           size;
    VirtualBlockCreateFlags  flags;
    vk::AllocationCallbacks* allocation_callbacks;   // optional, may be null
}
$assert(VirtualBlockCreateInfo::size == 24);

struct VirtualAllocationCreateInfo {
    vk::DeviceSize               size;        // must be nonzero
    vk::DeviceSize               alignment;   // power of two; 0 means 1
    VirtualAllocationCreateFlags flags;
    void*                        user_data;
}
$assert(VirtualAllocationCreateInfo::size == 32);

struct VirtualAllocationInfo {
    vk::DeviceSize offset;
    vk::DeviceSize size;
    void*          user_data;
}
$assert(VirtualAllocationInfo::size == 24);
```

`VirtualBlockCreateFlagBits`' / `VirtualAllocationCreateFlagBits`' `MASK` / `MAX_ENUM`
entries are not flags and are not bound. The strategy flag values are binary-compatible
with M1's `AllocationCreateFlags` strategy bits (16/17/18) — same numeric positions.

### Raw externs (`vma_virtual.c3i`)

```
fn vk::Result create_virtual_block(VirtualBlockCreateInfo* info, VirtualBlock* out_block) @cname("vmaCreateVirtualBlock");
fn void       VirtualBlock.destroy(self) @cname("vmaDestroyVirtualBlock");
fn vk::Bool32 VirtualBlock.is_empty(self) @cname("vmaIsVirtualBlockEmpty");
fn vk::Result VirtualBlock.allocate(self, VirtualAllocationCreateInfo* ci, VirtualAllocation* out_alloc, vk::DeviceSize* out_offset) @cname("vmaVirtualAllocate");
fn void       VirtualBlock.free(self, VirtualAllocation allocation) @cname("vmaVirtualFree");
fn void       VirtualBlock.clear(self) @cname("vmaClearVirtualBlock");
fn void       VirtualBlock.get_allocation_info(self, VirtualAllocation allocation, VirtualAllocationInfo* out_info) @cname("vmaGetVirtualAllocationInfo");
fn void       VirtualBlock.set_allocation_user_data(self, VirtualAllocation allocation, void* user_data) @cname("vmaSetVirtualAllocationUserData");
fn void       VirtualBlock.get_statistics(self, Statistics* out_stats) @cname("vmaGetVirtualBlockStatistics");
fn void       VirtualBlock.calculate_statistics(self, DetailedStatistics* out_stats) @cname("vmaCalculateVirtualBlockStatistics");
fn void       VirtualBlock.build_stats_string(self, ZString* out_str, vk::Bool32 detailed) @cname("vmaBuildVirtualBlockStatsString");
fn void       VirtualBlock.free_stats_string(self, ZString str) @cname("vmaFreeVirtualBlockStatsString");
```

### Idiomatic (`vma_virtual.c3`)

```
struct VirtualAllocationResult { VirtualAllocation allocation; vk::DeviceSize offset; }

fn VirtualBlock?             try_create_virtual_block(VirtualBlockCreateInfo* info);
fn VirtualAllocationResult?  VirtualBlock.try_allocate(self, VirtualAllocationCreateInfo* ci);
fn VirtualAllocationInfo     VirtualBlock.allocation_info(self, VirtualAllocation allocation);
fn Statistics                VirtualBlock.statistics(self);
fn DetailedStatistics        VirtualBlock.detailed_statistics(self);
fn String                    VirtualBlock.stats_string(self, bool detailed);
```

`destroy`/`free`/`clear`/`set_allocation_user_data` are used raw. The by-value accessor
names (`statistics`, `stats_string`, …) do not collide with M3's `Allocator.*` methods —
the receiver type differs. `stats_string` returns an owned `String` the caller frees
with `free(s.ptr)`.

## Testing

Extend the smoke (`test/src/main.c3`) with one **device-free** path, `virtual_round_trip`,
called first in `run()` before `create_headless_vk()`. Because the virtual allocator is
deterministic CPU bookkeeping, the assertions are exact, not best-effort:

1. `create_virtual_block({ size = VBLOCK_SIZE })`; `defer block.destroy()`.
2. Assert `is_empty() != 0` (empty at start).
3. Allocate `VALLOC_COUNT` allocations via `try_allocate({ size = VALLOC_SIZE, alignment = VALLOC_ALIGN })`,
   storing the handles; assert the first allocation's offset `== 0` and every offset is
   a multiple of `VALLOC_ALIGN`.
4. Assert `is_empty() == 0` (now non-empty).
5. `allocation_info(allocs[0])` → assert `.size == VALLOC_SIZE`; `set_allocation_user_data`
   with a known pointer, re-read → assert `.user_data` round-trips.
6. `statistics()` → assert `allocation_count == VALLOC_COUNT` and
   `allocation_bytes >= VALLOC_SIZE * VALLOC_COUNT`; `detailed_statistics()` → assert the
   nested count; `stats_string(true)` → non-empty, then `free(s.ptr)`.
7. `free` every allocation → assert `is_empty() != 0`; allocate one more, then `clear()`
   → assert `is_empty() != 0` (clear frees everything).

Faults: `VBLOCK_NOT_EMPTY`, `VBLOCK_NOT_CLEARED`, `VALLOC_BAD_OFFSET`,
`VALLOC_INFO_MISMATCH`, `VALLOC_USERDATA_MISMATCH`, `VSTATS_MISMATCH`. Constants:
`VBLOCK_SIZE`, `VALLOC_COUNT`, `VALLOC_SIZE`, `VALLOC_ALIGN`. The smoke success message
gains `+ virtual`.

`is_empty()` returns `vk::Bool32` where nonzero means empty, so "empty" asserts compare
`!= 0` and "non-empty" asserts compare `== 0`.

## File layout

```
vma_virtual.c3i  (new)  VirtualBlock + VirtualAllocation handles, 2 bitstructs, 3 structs + $asserts, 12 raw externs
vma_virtual.c3   (new)  VirtualAllocationResult + try_create_virtual_block, try_allocate, allocation_info, statistics, detailed_statistics, stats_string
scripts/vma_size_probe.cpp (+)  3 virtual struct sizes (24/32/24)
scripts/build-vma.sh       (+)  3 expect_size entries
test/src/main.c3           (+)  device-free virtual_round_trip (called first in run()); faults, consts, message
```

`vma.c3` is unchanged — `check()` is reused. No struct retypes.

## Out of scope (later milestones)

- `linear_algorithm` / `upper_address` / `strategy_*` flags are bound but not
  runtime-exercised (the test uses defaults).
- M7 (final milestone): `vmaSetCurrentFrameIndex`, aliasing buffers/images,
  `vmaCreateBufferWithAlignment`, `vmaAllocateMemoryPages`/`vmaFreeMemoryPages`,
  allocation name/user-data setters on device allocations,
  `vmaGetAllocationMemoryProperties`, **cross-target `linked-libs/` population** for the
  15 non-linux-x64 targets, and docs polish.
