# M5 — Defragmentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bind VMA's defragmentation API (begin → pass-loop → end) — raw externs plus idiomatic wrappers — and prove the lifecycle headless with a `defrag_round_trip` smoke that drives the pass loop using `operation = IGNORE` (no GPU copy).

**Architecture:** Extend `module vma;` with a new file pair `vma_defrag.c3i`/`.c3`: a `DefragmentationContext` handle, four layout-pinned structs, a `DefragmentationFlags` bitstruct, a `DefragmentationMoveOperation` enum, a break-callback function-pointer alias, four raw externs, and three idiomatic wrappers. The pass functions return `VK_SUCCESS`/`VK_INCOMPLETE` (both non-error), so their wrappers return `bool?` ("incomplete / more to do") via a private `check_pass()` — NOT the shared `check()`. Reuses M4's `Pool` and M1's `Allocation`. The test fragments a small-block custom pool and runs the loop with `IGNORE` moves.

**Tech Stack:** C3 0.8.0 (`c3c`), VMA static lib from M0 (`linked-libs/linux-x64/libVulkanMemoryAllocator.a` — already contains every M5 symbol), `vk.c3l`, headless Vulkan + lavapipe.

## Global Constraints

- **C3 0.8.0.** Externs use `@cname("vmaXxx")`, NOT `@extern`. Allocator-first functions are methods with receiver `self` **by value** (handle is `inline void*`). Lift a fault with trailing `~`; propagate with `!`. `T::size`, never `T.sizeof`.
- **All Vulkan types come from `vk`** (`vk::DeviceSize`, `vk::Result`, `vk::Bool32`, `vk::BufferCreateInfo`). Never redefine them.
- **The pass functions return `VK_SUCCESS` (done) or `VK_INCOMPLETE` (more to do)** — both non-error. They must NOT route through `check()`; use the private `check_pass()` mapping `SUCCESS`→`false`, `INCOMPLETE`→`true`, real errors→`check()`. `begin_defragmentation` returns `VkResult` (→ `try_*` + `check()`); `end_defragmentation` returns `void` (→ used raw, no wrapper).
- **`DefragmentationInfo.pool` is M4's `Pool`; the `*_allocation` fields are M1's `Allocation`.** Reused, not redefined.
- **Four new layout-pinned structs**, each `$assert(T::size == N)` immediately after it, with `N` from the size probe: `DefragmentationInfo` 48, `DefragmentationMove` 24, `DefragmentationPassMoveInfo` 16, `DefragmentationStats` 24.
- **Naming:** types PascalCase, functions/fields snake_case, faults one-per-line, named constants (no bare magic numbers — test fixtures exempt), no `@builtin`, no all-uppercase type names. K&R braces. Do not run `c3fmt`.
- **No milestone tags in code or comments.** `(M5)` may appear in commit messages only.

## File Structure

| File | Responsibility |
|------|----------------|
| `scripts/vma_size_probe.cpp` (modify) | Add the four defrag struct sizes to the probe table. |
| `scripts/build-vma.sh` (modify) | Add four `expect_size` entries to the size guard. |
| `vma_defrag.c3i` (create) | Handle, 2 enums-family (move-op enum + flags bitstruct), PFN alias, 4 structs + `$assert`s, 4 raw externs. |
| `vma_defrag.c3` (create) | 3 idiomatic wrappers + private `check_pass`. |
| `test/src/main.c3` (modify) | `defrag_round_trip` path + updated success message. |

All `vma*` files are `module vma;`; the repo compile hook compiles sibling module files together so cross-file refs resolve. `vma.c3` is unchanged — `check()` is reused. Every code block below was compile-checked against `vk` during planning.

---

### Task 1: Defrag types + size-probe pinning + raw externs

**Files:**
- Modify: `scripts/vma_size_probe.cpp`
- Modify: `scripts/build-vma.sh`
- Create: `vma_defrag.c3i`

