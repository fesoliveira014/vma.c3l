# vma.c3l

C3 language bindings for the [Vulkan Memory Allocator (VMA)](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator)
C API, packaged as a C3 library (`.c3l`). It provides the `vma` module.

VMA is AMD's memory allocator for Vulkan — it manages `VkDeviceMemory` blocks and
sub-allocates buffers and images out of them. This package wraps VMA's
`extern "C"` surface in idiomatic C3: the C `vmaXxx` names become
`vma::create_allocator`, `vma::AllocationCreateInfo`, and so on.

Bound against **VMA 3.3.0** and **C3 0.8.0**.

## Requirements

- **C3 0.8.0** (`c3c`). The binding tracks this release; C3 is pre-1.0 and its
  syntax drifts between versions.
- **The `vk` C3 binding** ([vk.c3l](https://github.com/fesoliveira014/vk.c3l)).
  Every VMA signature references Vulkan types (`VkDevice`, `VkBuffer`,
  `VkResult`, `VkBufferCreateInfo`, …), and those come from `vk`. This is a real
  dependency of the library, not test-only — `vma` cannot compile without it, and
  any consumer must also provide `vk` on its dependency search path.
- **A compiled VMA static library for your target** under `linked-libs/<target>/`.
  The git tree does not carry binaries; take them from a
  [GitHub release](https://github.com/fesoliveira014/vma.c3l/releases) or build
  them with the scripts. See [Platform support](#platform-support).

## What's bound

The full VMA `extern "C"` surface, each function exposed two ways: a faithful raw
`extern` (returns `VkResult` verbatim) and a thin idiomatic wrapper (returns a C3
optional and maps `VkResult` to a fault).

- **Allocator lifecycle** — create / destroy.
- **Buffers & images** — create/destroy with backing allocation; manual
  allocate-memory + bind; buffer-with-alignment; aliasing buffers/images over an
  existing allocation.
- **Host memory access** — map / unmap, flush / invalidate, copy to/from an
  allocation.
- **Statistics & budget** — allocator, pool, and per-heap statistics; the JSON
  stats string; device/memory property queries.
- **Custom pools** — create/destroy, allocate from a pool, pool statistics,
  naming, corruption check; plus the find-memory-type-index helpers.
- **Defragmentation** — the begin → pass-loop → end cycle.
- **Virtual allocator** — a device-independent, pure-CPU offset sub-allocator.
- **Misc** — current-frame index, allocation name / user-data, allocation memory
  properties, memory pages (batch allocate/free), corruption check.

## What's not supported

- `vmaGetMemoryWin32Handle` (requires `VMA_EXTERNAL_MEMORY_WIN32`) and
  `vmaImportVulkanFunctionsFromVolk` (volk loader). These are not compiled into
  the shipped library, so they are intentionally not bound.
- **A dynamic Vulkan function loader.** The library is built with
  `VMA_STATIC_VULKAN_FUNCTIONS=1`: VMA calls `vkAllocateMemory` and friends
  directly against the `libvulkan` your program already links. There is no volk /
  dynamic-loader path.
- **Prebuilt static libraries for targets other than `linux-x64` and
  `windows-x64`.** See below.

## Platform support

| Target | Prebuilt static lib | Notes |
| --- | --- | --- |
| `linux-x64` | release asset `libVulkanMemoryAllocator-linux-x64.a` | GCC, `-fPIC` |
| `windows-x64` | release asset `VulkanMemoryAllocator-windows-x64.lib` | MSVC, built `/MT`; the manifest sets `"wincrt": "static"` for consumers |
| macOS, BSD, 32-bit, ARM, WASM, … | not provided | build your own with `scripts/build-vma.sh` |

Every `v*` tag runs the `build-vma-libs` workflow, which compiles both targets and
publishes a GitHub release with three kinds of asset: the two static libs above, a
`vma.c3l-<tag>.zip` bundle (sources + `manifest.json` + `linked-libs/` for both
targets, ready to drop into a dependency search path), and `SHA256SUMS`.

## Using it in your project

1. **Vendor this binding and `vk`** into your dependency search path. The
   simplest route is the release bundle, which already contains the static libs:

   ```sh
   curl -fsSLO https://github.com/fesoliveira014/vma.c3l/releases/latest/download/vma.c3l-<tag>.zip
   unzip vma.c3l-<tag>.zip -d libs          # -> libs/vma.c3l
   git clone https://github.com/fesoliveira014/vk.c3l libs/vk.c3l
   ```

   Cloning this repository works too, but then step 3 is on you: the clone has no
   binaries under `linked-libs/`.

2. **Declare the dependencies** in your `project.json`:

   ```json
   {
     "dependency-search-paths": [ "libs" ],
     "dependencies": [ "vma", "vk" ]
   }
   ```

   Dependencies resolve by their manifest `provides` name (`vma`, `vk`), not by
   directory name.

3. **Provide a VMA static lib for your build target** under
   `linked-libs/<target>/`: from the release bundle, from the per-target release
   assets, or built locally (next section).

### Example

```c3
import vma;
import vk;

fn void? upload_path(vk::Instance instance, vk::PhysicalDevice gpu, vk::Device device) {
    vma::AllocatorCreateInfo aci = {
        .physical_device    = gpu,
        .device             = device,
        .instance           = instance,
        .vulkan_api_version = 1u << 22,   // VK_API_VERSION_1_0
    };
    vma::Allocator alloc = vma::try_create_allocator(&aci)!;
    defer alloc.destroy();

    vk::BufferCreateInfo bi = {
        .s_type       = vk::StructureType.BUFFER_CREATE_INFO,
        .size         = 65536,
        .usage        = vk::BufferUsageFlagBits.TRANSFER_DST_BIT,
        .sharing_mode = vk::SharingMode.EXCLUSIVE,
    };
    vma::AllocationCreateInfo ai = { .usage = vma::MemoryUsage.AUTO };

    vma::BufferAllocation ba = alloc.try_create_buffer(&bi, &ai)!;
    defer alloc.destroy_buffer(ba.buffer, ba.allocation);
    // ba.buffer is a vk::Buffer; ba.allocation is the backing vma::Allocation.
}
```

**Naming.** The `vma` C prefix never appears on the C3 side: `vma::create_allocator`,
not `vmaCreateAllocator`. Types are PascalCase (`vma::AllocationCreateInfo`),
functions and fields are snake_case. Idiomatic wrappers are prefixed `try_` and
return optionals (`vma::Allocator?`); the raw externs keep the faithful `VkResult`
and are reachable if you want them.

## Building the static library

The lib is a single translation unit compiled with `VMA_IMPLEMENTATION`
(`scripts/vma_impl.cpp`). To build it for the host:

```sh
export VULKAN_SDK=/path/to/vulkan/sdk   # must contain include/vma/vk_mem_alloc.h
bash scripts/build-vma.sh               # -> linked-libs/linux-x64/libVulkanMemoryAllocator.a
```

The script also runs a size probe that pins the C struct layouts the bindings
assert at compile time, so an ABI drift fails the build rather than corrupting
memory silently.

On Windows the archive is built with the static CRT (`/MT`). An MSVC archive carries
a `RuntimeLibrary` mismatch record, so it links only into an executable built against
the same CRT; `manifest.json`'s `windows-x64` target therefore declares
`"wincrt": "static"` and consumers inherit it. Mixing CRTs surfaces as
`lld-link: error: /failifmismatch: mismatch detected for 'RuntimeLibrary'`, not as a
runtime bug.

Without a Vulkan SDK, `scripts/fetch-vma-headers.sh <dir>` clones the pinned
Vulkan-Headers and VMA releases into an SDK-shaped `<dir>/include`; point
`VULKAN_SDK` at `<dir>` and run the build script. CI (`.github/workflows/ci.yml`)
does exactly this before it links the smoke harness, and the release workflow
(`.github/workflows/build-vma-libs.yml`) does it for both targets.

To cut a release: tag a commit `vX.Y.Z` and push the tag. The workflow builds
`linux-x64` (GCC) and `windows-x64` (MSVC, `/MT`), and publishes the release
with the libs, the `vma.c3l-vX.Y.Z.zip` bundle, and `SHA256SUMS`.

## Repository layout

| Path | Contents |
| --- | --- |
| `vma.c3i` | handles, enums, bitstructs, layout-pinned structs, and the raw `extern` declarations |
| `vma.c3` | the idiomatic wrappers and their result structs |
| `vma_check.c3` | the `VkResult` → fault mapping (`faultdef` + `check`) |
| `manifest.json` | library manifest (`provides: vma`) |
| `linked-libs/<target>/` | per-target compiled VMA libraries (release assets; not tracked in git) |
| `scripts/` | header fetch, the static-lib builds, and the struct-size probe |
| `test/` | a standalone consumer harness — **not part of the shipped library** (see [`test/README.md`](test/README.md)) |

The library manifest never references `test/`, so consumers of `vma` never pull
the test dependencies.

## License

Released under the MIT License — see [`LICENSE`](LICENSE). The wrapped VMA library
is itself MIT-licensed.
