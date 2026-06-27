# M1 — Memory Allocation + Buffer Round-Trip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bind VMA's buffer allocation path (`vmaCreateBuffer`/`vmaDestroyBuffer`/`vmaGetAllocationInfo`) — raw externs plus an idiomatic `try_create_buffer` returning a `BufferAllocation` — and prove it with a headless buffer round-trip test.

**Architecture:** Two new `module vma;` files alongside M0's: `vma_memory.c3i` (raw handle/structs/enum/bitstruct/externs) and `vma_memory.c3` (idiomatic result struct + wrapper). All Vulkan types come from the `vk` dependency. The test extends M0's headless-Vulkan harness with a create-buffer → inspect → destroy cycle on the lavapipe ICD.

**Tech Stack:** C3 0.8.0 (`c3c`), VMA static lib from M0, `vk.c3l`, headless Vulkan + lavapipe.

## Global Constraints

- **C3 0.8.0.** Externs use `@cname("vmaXxx")`, NOT `@extern(...)` (removed in 0.8.0). A method's first parameter must be the receiver type; the `Allocator` handle is an `inline void*` typedef, so handle-first functions are methods with receiver `self` **by value**.
- **All Vulkan types come from `vk`** (`vk::Buffer`, `vk::BufferCreateInfo`, `vk::DeviceMemory`, `vk::DeviceSize`, `vk::MemoryPropertyFlags`, `vk::Result`, `vk::SharingMode`, `vk::BufferUsageFlagBits`). Never redefine them.
- **Layout pinning (measured against the header with `VMA_EXTERNAL_MEMORY=0`):** `$assert(AllocationCreateInfo::size == 48)`, `$assert(AllocationInfo::size == 56)`. Both numbers are confirmed by a C++ probe; do not change them to silence a failure — a failure means the struct is wrong.
- **Scope: buffer path only.** Bind `vmaCreateBuffer`, `vmaDestroyBuffer`, `vmaGetAllocationInfo`. Do NOT bind `vmaAllocateMemory*` (deferred to M2). The `VmaPool` field of `AllocationCreateInfo` is typed `void*` (opaque until M4; pass null).
- **Idiomatic layer** returns `BufferAllocation { vk::Buffer buffer; Allocation allocation; AllocationInfo info; }` — an engine-side type, never passed to C — and routes the `vk::Result` through M0's existing `vma::check()`.
- Naming: types PascalCase (strip `Vma`), functions/fields snake_case, no all-uppercase struct/enum/bitstruct names. Faults one-per-line. No `@builtin`. K&R braces. Do not run `c3fmt`.

## File Structure

| File | Responsibility |
|------|----------------|
| `vma_memory.c3i` (create) | Raw layer: `Allocation` handle, `MemoryUsage` enum, `AllocationCreateFlags` bitstruct, `AllocationCreateInfo`+`AllocationInfo` structs (both `$assert`-pinned), buffer externs. |
| `vma_memory.c3` (create) | Idiomatic layer: `BufferAllocation` struct + `Allocator.try_create_buffer`. |
| `test/src/main.c3` (modify) | Extend the headless `run()` with the buffer round-trip. |

`vma.c3i` / `vma.c3` (M0) are unchanged. All four `vma*` files are `module vma;`; the syntax-check hook compiles sibling module files together so cross-file references resolve.

---

### Task 1: Raw buffer-binding layer

**Files:**
- Create: `vma_memory.c3i`
- Verify against: `test/libs/vk.c3l`

**Interfaces:**
- Consumes (from M0 `vma.c3i`): `vma::Allocator` (the `inline void*` handle methods attach to).
- Consumes (from `vk`): `vk::Buffer`, `vk::BufferCreateInfo`, `vk::DeviceMemory`, `vk::DeviceSize`, `vk::MemoryPropertyFlags`, `vk::Result`.
- Produces: `vma::Allocation`, `vma::MemoryUsage` (enum), `vma::AllocationCreateFlags` (bitstruct), `vma::AllocationCreateInfo` (48 B), `vma::AllocationInfo` (56 B), and methods `Allocator.create_buffer(self, vk::BufferCreateInfo*, AllocationCreateInfo*, vk::Buffer*, Allocation*, AllocationInfo*) -> vk::Result`, `Allocator.destroy_buffer(self, vk::Buffer, Allocation)`, `Allocator.get_allocation_info(self, Allocation, AllocationInfo*)`. Tasks 2–3 consume these.

- [ ] **Step 1: Write the raw binding file**

Create `vma_memory.c3i` with exactly:

