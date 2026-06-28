# M3 — Statistics, Budget + closing the M2 leftovers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bind VMA's statistics & budget surface (raw externs + by-value idiomatic accessors), and in the same milestone close every binding gap M2 deferred — `vmaAllocateMemoryForImage`, the `bind_*2` variants, and the batch flush/invalidate + raw `allocate_memory` paths — proving the whole surface with a headless smoke on lavapipe.

**Architecture:** Extend `module vma;`. Statistics get a new file pair `vma_stats.c3i`/`.c3`: five layout-pinned C structs (`Statistics`, `DetailedStatistics`, `TotalStatistics`, `Budget`, `AllocatorInfo`) plus eight `void`-returning raw externs, and seven by-value idiomatic accessors. The M3 statistics functions return `void`, not `VkResult`, so they have **no fault paths** — `check()` is untouched by them; the idiomatic layer is pure convenience plus one owned-`String` copy-out. The deferred items *do* return `VkResult` and route through `check()` like M1/M2; they extend the existing `vma_memory.c3`/`vma_image.*` files. The test bumps the headless device to Vulkan 1.1 so `bind_*2` resolves as core.

**Tech Stack:** C3 0.8.0 (`c3c`), VMA static lib from M0 (`linked-libs/linux-x64/libVulkanMemoryAllocator.a` — already contains every M3 symbol), `vk.c3l`, headless Vulkan + lavapipe.

## Global Constraints

- **C3 0.8.0.** Externs use `@cname("vmaXxx")`, NOT `@extern`. Allocator-first functions are methods with receiver `self` **by value** (handle is `inline void*`). Lift a fault into an optional with trailing `~` (e.g. `return STATS_EMPTY~;`); the pre-0.8.0 `?` suffix is removed.
- **All Vulkan types come from `vk`** (`vk::DeviceSize`, `vk::Instance`, `vk::PhysicalDevice`, `vk::Device`, `vk::Image`, `vk::Buffer`, `vk::MemoryRequirements`, `vk::PhysicalDeviceProperties`, `vk::PhysicalDeviceMemoryProperties`, `vk::MemoryPropertyFlags`, `vk::Bool32`, `vk::MAX_MEMORY_TYPES`, `vk::MAX_MEMORY_HEAPS`, `vk::Result`). Never redefine them.
- **Type properties via `::`** — `T::size`, never `T.sizeof`. Every fully-declared C struct gets a `$assert(T::size == N);` immediately after it, with `N` from the size probe.
- **The M3 statistics functions return `void`** — no idiomatic `try_*`/`check()` wrappers; their idiomatic layer returns values by value. The **deferred** functions return `vk::Result` and route through `check()` with `try_*` wrappers.
- **Naming:** types PascalCase, functions/fields snake_case, faults one-per-line, named constants (no bare magic numbers), no `@builtin`, no all-uppercase type names. K&R braces (opening brace same line). Do not run `c3fmt`.
- **No milestone tags in code or comments.** `(M3)` may appear in commit messages only.

## File Structure

| File | Responsibility |
|------|----------------|
| `scripts/vma_size_probe.cpp` (modify) | Print `sizeof` for `AllocatorCreateInfo` + the five new stat structs, one `name size` per line. |
| `scripts/build-vma.sh` (modify) | Generalize the single-size guard to a `name → expected` table covering all six sizes. |
| `vma_stats.c3i` (create) | Five layout-pinned stat structs + `$assert`s + eight `void` raw externs. |
| `vma_stats.c3` (create) | Seven by-value idiomatic accessors (`info`, `physical_device_properties`, `memory_properties`, `memory_type_properties`, `statistics`, `heap_budgets`, `stats_string`). |
| `vma.c3` (modify) | Add the `BATCH_LENGTH_MISMATCH` fault to the existing `faultdef` block. |
| `vma_image.c3i` (modify) | Append the `allocate_memory_for_image` raw extern. |
| `vma_image.c3` (modify) | Append `try_allocate_memory_for_image`, `try_bind_image_memory2`. |
| `vma_memory.c3` (modify) | Append `try_allocate_memory`, `try_bind_buffer_memory2`, `try_flush_allocations`, `try_invalidate_allocations`. |
| `test/src/vk_bootstrap.c3` (modify) | Add `VK_API_1_1`; set the app `api_version` to it. |
| `test/src/main.c3` (replace) | Bump allocator to 1.1; add `stats_round_trip` + `manual_image_bind`; rewrite `manual_alloc_bind` (raw allocate + `bind_*2`); add batch flush/invalidate to `map_round_trip`. |

`vma.c3i` (M0) and the M1/M2 externs in `vma_memory.c3i` are unchanged. All `vma*` files are `module vma;`; the repo's compile hook compiles sibling module files together so cross-file refs resolve. Every code block below was compile-checked against `vk` during planning.

