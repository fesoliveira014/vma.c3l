# M1 — Memory Allocation + Buffer Round-Trip (design)

Date: 2026-06-26
Status: approved (brainstorming)
Predecessor: [M0 plan](../plans/2026-06-26-m0-foundation-allocator.md) · [roadmap](2026-06-26-vma-binding-roadmap-design.md)

Bind VMA's buffer allocation path so a caller can allocate a `VkBuffer` (memory +
buffer + bind, in one call), inspect the allocation, and free it. Builds directly
on M0's `Allocator` lifecycle and headless-Vulkan test harness.

## Context

M0 shipped the `Allocator` handle, `create_allocator`/`try_create_allocator`,
`Allocator.destroy`, the `check()` VkResult→fault helper, the VMA static lib, and
a headless-Vulkan smoke test (instance + device, no surface) that runs on the
lavapipe software ICD. M1 adds the first thing you actually *allocate*.

The `vk` dependency already provides every Vulkan type M1 needs: `vk::Buffer`
(`inline void*`), `vk::BufferCreateInfo`, `vk::DeviceMemory`, `vk::DeviceSize`,
`vk::MemoryPropertyFlags`, `vk::SharingMode`, `vk::BufferUsageFlags`, `vk::Result`.

## Settled decisions

1. **Scope: the buffer path only.** Bind `vmaCreateBuffer`, `vmaDestroyBuffer`,
   `vmaGetAllocationInfo` plus the types they require. The lower-level
   `vmaAllocateMemory` / `vmaAllocateMemoryForBuffer` / `vmaFreeMemory` are
   **deferred to M2**, because they cannot be exercised without `vmaBindBufferMemory`
   (an M2 binding); binding them now would ship untested surface. The roadmap's M1
   and M2 sections are updated to reflect this move.
2. **Idiomatic result struct.** `vmaCreateBuffer` has three out-parameters
   (buffer, allocation, allocation-info). The idiomatic layer returns a single
   engine-side `BufferAllocation { buffer, allocation, info }` value, so call sites
   read `BufferAllocation ba = allocator.try_create_buffer(&bi, &ai)!;`.
3. **`MemoryUsage` as a C3 `enum : int`.** The C `VmaMemoryUsage` set is closed
   and contiguous (0–9), so a C3 enum with `: int` backing is the idiomatic form
   (per `docs/bindings_guidelines.md`); its ordinals match the C values. The
   int-ordinal ABI marshaling is verified at plan time.

## Binding surface

### Raw layer — `vma_memory.c3i` (`module vma;`)