```c3
module vma;

import vk;

typedef Allocation = inline void*;

enum MemoryUsage : int {
    UNKNOWN,
    GPU_ONLY,
    CPU_ONLY,
    CPU_TO_GPU,
    GPU_TO_CPU,
    CPU_COPY,
    GPU_LAZILY_ALLOCATED,
    AUTO,
    AUTO_PREFER_DEVICE,
    AUTO_PREFER_HOST,
}

bitstruct AllocationCreateFlags : uint {
    bool dedicated_memory                   : 0;
    bool never_allocate                     : 1;
    bool mapped                             : 2;
    bool user_data_copy_string              : 5;
    bool upper_address                      : 6;
    bool dont_bind                          : 7;
    bool within_budget                      : 8;
    bool can_alias                          : 9;
    bool host_access_sequential_write       : 10;
    bool host_access_random                 : 11;
    bool host_access_allow_transfer_instead : 12;
    bool strategy_min_memory                : 16;
    bool strategy_min_time                  : 17;
}

struct AllocationCreateInfo {
    AllocationCreateFlags   flags;
    MemoryUsage             usage;
    vk::MemoryPropertyFlags required_flags;
    vk::MemoryPropertyFlags preferred_flags;
    uint                    memory_type_bits;
    void*                   pool;
    void*                   user_data;
    float                   priority;
}
// 48 assumes the lib was built with VMA_EXTERNAL_MEMORY=0 (scripts/build-vma.sh).
$assert(AllocationCreateInfo::size == 48);

struct AllocationInfo {
    uint             memory_type;
    vk::DeviceMemory device_memory;
    vk::DeviceSize   offset;
    vk::DeviceSize   size;
    void*            mapped_data;
    void*            user_data;
    char*            name;
}
$assert(AllocationInfo::size == 56);

extern fn vk::Result Allocator.create_buffer(self, vk::BufferCreateInfo* buffer_info, AllocationCreateInfo* alloc_info, vk::Buffer* out_buffer, Allocation* out_allocation, AllocationInfo* out_info) @cname("vmaCreateBuffer");
extern fn void Allocator.destroy_buffer(self, vk::Buffer buffer, Allocation allocation) @cname("vmaDestroyBuffer");
extern fn void Allocator.get_allocation_info(self, Allocation allocation, AllocationInfo* out_info) @cname("vmaGetAllocationInfo");
```

- [ ] **Step 2: Verify it compiles against `vk` with both size asserts holding**

Run (from the repo root):
```sh
cd test && c3c compile-only --no-obj ../vma.c3i ../vma_memory.c3i --libdir libs --lib vk ; rm -rf obj ; cd ..
```
Expected: exit 0 (`Object files written…` is success). A `Compile time assert failed` means a struct field type/order is wrong — re-check against the spec, do not edit the asserted number. A `could not be found` for a `vk::` type means a name typo.

- [ ] **Step 3: Commit**

```sh
git add vma_memory.c3i
git commit -m "vma: bind raw buffer allocation layer (create/destroy/get-info) (M1)"
```

---

### Task 2: Idiomatic buffer layer

**Files:**
- Create: `vma_memory.c3`

**Interfaces:**
- Consumes: `vma::Allocator`, `vma::Allocation`, `vma::AllocationCreateInfo`, `vma::AllocationInfo`, `Allocator.create_buffer` (Task 1); `vma::check` (M0 `vma.c3`); `vk::Buffer`, `vk::BufferCreateInfo`.
- Produces: `vma::BufferAllocation { vk::Buffer buffer; Allocation allocation; AllocationInfo info; }` and `Allocator.try_create_buffer(self, vk::BufferCreateInfo*, AllocationCreateInfo*) -> BufferAllocation?`. Task 3 consumes `try_create_buffer`.

- [ ] **Step 1: Write the idiomatic file**

Create `vma_memory.c3` with exactly:

```c3
module vma;

import vk;

struct BufferAllocation {
    vk::Buffer     buffer;
    Allocation     allocation;
    AllocationInfo info;
}

<* Create a buffer with its backing allocation, returning a vma fault instead of
   a raw VkResult. The returned handles are destroyed with
   `allocator.destroy_buffer(ba.buffer, ba.allocation)`. *>
fn BufferAllocation? Allocator.try_create_buffer(self, vk::BufferCreateInfo* buffer_info, AllocationCreateInfo* alloc_info) {
    BufferAllocation ba;
    check(self.create_buffer(buffer_info, alloc_info, &ba.buffer, &ba.allocation, &ba.info))!;
    return ba;
}
```

- [ ] **Step 2: Verify the full module compiles against `vk`**

