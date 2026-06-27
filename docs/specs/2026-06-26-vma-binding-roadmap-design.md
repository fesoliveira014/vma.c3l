# VMA C3 Binding — Implementation Roadmap (design)

Date: 2026-06-26
Status: approved (brainstorming)
Predecessor: none (first spec for this package)

C3 bindings for the Vulkan Memory Allocator (VMA) C API, packaged as the `vma`
C3 library (`.c3l`). This document is the milestone roadmap for the whole
binding effort. Each milestone gets its own plan and is executed independently;
the binding surface grows incrementally per `add-binding`.

## Context

- VMA is a **header-only C++ library** (`vk_mem_alloc.h`, ~19k lines) exposing a
  flat `extern "C"` API. There is no prebuilt VMA library on the system; a
  linkable artifact must be produced by compiling one translation unit with
  `#define VMA_IMPLEMENTATION`.
- The `vk` C3 library (test dependency, module `vk`) already provides every
  Vulkan type VMA's signatures need: handles as `inline void*` typedefs
  (`vk::Instance`, `vk::PhysicalDevice`, `vk::Device`, `vk::Buffer`, `vk::Image`,
  `vk::DeviceMemory`), `vk::Result`, `vk::DeviceSize`, `vk::AllocationCallbacks`,
  `vk::MemoryRequirements`, `vk::BufferCreateInfo`, etc. The `vma` binding
  **depends on `vk` for these types and never redefines them**.
- The `vma` module is currently a stub; `linked-libs/<target>/` is empty.

## Settled decisions

1. **Vulkan function resolution: static.** Build the VMA implementation TU with
   `VMA_STATIC_VULKAN_FUNCTIONS=1`. VMA calls `vkAllocateMemory` etc. directly
   against linked `libvulkan` (which `vk` already links). `VmaVulkanFunctions`
   stays null in `AllocatorCreateInfo`; the ~30 `PFN_vk*` pointer types are
   **not** bound. (Revisit only if a consumer needs a dynamic loader such as
   volk — that would switch to `VMA_DYNAMIC_VULKAN_FUNCTIONS` and bind the two
   proc-address getters.)
2. **API style: raw externs + thin idiomatic layer.** Every milestone ships both
   the faithful raw externs and a thin C3-idiomatic layer that converts
   `vk::Result` to a C3 optional + fault. Consumers get ergonomics
   (`allocator.create_buffer(...)!`); the raw layer stays reachable.
3. **Static-lib target coverage: host first.** Build `linux-x64` into
   `linked-libs/linux-x64/` now to unblock testing; a build script plus docs
   make the other targets producible on demand. Full 16-target population is the
   final milestone (M7).
4. **`vk` is a real dependency of the shipped library, not test-only.** VMA's
   extern signatures reference Vulkan types (`vk::Device`, `vk::Buffer`,
   `vk::Result`, …), so `vma` cannot compile without the `vk` binding. `vk` is
   therefore added to `manifest.json`'s per-target `dependencies`, and any
   consumer of `vma` must also provide `vk` on its dependency-search-path. This
   refines the initial framing where SDL3 and vk were both treated as
   test-only: **only SDL3 is test-only** (a future windowed demo); **vk is a
   true runtime dependency** of the binding. (The alternative — `vma` stubbing
   its own minimal Vulkan handles to stay self-contained — is rejected: it would
   collide with the consumer's own Vulkan types, which `add-binding` §2 warns
   against when a Vulkan binding already exists.)

## Architecture & conventions (apply to every milestone)

### Two file kinds

`.c3i` interface files cannot contain function bodies, so the layers split by
file kind, both `module vma;`:

- **Raw layer** (`vma.c3i`, plus per-topic `vma_*.c3i`): opaque handles,
  fully-declared + layout-pinned structs, enums / bitstructs, and `extern fn`
  declarations. Returns are faithful (`vk::Result`); functions that act on a
  handle use method syntax (`fn vk::Result Allocator.create(...)`,
  `fn void Allocator.destroy(&self)`). `@extern("vmaXxx")` holds the real C
  symbol verbatim.
- **Idiomatic layer** (`vma.c3`, plus per-topic `vma_*.c3`): fault-returning
  wrappers (bodies) and the `faultdef` block.

