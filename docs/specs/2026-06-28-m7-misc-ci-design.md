# M7 — Misc leftovers + CI cross-build (design)

Date: 2026-06-28
Status: approved (brainstorming)
Predecessor: [M6 design](2026-06-28-m6-virtual-allocator-design.md) · [roadmap](2026-06-26-vma-binding-roadmap-design.md)

The final milestone. Two independent parts:

- **(A) Binding leftovers** — the last 13 `extern "C"` VMA functions, completing the
  binding surface, in a new `vma_misc.c3i`/`.c3`. Fully testable locally.
- **(B) CI cross-build** — a GitHub Actions workflow that builds the VMA static lib
  for `linux-x64` and `windows-x64` and uploads them as artifacts, plus wiring the
  `windows-x64` manifest target. Authored now; it runs only once a GitHub remote
  exists and is pushed to — there is no remote in this workspace, so part B is
  **not verifiable in-session** and the spec/plan say so plainly rather than
  pretending otherwise.

## Context

M0–M6 bound the device allocator, buffers/images, host access, statistics & budget,
custom pools, defragmentation, and the device-independent virtual allocator. A diff
of the header's public functions against the bound `@cname`s leaves 15 unbound; two
are excluded because they are not in the built lib (so binding them would break
linking):

- `vmaGetMemoryWin32Handle` — requires `VMA_EXTERNAL_MEMORY_WIN32`; the lib is built
  `VMA_EXTERNAL_MEMORY=0`.
- `vmaImportVulkanFunctionsFromVolk` — volk integration, deferred by roadmap
  decision 1.

The remaining 13 are M7's binding surface. One new struct (`AllocationInfo2`) is
introduced; everything else reuses M1's `AllocationInfo`/`AllocationCreateInfo`/
`BufferAllocation`, M3's stat structs are untouched, and M4's `CORRUPTION_DETECTED`
fault is reused.

## Settled decisions

1. **Bind all 13 remaining functions** (the final surface): `vmaSetCurrentFrameIndex`,
   `vmaCheckCorruption`, `vmaSetAllocationName`, `vmaSetAllocationUserData`,
   `vmaGetAllocationMemoryProperties`, `vmaGetAllocationInfo2`,
   `vmaCreateAliasingBuffer`(+`2`), `vmaCreateAliasingImage`(+`2`),
   `vmaCreateBufferWithAlignment`, `vmaAllocateMemoryPages`, `vmaFreeMemoryPages`.