Run:
```sh
cd test && c3c compile-only --no-obj ../vma.c3i ../vma.c3 ../vma_memory.c3i ../vma_memory.c3 --libdir libs --lib vk ; rm -rf obj ; cd ..
```
Expected: exit 0. A `check could not be found` means M0's `vma.c3` wasn't included in the command; a `create_buffer` mismatch means Task 1's signature drifted.

- [ ] **Step 3: Commit**

```sh
git add vma_memory.c3
git commit -m "vma: add idiomatic try_create_buffer returning BufferAllocation (M1)"
```

---

### Task 3: Headless buffer round-trip test

**Files:**
- Modify: `test/src/main.c3`

**Interfaces:**
- Consumes: `vma_smoke::create_headless_vk` / `destroy_headless_vk` / `HeadlessVk` / `VK_API_1_0` (M0 `vk_bootstrap.c3`); `vma::try_create_allocator`, `Allocator.destroy` (M0); `vma::AllocationCreateInfo`, `vma::MemoryUsage`, `vma::BufferAllocation`, `Allocator.try_create_buffer`, `Allocator.destroy_buffer` (Tasks 1–2); `vk::BufferCreateInfo`, `vk::BufferUsageFlagBits`, `vk::SharingMode`, `vk::StructureType`.

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
    ALLOCATION_TOO_SMALL;

const ulong BUFFER_SIZE = 65536;

fn int main() {
    if (catch err = run()) {
        io::printfn("vma smoke FAILED: %s", err);
        return 1;
    }
    io::printn("vma smoke OK: allocator + buffer round-trip");
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

    vk::BufferCreateInfo buffer_info = {
        .s_type       = vk::StructureType.BUFFER_CREATE_INFO,
        .size         = BUFFER_SIZE,
        .usage        = vk::BufferUsageFlagBits.TRANSFER_SRC_BIT | vk::BufferUsageFlagBits.TRANSFER_DST_BIT,
        .sharing_mode = vk::SharingMode.EXCLUSIVE,
    };
    vma::AllocationCreateInfo alloc_info = { .usage = vma::MemoryUsage.AUTO };

    vma::BufferAllocation ba = alloc.try_create_buffer(&buffer_info, &alloc_info)!;
    defer alloc.destroy_buffer(ba.buffer, ba.allocation);

    if (ba.buffer == null) return BUFFER_NULL~;
    if (ba.allocation == null) return ALLOCATION_NULL~;
    if (ba.info.size < BUFFER_SIZE) return ALLOCATION_TOO_SMALL~;
}
```

(The `defer`s tear down in LIFO order — buffer, then allocator, then device/instance — on every exit path, so even a failed assertion leaks nothing. M0's `vk_bootstrap.c3` is unchanged and still supplies `HeadlessVk`, `VK_API_1_0`, and the create/destroy helpers.)

- [ ] **Step 2: Build the smoke executable**

Run:
```sh
cd test && c3c build smoke 2>&1 | tail -5 ; cd ..
```
Expected: `Program linked to executable 'build/smoke'.`, exit 0. An undefined reference to `vmaCreateBuffer` means the M0 VMA `.a` predates this binding — it does not; the same archive exports all VMA symbols, so a link error here points at a `@cname` typo in Task 1.

- [ ] **Step 3: Run the round-trip on lavapipe**

Run:
```sh
cd test && VK_LOADER_DRIVERS_SELECT='*lvp*' ./build/smoke ; echo "exit=$?" ; cd ..
```
Expected: prints `vma smoke OK: allocator + buffer round-trip` and `exit=0`.
- `vma smoke FAILED: BUFFER_NULL` / `ALLOCATION_NULL` / `ALLOCATION_TOO_SMALL` → the allocation assertions caught a real problem; investigate before proceeding.
- A `vk`-layer fault (e.g. `OUT_OF_DEVICE_MEMORY`) → run under `VK_LOADER_DEBUG=error` to see the ICD/stage; retry without the loader env var as a fallback (M0's device-selection loop already skips non-working ICDs).

- [ ] **Step 4: Clean artifacts and commit**

```sh
rm -rf test/build test/obj
git add test/src/main.c3
git commit -m "test: headless buffer round-trip (create_buffer -> inspect -> destroy) (M1)"
```

---

## Done criteria

- `vma_memory.c3i` + `vma_memory.c3` compile against `vk`; both `$assert`s hold.
- `cd test && c3c build smoke` links; `./build/smoke` prints `vma smoke OK: allocator + buffer round-trip` and exits 0 on lavapipe.
- M2 can build on this: `vmaAllocateMemory*`, `vmaBindBufferMemory`, images, and memory mapping.
