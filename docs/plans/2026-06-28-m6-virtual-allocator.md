# M6 — Virtual allocator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bind VMA's device-independent virtual allocator (a pure-CPU offset sub-allocator) — raw externs plus idiomatic wrappers — and prove it with a `virtual_round_trip` test that needs no Vulkan device.

**Architecture:** Extend `module vma;` with a new file pair `vma_virtual.c3i`/`.c3`: a `VirtualBlock` handle, a `VirtualAllocation` handle, two flags bitstructs, three layout-pinned structs, twelve raw externs (one free function + eleven `VirtualBlock` methods, names stripped of the `Virtual` prefix since the receiver carries it), and six idiomatic wrappers. Statistics reuse M3's `Statistics`/`DetailedStatistics`; `check()` (M0) handles the two `VkResult` functions. The test is pure CPU and runs first in the smoke, before any device is created.

**Tech Stack:** C3 0.8.0 (`c3c`), VMA static lib from M0 (`linked-libs/linux-x64/libVulkanMemoryAllocator.a` — already contains every M6 symbol), `vk.c3l`, no device required for the M6 test.

## Global Constraints

- **C3 0.8.0.** Externs use `@cname("vmaXxx")`, NOT `@extern`. The handle is `inline void*`, so methods take receiver `self` **by value**. Lift a fault with trailing `~`; propagate with `!`. `T::size`, never `T.sizeof`.
- **All Vulkan types come from `vk`** (`vk::DeviceSize`, `vk::Result`, `vk::Bool32`, `vk::AllocationCallbacks`). Never redefine them.
- **Functions are methods on `VirtualBlock`, not `Allocator`** (except `create_virtual_block`, a free function with a block out-param). Method names strip the `Virtual`/`VirtualBlock` prefix: `allocate`, `free`, `clear`, `is_empty`, `get_allocation_info`, `set_allocation_user_data`, `get_statistics`, `calculate_statistics`, `build_stats_string`, `free_stats_string`, plus `destroy`.
- **Statistics reuse M3's `Statistics`/`DetailedStatistics`** (in `vma_stats.c3i`). No new stat structs.
- **The two `VkResult` functions** (`create_virtual_block`, `allocate`) get `try_*` wrappers via `check()`. The `void` getters get by-value accessors. `void` mutators (`destroy`/`free`/`clear`/`set_allocation_user_data`) are used raw. `is_empty` returns `vk::Bool32` and is bound raw (caller compares `!= 0`; nonzero = empty).
- **Three new layout-pinned structs**, each `$assert(T::size == N)` immediately after it: `VirtualBlockCreateInfo` 24, `VirtualAllocationCreateInfo` 32, `VirtualAllocationInfo` 24.
- **Naming:** types PascalCase, functions/fields snake_case, faults one-per-line, named constants (no bare magic numbers — test fixtures exempt), no `@builtin`, no all-uppercase type names. K&R braces. Do not run `c3fmt`.
- **No milestone tags in code or comments.** `(M6)` may appear in commit messages only.

## File Structure

| File | Responsibility |
|------|----------------|
| `scripts/vma_size_probe.cpp` (modify) | Add the three virtual struct sizes to the probe table. |
| `scripts/build-vma.sh` (modify) | Add three `expect_size` entries to the size guard. |
| `vma_virtual.c3i` (create) | Two handles, two bitstructs, three structs + `$assert`s, twelve raw externs. |
| `vma_virtual.c3` (create) | `VirtualAllocationResult` + six idiomatic wrappers. |
| `test/src/main.c3` (modify) | Device-free `virtual_round_trip` (called first in `run()`) + faults, constants, message. |

All `vma*` files are `module vma;`; the repo compile hook compiles sibling module files together so cross-file refs resolve. `vma.c3` is unchanged — `check()` is reused. Every code block below was compile-checked against `vk` during planning.

---

### Task 1: Virtual types + size-probe pinning + raw externs

**Files:**
- Modify: `scripts/vma_size_probe.cpp`
- Modify: `scripts/build-vma.sh`
- Create: `vma_virtual.c3i`

