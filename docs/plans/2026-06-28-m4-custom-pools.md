# M4 — Custom pools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bind VMA's custom-pool surface (create/destroy, allocate-from-pool, pool statistics, name, corruption check) plus the find-memory-type-index helpers, and prove the whole path with a headless `pool_round_trip` smoke on lavapipe.

**Architecture:** Extend `module vma;`. Pools get a new file pair `vma_pool.c3i`/`.c3`: one layout-pinned struct (`PoolCreateInfo`), a `Pool` handle, a `PoolCreateFlags` bitstruct, 7 raw externs, and 5 idiomatic wrappers. Pool statistics **reuse M3's `Statistics`/`DetailedStatistics`** — no new stat structs. The find-memory-type-index helpers and the `AllocationCreateInfo.pool` retype (`void*`→`Pool`, which makes pools usable through the existing allocate paths) extend `vma_memory.c3i`/`.c3`. One new fault `CORRUPTION_DETECTED` extends `check()`.

**Tech Stack:** C3 0.8.0 (`c3c`), VMA static lib from M0 (`linked-libs/linux-x64/libVulkanMemoryAllocator.a` — already contains every M4 symbol), `vk.c3l`, headless Vulkan + lavapipe.

## Global Constraints

- **C3 0.8.0.** Externs use `@cname("vmaXxx")`, NOT `@extern`. Allocator-first functions are methods with receiver `self` **by value** (handle is `inline void*`). Lift a fault into an optional with trailing `~`; the pre-0.8.0 `?` suffix is removed. `T::size`, never `T.sizeof`.
- **All Vulkan types come from `vk`** (`vk::DeviceSize`, `vk::Result`, `vk::BufferCreateInfo`, `vk::ImageCreateInfo`). Never redefine them. `size_t` maps to C3 `usz`.
- **Functions returning `VkResult`** (`create_pool`, `check_pool_corruption`, the 3 `find_memory_type_index*`) get `try_*` wrappers via `check()`. **`void`-returning getters** (`get_pool_statistics`, `calculate_pool_statistics`, `get_pool_name`) get by-value accessors with no fault path. `destroy_pool`/`set_pool_name` are used raw.
- **Pool statistics reuse M3's `Statistics`/`DetailedStatistics`.** No new stat structs.
- **`PoolCreateInfo` is layout-pinned:** `$assert(PoolCreateInfo::size == 56);` immediately after it. The `AllocationCreateInfo.pool` retype is pointer-width-identical — its existing `$assert(... == 48)` is unchanged.
- **Naming:** types PascalCase, functions/fields snake_case, faults one-per-line, named constants (no bare magic numbers), no `@builtin`, no all-uppercase type names. K&R braces. Do not run `c3fmt`.
- **No milestone tags in code or comments.** `(M4)` may appear in commit messages only. The test pool name is `"smoke_pool"` (not a milestone tag).

## File Structure

| File | Responsibility |
|------|----------------|
| `scripts/vma_size_probe.cpp` (modify) | Add `sizeof(VmaPoolCreateInfo)` to the probe table. |
| `scripts/build-vma.sh` (modify) | Add `expect_size PoolCreateInfo 56` to the size guard. |
| `vma_pool.c3i` (create) | `Pool`, `PoolCreateFlags`, `PoolCreateInfo` + `$assert`, 7 raw externs. |
| `vma_pool.c3` (create) | 5 idiomatic pool wrappers. |
| `vma.c3` (modify) | `CORRUPTION_DETECTED` fault + `check()` case. |
| `vma_memory.c3i` (modify) | Retype `AllocationCreateInfo.pool` → `Pool`; + 3 find-memtype raw externs. |
| `vma_memory.c3` (modify) | + 3 find-memtype idiomatic wrappers. |
| `test/src/main.c3` (modify) | + `pool_round_trip` path; updated success message. |

All `vma*` files are `module vma;`; the repo compile hook compiles sibling module files together so cross-file refs resolve. Every code block below was compile-checked against `vk` during planning.

---

### Task 1: Pool types + size-probe pinning + raw externs

**Files:**
- Modify: `scripts/vma_size_probe.cpp`
- Modify: `scripts/build-vma.sh`
- Create: `vma_pool.c3i`