---

### Task 1: Stat structs + size-probe pinning + raw externs

**Files:**
- Modify: `scripts/vma_size_probe.cpp`
- Modify: `scripts/build-vma.sh`
- Create: `vma_stats.c3i`

**Interfaces:**
- Consumes: `vma::Allocator` (M0); `vk::DeviceSize`, `vk::Instance`, `vk::PhysicalDevice`, `vk::Device`, `vk::PhysicalDeviceProperties`, `vk::PhysicalDeviceMemoryProperties`, `vk::MemoryPropertyFlags`, `vk::Bool32`, `vk::MAX_MEMORY_TYPES`, `vk::MAX_MEMORY_HEAPS` (vk).
- Produces: structs `vma::Statistics`, `DetailedStatistics`, `TotalStatistics`, `Budget`, `AllocatorInfo`; methods `Allocator.get_allocator_info`, `get_physical_device_properties`, `get_memory_properties`, `get_memory_type_properties`, `calculate_statistics`, `get_heap_budgets`, `build_stats_string`, `free_stats_string`. Tasks 2 and 4 consume these.

- [ ] **Step 1: Replace `scripts/vma_size_probe.cpp`**

Replace the entire file with:

```cpp
#include <cstdio>
#define VMA_STATIC_VULKAN_FUNCTIONS  1
#define VMA_DYNAMIC_VULKAN_FUNCTIONS 0
#define VMA_EXTERNAL_MEMORY          0
#include <vma/vk_mem_alloc.h>

int main(void) {
    std::printf("AllocatorCreateInfo %zu\n", sizeof(VmaAllocatorCreateInfo));
    std::printf("Statistics %zu\n", sizeof(VmaStatistics));
    std::printf("DetailedStatistics %zu\n", sizeof(VmaDetailedStatistics));
    std::printf("TotalStatistics %zu\n", sizeof(VmaTotalStatistics));
    std::printf("Budget %zu\n", sizeof(VmaBudget));
    std::printf("AllocatorInfo %zu\n", sizeof(VmaAllocatorInfo));
    return 0;
}
```

- [ ] **Step 2: Generalize the size guard in `scripts/build-vma.sh`**

Find this block (the old single-size guard):

```sh
sz=$("$CXX" -std=c++17 -I"$VULKAN_SDK/include" "$ROOT/scripts/vma_size_probe.cpp" -o "$OUT/vma_size_probe" && "$OUT/vma_size_probe")
rm -f "$OUT/vma_size_probe"
if [ "$sz" != "80" ]; then
    echo "ERROR: sizeof(VmaAllocatorCreateInfo) = $sz, expected 80 (VMA_EXTERNAL_MEMORY must be 0). vma.c3i \$assert will mismatch." >&2
    exit 1
fi
```

Replace it with:

```sh
"$CXX" -std=c++17 -I"$VULKAN_SDK/include" "$ROOT/scripts/vma_size_probe.cpp" -o "$OUT/vma_size_probe"
sizes=$("$OUT/vma_size_probe")
rm -f "$OUT/vma_size_probe"
echo "$sizes"
expect_size() {
    got=$(printf '%s\n' "$sizes" | awk -v n="$1" '$1 == n { print $2 }')
    if [ "$got" != "$2" ]; then
        echo "ERROR: sizeof(Vma$1) = $got, expected $2 (VMA_EXTERNAL_MEMORY must be 0). \$assert in the binding will mismatch." >&2
        exit 1
    fi
}
expect_size AllocatorCreateInfo 80
expect_size Statistics 24
expect_size DetailedStatistics 64
expect_size TotalStatistics 3136
expect_size Budget 40
expect_size AllocatorInfo 24
```

- [ ] **Step 3: Run the build script to confirm the sizes and that the lib still builds**

Run:
```sh
cd /home/fesol/source/repos/c3vma.c3l && bash scripts/build-vma.sh ; echo "exit=$?"
```
Expected: prints the six `name size` lines (`AllocatorCreateInfo 80`, `Statistics 24`, `DetailedStatistics 64`, `TotalStatistics 3136`, `Budget 40`, `AllocatorInfo 24`), then `Done.` and `exit=0`. A non-zero exit with an `ERROR: sizeof(...)` line means a struct size differs from the `$assert` value in Step 4 — STOP and reconcile (the printed size is authoritative; update both the guard and the `$assert`). `VULKAN_SDK` must be set (it is: `/home/fesol/opt/vulkan/x86_64`).

- [ ] **Step 4: Create `vma_stats.c3i`**