**Interfaces:**
- Consumes: `vma::Statistics`, `vma::DetailedStatistics` (M3); `vk::DeviceSize`, `vk::Result`, `vk::Bool32`, `vk::AllocationCallbacks` (vk).
- Produces: `vma::VirtualBlock`, `vma::VirtualAllocation` (handles); `vma::VirtualBlockCreateFlags`, `vma::VirtualAllocationCreateFlags` (bitstructs); `vma::VirtualBlockCreateInfo`/`VirtualAllocationCreateInfo`/`VirtualAllocationInfo` (structs); free function `create_virtual_block`; methods `VirtualBlock.destroy`, `is_empty`, `allocate`, `free`, `clear`, `get_allocation_info`, `set_allocation_user_data`, `get_statistics`, `calculate_statistics`, `build_stats_string`, `free_stats_string`. Tasks 2 and 3 consume these.

- [ ] **Step 1: Add the three virtual structs to `scripts/vma_size_probe.cpp`**

In `main`, after the last existing `Defragmentation*` line, add:

```cpp
    std::printf("VirtualBlockCreateInfo %zu\n", sizeof(VmaVirtualBlockCreateInfo));
    std::printf("VirtualAllocationCreateInfo %zu\n", sizeof(VmaVirtualAllocationCreateInfo));
    std::printf("VirtualAllocationInfo %zu\n", sizeof(VmaVirtualAllocationInfo));
```

- [ ] **Step 2: Add the guard entries in `scripts/build-vma.sh`**

After the existing `expect_size DefragmentationStats 24` line, add:

```sh
expect_size VirtualBlockCreateInfo 24
expect_size VirtualAllocationCreateInfo 32
expect_size VirtualAllocationInfo 24
```

- [ ] **Step 3: Run the build script to confirm the sizes and that the lib still builds**

Run:
```sh
cd /home/fesol/source/repos/c3vma.c3l && bash scripts/build-vma.sh ; echo "exit=$?"
```
Expected: prints all `name size` lines including `VirtualBlockCreateInfo 24`, `VirtualAllocationCreateInfo 32`, `VirtualAllocationInfo 24`, then `Done.` and `exit=0`. A non-zero exit with `ERROR: sizeof(...)` means a size differs — STOP and reconcile (the printed size is authoritative; update both the guard and the Step 4 `$assert`). `VULKAN_SDK` is `/home/fesol/opt/vulkan/x86_64`.

- [ ] **Step 4: Create `vma_virtual.c3i`**

```c3
module vma;

import vk;

typedef VirtualBlock      = inline void*;
typedef VirtualAllocation = inline void*;

bitstruct VirtualBlockCreateFlags : uint {
    bool linear_algorithm : 0;
}

bitstruct VirtualAllocationCreateFlags : uint {
    bool upper_address       : 6;
    bool strategy_min_memory : 16;
    bool strategy_min_time   : 17;
    bool strategy_min_offset : 18;
}

struct VirtualBlockCreateInfo {
    vk::DeviceSize           size;
    VirtualBlockCreateFlags  flags;
    vk::AllocationCallbacks* allocation_callbacks;
}
$assert(VirtualBlockCreateInfo::size == 24);

struct VirtualAllocationCreateInfo {
    vk::DeviceSize               size;
    vk::DeviceSize               alignment;
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

extern fn vk::Result create_virtual_block(VirtualBlockCreateInfo* info, VirtualBlock* out_block) @cname("vmaCreateVirtualBlock");
extern fn void VirtualBlock.destroy(self) @cname("vmaDestroyVirtualBlock");
extern fn vk::Bool32 VirtualBlock.is_empty(self) @cname("vmaIsVirtualBlockEmpty");
extern fn vk::Result VirtualBlock.allocate(self, VirtualAllocationCreateInfo* ci, VirtualAllocation* out_alloc, vk::DeviceSize* out_offset) @cname("vmaVirtualAllocate");
extern fn void VirtualBlock.free(self, VirtualAllocation allocation) @cname("vmaVirtualFree");
extern fn void VirtualBlock.clear(self) @cname("vmaClearVirtualBlock");
extern fn void VirtualBlock.get_allocation_info(self, VirtualAllocation allocation, VirtualAllocationInfo* out_info) @cname("vmaGetVirtualAllocationInfo");
extern fn void VirtualBlock.set_allocation_user_data(self, VirtualAllocation allocation, void* user_data) @cname("vmaSetVirtualAllocationUserData");
extern fn void VirtualBlock.get_statistics(self, Statistics* out_stats) @cname("vmaGetVirtualBlockStatistics");
extern fn void VirtualBlock.calculate_statistics(self, DetailedStatistics* out_stats) @cname("vmaCalculateVirtualBlockStatistics");
extern fn void VirtualBlock.build_stats_string(self, ZString* out_str, vk::Bool32 detailed) @cname("vmaBuildVirtualBlockStatsString");
extern fn void VirtualBlock.free_stats_string(self, ZString str) @cname("vmaFreeVirtualBlockStatsString");
```