**Interfaces:**
- Consumes: `vma::Allocator` (M0); `vma::Statistics`, `vma::DetailedStatistics` (M3); `vk::DeviceSize`, `vk::Result` (vk).
- Produces: `vma::Pool` (handle), `vma::PoolCreateFlags`, `vma::PoolCreateInfo`; methods `Allocator.create_pool`, `destroy_pool`, `get_pool_statistics`, `calculate_pool_statistics`, `check_pool_corruption`, `get_pool_name`, `set_pool_name`. Tasks 2 and 4 consume these.

- [ ] **Step 1: Add `VmaPoolCreateInfo` to `scripts/vma_size_probe.cpp`**

The file currently prints six sizes (AllocatorCreateInfo + the 5 M3 stat structs). Add one line in `main`, after the `AllocatorInfo` line:

```cpp
    std::printf("PoolCreateInfo %zu\n", sizeof(VmaPoolCreateInfo));
```

- [ ] **Step 2: Add the guard entry in `scripts/build-vma.sh`**

After the existing `expect_size AllocatorInfo 24` line, add:

```sh
expect_size PoolCreateInfo 56
```

- [ ] **Step 3: Run the build script to confirm the size and that the lib still builds**

Run:
```sh
cd /home/fesol/source/repos/c3vma.c3l && bash scripts/build-vma.sh ; echo "exit=$?"
```
Expected: prints the seven `name size` lines including `PoolCreateInfo 56`, then `Done.` and `exit=0`. A non-zero exit with `ERROR: sizeof(VmaPoolCreateInfo) = ...` means the size differs from 56 — STOP and reconcile (the printed size is authoritative; update both the guard and the Step 4 `$assert`). `VULKAN_SDK` is set to `/home/fesol/opt/vulkan/x86_64`.

- [ ] **Step 4: Create `vma_pool.c3i`**

```c3
module vma;

import vk;

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

extern fn vk::Result Allocator.create_pool(self, PoolCreateInfo* ci, Pool* out_pool) @cname("vmaCreatePool");
extern fn void Allocator.destroy_pool(self, Pool pool) @cname("vmaDestroyPool");
extern fn void Allocator.get_pool_statistics(self, Pool pool, Statistics* out_stats) @cname("vmaGetPoolStatistics");
extern fn void Allocator.calculate_pool_statistics(self, Pool pool, DetailedStatistics* out_stats) @cname("vmaCalculatePoolStatistics");
extern fn vk::Result Allocator.check_pool_corruption(self, Pool pool) @cname("vmaCheckPoolCorruption");
extern fn void Allocator.get_pool_name(self, Pool pool, ZString* out_name) @cname("vmaGetPoolName");
extern fn void Allocator.set_pool_name(self, Pool pool, ZString name) @cname("vmaSetPoolName");
```

- [ ] **Step 5: Verify the module compiles against `vk` (this runs the `$assert` size pin)**

Run:
```sh
cd /home/fesol/source/repos/c3vma.c3l/test && c3c compile-only --no-obj ../vma.c3i ../vma.c3 ../vma_memory.c3i ../vma_memory.c3 ../vma_image.c3i ../vma_image.c3 ../vma_stats.c3i ../vma_stats.c3 ../vma_pool.c3i --libdir libs --lib vk ; echo "exit=$?" ; rm -rf obj ; cd ..
```
Expected: `Object files written…` and `exit=0`. A `$assert` failure means the size differs from Step 3's probe — set the `$assert` to the probed value. A `Statistics could not be found` means M3's `vma_stats.c3i` was omitted from the command.

- [ ] **Step 6: Commit**

```sh
git add scripts/vma_size_probe.cpp scripts/build-vma.sh vma_pool.c3i
git commit -m "vma: bind Pool handle + PoolCreateInfo (size-pinned) + raw externs (M4)"
```

---

### Task 2: Pool idiomatic wrappers + corruption fault

**Files:**
- Create: `vma_pool.c3`
- Modify: `vma.c3`