```c3
module vma;

import vk;

struct Statistics {
    uint           block_count;
    uint           allocation_count;
    vk::DeviceSize block_bytes;
    vk::DeviceSize allocation_bytes;
}
$assert(Statistics::size == 24);

struct DetailedStatistics {
    Statistics     statistics;
    uint           unused_range_count;
    vk::DeviceSize allocation_size_min;
    vk::DeviceSize allocation_size_max;
    vk::DeviceSize unused_range_size_min;
    vk::DeviceSize unused_range_size_max;
}
$assert(DetailedStatistics::size == 64);

struct TotalStatistics {
    DetailedStatistics[vk::MAX_MEMORY_TYPES] memory_type;
    DetailedStatistics[vk::MAX_MEMORY_HEAPS] memory_heap;
    DetailedStatistics                       total;
}
$assert(TotalStatistics::size == 3136);

struct Budget {
    Statistics     statistics;
    vk::DeviceSize usage;
    vk::DeviceSize budget;
}
$assert(Budget::size == 40);

struct AllocatorInfo {
    vk::Instance       instance;
    vk::PhysicalDevice physical_device;
    vk::Device         device;
}
$assert(AllocatorInfo::size == 24);

extern fn void Allocator.get_allocator_info(self, AllocatorInfo* out_info) @cname("vmaGetAllocatorInfo");
extern fn void Allocator.get_physical_device_properties(self, vk::PhysicalDeviceProperties** out_props) @cname("vmaGetPhysicalDeviceProperties");
extern fn void Allocator.get_memory_properties(self, vk::PhysicalDeviceMemoryProperties** out_props) @cname("vmaGetMemoryProperties");
extern fn void Allocator.get_memory_type_properties(self, uint type_index, vk::MemoryPropertyFlags* out_flags) @cname("vmaGetMemoryTypeProperties");
extern fn void Allocator.calculate_statistics(self, TotalStatistics* out_stats) @cname("vmaCalculateStatistics");
extern fn void Allocator.get_heap_budgets(self, Budget* out_budgets) @cname("vmaGetHeapBudgets");
extern fn void Allocator.build_stats_string(self, ZString* out_str, vk::Bool32 detailed) @cname("vmaBuildStatsString");
extern fn void Allocator.free_stats_string(self, ZString str) @cname("vmaFreeStatsString");
```

- [ ] **Step 5: Verify the module compiles against `vk` (this also runs the `$assert` size pins)**

Run:
```sh
cd /home/fesol/source/repos/c3vma.c3l/test && c3c compile-only --no-obj ../vma.c3i ../vma.c3 ../vma_memory.c3i ../vma_memory.c3 ../vma_image.c3i ../vma_image.c3 ../vma_stats.c3i --libdir libs --lib vk ; echo "exit=$?" ; rm -rf obj ; cd ..
```
Expected: `Object files written…` and `exit=0`. A `$assert` failure (`Contract violation` / `static assert`) means a size differs from Step 3's probe — fix the `$assert` to the probed value. A `vk::… could not be found` is a type-name typo.

- [ ] **Step 6: Commit**

```sh
git add scripts/vma_size_probe.cpp scripts/build-vma.sh vma_stats.c3i
git commit -m "vma: bind statistics/budget structs + raw externs, size-pinned (M3)"
```

---

### Task 2: Idiomatic statistics accessors

**Files:**
- Create: `vma_stats.c3`

**Interfaces:**
- Consumes: Task 1's structs and raw methods; `vk::PhysicalDeviceProperties`, `vk::PhysicalDeviceMemoryProperties`, `vk::MemoryPropertyFlags`, `vk::Bool32` (vk); the stdlib `mem` allocator and `ZString.copy`.
- Produces: methods `Allocator.info -> AllocatorInfo`, `physical_device_properties -> vk::PhysicalDeviceProperties*`, `memory_properties -> vk::PhysicalDeviceMemoryProperties*`, `memory_type_properties -> vk::MemoryPropertyFlags`, `statistics -> TotalStatistics`, `heap_budgets(Budget[]) -> Budget[]`, `stats_string(bool) -> String`. Task 4 consumes these. None return an optional — the statistics surface has no fault paths.

- [ ] **Step 1: Create `vma_stats.c3`**

```c3
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
```

- [ ] **Step 2: Verify the module compiles against `vk`**

Run:
```sh
cd /home/fesol/source/repos/c3vma.c3l/test && c3c compile-only --no-obj ../vma.c3i ../vma.c3 ../vma_memory.c3i ../vma_memory.c3 ../vma_image.c3i ../vma_image.c3 ../vma_stats.c3i ../vma_stats.c3 --libdir libs --lib vk ; echo "exit=$?" ; rm -rf obj ; cd ..
```
Expected: `Object files written…` and `exit=0`. A `mem could not be found` means the stdlib import is missing — `mem` is part of `std::core` and resolves without an explicit import; if it errors, add `import std::core::mem;` at the top. A `copy` mismatch means `ZString.copy(Allocator)` drifted — re-grep the stdlib.