- [ ] **Step 5: Verify the module compiles against `vk` (runs the `$assert` size pins)**

Run:
```sh
cd /home/fesol/source/repos/c3vma.c3l/test && c3c compile-only --no-obj ../vma.c3i ../vma.c3 ../vma_memory.c3i ../vma_memory.c3 ../vma_image.c3i ../vma_image.c3 ../vma_stats.c3i ../vma_stats.c3 ../vma_pool.c3i ../vma_pool.c3 ../vma_defrag.c3i ../vma_defrag.c3 ../vma_virtual.c3i --libdir libs --lib vk ; echo "exit=$?" ; rm -rf obj ; cd ..
```
Expected: `Object files written…` and `exit=0`. A `$assert` failure means a size differs from Step 3's probe — set the `$assert` to the probed value. A `Statistics could not be found` means M3's `vma_stats.c3i` was omitted from the command.

- [ ] **Step 6: Commit**

```sh
git add scripts/vma_size_probe.cpp scripts/build-vma.sh vma_virtual.c3i
git commit -m "vma: bind virtual allocator handles/structs + raw externs, size-pinned (M6)"
```

---

### Task 2: Idiomatic virtual-allocator wrappers

**Files:**
- Create: `vma_virtual.c3`

**Interfaces:**
- Consumes: Task 1's handles/structs and raw methods; `vma::check` (M0); `vma::Statistics`, `vma::DetailedStatistics` (M3); the stdlib `mem` allocator and `ZString.copy`.
- Produces: `vma::VirtualAllocationResult { VirtualAllocation allocation; vk::DeviceSize offset; }`; free function `try_create_virtual_block -> VirtualBlock?`; methods `VirtualBlock.try_allocate -> VirtualAllocationResult?`, `allocation_info -> VirtualAllocationInfo`, `statistics -> Statistics`, `detailed_statistics -> DetailedStatistics`, `stats_string(bool) -> String`. Task 3 consumes these. `destroy`/`free`/`clear`/`set_allocation_user_data`/`is_empty` are used raw (Task 1) — no wrappers here.

- [ ] **Step 1: Create `vma_virtual.c3`**

```c3
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
```

- [ ] **Step 2: Verify the module compiles against `vk`**

Run:
```sh
cd /home/fesol/source/repos/c3vma.c3l/test && c3c compile-only --no-obj ../vma.c3i ../vma.c3 ../vma_memory.c3i ../vma_memory.c3 ../vma_image.c3i ../vma_image.c3 ../vma_stats.c3i ../vma_stats.c3 ../vma_pool.c3i ../vma_pool.c3 ../vma_defrag.c3i ../vma_defrag.c3 ../vma_virtual.c3i ../vma_virtual.c3 --libdir libs --lib vk ; echo "exit=$?" ; rm -rf obj ; cd ..
```
Expected: `Object files written…` and `exit=0`. A `check could not be found` means M0's `vma.c3` was omitted; a `mem could not be found` means the stdlib import resolution differs — add `import std::core::mem;` at the top (it is normally implicit).

- [ ] **Step 3: Commit**

```sh
git add vma_virtual.c3
git commit -m "vma: add idiomatic virtual-allocator wrappers (M6)"
```

---