**Interfaces:**
- Consumes: Task 1's `Pool`, `PoolCreateInfo`, and raw methods; `vma::check` (M0); `vma::Statistics`, `vma::DetailedStatistics` (M3).
- Produces: fault `vma::CORRUPTION_DETECTED`; methods `Allocator.try_create_pool -> Pool?`, `pool_statistics -> Statistics`, `pool_detailed_statistics -> DetailedStatistics`, `try_check_pool_corruption -> void?`, `pool_name -> ZString`. Task 4 consumes these.

- [ ] **Step 1: Add the `CORRUPTION_DETECTED` fault and `check()` case in `vma.c3`**

In the `faultdef` block, add `CORRUPTION_DETECTED,` on the line before `UNKNOWN;` so it reads:

```c3
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
```

In the `check()` switch, add one case before the `default:` line:

```c3
        case vk::Result.ERROR_VALIDATION_FAILED_EXT:   return CORRUPTION_DETECTED~;
```

- [ ] **Step 2: Create `vma_pool.c3`**

```c3
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
```

- [ ] **Step 3: Verify the module compiles against `vk`**

Run:
```sh
cd /home/fesol/source/repos/c3vma.c3l/test && c3c compile-only --no-obj ../vma.c3i ../vma.c3 ../vma_memory.c3i ../vma_memory.c3 ../vma_image.c3i ../vma_image.c3 ../vma_stats.c3i ../vma_stats.c3 ../vma_pool.c3i ../vma_pool.c3 --libdir libs --lib vk ; echo "exit=$?" ; rm -rf obj ; cd ..
```
Expected: `Object files written…` and `exit=0`. A `CORRUPTION_DETECTED could not be found` means Step 1's faultdef edit was missed.

- [ ] **Step 4: Commit**

```sh
git add vma.c3 vma_pool.c3
git commit -m "vma: add idiomatic pool wrappers + CORRUPTION_DETECTED fault (M4)"
```

---

### Task 3: Find-memory-type-index helpers + pool-field retype

**Files:**
- Modify: `vma_memory.c3i`
- Modify: `vma_memory.c3`

**Interfaces:**
- Consumes: `vma::Allocator`, `vma::AllocationCreateInfo` (M1); `vma::check` (M0); `vma::Pool` (Task 1); `vk::BufferCreateInfo`, `vk::ImageCreateInfo`, `vk::Result` (vk).
- Produces: retyped field `AllocationCreateInfo.pool` (now `Pool`); methods `Allocator.find_memory_type_index`, `find_memory_type_index_for_buffer_info`, `find_memory_type_index_for_image_info` (raw); `try_find_memory_type_index -> uint?`, `try_find_memory_type_index_for_buffer_info -> uint?`, `try_find_memory_type_index_for_image_info -> uint?`. Task 4 consumes these and `ai.pool`.

- [ ] **Step 1: Retype the `pool` field in `vma_memory.c3i`**

In the `AllocationCreateInfo` struct, change the line:
```c3
    void*                   pool;
```
to:
```c3
    Pool                    pool;
```
(`Pool` is defined in `vma_pool.c3i`, same module. Pointer-width-identical, so the `$assert(AllocationCreateInfo::size == 48)` below the struct is unchanged.)

- [ ] **Step 2: Append the find-memtype raw externs to `vma_memory.c3i`**

Append to the end of `vma_memory.c3i`:

```c3

extern fn vk::Result Allocator.find_memory_type_index(self, uint memory_type_bits, AllocationCreateInfo* ci, uint* out_index) @cname("vmaFindMemoryTypeIndex");
extern fn vk::Result Allocator.find_memory_type_index_for_buffer_info(self, vk::BufferCreateInfo* bi, AllocationCreateInfo* ci, uint* out_index) @cname("vmaFindMemoryTypeIndexForBufferInfo");
extern fn vk::Result Allocator.find_memory_type_index_for_image_info(self, vk::ImageCreateInfo* ii, AllocationCreateInfo* ci, uint* out_index) @cname("vmaFindMemoryTypeIndexForImageInfo");
```

- [ ] **Step 3: Append the find-memtype idiomatic wrappers to `vma_memory.c3`**

Append to the end of `vma_memory.c3`:

```c3

fn uint? Allocator.try_find_memory_type_index(self, uint memory_type_bits, AllocationCreateInfo* ci) {
    uint idx;
    check(self.find_memory_type_index(memory_type_bits, ci, &idx))!;
    return idx;
}

fn uint? Allocator.try_find_memory_type_index_for_buffer_info(self, vk::BufferCreateInfo* bi, AllocationCreateInfo* ci) {
    uint idx;
    check(self.find_memory_type_index_for_buffer_info(bi, ci, &idx))!;
    return idx;
}

fn uint? Allocator.try_find_memory_type_index_for_image_info(self, vk::ImageCreateInfo* ii, AllocationCreateInfo* ci) {
    uint idx;
    check(self.find_memory_type_index_for_image_info(ii, ci, &idx))!;
    return idx;
}
```

- [ ] **Step 4: Verify the module compiles against `vk`**

Run:
```sh
cd /home/fesol/source/repos/c3vma.c3l/test && c3c compile-only --no-obj ../vma.c3i ../vma.c3 ../vma_memory.c3i ../vma_memory.c3 ../vma_image.c3i ../vma_image.c3 ../vma_stats.c3i ../vma_stats.c3 ../vma_pool.c3i ../vma_pool.c3 --libdir libs --lib vk ; echo "exit=$?" ; rm -rf obj ; cd ..
```
Expected: `Object files written…` and `exit=0`. A `Pool could not be found` means Task 1's `vma_pool.c3i` is missing from the command or the retype was applied before Task 1 landed.

- [ ] **Step 5: Commit**

```sh
git add vma_memory.c3i vma_memory.c3
git commit -m "vma: bind find-memory-type-index helpers + retype AllocationCreateInfo.pool (M4)"
```

---

### Task 4: Pool round-trip smoke

**Files:**
- Modify: `test/src/main.c3`

**Interfaces:**
- Consumes: M0 bootstrap (`HeadlessVk`/`create_headless_vk`/`destroy_headless_vk`); `vma::try_create_allocator`/`Allocator.destroy` (M0); `try_create_buffer`/`destroy_buffer`/`AllocationCreateInfo`/`MemoryUsage`/`BufferAllocation` (M1/M2); Task 1–3 (`try_create_pool`/`destroy_pool`/`set_pool_name`/`pool_name`/`pool_statistics`/`pool_detailed_statistics`/`try_check_pool_corruption`/`try_find_memory_type_index_for_buffer_info`/`PoolCreateInfo`/`Pool`); `vma::FEATURE_NOT_PRESENT` (M0 fault); `std::io`.
- Produces: the runnable smoke proving the M4 pool path.

- [ ] **Step 1: Add the new faults to the `faultdef` block in `test/src/main.c3`**

The block currently ends:
```c3
    STATS_EMPTY,
    INFO_MISMATCH;
```
Change it to:
```c3
    STATS_EMPTY,
    INFO_MISMATCH,
    POOL_NAME_MISMATCH,
    POOL_STATS_EMPTY;
```

- [ ] **Step 2: Wire `pool_round_trip` into `run()`**

In `run()`, the last sub-test call is:
```c3
    stats_round_trip(alloc, h.device)!;
```
Add a line right after it:
```c3
    pool_round_trip(alloc, h.device)!;
```

- [ ] **Step 3: Update the success message in `main()`**

Change:
```c3
    io::printn("vma smoke OK: map + image + manual buffer/reqs/image + stats");
```
to:
```c3
    io::printn("vma smoke OK: map + image + manual buffer/reqs/image + stats + pool");
```

- [ ] **Step 4: Append the `pool_round_trip` function to `test/src/main.c3`**

Append at the end of the file:

```c3

<* Custom pool: find a memory type for a buffer, create a pool on it, name it,
   allocate a buffer from the pool, query pool statistics, check corruption. *>
fn void? pool_round_trip(vma::Allocator alloc, vk::Device device) {
    vk::BufferCreateInfo bi = {
        .s_type       = vk::StructureType.BUFFER_CREATE_INFO,
        .size         = BUFFER_SIZE,
        .usage        = vk::BufferUsageFlagBits.TRANSFER_DST_BIT,
        .sharing_mode = vk::SharingMode.EXCLUSIVE,
    };
    vma::AllocationCreateInfo find_ai = { .usage = vma::MemoryUsage.AUTO };
    uint mem_type = alloc.try_find_memory_type_index_for_buffer_info(&bi, &find_ai)!;

    vma::PoolCreateInfo pci = { .memory_type_index = mem_type };
    vma::Pool pool = alloc.try_create_pool(&pci)!;
    defer alloc.destroy_pool(pool);

    alloc.set_pool_name(pool, "smoke_pool");
    if (alloc.pool_name(pool).str_view() != "smoke_pool") return POOL_NAME_MISMATCH~;

    vma::AllocationCreateInfo pool_ai = { .pool = pool };
    vma::BufferAllocation ba = alloc.try_create_buffer(&bi, &pool_ai)!;
    defer alloc.destroy_buffer(ba.buffer, ba.allocation);

    vma::Statistics ps = alloc.pool_statistics(pool);
    if (ps.allocation_bytes == 0 || ps.block_count == 0) return POOL_STATS_EMPTY~;
    vma::DetailedStatistics pds = alloc.pool_detailed_statistics(pool);
    if (pds.statistics.allocation_bytes == 0) return POOL_STATS_EMPTY~;

    if (catch err = alloc.try_check_pool_corruption(pool)) {
        if (err != vma::FEATURE_NOT_PRESENT) return err~;
    }
}
```

- [ ] **Step 5: Build the smoke executable**

Run:
```sh
cd /home/fesol/source/repos/c3vma.c3l/test && c3c build smoke 2>&1 | tail -8 ; echo "exit=$?" ; cd ..
```
Expected: `Program linked to executable 'build/smoke'.` and `exit=0`. An undefined `vma*` symbol points at a `@cname` typo in Tasks 1–3; a C3 type/cast error is a transcription issue in this file. A `pool` field type error means Task 3's retype didn't land.

- [ ] **Step 6: Run the smoke on lavapipe**

Run:
```sh
cd /home/fesol/source/repos/c3vma.c3l/test && VK_LOADER_DRIVERS_SELECT='*lvp*' ./build/smoke ; echo "exit=$?" ; cd ..
```
Expected: prints `vma smoke OK: map + image + manual buffer/reqs/image + stats + pool` and `exit=0`.
- `vma smoke FAILED: POOL_STATS_EMPTY` → the pool reported zero usage while a buffer is allocated from it — check that `pool_ai.pool` is set and `try_create_buffer` actually allocated from the pool (not a default block).
- `vma smoke FAILED: POOL_NAME_MISMATCH` → `set_pool_name`/`pool_name` round-trip failed — check the `ZString`/`str_view` handling and that VMA copied the name.
- A vk-layer fault at `try_create_pool` or `try_create_buffer` → the chosen `mem_type` may be incompatible; rerun under `VK_LOADER_DEBUG=error`.
- A `CORRUPTION_DETECTED` fault → unexpected (our lib has no corruption detection); report it, do not suppress.
If it still won't run after these checks, STOP and report BLOCKED with the exact output — do not weaken assertions.

- [ ] **Step 7: Clean artifacts and commit**

```sh
rm -rf test/build test/obj
git add test/src/main.c3
git commit -m "test: pool round-trip (find type, create, allocate-from, stats, name) (M4)"
```

---

## Done criteria

- `bash scripts/build-vma.sh` prints `PoolCreateInfo 56` and exits 0; the `$assert` in `vma_pool.c3i` holds.
- `vma_pool.c3i`/`.c3` (new) + the Task 2/3 additions to `vma.c3`/`vma_memory.*` compile against `vk`.
- `cd test && c3c build smoke` links; `./build/smoke` prints `vma smoke OK: map + image + manual buffer/reqs/image + stats + pool` and exits 0 on lavapipe.
- Pools are usable end-to-end: find memory type → create pool → name → allocate a buffer **from** the pool → non-zero pool statistics → corruption check (accepts `FEATURE_NOT_PRESENT`).
- Next milestone (M5 defragmentation or M6 virtual allocator) can build on this.
```
