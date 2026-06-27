# M2 — Manual Alloc, Images, Mapping, Flush, Bind, Copy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bind VMA's manual allocate/bind path, image creation, and host-memory access (map / flush / invalidate / copy) — raw externs plus idiomatic wrappers — and prove the primaries with a headless three-path round-trip test.

**Architecture:** Extend `module vma;` with M2 functions: memory operations go in `vma_memory.c3i`/`.c3` (alongside M1's buffer path); image operations get new `vma_image.c3i`/`.c3`. M2 introduces no new layout-pinned VMA structs — it reuses M1's `Allocation`/`AllocationCreateInfo`/`AllocationInfo` and vk's `Image`/`ImageCreateInfo`/`MemoryRequirements`; the only new types are engine-side `MemoryAllocation`/`ImageAllocation` result structs. The test extends M0's headless harness.

**Tech Stack:** C3 0.8.0 (`c3c`), VMA static lib from M0, `vk.c3l`, headless Vulkan + lavapipe.

## Global Constraints

- **C3 0.8.0.** Externs use `@cname("vmaXxx")`, NOT `@extern`. Allocator-first functions are methods with receiver `self` **by value** (handle is `inline void*`).
- **All Vulkan types come from `vk`** (`vk::Buffer`, `vk::Image`, `vk::ImageCreateInfo`, `vk::MemoryRequirements`, `vk::DeviceSize`, `vk::Result`). Never redefine them. Functions returning `VkResult` are faithful in the raw layer; `void`-returning ones (`unmap_memory`, `free_memory`, `destroy_image`) get no idiomatic wrapper.
- **No new `$assert`-pinned structs.** M2 adds no VMA structs with C layout; `MemoryAllocation`/`ImageAllocation` are engine-side (never passed to C).
- **`try_map` returns a bounded `char[]` slice** built as `((char*)ptr)[:info.size]`, the size fetched via `get_allocation_info`.
- **Batch + `*2` variants are bound but compile-checked only** — `flush_allocations`/`invalidate_allocations`, `bind_buffer_memory2`/`bind_image_memory2`. Their primaries are runtime-tested. (`allocate_memory` with raw `VkMemoryRequirements` is likewise bound but the test exercises `allocate_memory_for_buffer`.)
- Naming: types PascalCase, functions/fields snake_case, faults one-per-line, named constants (no bare magic numbers), no `@builtin`, no all-uppercase type names. K&R braces. Do not run `c3fmt`.

## File Structure

| File | Responsibility |
|------|----------------|
| `vma_memory.c3i` (modify) | Append M2 memory-op externs (alloc/free, map/unmap, flush/invalidate(+batch), copy, bind-buffer(+2)). |
| `vma_memory.c3` (modify) | Append `MemoryAllocation` + idiomatic memory wrappers. |
| `vma_image.c3i` (create) | Image externs (create/destroy/bind(+2)). |
| `vma_image.c3` (create) | `ImageAllocation` + `try_create_image` / `try_bind_image_memory`. |
| `test/src/main.c3` (modify) | Three round-trip paths (map+flush+copy, image, manual alloc+bind). |

`vma.c3i`/`vma.c3` (M0) and the M1 portions of `vma_memory.*` are unchanged. All `vma*` files are `module vma;`; the hook compiles sibling module files together so cross-file refs resolve.

---

### Task 1: Memory-op raw externs

**Files:**
- Modify: `vma_memory.c3i` (append)

**Interfaces:**
- Consumes: `vma::Allocator`, `vma::Allocation`, `vma::AllocationCreateInfo`, `vma::AllocationInfo` (M1); `vk::Buffer`, `vk::MemoryRequirements`, `vk::DeviceSize`, `vk::Result` (vk).
- Produces: the methods `Allocator.allocate_memory`, `allocate_memory_for_buffer`, `free_memory`, `map_memory`, `unmap_memory`, `flush_allocation`, `invalidate_allocation`, `flush_allocations`, `invalidate_allocations`, `copy_memory_to_allocation`, `copy_allocation_to_memory`, `bind_buffer_memory`, `bind_buffer_memory2`.

- [ ] **Step 1: Append the externs to `vma_memory.c3i`**

Append these lines to the end of `vma_memory.c3i` (after the M1 externs):

```c3

extern fn vk::Result Allocator.allocate_memory(self, vk::MemoryRequirements* reqs, AllocationCreateInfo* ci, Allocation* out_alloc, AllocationInfo* out_info) @cname("vmaAllocateMemory");
extern fn vk::Result Allocator.allocate_memory_for_buffer(self, vk::Buffer buffer, AllocationCreateInfo* ci, Allocation* out_alloc, AllocationInfo* out_info) @cname("vmaAllocateMemoryForBuffer");
extern fn void Allocator.free_memory(self, Allocation allocation) @cname("vmaFreeMemory");
extern fn vk::Result Allocator.map_memory(self, Allocation allocation, void** pp_data) @cname("vmaMapMemory");
extern fn void Allocator.unmap_memory(self, Allocation allocation) @cname("vmaUnmapMemory");
extern fn vk::Result Allocator.flush_allocation(self, Allocation allocation, vk::DeviceSize offset, vk::DeviceSize size) @cname("vmaFlushAllocation");
extern fn vk::Result Allocator.invalidate_allocation(self, Allocation allocation, vk::DeviceSize offset, vk::DeviceSize size) @cname("vmaInvalidateAllocation");
extern fn vk::Result Allocator.flush_allocations(self, uint count, Allocation* allocations, vk::DeviceSize* offsets, vk::DeviceSize* sizes) @cname("vmaFlushAllocations");
extern fn vk::Result Allocator.invalidate_allocations(self, uint count, Allocation* allocations, vk::DeviceSize* offsets, vk::DeviceSize* sizes) @cname("vmaInvalidateAllocations");
extern fn vk::Result Allocator.copy_memory_to_allocation(self, void* src, Allocation allocation, vk::DeviceSize dst_offset, vk::DeviceSize size) @cname("vmaCopyMemoryToAllocation");
extern fn vk::Result Allocator.copy_allocation_to_memory(self, Allocation allocation, vk::DeviceSize src_offset, void* dst, vk::DeviceSize size) @cname("vmaCopyAllocationToMemory");
extern fn vk::Result Allocator.bind_buffer_memory(self, Allocation allocation, vk::Buffer buffer) @cname("vmaBindBufferMemory");
extern fn vk::Result Allocator.bind_buffer_memory2(self, Allocation allocation, vk::DeviceSize offset, vk::Buffer buffer, void* next) @cname("vmaBindBufferMemory2");
```

- [ ] **Step 2: Verify the module still compiles against `vk`**

Run:
```sh
cd test && c3c compile-only --no-obj ../vma.c3i ../vma.c3 ../vma_memory.c3i ../vma_memory.c3 --libdir libs --lib vk ; rm -rf obj ; cd ..
```
Expected: exit 0 (`Object files written…`). A `could not be found` for a `vk::` type is a name typo; a parameter-type error means a signature drifted from the brief.

- [ ] **Step 3: Commit**

```sh
git add vma_memory.c3i
git commit -m "vma: bind raw memory ops (alloc/map/flush/copy/bind) (M2)"
```

---

### Task 2: Memory-op idiomatic wrappers

**Files:**
- Modify: `vma_memory.c3` (append)

**Interfaces:**
- Consumes: Task 1's methods; `vma::Allocation`, `vma::AllocationInfo`, `Allocator.get_allocation_info` (M1); `vma::check` (M0); `vk::Buffer`, `vk::DeviceSize`.
- Produces: `vma::MemoryAllocation { Allocation allocation; AllocationInfo info; }`; methods `Allocator.try_map -> char[]?`, `try_flush`, `try_invalidate`, `try_copy_to_allocation`, `try_copy_from_allocation` (all `void?`), `try_allocate_memory_for_buffer -> MemoryAllocation?`, `try_bind_buffer_memory -> void?`. Task 4 consumes these.

- [ ] **Step 1: Append the wrappers to `vma_memory.c3`**

Append to the end of `vma_memory.c3`:

```c3

struct MemoryAllocation {
    Allocation     allocation;
    AllocationInfo info;
}

<* Map an allocation's memory and return it as a bounded slice. The length is the
   allocation size from `get_allocation_info`. Pair with `unmap_memory`. *>
fn char[]? Allocator.try_map(self, Allocation allocation) {
    void* p;
    check(self.map_memory(allocation, &p))!;
    AllocationInfo info;
    self.get_allocation_info(allocation, &info);
    return ((char*)p)[:info.size];
}

fn void? Allocator.try_flush(self, Allocation allocation, vk::DeviceSize offset, vk::DeviceSize size) {
    check(self.flush_allocation(allocation, offset, size))!;
}

fn void? Allocator.try_invalidate(self, Allocation allocation, vk::DeviceSize offset, vk::DeviceSize size) {
    check(self.invalidate_allocation(allocation, offset, size))!;
}

fn void? Allocator.try_copy_to_allocation(self, void* src, Allocation allocation, vk::DeviceSize dst_offset, vk::DeviceSize size) {
    check(self.copy_memory_to_allocation(src, allocation, dst_offset, size))!;
}

fn void? Allocator.try_copy_from_allocation(self, Allocation allocation, vk::DeviceSize src_offset, void* dst, vk::DeviceSize size) {
    check(self.copy_allocation_to_memory(allocation, src_offset, dst, size))!;
}

<* Allocate memory sized/typed for an existing buffer (does not bind it; call
   `try_bind_buffer_memory` after). Free with `free_memory`. *>
fn MemoryAllocation? Allocator.try_allocate_memory_for_buffer(self, vk::Buffer buffer, AllocationCreateInfo* ci) {
    MemoryAllocation ma;
    check(self.allocate_memory_for_buffer(buffer, ci, &ma.allocation, &ma.info))!;
    return ma;
}

fn void? Allocator.try_bind_buffer_memory(self, Allocation allocation, vk::Buffer buffer) {
    check(self.bind_buffer_memory(allocation, buffer))!;
}
```

- [ ] **Step 2: Verify the module compiles against `vk`**

Run:
```sh
cd test && c3c compile-only --no-obj ../vma.c3i ../vma.c3 ../vma_memory.c3i ../vma_memory.c3 --libdir libs --lib vk ; rm -rf obj ; cd ..
```
Expected: exit 0. A `check could not be found` means M0's `vma.c3` was left out of the command; a `map_memory`/`get_allocation_info` mismatch means a Task-1/M1 signature drifted.

- [ ] **Step 3: Commit**

```sh
git add vma_memory.c3
git commit -m "vma: add idiomatic memory wrappers (try_map slice, flush, copy, bind) (M2)"
```

---

### Task 3: Image binding (raw + idiomatic)

**Files:**
- Create: `vma_image.c3i`
- Create: `vma_image.c3`

**Interfaces:**
- Consumes: `vma::Allocator`, `vma::Allocation`, `vma::AllocationCreateInfo`, `vma::AllocationInfo` (M1); `vma::check` (M0); `vk::Image`, `vk::ImageCreateInfo`, `vk::DeviceSize`, `vk::Result` (vk).
- Produces: image methods `Allocator.create_image`, `destroy_image`, `bind_image_memory`, `bind_image_memory2`; `vma::ImageAllocation { vk::Image image; Allocation allocation; AllocationInfo info; }`; `Allocator.try_create_image -> ImageAllocation?`; `Allocator.try_bind_image_memory -> void?`. Task 4 consumes these.

- [ ] **Step 1: Create `vma_image.c3i`**

```c3
module vma;

import vk;

extern fn vk::Result Allocator.create_image(self, vk::ImageCreateInfo* image_info, AllocationCreateInfo* alloc_info, vk::Image* out_image, Allocation* out_allocation, AllocationInfo* out_info) @cname("vmaCreateImage");
extern fn void Allocator.destroy_image(self, vk::Image image, Allocation allocation) @cname("vmaDestroyImage");
extern fn vk::Result Allocator.bind_image_memory(self, Allocation allocation, vk::Image image) @cname("vmaBindImageMemory");
extern fn vk::Result Allocator.bind_image_memory2(self, Allocation allocation, vk::DeviceSize offset, vk::Image image, void* next) @cname("vmaBindImageMemory2");
```

- [ ] **Step 2: Create `vma_image.c3`**

```c3
module vma;

import vk;

struct ImageAllocation {
    vk::Image      image;
    Allocation     allocation;
    AllocationInfo info;
}

<* Create an image with its backing allocation. Destroy with
   `allocator.destroy_image(ia.image, ia.allocation)`. *>
fn ImageAllocation? Allocator.try_create_image(self, vk::ImageCreateInfo* image_info, AllocationCreateInfo* alloc_info) {
    ImageAllocation ia;
    check(self.create_image(image_info, alloc_info, &ia.image, &ia.allocation, &ia.info))!;
    return ia;
}

fn void? Allocator.try_bind_image_memory(self, Allocation allocation, vk::Image image) {
    check(self.bind_image_memory(allocation, image))!;
}
```

- [ ] **Step 3: Verify the full module compiles against `vk`**

Run:
```sh
cd test && c3c compile-only --no-obj ../vma.c3i ../vma.c3 ../vma_memory.c3i ../vma_memory.c3 ../vma_image.c3i ../vma_image.c3 --libdir libs --lib vk ; rm -rf obj ; cd ..
```
Expected: exit 0.

- [ ] **Step 4: Commit**

```sh
git add vma_image.c3i vma_image.c3
git commit -m "vma: bind image create/destroy/bind + idiomatic try_create_image (M2)"
```

---

### Task 4: Three-path round-trip test

**Files:**
- Modify: `test/src/main.c3` (replace entirely)

**Interfaces:**
- Consumes: M0 bootstrap (`HeadlessVk`/`create_headless_vk`/`destroy_headless_vk`/`VK_API_1_0`); `vma::try_create_allocator`/`Allocator.destroy` (M0); `Allocator.try_create_buffer`/`destroy_buffer`/`AllocationCreateInfo`/`MemoryUsage`/`BufferAllocation` (M1); Tasks 1–3 (`try_map`/`unmap_memory`/`try_flush`/`try_invalidate`/`try_copy_to_allocation`/`try_copy_from_allocation`/`try_allocate_memory_for_buffer`/`free_memory`/`try_bind_buffer_memory`/`MemoryAllocation`/`try_create_image`/`destroy_image`/`ImageAllocation`); `vk::create_buffer`/`destroy_buffer` and the vk image/buffer enums.

- [ ] **Step 1: Replace `test/src/main.c3`**

Replace the entire contents of `test/src/main.c3` with:

```c3
module vma_smoke;

import vma;
import vk;
import std::io;

faultdef
    BUFFER_NULL,
    ALLOCATION_NULL,
    ALLOCATION_TOO_SMALL,
    IMAGE_NULL,
    MAP_MISMATCH;

const ulong BUFFER_SIZE = 65536;

fn int main() {
    if (catch err = run()) {
        io::printfn("vma smoke FAILED: %s", err);
        return 1;
    }
    io::printn("vma smoke OK: buffer + map + image + manual alloc/bind");
    return 0;
}

fn void? run() {
    HeadlessVk h = create_headless_vk()!;
    defer destroy_headless_vk(&h);

    vma::AllocatorCreateInfo info = {
        .physical_device    = h.physical_device,
        .device             = h.device,
        .instance           = h.instance,
        .vulkan_api_version = VK_API_1_0,
    };
    vma::Allocator alloc = vma::try_create_allocator(&info)!;
    defer alloc.destroy();

    map_round_trip(alloc)!;
    image_round_trip(alloc)!;
    manual_alloc_bind(alloc, h.device)!;
}

<* Map a host-visible buffer, write+flush+invalidate+read through the mapped
   slice, then exercise copy-to/from-allocation; assert the bytes survive. *>
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

    char[] mapped = alloc.try_map(ba.allocation)!;
    for (uint i = 0; i < 4; i++) mapped[i] = (char)(0x10 + i);
    alloc.try_flush(ba.allocation, 0, 4)!;
    alloc.unmap_memory(ba.allocation);

    alloc.try_invalidate(ba.allocation, 0, 4)!;
    char[] rb = alloc.try_map(ba.allocation)!;
    bool map_ok = true;
    for (uint i = 0; i < 4; i++) {
        if (rb[i] != (char)(0x10 + i)) map_ok = false;
    }
    alloc.unmap_memory(ba.allocation);
    if (!map_ok) return MAP_MISMATCH~;

    char[4] src = { 0xDE, 0xAD, 0xBE, 0xEF };
    char[4] dst;
    alloc.try_copy_to_allocation((void*)&src, ba.allocation, 0, 4)!;
    alloc.try_copy_from_allocation(ba.allocation, 0, (void*)&dst, 4)!;
    for (uint i = 0; i < 4; i++) {
        if (dst[i] != src[i]) return MAP_MISMATCH~;
    }
}

<* Allocate a small 2D image with its backing memory, assert the handles, free. *>
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
    if (ia.image == null) return IMAGE_NULL~;
    if (ia.allocation == null) return ALLOCATION_NULL~;
}

<* Manual path: create a raw VkBuffer, allocate memory for it, bind, free. *>
fn void? manual_alloc_bind(vma::Allocator alloc, vk::Device device) {
    vk::BufferCreateInfo bi = {
        .s_type       = vk::StructureType.BUFFER_CREATE_INFO,
        .size         = BUFFER_SIZE,
        .usage        = vk::BufferUsageFlagBits.TRANSFER_SRC_BIT,
        .sharing_mode = vk::SharingMode.EXCLUSIVE,
    };
    vk::Buffer buffer;
    if (vk::create_buffer(device, &bi, null, &buffer) != vk::Result.SUCCESS) return BUFFER_NULL~;
    defer vk::destroy_buffer(device, buffer, null);

    vma::AllocationCreateInfo ai = { .usage = vma::MemoryUsage.AUTO };
    vma::MemoryAllocation ma = alloc.try_allocate_memory_for_buffer(buffer, &ai)!;
    defer alloc.free_memory(ma.allocation);

    alloc.try_bind_buffer_memory(ma.allocation, buffer)!;
}
```

- [ ] **Step 2: Build the smoke executable**

Run:
```sh
cd test && c3c build smoke 2>&1 | tail -8 ; cd ..
```
Expected: `Program linked to executable 'build/smoke'.`, exit 0. Undefined `vma*`/`vk*` symbols point at a `@cname` typo in Tasks 1–3; a C3 type/cast error in the test is a transcription issue in this file — fix it here.

- [ ] **Step 3: Run the three-path round-trip on lavapipe**

Run:
```sh
cd test && VK_LOADER_DRIVERS_SELECT='*lvp*' ./build/smoke ; echo "exit=$?" ; cd ..
```
Expected: prints `vma smoke OK: buffer + map + image + manual alloc/bind` and `exit=0`.
- `vma smoke FAILED: MAP_MISMATCH` → mapped/copied bytes didn't survive — investigate the map/flush/invalidate/copy path, not the harness.
- `vma smoke FAILED: IMAGE_NULL`/`ALLOCATION_NULL`/`BUFFER_NULL` → the named creation step failed; run under `VK_LOADER_DEBUG=error`.
- A vk-layer fault → retry without the loader env var (M0's device loop skips non-working ICDs).
If it still won't link or run after these checks, STOP and report BLOCKED with the exact output — do not weaken the assertions.

- [ ] **Step 4: Clean artifacts and commit**

```sh
rm -rf test/build test/obj
git add test/src/main.c3
git commit -m "test: map/flush/copy + image + manual alloc/bind round-trips (M2)"
```

---

## Done criteria

- `vma_memory.c3i`/`.c3` (extended) + `vma_image.c3i`/`.c3` (new) compile against `vk`.
- `cd test && c3c build smoke` links; `./build/smoke` prints `vma smoke OK: buffer + map + image + manual alloc/bind` and exits 0 on lavapipe.
- Batch (`flush_allocations`/`invalidate_allocations`), `*2` bind variants, and `allocate_memory` are bound and compile-clean (not runtime-exercised, per the spec).
- Next milestone (statistics & budget) can build on this.