- [ ] **Step 3: Commit**

```sh
git add vma_stats.c3
git commit -m "vma: add by-value statistics accessors + owned stats_string (M3)"
```

---

### Task 3: Close the M2-deferred binding gaps

**Files:**
- Modify: `vma.c3` (add one fault)
- Modify: `vma_image.c3i` (append one extern)
- Modify: `vma_image.c3` (append two wrappers)
- Modify: `vma_memory.c3` (append four wrappers)

**Interfaces:**
- Consumes: `vma::check` (M0); `vma::MemoryAllocation`, `Allocator.allocate_memory`, `flush_allocations`, `invalidate_allocations`, `bind_buffer_memory2` (M2); `Allocator.bind_image_memory2` (M2); `vma::AllocationCreateInfo`, `AllocationInfo`, `Allocation` (M1); `vk::Image`, `vk::Buffer`, `vk::MemoryRequirements`, `vk::DeviceSize`, `vk::Result` (vk).
- Produces: fault `vma::BATCH_LENGTH_MISMATCH`; raw `Allocator.allocate_memory_for_image`; methods `Allocator.try_allocate_memory_for_image -> MemoryAllocation?`, `try_bind_image_memory2 -> void?`, `try_allocate_memory -> MemoryAllocation?`, `try_bind_buffer_memory2 -> void?`, `try_flush_allocations -> void?`, `try_invalidate_allocations -> void?`. Task 4 consumes these.

- [ ] **Step 1: Add the `BATCH_LENGTH_MISMATCH` fault to `vma.c3`**

In `vma.c3`, the `faultdef` block currently ends `INVALID_EXTERNAL_HANDLE,` then `UNKNOWN;`. Add the new fault on the line before `UNKNOWN;` so the block reads:

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
    UNKNOWN;
```

- [ ] **Step 2: Append the image extern to `vma_image.c3i`**

Append to the end of `vma_image.c3i`:

```c3
extern fn vk::Result Allocator.allocate_memory_for_image(self, vk::Image image, AllocationCreateInfo* ci, Allocation* out_alloc, AllocationInfo* out_info) @cname("vmaAllocateMemoryForImage");
```

- [ ] **Step 3: Append the image wrappers to `vma_image.c3`**

Append to the end of `vma_image.c3`:

```c3

<* Allocate memory sized/typed for an existing image (does not bind it; call
   `try_bind_image_memory`/`try_bind_image_memory2` after). Free with `free_memory`. *>
fn MemoryAllocation? Allocator.try_allocate_memory_for_image(self, vk::Image image, AllocationCreateInfo* ci) {
    MemoryAllocation ma;
    check(self.allocate_memory_for_image(image, ci, &ma.allocation, &ma.info))!;
    return ma;
}

fn void? Allocator.try_bind_image_memory2(self, Allocation allocation, vk::DeviceSize offset, vk::Image image, void* next) {
    check(self.bind_image_memory2(allocation, offset, image, next))!;
}
```

- [ ] **Step 4: Append the memory wrappers to `vma_memory.c3`**

Append to the end of `vma_memory.c3`:

```c3

<* Allocate memory satisfying raw VkMemoryRequirements (does not bind it; call a
   bind wrapper after). Free with `free_memory`. *>
fn MemoryAllocation? Allocator.try_allocate_memory(self, vk::MemoryRequirements* reqs, AllocationCreateInfo* ci) {
    MemoryAllocation ma;
    check(self.allocate_memory(reqs, ci, &ma.allocation, &ma.info))!;
    return ma;
}

fn void? Allocator.try_bind_buffer_memory2(self, Allocation allocation, vk::DeviceSize offset, vk::Buffer buffer, void* next) {
    check(self.bind_buffer_memory2(allocation, offset, buffer, next))!;
}

<* Flush a batch of allocations. The three slices must be equal length. *>
fn void? Allocator.try_flush_allocations(self, Allocation[] allocs, vk::DeviceSize[] offsets, vk::DeviceSize[] sizes) {
    if (allocs.len != offsets.len || allocs.len != sizes.len) return BATCH_LENGTH_MISMATCH~;
    check(self.flush_allocations((uint)allocs.len, &allocs[0], &offsets[0], &sizes[0]))!;
}