**Interfaces:**
- Consumes: `vma::Allocator` (M0); `vma::Allocation` (M1); `vma::Pool` (M4); `vk::DeviceSize`, `vk::Result`, `vk::Bool32` (vk).
- Produces: `vma::DefragmentationContext` (handle), `vma::DefragmentationMoveOperation` (enum), `vma::DefragmentationFlags` (bitstruct), `vma::CheckDefragmentationBreakFunc` (alias), `vma::DefragmentationInfo`/`DefragmentationMove`/`DefragmentationPassMoveInfo`/`DefragmentationStats` (structs); methods `Allocator.begin_defragmentation`, `end_defragmentation`, `begin_defragmentation_pass`, `end_defragmentation_pass`. Tasks 2 and 3 consume these.

- [ ] **Step 1: Add the four defrag structs to `scripts/vma_size_probe.cpp`**

In `main`, after the `PoolCreateInfo` line, add:

```cpp
    std::printf("DefragmentationInfo %zu\n", sizeof(VmaDefragmentationInfo));
    std::printf("DefragmentationMove %zu\n", sizeof(VmaDefragmentationMove));
    std::printf("DefragmentationPassMoveInfo %zu\n", sizeof(VmaDefragmentationPassMoveInfo));
    std::printf("DefragmentationStats %zu\n", sizeof(VmaDefragmentationStats));
```

- [ ] **Step 2: Add the guard entries in `scripts/build-vma.sh`**

After the existing `expect_size PoolCreateInfo 56` line, add:

```sh
expect_size DefragmentationInfo 48
expect_size DefragmentationMove 24
expect_size DefragmentationPassMoveInfo 16
expect_size DefragmentationStats 24
```

- [ ] **Step 3: Run the build script to confirm the sizes and that the lib still builds**

Run:
```sh
cd /home/fesol/source/repos/c3vma.c3l && bash scripts/build-vma.sh ; echo "exit=$?"
```
Expected: prints all `name size` lines including `DefragmentationInfo 48`, `DefragmentationMove 24`, `DefragmentationPassMoveInfo 16`, `DefragmentationStats 24`, then `Done.` and `exit=0`. A non-zero exit with `ERROR: sizeof(...)` means a size differs — STOP and reconcile (the printed size is authoritative; update both the guard and the Step 4 `$assert`). `VULKAN_SDK` is `/home/fesol/opt/vulkan/x86_64`.

- [ ] **Step 4: Create `vma_defrag.c3i`**

```c3
module vma;

import vk;

typedef DefragmentationContext = inline void*;

enum DefragmentationMoveOperation : int {
    COPY,
    IGNORE,
    DESTROY,
}

bitstruct DefragmentationFlags : uint {
    bool algorithm_fast      : 0;
    bool algorithm_balanced  : 1;
    bool algorithm_full      : 2;
    bool algorithm_extensive : 3;
}

alias CheckDefragmentationBreakFunc = fn vk::Bool32(void* user_data);

struct DefragmentationInfo {
    DefragmentationFlags          flags;
    Pool                          pool;
    vk::DeviceSize                max_bytes_per_pass;
    uint                          max_allocations_per_pass;
    CheckDefragmentationBreakFunc pfn_break_callback;
    void*                         break_callback_user_data;
}
$assert(DefragmentationInfo::size == 48);

struct DefragmentationMove {
    DefragmentationMoveOperation operation;
    Allocation                   src_allocation;
    Allocation                   dst_tmp_allocation;
}
$assert(DefragmentationMove::size == 24);

struct DefragmentationPassMoveInfo {
    uint                 move_count;
    DefragmentationMove* moves;
}
$assert(DefragmentationPassMoveInfo::size == 16);

struct DefragmentationStats {
    vk::DeviceSize bytes_moved;
    vk::DeviceSize bytes_freed;
    uint           allocations_moved;
    uint           device_memory_blocks_freed;
}
$assert(DefragmentationStats::size == 24);

extern fn vk::Result Allocator.begin_defragmentation(self, DefragmentationInfo* info, DefragmentationContext* out_ctx) @cname("vmaBeginDefragmentation");
extern fn void Allocator.end_defragmentation(self, DefragmentationContext ctx, DefragmentationStats* out_stats) @cname("vmaEndDefragmentation");
extern fn vk::Result Allocator.begin_defragmentation_pass(self, DefragmentationContext ctx, DefragmentationPassMoveInfo* pass_info) @cname("vmaBeginDefragmentationPass");
extern fn vk::Result Allocator.end_defragmentation_pass(self, DefragmentationContext ctx, DefragmentationPassMoveInfo* pass_info) @cname("vmaEndDefragmentationPass");
```