### Task 3: Device-free virtual round-trip smoke

**Files:**
- Modify: `test/src/main.c3`

**Interfaces:**
- Consumes: Task 1–2 (`try_create_virtual_block`/`VirtualBlock.destroy`/`is_empty`/`try_allocate`/`free`/`clear`/`allocation_info`/`set_allocation_user_data`/`statistics`/`detailed_statistics`/`stats_string`/`VirtualBlockCreateInfo`/`VirtualAllocationCreateInfo`/`VirtualAllocationInfo`/`VirtualAllocation`/`VirtualAllocationResult`); `vma::Statistics`/`DetailedStatistics` (M3); `std::io`.
- Produces: the runnable device-free smoke proving the M6 virtual allocator.

- [ ] **Step 1: Add the six faults to the `faultdef` block in `test/src/main.c3`**

The block currently ends:
```c3
    POOL_STATS_EMPTY,
    DEFRAG_RUNAWAY;
```
Change it to:
```c3
    POOL_STATS_EMPTY,
    DEFRAG_RUNAWAY,
    VBLOCK_NOT_EMPTY,
    VBLOCK_NOT_CLEARED,
    VALLOC_BAD_OFFSET,
    VALLOC_INFO_MISMATCH,
    VALLOC_USERDATA_MISMATCH,
    VSTATS_MISMATCH;
```

- [ ] **Step 2: Add the virtual constants to `test/src/main.c3`**

After the existing `const uint MAX_DEFRAG_PASSES = 64;` line, add:

```c3
const ulong VBLOCK_SIZE = 1 << 20;
const uint VALLOC_COUNT = 8;
const ulong VALLOC_SIZE = 1024;
const ulong VALLOC_ALIGN = 256;
```

- [ ] **Step 3: Wire `virtual_round_trip` into `run()` as the first call (device-free)**

`run()` begins:
```c3
fn void? run() {
    HeadlessVk h = create_headless_vk()!;
```
Insert the virtual call before the device is created, so it reads:
```c3
fn void? run() {
    virtual_round_trip()!;

    HeadlessVk h = create_headless_vk()!;
```

- [ ] **Step 4: Update the success message in `main()`**

Change:
```c3
    io::printn("vma smoke OK: map + image + manual buffer/reqs/image + stats + pool + defrag");
```
to:
```c3
    io::printn("vma smoke OK: virtual + map + image + manual buffer/reqs/image + stats + pool + defrag");
```

- [ ] **Step 5: Append the `virtual_round_trip` function to `test/src/main.c3`**

Append at the end of the file:

```c3

<* Device-free: create a virtual block, sub-allocate ranges, check offsets/info/
   user-data/statistics round-trip, free and clear. Needs no Vulkan device. *>
fn void? virtual_round_trip() {
    vma::VirtualBlockCreateInfo bci = { .size = VBLOCK_SIZE };
    vma::VirtualBlock block = vma::try_create_virtual_block(&bci)!;
    defer block.destroy();

    if (block.is_empty() == 0) return VBLOCK_NOT_EMPTY~;

    vma::VirtualAllocation[VALLOC_COUNT] allocs;
    for (uint i = 0; i < VALLOC_COUNT; i++) {
        vma::VirtualAllocationCreateInfo aci = { .size = VALLOC_SIZE, .alignment = VALLOC_ALIGN };
        vma::VirtualAllocationResult r = block.try_allocate(&aci)!;
        allocs[i] = r.allocation;
        if (i == 0 && r.offset != 0) return VALLOC_BAD_OFFSET~;
        if (r.offset % VALLOC_ALIGN != 0) return VALLOC_BAD_OFFSET~;
    }

    if (block.is_empty() != 0) return VBLOCK_NOT_EMPTY~;

    vma::VirtualAllocationInfo info = block.allocation_info(allocs[0]);
    if (info.size != VALLOC_SIZE) return VALLOC_INFO_MISMATCH~;

    int marker = 42;
    block.set_allocation_user_data(allocs[0], &marker);
    vma::VirtualAllocationInfo info2 = block.allocation_info(allocs[0]);
    if (info2.user_data != (void*)&marker) return VALLOC_USERDATA_MISMATCH~;

    vma::Statistics stats = block.statistics();
    if (stats.allocation_count != VALLOC_COUNT) return VSTATS_MISMATCH~;
    if (stats.allocation_bytes < VALLOC_SIZE * VALLOC_COUNT) return VSTATS_MISMATCH~;
    vma::DetailedStatistics dstats = block.detailed_statistics();
    if (dstats.statistics.allocation_count != VALLOC_COUNT) return VSTATS_MISMATCH~;

    String js = block.stats_string(true);
    defer free(js.ptr);
    if (js.len == 0) return VSTATS_MISMATCH~;

    for (uint i = 0; i < VALLOC_COUNT; i++) block.free(allocs[i]);
    if (block.is_empty() == 0) return VBLOCK_NOT_EMPTY~;

    vma::VirtualAllocationCreateInfo aci2 = { .size = VALLOC_SIZE };
    block.try_allocate(&aci2)!;
    block.clear();
    if (block.is_empty() == 0) return VBLOCK_NOT_CLEARED~;
}
```