<* Invalidate a batch of allocations. The three slices must be equal length. *>
fn void? Allocator.try_invalidate_allocations(self, Allocation[] allocs, vk::DeviceSize[] offsets, vk::DeviceSize[] sizes) {
    if (allocs.len != offsets.len || allocs.len != sizes.len) return BATCH_LENGTH_MISMATCH~;
    check(self.invalidate_allocations((uint)allocs.len, &allocs[0], &offsets[0], &sizes[0]))!;
}
```

- [ ] **Step 5: Verify the whole module compiles against `vk`**

Run:
```sh
cd /home/fesol/source/repos/c3vma.c3l/test && c3c compile-only --no-obj ../vma.c3i ../vma.c3 ../vma_memory.c3i ../vma_memory.c3 ../vma_image.c3i ../vma_image.c3 ../vma_stats.c3i ../vma_stats.c3 --libdir libs --lib vk ; echo "exit=$?" ; rm -rf obj ; cd ..
```
Expected: `Object files written…` and `exit=0`. A `BATCH_LENGTH_MISMATCH could not be found` means Step 1's faultdef edit was missed; an `allocate_memory`/`bind_buffer_memory2` mismatch means an M2 extern signature drifted.

- [ ] **Step 6: Commit**

```sh
git add vma.c3 vma_image.c3i vma_image.c3 vma_memory.c3
git commit -m "vma: bind allocate-for-image + idiomatic bind2/allocate/batch wrappers (M3)"
```

---

### Task 4: Vulkan 1.1 bump + full headless smoke (stats + deferred runtime coverage)

**Files:**
- Modify: `test/src/vk_bootstrap.c3` (add `VK_API_1_1`; use it for the app version)
- Replace: `test/src/main.c3`

**Interfaces:**
- Consumes: M0 bootstrap (`HeadlessVk`/`create_headless_vk`/`destroy_headless_vk`); `vma::try_create_allocator`/`Allocator.destroy` (M0); `try_create_buffer`/`destroy_buffer`/`try_create_image`/`destroy_image`/`AllocationCreateInfo`/`MemoryUsage`/`BufferAllocation`/`ImageAllocation`/`MemoryAllocation`/`try_map`/`unmap_memory`/`try_flush`/`try_invalidate`/`try_copy_to_allocation`/`try_copy_from_allocation`/`try_allocate_memory_for_buffer`/`try_bind_buffer_memory`/`free_memory` (M1/M2 — preserved so the M2 buffer paths keep their runtime coverage); Task 2 accessors (`statistics`/`heap_budgets`/`info`/`physical_device_properties`/`memory_properties`/`memory_type_properties`/`stats_string`); Task 3 wrappers (`try_allocate_memory`/`try_allocate_memory_for_image`/`try_bind_buffer_memory2`/`try_bind_image_memory2`/`try_flush_allocations`/`try_invalidate_allocations`); `vk::create_buffer`/`destroy_buffer`/`create_image`/`destroy_image`/`get_buffer_memory_requirements` and the vk image/buffer enums, `vk::MAX_MEMORY_HEAPS`.
- Produces: the runnable smoke proving the M3 surface.

- [ ] **Step 1: Add `VK_API_1_1` to `test/src/vk_bootstrap.c3` and use it**

In `test/src/vk_bootstrap.c3`, after the line:
```c3
const uint VK_API_1_0 = 1 << 22;
```
add:
```c3
const uint VK_API_1_1 = (1 << 22) | (1 << 12);
```
Then change the application info version from `VK_API_1_0` to `VK_API_1_1`:
```c3
    vk::ApplicationInfo app = {
        .s_type      = vk::StructureType.APPLICATION_INFO,
        .api_version = VK_API_1_1,
    };
```

- [ ] **Step 2: Replace `test/src/main.c3`**

Replace the entire contents of `test/src/main.c3` with:

```c3
module vma_smoke;

import vma;
import vk;
import std::io;

faultdef
    BUFFER_NULL,
    ALLOCATION_TOO_SMALL,
    MAP_MISMATCH,
    IMAGE_NULL,
    STATS_EMPTY,
    INFO_MISMATCH;

const ulong BUFFER_SIZE = 65536;
const uint MAP_CHECK_BYTES = 4;

fn int main() {
    if (catch err = run()) {
        io::printfn("vma smoke FAILED: %s", err);
        return 1;
    }
    io::printn("vma smoke OK: map + image + manual buffer/reqs/image + stats");
    return 0;
}

fn void? run() {
    HeadlessVk h = create_headless_vk()!;
    defer destroy_headless_vk(&h);

    vma::AllocatorCreateInfo info = {
        .physical_device    = h.physical_device,
        .device             = h.device,
        .instance           = h.instance,
        .vulkan_api_version = VK_API_1_1,
    };
    vma::Allocator alloc = vma::try_create_allocator(&info)!;
    defer alloc.destroy();

    map_round_trip(alloc)!;
    image_round_trip(alloc)!;
    manual_alloc_bind(alloc, h.device)!;
    manual_reqs_bind(alloc, h.device)!;
    manual_image_bind(alloc, h.device)!;
    stats_round_trip(alloc, h.device)!;
}