- [ ] **Step 5: Verify the module compiles against `vk` (runs the `$assert` size pins)**

Run:
```sh
cd /home/fesol/source/repos/c3vma.c3l/test && c3c compile-only --no-obj ../vma.c3i ../vma.c3 ../vma_memory.c3i ../vma_memory.c3 ../vma_image.c3i ../vma_image.c3 ../vma_stats.c3i ../vma_stats.c3 ../vma_pool.c3i ../vma_pool.c3 ../vma_defrag.c3i --libdir libs --lib vk ; echo "exit=$?" ; rm -rf obj ; cd ..
```
Expected: `Object files written…` and `exit=0`. A `$assert` failure means a size differs from Step 3's probe — set the `$assert` to the probed value. A `Pool could not be found` means M4's `vma_pool.c3i` was omitted from the command.

- [ ] **Step 6: Commit**

```sh
git add scripts/vma_size_probe.cpp scripts/build-vma.sh vma_defrag.c3i
git commit -m "vma: bind defragmentation handle/structs/enums + raw externs, size-pinned (M5)"
```

---

### Task 2: Idiomatic defragmentation wrappers

**Files:**
- Create: `vma_defrag.c3`

**Interfaces:**
- Consumes: Task 1's handle/structs and raw methods; `vma::check` (M0); `vk::Result` (vk).
- Produces: methods `Allocator.try_begin_defragmentation -> DefragmentationContext?`, `try_begin_defragmentation_pass -> bool?`, `try_end_defragmentation_pass -> bool?`; private `check_pass(vk::Result) -> bool?`. Task 3 consumes these. `end_defragmentation` is used raw (Task 1) — no wrapper here.

- [ ] **Step 1: Create `vma_defrag.c3`**

```c3
module vma;

import vk;

fn DefragmentationContext? Allocator.try_begin_defragmentation(self, DefragmentationInfo* info) {
    DefragmentationContext ctx;
    check(self.begin_defragmentation(info, &ctx))!;
    return ctx;
}

<* Begin a defragmentation pass. Returns true if there are moves to process
   (VK_INCOMPLETE), false if defragmentation is finished (VK_SUCCESS). *>
fn bool? Allocator.try_begin_defragmentation_pass(self, DefragmentationContext ctx, DefragmentationPassMoveInfo* pass_info) {
    return check_pass(self.begin_defragmentation_pass(ctx, pass_info));
}

<* End a defragmentation pass. Returns true if another pass is needed
   (VK_INCOMPLETE), false if defragmentation is finished (VK_SUCCESS). *>
fn bool? Allocator.try_end_defragmentation_pass(self, DefragmentationContext ctx, DefragmentationPassMoveInfo* pass_info) {
    return check_pass(self.end_defragmentation_pass(ctx, pass_info));
}

<* Map a defragmentation pass result: SUCCESS -> false (done), INCOMPLETE -> true
   (more to do), any other result -> the corresponding vma fault. *>
fn bool? check_pass(vk::Result r) @private {
    switch (r) {
        case vk::Result.SUCCESS:    return false;
        case vk::Result.INCOMPLETE: return true;
        default:                    check(r)!;
    }
    return false;
}
```

- [ ] **Step 2: Verify the module compiles against `vk`**

