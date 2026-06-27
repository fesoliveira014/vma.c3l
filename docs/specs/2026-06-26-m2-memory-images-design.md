# M2 — Manual Allocation, Images, Mapping, Flush, Bind, Copy (design)

Date: 2026-06-26
Status: approved (brainstorming)
Predecessor: [M1 design](2026-06-26-m1-memory-buffer-design.md) · [roadmap](2026-06-26-vma-binding-roadmap-design.md)

Bind the rest of VMA's core resource path on top of M1's buffer round-trip: the
manual allocate/bind path, image creation, host-memory access (map / flush /
invalidate / copy). After M2 a caller can put data into an allocation and back
out of it, and allocate images as well as buffers.

## Context

M0 shipped the `Allocator` lifecycle; M1 shipped the `Allocation` handle,
`AllocationCreateInfo`/`AllocationInfo` structs, `MemoryUsage`/`AllocationCreateFlags`,
the `BufferAllocation` result struct, `try_create_buffer`, and `check()`. M2 reuses
all of those — **it introduces no new layout-pinned VMA structs.** Every M2 function
either takes M1's `Allocation`/`AllocationCreateInfo`/`AllocationInfo`, or a Vulkan
type already provided by `vk` (`vk::Image`, `vk::ImageCreateInfo`, `vk::Buffer`,
`vk::MemoryRequirements`, `vk::DeviceSize`, `vk::Result`). The only new structs are
two engine-side result types (`MemoryAllocation`, `ImageAllocation`) that never
cross the C ABI. M2's risk is therefore **signature fidelity**, not struct layout —
no `$assert` size pins are needed.

## Settled decisions

1. **Full M2: all three themes in one milestone** — manual alloc + bind, images,
   and host-memory access (map / flush / invalidate / copy).
2. **`try_map` returns a bounded slice `char[]`.** The idiomatic map fetches the
   allocation length via `get_allocation_info` and returns `((char*)ptr)[:size]`,
   per `docs/style.md` §5 (prefer slices over raw pointers). `unmap`/`free_memory`
   stay raw (they return `void`).
3. **Batch and `*2` variants are bound but compile-checked only.**
   `flush_allocations`/`invalidate_allocations` (batch) and `bind_buffer_memory2`/
   `bind_image_memory2` (with `allocationLocalOffset` + `pNext`) are faithful raw
   bindings with no runtime test path. This is a deliberate, recorded exception to
   the "bind only what you exercise" rule, taken because the roadmap M2 surface is
   completed in one pass; their primaries (`flush_allocation`, `bind_buffer_memory`,
   `bind_image_memory`) are runtime-tested.
4. **File split by theme.** Memory operations extend `vma_memory.c3i`/`.c3`; image
   operations get new `vma_image.c3i`/`.c3`. Both `module vma;`.

## Binding surface

All functions take the allocator first → **methods** with receiver `self` by value
(handle is `inline void*`), `@cname` holding the real C symbol. Functions returning
`VkResult` are faithful in the raw layer; `void`-returning ones (`unmap_memory`,
`free_memory`) need no idiomatic wrapper.

### Raw — memory ops (`vma_memory.c3i`)

```
fn vk::Result Allocator.allocate_memory(self, vk::MemoryRequirements*, AllocationCreateInfo*, Allocation*, AllocationInfo*) @cname("vmaAllocateMemory");
fn vk::Result Allocator.allocate_memory_for_buffer(self, vk::Buffer, AllocationCreateInfo*, Allocation*, AllocationInfo*) @cname("vmaAllocateMemoryForBuffer");
fn void       Allocator.free_memory(self, Allocation) @cname("vmaFreeMemory");
fn vk::Result Allocator.map_memory(self, Allocation, void** pp_data) @cname("vmaMapMemory");
fn void       Allocator.unmap_memory(self, Allocation) @cname("vmaUnmapMemory");
fn vk::Result Allocator.flush_allocation(self, Allocation, vk::DeviceSize offset, vk::DeviceSize size) @cname("vmaFlushAllocation");
fn vk::Result Allocator.invalidate_allocation(self, Allocation, vk::DeviceSize offset, vk::DeviceSize size) @cname("vmaInvalidateAllocation");
fn vk::Result Allocator.flush_allocations(self, uint count, Allocation* allocations, vk::DeviceSize* offsets, vk::DeviceSize* sizes) @cname("vmaFlushAllocations");
fn vk::Result Allocator.invalidate_allocations(self, uint count, Allocation* allocations, vk::DeviceSize* offsets, vk::DeviceSize* sizes) @cname("vmaInvalidateAllocations");
fn vk::Result Allocator.copy_memory_to_allocation(self, void* src, Allocation, vk::DeviceSize dst_offset, vk::DeviceSize size) @cname("vmaCopyMemoryToAllocation");
fn vk::Result Allocator.copy_allocation_to_memory(self, Allocation, vk::DeviceSize src_offset, void* dst, vk::DeviceSize size) @cname("vmaCopyAllocationToMemory");
fn vk::Result Allocator.bind_buffer_memory(self, Allocation, vk::Buffer) @cname("vmaBindBufferMemory");
fn vk::Result Allocator.bind_buffer_memory2(self, Allocation, vk::DeviceSize offset, vk::Buffer, void* next) @cname("vmaBindBufferMemory2");
```