### Vulkan interop

All Vulkan types come from the `vk` dependency. The library manifest gains a
`vk` dependency entry. Nothing Vulkan-owned is redefined in `vma`.

### Error handling

A single `faultdef` block maps the VkResults VMA actually returns to granular
fault names (e.g. `OUT_OF_DEVICE_MEMORY`, `OUT_OF_HOST_MEMORY`,
`MEMORY_MAP_FAILED`, `TOO_MANY_OBJECTS`, `FEATURE_NOT_PRESENT`,
`INVALID_EXTERNAL_HANDLE`, plus a catch-all `UNKNOWN`). C3 faults carry no
payload, so granular names are how the originating VkResult survives into logs.
One helper, `check(vk::Result) -> void?`, performs the mapping; every idiomatic
wrapper routes its result through it.

### Per-binding workflow

Per the `add-binding` skill, for each symbol: read the exact signature from
`vk_mem_alloc.h` (never from memory); invoke `c3-expert` before writing C3; add
`$assert T::size == N;` after every fully-declared struct, with `N` obtained
from a 3-line C probe compiled against the header; compile-check the edited file
(`c3c compile-only`), which the repo's PostToolUse hook mirrors.

## Milestone ladder

Each milestone is independently shippable and testable. M0 unblocks everything.

### M0 — Foundation + allocator lifecycle
- Build the VMA static lib: one TU with `VMA_IMPLEMENTATION` +
  `VMA_STATIC_VULKAN_FUNCTIONS=1` → `linked-libs/linux-x64/`. Add
  `scripts/build-vma.sh`. Wire the manifest `linked-libraries` (the VMA lib) and
  the `vk` dependency.
- Bind: `Allocator` (opaque handle), `AllocatorCreateInfo` (declared,
  layout-pinned), `AllocatorCreateFlagBits` (bitstruct), `vmaCreateAllocator` /
  `vmaDestroyAllocator` + idiomatic `create_allocator` / `destroy`.
- Test infra: a headless Vulkan bootstrap in the test harness
  (`test/src/vk_bootstrap.c3`) — instance + physical-device pick + logical
  device, no window/surface — reused by every later milestone.
- **Runnable test:** create allocator → destroy allocator.

### M1 — Memory allocation + buffer round-trip
- Bind: `Allocation` (handle), `AllocationCreateInfo`, `AllocationInfo`,
  `MemoryUsage` (enum), `AllocationCreateFlagBits` (bitstruct);
  `vmaCreateBuffer` / `vmaDestroyBuffer`, `vmaAllocateMemory` /
  `vmaAllocateMemoryForBuffer` / `vmaFreeMemory`, `vmaGetAllocationInfo`
  (+ idiomatic wrappers).
- **Runnable test:** create_buffer → query `AllocationInfo` → destroy_buffer.

### M2 — Images, mapping, flush, bind
- Bind: `vmaCreateImage` / `vmaDestroyImage`, `vmaMapMemory` /
  `vmaUnmapMemory`, `vmaFlushAllocation(s)` / `vmaInvalidateAllocation(s)`,
  `vmaBindBufferMemory(2)` / `vmaBindImageMemory(2)`,
  `vmaCopyMemoryToAllocation` / `vmaCopyAllocationToMemory`.
- **Runnable test:** map a host-visible buffer, write, flush, unmap; create an
  image.

### M3 — Statistics & budget
- Bind: `Statistics`, `DetailedStatistics`, `TotalStatistics`, `Budget`
  (declared, layout-pinned); `vmaCalculateStatistics`, `vmaGetHeapBudgets`,
  `vmaGetAllocatorInfo`, `vmaBuildStatsString` / `vmaFreeStatsString`,
  `vmaGetPhysicalDeviceProperties` / `vmaGetMemoryProperties` /
  `vmaGetMemoryTypeProperties`.
- **Runnable test:** allocate, calculate statistics, assert non-zero usage.

### M4 — Custom pools
- Bind: `Pool` (handle), `PoolCreateInfo`, `vmaCreatePool` / `vmaDestroyPool`,
  `vmaGetPoolStatistics` / `vmaCalculatePoolStatistics`,
  `vmaCheckPoolCorruption`, `vmaGetPoolName` / `vmaSetPoolName`.