All three functions take the allocator handle first, so they bind as **methods**
with the receiver `self` by value (the handle is an `inline void*` typedef, as in
M0's `Allocator.destroy`):

```c3
fn vk::Result Allocator.create_buffer(self,
    vk::BufferCreateInfo* buffer_info,
    AllocationCreateInfo* alloc_info,
    vk::Buffer* out_buffer,
    Allocation* out_allocation,
    AllocationInfo* out_info) @cname("vmaCreateBuffer");

fn void Allocator.destroy_buffer(self, vk::Buffer buffer, Allocation allocation) @cname("vmaDestroyBuffer");

fn void Allocator.get_allocation_info(self, Allocation allocation, AllocationInfo* out_info) @cname("vmaGetAllocationInfo");
```

Types (all `Vma`-prefix stripped, sizes measured against the header with
`VMA_EXTERNAL_MEMORY=0`, the same define the lib is built with):

- `typedef Allocation = inline void*;` — the `VK_DEFINE_HANDLE(VmaAllocation)` handle.
- `enum MemoryUsage : int { UNKNOWN, GPU_ONLY, CPU_ONLY, CPU_TO_GPU, GPU_TO_CPU, CPU_COPY, GPU_LAZILY_ALLOCATED, AUTO, AUTO_PREFER_DEVICE, AUTO_PREFER_HOST }` — ordinals 0–9 match the C values.
- `bitstruct AllocationCreateFlags : uint { … }` — bits **0, 1, 2, 5, 6, 7, 8, 9, 10, 11, 12, 16, 17** (the C `Vma*FlagBits` set has gaps: bits 3–4, 13–15 are unused). The plan verifies C3 accepts non-contiguous bitstruct positions; if it does not, fall back to a set of `const uint` flag values.
- `struct AllocationCreateInfo` — **48 bytes** (`$assert(AllocationCreateInfo::size == 48)`):
  `AllocationCreateFlags flags`, `MemoryUsage usage`, `vk::MemoryPropertyFlags required_flags`, `vk::MemoryPropertyFlags preferred_flags`, `uint memory_type_bits`, `void* pool` (the `VmaPool` handle is opaque until M4; passing null = default pool), `void* user_data`, `float priority`.
- `struct AllocationInfo` — **56 bytes** (`$assert(AllocationInfo::size == 56)`):
  `uint memory_type`, `vk::DeviceMemory device_memory`, `vk::DeviceSize offset`, `vk::DeviceSize size`, `void* mapped_data`, `void* user_data`, `char* name` (the `const char* pName` field).

### Idiomatic layer — `vma_memory.c3` (`module vma;`)

```c3
struct BufferAllocation {
    vk::Buffer     buffer;
    Allocation     allocation;
    AllocationInfo info;
}

fn BufferAllocation? Allocator.try_create_buffer(self,
    vk::BufferCreateInfo* buffer_info,
    AllocationCreateInfo* alloc_info);
```

`try_create_buffer` calls the raw `create_buffer`, routes its `vk::Result` through
M0's `check()!`, and returns a populated `BufferAllocation`. `BufferAllocation` is
an engine-side convenience type, **not** an ABI struct — it is never passed to C.

Teardown stays the raw method: `allocator.destroy_buffer(ba.buffer, ba.allocation)`.
`vmaDestroyBuffer` returns `void`, so no fault wrapper is warranted.

## Testing

Extend the M0 headless smoke (reusing `create_headless_vk` / `destroy_headless_vk`):

1. Create the allocator (M0 path).
2. Build a `vk::BufferCreateInfo`: `size = 65536`, `usage = TRANSFER_SRC | TRANSFER_DST`
   (always supported, needs no device feature), `sharing_mode = EXCLUSIVE`.
3. `AllocationCreateInfo { usage = MemoryUsage.AUTO }`.
4. `BufferAllocation ba = allocator.try_create_buffer(&bi, &ai)!;`
5. Assert `ba.info.size >= 65536`, `ba.buffer != null`, `ba.allocation != null`.
6. `allocator.destroy_buffer(ba.buffer, ba.allocation);` then destroy the allocator.

Runs headless on lavapipe (`VK_LOADER_DRIVERS_SELECT='*lvp*'`), exit 0 on success —
same gate shape as M0. Pure create/destroy needs no memory mapping (that is M2).

## File layout

```
vma.c3i          (M0) allocator core — unchanged
vma.c3           (M0) faultdef + check + try_create_allocator — unchanged
vma_memory.c3i   (M1) Allocation, MemoryUsage, AllocationCreateFlags, AllocationCreateInfo, AllocationInfo, buffer externs
vma_memory.c3    (M1) BufferAllocation + try_create_buffer
test/src/main.c3 (M1) extended with the buffer round-trip
```

All four `vma*.c3i`/`.c3` files are `module vma;`; the syntax-check hook already
compiles sibling module files together, so cross-file references resolve.

## Out of scope (later milestones)

- `vmaAllocateMemory` / `vmaAllocateMemoryForBuffer` / `vmaFreeMemory`, and
  `vmaBindBufferMemory` — **M2**.
- Memory mapping / flush / images — M2.
- Custom pools (the `pool` field stays `void*`/null) — M4.
- `pName` / user-data setters and `pUserData` semantics beyond carrying the field — later.