### Raw — image ops (`vma_image.c3i`)

```
fn vk::Result Allocator.create_image(self, vk::ImageCreateInfo*, AllocationCreateInfo*, vk::Image*, Allocation*, AllocationInfo*) @cname("vmaCreateImage");
fn void       Allocator.destroy_image(self, vk::Image, Allocation) @cname("vmaDestroyImage");
fn vk::Result Allocator.bind_image_memory(self, Allocation, vk::Image) @cname("vmaBindImageMemory");
fn vk::Result Allocator.bind_image_memory2(self, Allocation, vk::DeviceSize offset, vk::Image, void* next) @cname("vmaBindImageMemory2");
```

### Idiomatic — memory (`vma_memory.c3`)

```
struct MemoryAllocation { Allocation allocation; AllocationInfo info; }

fn char[]?           Allocator.try_map(self, Allocation);                          // map + get_allocation_info -> bounded slice
fn void?             Allocator.try_flush(self, Allocation, vk::DeviceSize offset, vk::DeviceSize size);
fn void?             Allocator.try_invalidate(self, Allocation, vk::DeviceSize offset, vk::DeviceSize size);
fn void?             Allocator.try_copy_to_allocation(self, void* src, Allocation, vk::DeviceSize dst_offset, vk::DeviceSize size);
fn void?             Allocator.try_copy_from_allocation(self, Allocation, vk::DeviceSize src_offset, void* dst, vk::DeviceSize size);
fn MemoryAllocation? Allocator.try_allocate_memory_for_buffer(self, vk::Buffer, AllocationCreateInfo*);
fn void?             Allocator.try_bind_buffer_memory(self, Allocation, vk::Buffer);
```

`unmap_memory` and `free_memory` are used raw (no fault). All wrappers route their
`vk::Result` through M0's `check()`.

### Idiomatic — image (`vma_image.c3`)

```
struct ImageAllocation { vk::Image image; Allocation allocation; AllocationInfo info; }

fn ImageAllocation? Allocator.try_create_image(self, vk::ImageCreateInfo*, AllocationCreateInfo*);
fn void?            Allocator.try_bind_image_memory(self, Allocation, vk::Image);
```

## Testing

Extend the headless smoke (M0 device, M1 allocator) with three paths:

1. **Map round-trip.** Create a host-visible buffer (`MemoryUsage.AUTO` +
   `host_access_sequential_write`), `try_map` → write a known byte pattern → `try_flush`
   → `unmap`. Then `try_invalidate` and re-`try_map` (or `try_copy_from_allocation`)
   → assert the bytes read back match the pattern. Destroy the buffer.
2. **Image.** `try_create_image` for a small 2D image (e.g. 64×64 `R8G8B8A8_UNORM`,
   `OPTIMAL` tiling, `SAMPLED | TRANSFER_DST` usage, `usage = AUTO`) → assert image +
   allocation non-null → `destroy_image`.
3. **Manual alloc + bind.** Create a raw `VkBuffer` via `vk::create_buffer` →
   `try_allocate_memory_for_buffer` → `try_bind_buffer_memory` → `free_memory` +
   `vk::destroy_buffer`.

All headless on lavapipe, exit 0 on success, same gate shape as M0/M1. The batch
and `*2` variants are not exercised at runtime (decision 3) — their compile against
`vk` is their gate.

## File layout

```
vma_memory.c3i   (M1 + M2) allocation/buffer + alloc/map/flush/copy/bind-buffer externs
vma_memory.c3    (M1 + M2) BufferAllocation, try_create_buffer + MemoryAllocation, map/flush/copy/bind wrappers
vma_image.c3i    (M2 new)  create/destroy/bind image externs
vma_image.c3     (M2 new)  ImageAllocation + try_create_image / try_bind_image_memory
test/src/main.c3 (M2)      extended with the three round-trip paths
```

## Out of scope (later milestones)

- Statistics & budget (`vmaCalculateStatistics`, `Budget`, stats string) — next.
- Custom pools (the `pool` field stays `void*`/null), defragmentation, virtual allocator.
- Sparse-binding page functions (`vmaAllocateMemoryPages`/`vmaFreeMemoryPages`).
- Aliasing buffers/images, `vmaCreateBufferWithAlignment`.