- **Runnable test:** create pool, allocate from it, query stats, destroy.

### M5 — Defragmentation
- Bind: `DefragmentationContext` (handle), `DefragmentationInfo`,
  `DefragmentationMove`, `DefragmentationPassMoveInfo`, `DefragmentationStats`;
  `vmaBeginDefragmentation` / `vmaEndDefragmentation` /
  `vmaBeginDefragmentationPass` / `vmaEndDefragmentationPass`.
- **Runnable test:** structural + a minimal defragmentation pass.

### M6 — Virtual allocator *(device-independent — reorderable earlier)*
- Bind: `VirtualBlock` (handle), `VirtualBlockCreateInfo`, `VirtualAllocation`,
  `VirtualAllocationCreateInfo`, `VirtualAllocationInfo`;
  `vmaCreateVirtualBlock` / `vmaDestroyVirtualBlock` / `vmaVirtualAllocate` /
  `vmaVirtualFree` / `vmaClearVirtualBlock` / `vmaGetVirtualAllocationInfo` /
  virtual-block statistics.
- **Runnable test:** pure CPU, no Vulkan device required.

### M7 — Misc + cross-target population
- Bind leftovers: `vmaSetCurrentFrameIndex`, `vmaCheckCorruption`,
  `vmaSetAllocationName` / `vmaSetAllocationUserData` /
  `vmaGetAllocationMemoryProperties`, aliasing buffers/images,
  `vmaCreateBufferWithAlignment`, `vmaAllocateMemoryPages` /
  `vmaFreeMemoryPages`, `vmaAllocateMemoryForImage`.
- Populate `linked-libs/` for the remaining 15 targets via the build script and
  available toolchains.
- Docs polish.

### Dependencies between milestones

M0 blocks all. M1 → M2 is linear. M3, M4, M5 each depend on M1 and are mutually
reorderable. M6 is independent of M1–M5 (needs only M0's lib build). M7 is last.

## Testing strategy

**Headless Vulkan, not SDL.** VMA needs a `VkInstance` + `VkDevice`, not a
window or surface, so the binding's tests create a headless device through `vk`
alone:

- Runs on the development machine today — `libvulkan.so.1` is present with the
  `lavapipe` software ICD, whereas `libSDL3` is not installed. Headless tests are
  green now; SDL-dependent tests would not link.
- Deterministic and CI-friendly: no display, no swapchain.

The `test/src/vk_bootstrap.c3` helper (built in M0) owns instance/device creation
and is shared by every milestone's smoke test. Pure-CPU tests (handle math,
virtual allocator) need no device at all.

**SDL3 is demoted off the VMA critical path.** The `sdl3.c3l` submodule and its
manifest target stay in the repo, but SDL3 is **not** a dependency of the
headless smoke target — a headless test never imports `sdl`, and hard-linking
`libSDL3` would force it to be installed for no benefit (it is absent on the
dev/CI machine). SDL3 will be wired into a **separate windowed-demo target** if
and when that lands; VMA itself never needs a surface. This is a deliberate
change from SDL3's original "window provider for testing" role.

## Repository layout growth

```
vma.c3i                handles + core externs (M0+)
vma_memory.c3i         allocation / buffer externs (M1+)
vma_image.c3i, ...     per-topic externs as milestones land
vma.c3                 faultdef + check() + core idiomatic wrappers
vma_memory.c3, ...     idiomatic wrappers per topic
scripts/build-vma.sh   compile the impl TU per target -> linked-libs/<target>/
linked-libs/linux-x64/libVulkanMemoryAllocator.a   (M0)
test/src/vk_bootstrap.c3   headless Vulkan device (M0)
test/src/main.c3           grows per-milestone smoke checks
```

The library manifest never references `test/`, so consumers of `vma` never pull
the test dependencies.

## Out of scope

- C++-only VMA features not exposed through the `extern "C"` API.
- A dynamic Vulkan function loader (volk) integration — only if a consumer needs
  it (see decision 1).
- SDL-based windowed rendering beyond an optional future demo.