2. **`vmaCheckCorruption` reuses M4's corruption handling** — its idiomatic wrapper
   maps `VK_ERROR_UNKNOWN`→`CORRUPTION_DETECTED` locally (the same fix M4 applied to
   `try_check_pool_corruption`), with `FEATURE_NOT_PRESENT` when detection is off
   (our lib's case). No new fault for corruption.
3. **The `*2` aliasing variants are compile-checked only** (the M2 norm for `*2`
   variants); their primaries (`create_aliasing_buffer`/`create_aliasing_image`) are
   runtime-tested.
4. **One new layout-pinned struct**, `AllocationInfo2`, `$assert`-pinned at 72.
5. **CI builds linux-x64 + windows-x64 only** (per the milestone request), uploads
   the libs as **artifacts** (not auto-committed). The `windows-x64` manifest target
   is wired; the windows lib links only once the CI artifact is committed to
   `linked-libs/windows-x64/` — a documented one-step enablement.
6. **Part B is authored, not run.** No git remote exists here, and there is no local
   windows toolchain, so the windows lib cannot be produced or the workflow exercised
   in-session. The deliverable is a correct, well-formed workflow + manifest wiring +
   enablement docs; verification happens on the first push to a GitHub remote.

## Part A — binding surface

All signatures below are illustrative; exact forms are re-read from `vk_mem_alloc.h`
and verified with `c3-expert` at plan time per `add-binding`.

### New struct — layout-pinned (`vma_misc.c3i`)

```
struct AllocationInfo2 {
    AllocationInfo allocation_info;
    vk::DeviceSize block_size;
    vk::Bool32     dedicated_memory;
}
$assert(AllocationInfo2::size == 72);
```

### Raw externs (`vma_misc.c3i`, all `Allocator` methods)

```
fn void       Allocator.set_current_frame_index(self, uint frame_index) @cname("vmaSetCurrentFrameIndex");
fn vk::Result Allocator.check_corruption(self, uint memory_type_bits) @cname("vmaCheckCorruption");
fn void       Allocator.set_allocation_name(self, Allocation allocation, ZString name) @cname("vmaSetAllocationName");
fn void       Allocator.set_allocation_user_data(self, Allocation allocation, void* user_data) @cname("vmaSetAllocationUserData");
fn void       Allocator.get_allocation_memory_properties(self, Allocation allocation, vk::MemoryPropertyFlags* out_flags) @cname("vmaGetAllocationMemoryProperties");
fn void       Allocator.get_allocation_info2(self, Allocation allocation, AllocationInfo2* out_info) @cname("vmaGetAllocationInfo2");
fn vk::Result Allocator.create_aliasing_buffer(self, Allocation allocation, vk::BufferCreateInfo* bi, vk::Buffer* out_buffer) @cname("vmaCreateAliasingBuffer");
fn vk::Result Allocator.create_aliasing_buffer2(self, Allocation allocation, vk::DeviceSize offset, vk::BufferCreateInfo* bi, vk::Buffer* out_buffer) @cname("vmaCreateAliasingBuffer2");
fn vk::Result Allocator.create_aliasing_image(self, Allocation allocation, vk::ImageCreateInfo* ii, vk::Image* out_image) @cname("vmaCreateAliasingImage");
fn vk::Result Allocator.create_aliasing_image2(self, Allocation allocation, vk::DeviceSize offset, vk::ImageCreateInfo* ii, vk::Image* out_image) @cname("vmaCreateAliasingImage2");
fn vk::Result Allocator.create_buffer_with_alignment(self, vk::BufferCreateInfo* bi, AllocationCreateInfo* ci, vk::DeviceSize min_alignment, vk::Buffer* out_buffer, Allocation* out_alloc, AllocationInfo* out_info) @cname("vmaCreateBufferWithAlignment");
fn vk::Result Allocator.allocate_memory_pages(self, vk::MemoryRequirements* reqs, AllocationCreateInfo* cis, usz count, Allocation* out_allocs, AllocationInfo* out_infos) @cname("vmaAllocateMemoryPages");
fn void       Allocator.free_memory_pages(self, usz count, Allocation* allocations) @cname("vmaFreeMemoryPages");
```

`size_t` → C3 `usz`. `vmaAllocateMemoryPages` takes parallel arrays of `count`
elements (one `VkMemoryRequirements` and one `AllocationCreateInfo` per page).

### Idiomatic (`vma_misc.c3`)

```
fn void?                   Allocator.try_check_corruption(self, uint memory_type_bits);  // SUCCESS->ok, ERROR_UNKNOWN->CORRUPTION_DETECTED, else check()
fn vk::MemoryPropertyFlags Allocator.allocation_memory_properties(self, Allocation allocation);  // by value
fn AllocationInfo2         Allocator.allocation_info2(self, Allocation allocation);             // by value
fn vk::Buffer?             Allocator.try_create_aliasing_buffer(self, Allocation allocation, vk::BufferCreateInfo* bi);
fn vk::Image?              Allocator.try_create_aliasing_image(self, Allocation allocation, vk::ImageCreateInfo* ii);
fn BufferAllocation?       Allocator.try_create_buffer_with_alignment(self, vk::BufferCreateInfo* bi, AllocationCreateInfo* ci, vk::DeviceSize min_alignment);  // reuses M1 BufferAllocation
fn void?                   Allocator.try_allocate_memory_pages(self, vk::MemoryRequirements[] reqs, AllocationCreateInfo[] cis, Allocation[] out_allocs);  // count = out_allocs.len; equal-length guard
```

- `try_check_corruption` mirrors M4's `try_check_pool_corruption`: a local switch
  (`SUCCESS`→return, `ERROR_UNKNOWN`→`CORRUPTION_DETECTED~`, default→`check(r)!`).
- `try_allocate_memory_pages` derives `count` from `out_allocs.len`, returns
  `BATCH_LENGTH_MISMATCH` if the three slices differ in length (or any is empty),
  and passes null for the optional out-infos array.
- `set_current_frame_index`/`set_allocation_name`/`set_allocation_user_data`/
  `free_memory_pages` are `void` → used raw. The `create_aliasing_*2` variants are
  bound raw and compile-checked only (decision 3).
- `allocation_info2`/`allocation_memory_properties` do not collide with existing
  methods — distinct names.

## Part B — CI cross-build

### Workflow `.github/workflows/build-vma-libs.yml`

Triggers: `workflow_dispatch` (manual) and `push` touching `scripts/vma_impl.cpp` or
the workflow file. Two jobs, each compiling the existing `scripts/vma_impl.cpp`
(whose `VMA_IMPLEMENTATION` / `VMA_STATIC_VULKAN_FUNCTIONS=1` /
`VMA_DYNAMIC_VULKAN_FUNCTIONS=0` / `VMA_EXTERNAL_MEMORY=0` defines fix the ABI):

- **linux-x64** (`ubuntu-latest`): check out pinned `KhronosGroup/Vulkan-Headers` and
  `GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator` (v3.3.0); assemble an include tree
  exposing `vma/vk_mem_alloc.h` and `vulkan/*.h`; `g++ -std=c++17 -O2 -fPIC -c
  scripts/vma_impl.cpp` → `ar rcs libVulkanMemoryAllocator.a`; compile + run the size
  probe as a sanity gate (`AllocatorCreateInfo == 80`); upload `libVulkanMemoryAllocator.a`
  as an artifact.
- **windows-x64** (`windows-latest`): same headers; MSVC `cl /std:c++17 /O2 /c
  scripts\vma_impl.cpp` then `lib /OUT:VulkanMemoryAllocator.lib vma_impl.obj`; upload
  `VulkanMemoryAllocator.lib` as an artifact.

Header versions are pinned (VMA v3.3.0 to match the in-repo ABI; a compatible
`Vulkan-Headers` tag). The workflow is plain YAML; it cannot be executed in this
workspace.

### Manifest wiring

`manifest.json` `windows-x64` target gains `dependencies: ["vk"]` and
`linked-libraries: ["VulkanMemoryAllocator"]`. MSVC embeds C++-runtime references in
the `.lib`, so no extra runtime entry is listed (best-effort, to be confirmed on the
first real windows consumer build). `linux-x64` is unchanged (already wired with
`["VulkanMemoryAllocator", "stdc++"]`).

### Windows enablement (documented, manual one-step)

Because libs are artifacts (not auto-committed), the windows target links only after:
download the `VulkanMemoryAllocator.lib` artifact from a CI run → commit it to
`linked-libs/windows-x64/` → done (the manifest is already wired). This is recorded in
a short build/CI doc.

## Testing

### Part A — `misc_round_trip(alloc, device)` (headless, lavapipe)

Extend the smoke. With a host-visible buffer (`MemoryUsage.AUTO` + `host_access_random`):

1. `set_current_frame_index(0)` (call; no observable result).
2. `set_allocation_name(ba.allocation, "smoke_alloc")` → `get_allocation_info` →
   assert `name.str_view() == "smoke_alloc"` (`MISC_NAME_MISMATCH`).
3. `set_allocation_user_data(ba.allocation, &marker)` → `get_allocation_info` →
   assert `user_data == &marker` (`MISC_USERDATA_MISMATCH`).
4. `allocation_memory_properties(ba.allocation)` → assert the HOST_VISIBLE bit is set
   (`MISC_MEMPROPS`).
5. `allocation_info2(ba.allocation)` → assert `.allocation_info.size >= BUFFER_SIZE`
   and `.block_size >= .allocation_info.size` (`MISC_INFO2`).
6. `try_check_corruption(0xFFFFFFFF)` → accept `SUCCESS`; catch and accept
   `FEATURE_NOT_PRESENT`; any other fault fails.
7. `try_create_buffer_with_alignment(&bi, &ai, 256)` → assert
   `info.offset % 256 == 0` (`MISC_ALIGN`); destroy the buffer.
8. `try_allocate_memory_pages`: pull `vk::MemoryRequirements` from a raw `VkBuffer`
   (`MemoryUsage.GPU_ONLY`), fill `N` identical reqs + create-infos, allocate `N`
   pages, then `free_memory_pages`.
9. `try_create_aliasing_buffer`: create a buffer allocation, create an aliasing
   buffer (size ≤ allocation) on its memory, `vk::destroy_buffer` the alias, destroy
   the original.

The `create_aliasing_*2` variants are not runtime-exercised (compile-checked only).
Builds + runs exit 0 on lavapipe; success message gains `+ misc`.

### Part B — not runnable here

The workflow cannot run without a GitHub remote, and the windows lib needs CI to
build. The plan's "test" for part B is: the YAML is well-formed and the enablement
doc is correct. Verification is the first push to a GitHub remote — explicitly out of
this session's reach, and the plan does not claim otherwise.

## File layout

```
vma_misc.c3i   (new)  AllocationInfo2 + $assert + 13 raw externs
vma_misc.c3    (new)  7 idiomatic wrappers
scripts/vma_size_probe.cpp (+)  AllocationInfo2 size (72)
scripts/build-vma.sh       (+)  expect_size AllocationInfo2 72
.github/workflows/build-vma-libs.yml (new)  linux + windows lib build -> artifacts
manifest.json              (+)  wire windows-x64 (deps vk, linked-lib VulkanMemoryAllocator)
test/src/main.c3           (+)  misc_round_trip path; message
docs/ci-cross-build.md     (new)  CI usage + windows enablement steps; surface-complete note
```

`vma.c3` is unchanged — `check()` and `CORRUPTION_DETECTED` (M4) are reused.

## Out of scope

- `vmaGetMemoryWin32Handle`, `vmaImportVulkanFunctionsFromVolk` (not in the built lib).
- The other 13 manifest targets (macOS, BSD, wasm, 32-bit, aarch64) — only `linux-x64`
  + `windows-x64` per the milestone request.
- Auto-committing CI-built libs (artifacts only; manual commit step documented).
- A windowed SDL3 demo.