<* Map a host-visible buffer, write+flush+invalidate+read through the mapped
   slice, then exercise copy-to/from-allocation; assert the bytes survive.
   Also exercises the batch flush/invalidate variants over a one-element set. *>
fn void? map_round_trip(vma::Allocator alloc) {
    vk::BufferCreateInfo bi = {
        .s_type       = vk::StructureType.BUFFER_CREATE_INFO,
        .size         = BUFFER_SIZE,
        .usage        = vk::BufferUsageFlagBits.TRANSFER_SRC_BIT | vk::BufferUsageFlagBits.TRANSFER_DST_BIT,
        .sharing_mode = vk::SharingMode.EXCLUSIVE,
    };
    vma::AllocationCreateInfo ai = {
        .usage = vma::MemoryUsage.AUTO,
        .flags = { .host_access_random = true },
    };
    vma::BufferAllocation ba = alloc.try_create_buffer(&bi, &ai)!;
    defer alloc.destroy_buffer(ba.buffer, ba.allocation);
    if (ba.info.size < BUFFER_SIZE) return ALLOCATION_TOO_SMALL~;

    {
        char[] mapped = alloc.try_map(ba.allocation)!;
        defer alloc.unmap_memory(ba.allocation);
        for (uint i = 0; i < MAP_CHECK_BYTES; i++) mapped[i] = (char)(0x10 + i);
        alloc.try_flush(ba.allocation, 0, MAP_CHECK_BYTES)!;
    }

    vma::Allocation[1] batch_allocs  = { ba.allocation };
    vk::DeviceSize[1]  batch_offsets = { 0 };
    vk::DeviceSize[1]  batch_sizes   = { MAP_CHECK_BYTES };
    alloc.try_flush_allocations(&batch_allocs, &batch_offsets, &batch_sizes)!;

    alloc.try_invalidate(ba.allocation, 0, MAP_CHECK_BYTES)!;
    alloc.try_invalidate_allocations(&batch_allocs, &batch_offsets, &batch_sizes)!;

    bool map_ok = true;
    {
        char[] rb = alloc.try_map(ba.allocation)!;
        defer alloc.unmap_memory(ba.allocation);
        for (uint i = 0; i < MAP_CHECK_BYTES; i++) {
            if (rb[i] != (char)(0x10 + i)) map_ok = false;
        }
    }
    if (!map_ok) return MAP_MISMATCH~;

    char[MAP_CHECK_BYTES] src = { 0xDE, 0xAD, 0xBE, 0xEF };
    char[MAP_CHECK_BYTES] dst;
    alloc.try_copy_to_allocation((void*)&src, ba.allocation, 0, MAP_CHECK_BYTES)!;
    alloc.try_copy_from_allocation(ba.allocation, 0, (void*)&dst, MAP_CHECK_BYTES)!;
    for (uint i = 0; i < MAP_CHECK_BYTES; i++) {
        if (dst[i] != src[i]) return MAP_MISMATCH~;
    }
}

<* Allocate a small 2D image with its backing memory via try_create_image, free. *>
fn void? image_round_trip(vma::Allocator alloc) {
    vk::ImageCreateInfo ici = {
        .s_type         = vk::StructureType.IMAGE_CREATE_INFO,
        .image_type     = vk::ImageType.TYPE_2D,
        .format         = vk::Format.R8G8B8A8_UNORM,
        .extent         = { .width = 64, .height = 64, .depth = 1 },
        .mip_levels     = 1,
        .array_layers   = 1,
        .samples        = vk::SampleCountFlagBits.COUNT_1_BIT,
        .tiling         = vk::ImageTiling.OPTIMAL,
        .usage          = vk::ImageUsageFlagBits.SAMPLED_BIT | vk::ImageUsageFlagBits.TRANSFER_DST_BIT,
        .sharing_mode   = vk::SharingMode.EXCLUSIVE,
        .initial_layout = vk::ImageLayout.UNDEFINED,
    };
    vma::AllocationCreateInfo ai = { .usage = vma::MemoryUsage.AUTO };
    vma::ImageAllocation ia = alloc.try_create_image(&ici, &ai)!;
    defer alloc.destroy_image(ia.image, ia.allocation);
}

<* Manual buffer path: create a raw VkBuffer, allocate memory for it via
   try_allocate_memory_for_buffer, bind via bind_buffer_memory (v1), free. *>