Run:
```sh
cd /home/fesol/source/repos/c3vma.c3l/test && c3c compile-only --no-obj ../vma.c3i ../vma.c3 ../vma_memory.c3i ../vma_memory.c3 ../vma_image.c3i ../vma_image.c3 ../vma_stats.c3i ../vma_stats.c3 ../vma_pool.c3i ../vma_pool.c3 ../vma_defrag.c3i ../vma_defrag.c3 --libdir libs --lib vk ; echo "exit=$?" ; rm -rf obj ; cd ..
```
Expected: `Object files written…` and `exit=0`. A `check could not be found` means M0's `vma.c3` was omitted from the command.

- [ ] **Step 3: Commit**

```sh
git add vma_defrag.c3
git commit -m "vma: add idiomatic defragmentation wrappers (bool? pass loop) (M5)"
```

---

### Task 3: Defragmentation round-trip smoke

**Files:**
- Modify: `test/src/main.c3`

**Interfaces:**
- Consumes: M0 bootstrap + allocator; `try_create_buffer`/`destroy_buffer`/`AllocationCreateInfo`/`MemoryUsage`/`BufferAllocation` (M1); `try_find_memory_type_index_for_buffer_info`/`try_create_pool`/`destroy_pool`/`PoolCreateInfo`/`Pool` (M4); Task 1–2 (`try_begin_defragmentation`/`end_defragmentation`/`try_begin_defragmentation_pass`/`try_end_defragmentation_pass`/`DefragmentationInfo`/`DefragmentationContext`/`DefragmentationPassMoveInfo`/`DefragmentationStats`/`DefragmentationMoveOperation`); `std::io`.
- Produces: the runnable smoke proving the M5 defragmentation lifecycle.

- [ ] **Step 1: Add the `DEFRAG_RUNAWAY` fault to the `faultdef` block in `test/src/main.c3`**

The block currently ends:
```c3
    POOL_NAME_MISMATCH,
    POOL_STATS_EMPTY;
```
Change it to:
```c3
    POOL_NAME_MISMATCH,
    POOL_STATS_EMPTY,
    DEFRAG_RUNAWAY;
```

- [ ] **Step 2: Add the defrag constants near the top of `test/src/main.c3`**

After the existing `const uint MAP_CHECK_BYTES = 4;` line, add:

```c3
const ulong DEFRAG_BLOCK_SIZE = 131072;
const uint DEFRAG_BUFFERS = 16;
const uint MAX_DEFRAG_PASSES = 64;
```

- [ ] **Step 3: Wire `defrag_round_trip` into `run()`**

In `run()`, the last sub-test call is:
```c3
    pool_round_trip(alloc)!;
```
Add a line right after it:
```c3
    defrag_round_trip(alloc)!;
```

- [ ] **Step 4: Update the success message in `main()`**

Change:
```c3
    io::printn("vma smoke OK: map + image + manual buffer/reqs/image + stats + pool");
```
to:
```c3
    io::printn("vma smoke OK: map + image + manual buffer/reqs/image + stats + pool + defrag");
```

- [ ] **Step 5: Append the `defrag_round_trip` function to `test/src/main.c3`**

Append at the end of the file:

```c3

<* Fragment a small-block custom pool, then drive the full defragmentation
   begin->pass-loop->end lifecycle with operation=IGNORE (no GPU copy needed).
   Move count is best-effort (lavapipe-dependent); the loop handles zero moves. *>
fn void? defrag_round_trip(vma::Allocator alloc) {
    vk::BufferCreateInfo bi = {
        .s_type       = vk::StructureType.BUFFER_CREATE_INFO,
        .size         = BUFFER_SIZE,
        .usage        = vk::BufferUsageFlagBits.TRANSFER_SRC_BIT | vk::BufferUsageFlagBits.TRANSFER_DST_BIT,
        .sharing_mode = vk::SharingMode.EXCLUSIVE,
    };
    vma::AllocationCreateInfo find_ai = { .usage = vma::MemoryUsage.AUTO };
    uint mem_type = alloc.try_find_memory_type_index_for_buffer_info(&bi, &find_ai)!;

    vma::PoolCreateInfo pci = { .memory_type_index = mem_type, .block_size = DEFRAG_BLOCK_SIZE };
    vma::Pool pool = alloc.try_create_pool(&pci)!;
    defer alloc.destroy_pool(pool);

    vma::BufferAllocation[DEFRAG_BUFFERS] bufs;
    bool[DEFRAG_BUFFERS] live;
    defer {
        for (uint i = 0; i < DEFRAG_BUFFERS; i++) {
            if (live[i]) alloc.destroy_buffer(bufs[i].buffer, bufs[i].allocation);
        }
    }

    vma::AllocationCreateInfo pool_ai = { .pool = pool };
    for (uint i = 0; i < DEFRAG_BUFFERS; i++) {
        bufs[i] = alloc.try_create_buffer(&bi, &pool_ai)!;
        live[i] = true;
    }
    for (uint i = 0; i < DEFRAG_BUFFERS; i += 2) {
        alloc.destroy_buffer(bufs[i].buffer, bufs[i].allocation);
        live[i] = false;
    }

    vma::DefragmentationInfo info = {
        .flags = { .algorithm_balanced = true },
        .pool  = pool,
    };
    vma::DefragmentationContext ctx = alloc.try_begin_defragmentation(&info)!;
    vma::DefragmentationStats stats;
    defer alloc.end_defragmentation(ctx, &stats);

    vma::DefragmentationPassMoveInfo pass;
    uint passes = 0;
    while (alloc.try_begin_defragmentation_pass(ctx, &pass)!) {
        foreach (&m : pass.moves[:pass.move_count]) {
            m.operation = vma::DefragmentationMoveOperation.IGNORE;
        }
        passes++;
        if (passes > MAX_DEFRAG_PASSES) return DEFRAG_RUNAWAY~;
        if (!alloc.try_end_defragmentation_pass(ctx, &pass)!) break;
    }
}
```

Defer ordering (LIFO): `end_defragmentation` (last declared) runs first, then the buffer cleanup, then `destroy_pool` — so the context is ended and all pool allocations freed before the pool is destroyed. On the `DEFRAG_RUNAWAY` early return, the same defers still run.

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
Expected: prints `vma smoke OK: map + image + manual buffer/reqs/image + stats + pool + defrag` and `exit=0`.
- `vma smoke FAILED: DEFRAG_RUNAWAY` → the pass loop did not converge within `MAX_DEFRAG_PASSES` — investigate the begin-pass/end-pass return handling (`check_pass`), not the harness.
- A vk-layer fault at `try_create_pool`/`try_create_buffer` → the chosen `mem_type` or `DEFRAG_BLOCK_SIZE` is incompatible; rerun under `VK_LOADER_DEBUG=error`.
- A fault from `try_begin_defragmentation`/the pass calls → inspect the specific vma fault name; a `UNKNOWN` here would mean `check_pass` mis-mapped a status.
If it still won't run after these checks, STOP and report BLOCKED with the exact output — do not weaken assertions or skip the pass loop.

- [ ] **Step 8: Clean artifacts and commit**

```sh
rm -rf test/build test/obj
git add test/src/main.c3
git commit -m "test: defragmentation round-trip via IGNORE-move pass loop (M5)"
```

---

## Done criteria

- `bash scripts/build-vma.sh` prints the four defrag sizes (48/24/16/24) and exits 0; the four `$assert`s in `vma_defrag.c3i` hold.
- `vma_defrag.c3i`/`.c3` (new) compile against `vk`.
- `cd test && c3c build smoke` links; `./build/smoke` prints `vma smoke OK: map + image + manual buffer/reqs/image + stats + pool + defrag` and exits 0 on lavapipe.
- The defragmentation lifecycle (begin → bool?-driven pass loop → end) runs end-to-end headless; `VK_INCOMPLETE` is correctly surfaced as `true` (not a fault), and the loop terminates.
- Out of scope and unexercised: real GPU-copy moves (`operation = COPY`), the break callback (null), and the non-`balanced` algorithm flags — all documented in the spec.
- Next milestone (M6 virtual allocator) can build on this.
```