`is_empty()` returns `vk::Bool32` where nonzero = empty: an "is empty" check is `== 0` → fault (it was not empty); a "not empty" check is `!= 0` → fault (it claimed empty).

- [ ] **Step 6: Build the smoke executable**

Run:
```sh
cd /home/fesol/source/repos/c3vma.c3l/test && c3c build smoke 2>&1 | tail -8 ; echo "exit=$?" ; cd ..
```
Expected: `Program linked to executable 'build/smoke'.` and `exit=0`. An undefined `vma*` symbol points at a `@cname` typo in Task 1; a C3 type/cast error is a transcription issue in this file.

- [ ] **Step 7: Run the smoke on lavapipe**

Run:
```sh
cd /home/fesol/source/repos/c3vma.c3l/test && VK_LOADER_DRIVERS_SELECT='*lvp*' ./build/smoke ; echo "exit=$?" ; cd ..
```
Expected: prints `vma smoke OK: virtual + map + image + manual buffer/reqs/image + stats + pool + defrag` and `exit=0`. (The virtual path runs first and uses no device; the rest of the smoke still needs lavapipe.)
- `vma smoke FAILED: VBLOCK_NOT_EMPTY` / `VBLOCK_NOT_CLEARED` → the empty/clear lifecycle is wrong — check the `is_empty()` comparison direction (nonzero = empty).
- `vma smoke FAILED: VALLOC_BAD_OFFSET` → the first offset wasn't 0 or an offset wasn't `VALLOC_ALIGN`-aligned — inspect `try_allocate`'s offset out-param wiring.
- `vma smoke FAILED: VALLOC_INFO_MISMATCH` / `VALLOC_USERDATA_MISMATCH` → `allocation_info` / `set_allocation_user_data` round-trip failed.
- `vma smoke FAILED: VSTATS_MISMATCH` → block statistics didn't report the expected count/bytes — check the `get_statistics`/`calculate_statistics` wiring.
If it still won't run after these checks, STOP and report BLOCKED with the exact output — do not weaken the assertions.

- [ ] **Step 8: Clean artifacts and commit**

```sh
rm -rf test/build test/obj
git add test/src/main.c3
git commit -m "test: device-free virtual allocator round-trip (M6)"
```

---

## Done criteria

- `bash scripts/build-vma.sh` prints the three virtual sizes (24/32/24) and exits 0; the three `$assert`s in `vma_virtual.c3i` hold.
- `vma_virtual.c3i`/`.c3` (new) compile against `vk`.
- `cd test && c3c build smoke` links; `./build/smoke` prints `vma smoke OK: virtual + map + image + manual buffer/reqs/image + stats + pool + defrag` and exits 0 on lavapipe.
- The virtual allocator round-trip runs **device-free** (first in `run()`, before any device is created) with exact assertions: empty-at-start, first offset 0, aligned offsets, info/user-data round-trip, exact allocation count/bytes, empty-after-free, empty-after-clear.
- Next milestone (M7 — misc leftovers + cross-target `linked-libs/` population) is the final one.
```