fn void? manual_alloc_bind(vma::Allocator alloc, vk::Device device) {
    vk::BufferCreateInfo bi = {
        .s_type       = vk::StructureType.BUFFER_CREATE_INFO,
        .size         = BUFFER_SIZE,
        .usage        = vk::BufferUsageFlagBits.TRANSFER_SRC_BIT,
        .sharing_mode = vk::SharingMode.EXCLUSIVE,
    };
    vk::Buffer buffer;
    if (vk::create_buffer(device, &bi, null, &buffer) != vk::Result.SUCCESS) return BUFFER_NULL~;

    vma::AllocationCreateInfo ai = { .usage = vma::MemoryUsage.GPU_ONLY };
    vma::MemoryAllocation? ma_opt = alloc.try_allocate_memory_for_buffer(buffer, &ai);
    if (catch err = ma_opt) {
        vk::destroy_buffer(device, buffer, null);
        return err~;
    }
    vma::MemoryAllocation ma = ma_opt;

    defer alloc.free_memory(ma.allocation);
    defer vk::destroy_buffer(device, buffer, null);

    alloc.try_bind_buffer_memory(ma.allocation, buffer)!;
}

<* Raw-requirements path: create a VkBuffer, query its memory requirements,
   allocate via try_allocate_memory, bind via bind_buffer_memory2, free. *>
fn void? manual_reqs_bind(vma::Allocator alloc, vk::Device device) {
    vk::BufferCreateInfo bi = {
        .s_type       = vk::StructureType.BUFFER_CREATE_INFO,
        .size         = BUFFER_SIZE,
        .usage        = vk::BufferUsageFlagBits.TRANSFER_SRC_BIT,
        .sharing_mode = vk::SharingMode.EXCLUSIVE,
    };
    vk::Buffer buffer;
    if (vk::create_buffer(device, &bi, null, &buffer) != vk::Result.SUCCESS) return BUFFER_NULL~;

    vk::MemoryRequirements reqs;
    vk::get_buffer_memory_requirements(device, buffer, &reqs);

    vma::AllocationCreateInfo ai = { .usage = vma::MemoryUsage.GPU_ONLY };
    vma::MemoryAllocation? ma_opt = alloc.try_allocate_memory(&reqs, &ai);
    if (catch err = ma_opt) {
        vk::destroy_buffer(device, buffer, null);
        return err~;
    }
    vma::MemoryAllocation ma = ma_opt;

    defer alloc.free_memory(ma.allocation);
    defer vk::destroy_buffer(device, buffer, null);

    alloc.try_bind_buffer_memory2(ma.allocation, 0, buffer, null)!;
}

<* Manual image path: create a raw VkImage, allocate memory for it via
   try_allocate_memory_for_image, bind via bind_image_memory2, free. *>
fn void? manual_image_bind(vma::Allocator alloc, vk::Device device) {
    vk::ImageCreateInfo ici = {
        .s_type         = vk::StructureType.IMAGE_CREATE_INFO,
        .image_type     = vk::ImageType.TYPE_2D,
        .format         = vk::Format.R8G8B8A8_UNORM,
        .extent         = { .width = 64, .height = 64, .depth = 1 },
        .mip_levels     = 1,
        .array_layers   = 1,
        .samples        = vk::SampleCountFlagBits.COUNT_1_BIT,
        .tiling         = vk::ImageTiling.OPTIMAL,
        .usage          = vk::ImageUsageFlagBits.SAMPLED_BIT | vk::ImageUsageFlagBits.TRANSFER_DST_BIT,
        .sharing_mode   = vk::SharingMode.EXCLUSIVE,
        .initial_layout = vk::ImageLayout.UNDEFINED,
    };
    vk::Image image;
    if (vk::create_image(device, &ici, null, &image) != vk::Result.SUCCESS) return IMAGE_NULL~;

    vma::AllocationCreateInfo ai = { .usage = vma::MemoryUsage.GPU_ONLY };
    vma::MemoryAllocation? ma_opt = alloc.try_allocate_memory_for_image(image, &ai);
    if (catch err = ma_opt) {
        vk::destroy_image(device, image, null);
        return err~;
    }
    vma::MemoryAllocation ma = ma_opt;

    defer alloc.free_memory(ma.allocation);
    defer vk::destroy_image(device, image, null);

    alloc.try_bind_image_memory2(ma.allocation, 0, image, null)!;
}

<* With a live allocation present, query statistics, heap budgets, allocator
   info, properties, and the JSON stats string; assert they are populated. *>
fn void? stats_round_trip(vma::Allocator alloc, vk::Device device) {
    vk::BufferCreateInfo bi = {
        .s_type       = vk::StructureType.BUFFER_CREATE_INFO,
        .size         = BUFFER_SIZE,
        .usage        = vk::BufferUsageFlagBits.TRANSFER_DST_BIT,
        .sharing_mode = vk::SharingMode.EXCLUSIVE,
    };
    vma::AllocationCreateInfo ai = { .usage = vma::MemoryUsage.AUTO };
    vma::BufferAllocation ba = alloc.try_create_buffer(&bi, &ai)!;
    defer alloc.destroy_buffer(ba.buffer, ba.allocation);

    vma::TotalStatistics stats = alloc.statistics();
    if (stats.total.statistics.allocation_bytes == 0) return STATS_EMPTY~;
    if (stats.total.statistics.block_count == 0) return STATS_EMPTY~;

    vma::Budget[vk::MAX_MEMORY_HEAPS] budget_buf;
    vma::Budget[] budgets = alloc.heap_budgets(&budget_buf);
    if (budgets.len == 0) return STATS_EMPTY~;
    bool any_budget = false;
    foreach (b : budgets) {
        if (b.budget > 0) any_budget = true;
    }
    if (!any_budget) return STATS_EMPTY~;

    vma::AllocatorInfo ainfo = alloc.info();
    if (ainfo.device != device) return INFO_MISMATCH~;

    if (alloc.physical_device_properties() == null) return STATS_EMPTY~;
    vk::PhysicalDeviceMemoryProperties* mp = alloc.memory_properties();
    if (mp == null) return STATS_EMPTY~;

    uint combined = 0;
    for (uint i = 0; i < mp.memory_type_count; i++) {
        combined |= (uint)alloc.memory_type_properties(i);
    }
    if (combined == 0) return STATS_EMPTY~;

    String js = alloc.stats_string(true);
    defer free(js.ptr);
    if (js.len == 0) return STATS_EMPTY~;
}
```

- [ ] **Step 3: Build the smoke executable**

Run:
```sh
cd /home/fesol/source/repos/c3vma.c3l/test && c3c build smoke 2>&1 | tail -8 ; echo "exit=$?" ; cd ..
```
Expected: `Program linked to executable 'build/smoke'.` and `exit=0`. An undefined `vma*` symbol points at a `@cname` typo in Tasks 1–3; a C3 type/cast error in the test is a transcription issue in this file — fix it here. A `could not find … libVulkanMemoryAllocator` means Task 1 Step 3's `build-vma.sh` did not run — run it.

- [ ] **Step 4: Run the smoke on lavapipe**

Run:
```sh
cd /home/fesol/source/repos/c3vma.c3l/test && VK_LOADER_DRIVERS_SELECT='*lvp*' ./build/smoke ; echo "exit=$?" ; cd ..
```
Expected: prints `vma smoke OK: map + image + manual buffer/reqs/image + stats` and `exit=0`.
- `vma smoke FAILED: STATS_EMPTY` → a statistics getter returned zero while an allocation is live — investigate `statistics`/`heap_budgets`/`memory_*`/`stats_string`, not the harness.
- `vma smoke FAILED: INFO_MISMATCH` → `info().device` didn't equal the bootstrap device — check the `AllocatorInfo` field order in Task 1.
- `vma smoke FAILED: MAP_MISMATCH` → the batch flush/invalidate or copy path corrupted bytes — investigate the new batch calls.
- `vma smoke FAILED: BUFFER_NULL`/`IMAGE_NULL` → the named raw vk creation step failed; rerun under `VK_LOADER_DEBUG=error`.
- A vk-layer fault around `bind_*2` (e.g. a "requires Vulkan 1.1" message) → Step 1's `VK_API_1_1` bump or the allocator's `vulkan_api_version` was missed.
- A vk-layer fault unrelated to the above → retry without `VK_LOADER_DRIVERS_SELECT` (M0's device loop skips non-working ICDs).
If it still won't link or run after these checks, STOP and report BLOCKED with the exact output — do not weaken the assertions.

- [ ] **Step 5: Clean artifacts and commit**

```sh
rm -rf test/build test/obj
git add test/src/vk_bootstrap.c3 test/src/main.c3
git commit -m "test: stats round-trip + deferred runtime coverage on a 1.1 device (M3)"
```

---

## Done criteria

- `bash scripts/build-vma.sh` prints all six struct sizes and exits 0; the five `$assert`s in `vma_stats.c3i` hold.
- `vma_stats.c3i`/`.c3` (new) and the Task 3 additions to `vma.c3`/`vma_image.*`/`vma_memory.c3` compile against `vk`.
- `cd test && c3c build smoke` links; `./build/smoke` prints `vma smoke OK: map + image + manual alloc/bind2 + manual image + stats` and exits 0 on lavapipe.
- **Zero compile-checked-only gaps remain:** `allocate_memory`, batch flush/invalidate, `bind_buffer_memory2`, `bind_image_memory2`, and `allocate_memory_for_image` are all runtime-exercised, and the M2 buffer paths (`allocate_memory_for_buffer` + v1 `bind_buffer_memory`) keep their coverage. Two paths stay unexercised by design: a non-null `pNext` on `bind_*2` (needs the `khr_bind_memory2` flag), and v1 `bind_image_memory` (the image path uses `bind_image_memory2`); both are noted as out of scope.
- Next milestone (M4 custom pools) can build on this.
```
