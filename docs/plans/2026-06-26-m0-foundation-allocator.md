# M0 — Foundation + Allocator Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a linkable VMA static library, bind the allocator lifecycle (create/destroy) as raw externs plus a thin idiomatic layer, and prove the whole chain end-to-end with a headless-Vulkan smoke test that creates and destroys a `VmaAllocator`.

**Architecture:** VMA is header-only C++ with an `extern "C"` API; one translation unit compiled with `VMA_IMPLEMENTATION` becomes `linked-libs/linux-x64/libVulkanMemoryAllocator.a`. The `vma` C3 module binds the C symbols (raw layer in `.c3i`, idiomatic fault-returning layer in `.c3`), pulling all Vulkan types from the `vk` dependency. The test harness boots a headless `VkInstance`+`VkDevice` (no window/surface) via `vk` and runs the allocator round-trip on the lavapipe software ICD.

**Tech Stack:** C3 0.8.0 (`c3c`), VMA (`vk_mem_alloc.h` from `$VULKAN_SDK`), `vk.c3l` + `sdl3.c3l` (test submodules), g++/`c++` for the impl TU, Vulkan loader + lavapipe.

## Global Constraints

- **C3 0.8.0 only.** Verify any uncertain syntax with `c3c compile-only --no-obj`.
- **Use `@cname("vmaXxx")`, NOT `@extern("...")`.** `@extern` as a rename attribute was removed in 0.8.0; the project docs (CLAUDE.md, docs/style.md, docs/bindings_guidelines.md, add-binding skill) still say `@extern` and are stale on this point. `vk.c3l` confirms `@cname` is the working form.
- **Method receiver must be the first parameter.** A C function whose handle is not the first arg (e.g. `vmaCreateAllocator(info*, allocator*)`) is bound as a **free function**, not a method. Only allocator-first functions (`vmaDestroyAllocator(allocator)`) are methods.
- **Naming:** types `PascalCase` (strip `Vma`), functions `snake_case`, constants/flags `SCREAMING_SNAKE_CASE`. Struct/constdef names may not be all-uppercase (C3 rejects them).
- **Layout pinning:** every fully-declared struct gets `$assert(T::size == N)` with `N` measured by a C++ probe compiled against the real header with the same defines as the lib build.
- **Lib build defines (fixed for determinism):** `VMA_IMPLEMENTATION`, `VMA_STATIC_VULKAN_FUNCTIONS=1`, `VMA_DYNAMIC_VULKAN_FUNCTIONS=0`, `VMA_EXTERNAL_MEMORY=0`. The `=0` drops the trailing `pTypeExternalMemoryHandleTypes` field, giving a 10-field, 80-byte `AllocatorCreateInfo`.
- **Vulkan-function mode is static:** `VmaVulkanFunctions` stays null; do not bind PFN types.
- **Testing is headless Vulkan** (no SDL). SDL3 stays a declared test dependency for a future demo only.
- **Do not run `c3fmt`.** Hand-format K&R per docs/style.md.
- **VMA returns `vk::Result` faithfully in the raw layer** — no fault-wrapping inside an `extern`.

## File Structure

| File | Responsibility |
|------|----------------|
| `scripts/vma_impl.cpp` (create) | The VMA implementation TU: defines + `#include <vma/vk_mem_alloc.h>`. |
| `scripts/vma_size_probe.cpp` (create) | Prints `sizeof(VmaAllocatorCreateInfo)` to confirm the `$assert`. |
| `scripts/build-vma.sh` (create) | Compiles the impl TU → `linked-libs/linux-x64/libVulkanMemoryAllocator.a`. |
| `linked-libs/linux-x64/libVulkanMemoryAllocator.a` (build artifact, committed) | The shipped static lib for the host target. |
| `vma.c3i` (modify) | Raw layer: `Allocator` handle, `AllocatorCreateFlags` bitstruct, `AllocatorCreateInfo` struct + `$assert`, `create_allocator`/`Allocator.destroy` externs. |
| `vma.c3` (create) | Idiomatic layer: `faultdef`, `check()`, `try_create_allocator()`. |
| `manifest.json` (modify) | linux-x64 target gains `dependencies:["vk"]` and `linked-libraries:["VulkanMemoryAllocator","stdc++"]`. |
| `test/src/vk_bootstrap.c3` (create) | Headless `VkInstance`+`VkDevice` bootstrap, reused by all later milestones. |
| `test/src/main.c3` (modify) | Smoke: bootstrap → create allocator → destroy → teardown. |
| `.claude/hooks/c3-syntax-check.sh` (modify) | Resolve `vk` imports for repo-root library files against `test/libs` so editing `vma.c3i` doesn't false-fail. |

---

### Task 1: Build the VMA static library and pin the struct size

**Files:**
- Create: `scripts/vma_impl.cpp`
- Create: `scripts/vma_size_probe.cpp`
- Create: `scripts/build-vma.sh`
- Build artifact: `linked-libs/linux-x64/libVulkanMemoryAllocator.a`

**Interfaces:**
- Produces: a static lib exporting the C symbol `vmaCreateAllocator` (and the rest of the VMA C API); the measured size of `VmaAllocatorCreateInfo` (expected `80`) that Task 2's `$assert` depends on.

- [ ] **Step 1: Write the implementation TU**

Create `scripts/vma_impl.cpp`:

```cpp
// Single translation unit that compiles the VMA implementation into a static
// library. Defines are fixed here so any rebuild reproduces the same ABI.
#define VMA_IMPLEMENTATION
#define VMA_STATIC_VULKAN_FUNCTIONS 1
#define VMA_DYNAMIC_VULKAN_FUNCTIONS 0
#define VMA_EXTERNAL_MEMORY 0
#include <vma/vk_mem_alloc.h>
```

- [ ] **Step 2: Write the size probe**

Create `scripts/vma_size_probe.cpp`:

```cpp
#include <cstdio>
#define VMA_EXTERNAL_MEMORY 0
#include <vma/vk_mem_alloc.h>

int main(void) {
    std::printf("%zu\n", sizeof(VmaAllocatorCreateInfo));
    return 0;
}
```

- [ ] **Step 3: Write the build script**

Create `scripts/build-vma.sh`:

```sh
#!/bin/sh
# Build the VMA static library for the host target (linux-x64).
# Cross-compiling the other manifest targets is deferred to a later milestone.
set -e
: "${VULKAN_SDK:?set VULKAN_SDK to your Vulkan SDK root}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="linux-x64"
OUT="$ROOT/linked-libs/$TARGET"
CXX="${CXX:-c++}"
mkdir -p "$OUT"
echo "Building VMA static lib -> $OUT/libVulkanMemoryAllocator.a"
"$CXX" -std=c++17 -O2 -fPIC -c "$ROOT/scripts/vma_impl.cpp" \
    -I"$VULKAN_SDK/include" \
    -o "$OUT/vma_impl.o"
ar rcs "$OUT/libVulkanMemoryAllocator.a" "$OUT/vma_impl.o"
rm -f "$OUT/vma_impl.o"
echo "Done."
```

- [ ] **Step 4: Make the script executable and build the lib**

Run:
```sh
chmod +x scripts/build-vma.sh
./scripts/build-vma.sh
```
Expected: prints `Building VMA static lib -> .../linked-libs/linux-x64/libVulkanMemoryAllocator.a` then `Done.`, exit 0. (Compiling ~19k lines of C++ takes a few seconds.)

- [ ] **Step 5: Verify the C symbol is exported**

Run:
```sh
nm linked-libs/linux-x64/libVulkanMemoryAllocator.a | grep -E ' T (vmaCreateAllocator|vmaDestroyAllocator)$'
```
Expected: two lines ending in `T vmaCreateAllocator` and `T vmaDestroyAllocator` (capital `T` = defined text symbol). If empty, the build produced no public symbols — stop and diagnose.

- [ ] **Step 6: Measure the struct size**

Run:
```sh
c++ -std=c++17 -I"$VULKAN_SDK/include" scripts/vma_size_probe.cpp -o /tmp/vma_size_probe && /tmp/vma_size_probe
```
Expected: prints `80`. **If it prints anything other than 80, record that value** — Task 2's `$assert` must use the measured number, not 80.

- [ ] **Step 7: Commit**

```sh
git add scripts/vma_impl.cpp scripts/vma_size_probe.cpp scripts/build-vma.sh linked-libs/linux-x64/libVulkanMemoryAllocator.a
git commit -m "build: compile VMA static lib for linux-x64 (M0)"
```

---

### Task 2: Bind the raw allocator layer

**Files:**
- Modify: `vma.c3i`
- Modify: `.claude/hooks/c3-syntax-check.sh`
- Verify against: `test/libs/vk.c3l` (provides the Vulkan types)

**Interfaces:**
- Consumes: `vk::PhysicalDevice`, `vk::Device`, `vk::Instance`, `vk::DeviceSize`, `vk::AllocationCallbacks`, `vk::Result` (from the `vk` dependency).
- Produces: `vma::Allocator` (handle typedef), `vma::AllocatorCreateFlags` (bitstruct), `vma::AllocatorCreateInfo` (struct, 80 bytes), `vma::create_allocator(AllocatorCreateInfo* info, Allocator* out) -> vk::Result` (free fn), `Allocator.destroy(self)` (method). Task 3 and Task 4 consume these.

- [ ] **Step 1: Teach the syntax-check hook to resolve `vk` for repo-root library files**

The current hook compiles bare library files in isolation, so `vma.c3i`'s `import vk` would false-fail. Replace the `else` branch of `.claude/hooks/c3-syntax-check.sh` (the branch that runs when no ancestor `project.json` is found) with one that resolves imports against `test/libs` when present.

Find this block:
```sh
else
  out=$(c3c compile-only --no-obj "$f" 2>&1)
  rc=$?
  rm -rf obj 2>/dev/null
fi
```
Replace it with:
```sh
else
  # Bare library file (no consumer project.json). If a sibling test/libs with
  # the Vulkan binding exists, resolve external imports against it so files that
  # `import vk` do not false-fail; otherwise fall back to the isolated check.
  libs_dir=""
  d=$(dirname "$f")
  while [ "$d" != "/" ] && [ -n "$d" ]; do
    if [ -d "$d/test/libs" ]; then libs_dir="$d/test/libs"; break; fi
    d=$(dirname "$d")
  done
  if [ -n "$libs_dir" ]; then
    out=$(c3c compile-only --no-obj --libdir "$libs_dir" --lib vk "$f" 2>&1)
  else
    out=$(c3c compile-only --no-obj "$f" 2>&1)
  fi
  rc=$?
  rm -rf obj 2>/dev/null
fi
```

- [ ] **Step 2: Write the raw binding**

Replace the entire contents of `vma.c3i` with:

```c3
module vma;

import vk;

typedef Allocator = inline void*;

bitstruct AllocatorCreateFlags : uint {
    bool externally_synchronized    : 0;
    bool khr_dedicated_allocation   : 1;
    bool khr_bind_memory2           : 2;
    bool ext_memory_budget          : 3;
    bool amd_device_coherent_memory : 4;
    bool buffer_device_address      : 5;
    bool ext_memory_priority        : 6;
    bool khr_maintenance4           : 7;
    bool khr_maintenance5           : 8;
    bool khr_external_memory_win32  : 9;
}

struct AllocatorCreateInfo {
    AllocatorCreateFlags     flags;
    vk::PhysicalDevice       physical_device;
    vk::Device               device;
    vk::DeviceSize           preferred_large_heap_block_size;
    vk::AllocationCallbacks* allocation_callbacks;
    void*                    device_memory_callbacks;
    vk::DeviceSize*          heap_size_limit;
    void*                    vulkan_functions;
    vk::Instance             instance;
    uint                     vulkan_api_version;
}
$assert(AllocatorCreateInfo::size == 80);

extern fn vk::Result create_allocator(AllocatorCreateInfo* info, Allocator* out) @cname("vmaCreateAllocator");
extern fn void Allocator.destroy(self) @cname("vmaDestroyAllocator");
```

(If Task 1 Step 6 measured a size other than 80, use that number in the `$assert`. `device_memory_callbacks` and `vulkan_functions` are typed `void*` because we pass null and have not bound `VmaDeviceMemoryCallbacks`/`VmaVulkanFunctions`.)

- [ ] **Step 3: Verify the raw binding compiles against `vk` and the size assert holds**

Run:
```sh
cd test && c3c compile-only --no-obj ../vma.c3i --libdir libs --lib vk ; rm -rf obj ; cd ..
```
Expected: no output / exit 0 (`Object files written…` is also fine). A `Compile time assert failed` here means the struct layout does not match the lib — revisit Step 2 with the measured size. A `No module named 'vk'` means the `--libdir/--lib` flags were dropped.

- [ ] **Step 4: Commit**

```sh
git add vma.c3i .claude/hooks/c3-syntax-check.sh
git commit -m "vma: bind raw allocator lifecycle (create/destroy) (M0)"
```

---

### Task 3: Add the idiomatic fault-returning layer

**Files:**
- Create: `vma.c3`

**Interfaces:**
- Consumes: `vma::create_allocator`, `vma::Allocator`, `vma::AllocatorCreateInfo` (Task 2); `vk::Result` and its `ERROR_*` members (from `vk`).
- Produces: `vma::check(vk::Result) -> void?` and `vma::try_create_allocator(AllocatorCreateInfo* info) -> Allocator?`. Task 4 consumes `try_create_allocator`.

- [ ] **Step 1: Write the idiomatic layer**

Create `vma.c3`:

```c3
module vma;

import vk;

faultdef
    OUT_OF_HOST_MEMORY,
    OUT_OF_DEVICE_MEMORY,
    INITIALIZATION_FAILED,
    MEMORY_MAP_FAILED,
    FEATURE_NOT_PRESENT,
    TOO_MANY_OBJECTS,
    INVALID_EXTERNAL_HANDLE,
    UNKNOWN;

<* Map a VkResult to a vma fault. Returns normally on VK_SUCCESS. *>
fn void? check(vk::Result r) {
    switch (r) {
        case vk::Result.SUCCESS:                       return;
        case vk::Result.ERROR_OUT_OF_HOST_MEMORY:      return OUT_OF_HOST_MEMORY~;
        case vk::Result.ERROR_OUT_OF_DEVICE_MEMORY:    return OUT_OF_DEVICE_MEMORY~;
        case vk::Result.ERROR_INITIALIZATION_FAILED:   return INITIALIZATION_FAILED~;
        case vk::Result.ERROR_MEMORY_MAP_FAILED:       return MEMORY_MAP_FAILED~;
        case vk::Result.ERROR_FEATURE_NOT_PRESENT:     return FEATURE_NOT_PRESENT~;
        case vk::Result.ERROR_TOO_MANY_OBJECTS:        return TOO_MANY_OBJECTS~;
        case vk::Result.ERROR_INVALID_EXTERNAL_HANDLE: return INVALID_EXTERNAL_HANDLE~;
        default:                                       return UNKNOWN~;
    }
}

<* Create an allocator, returning a vma fault instead of a raw VkResult. *>
fn Allocator? try_create_allocator(AllocatorCreateInfo* info) {
    Allocator a;
    check(create_allocator(info, &a))!;
    return a;
}
```

- [ ] **Step 2: Verify the raw + idiomatic layers compile together**

Run:
```sh
cd test && c3c compile-only --no-obj ../vma.c3i ../vma.c3 --libdir libs --lib vk ; rm -rf obj ; cd ..
```
Expected: exit 0. An `ERROR_… could not be found` means a `vk::Result` member name is wrong — re-grep `test/libs/vk.c3l/vk.c3` for the exact identifier.

- [ ] **Step 3: Commit**

```sh
git add vma.c3
git commit -m "vma: add idiomatic try_create_allocator + VkResult fault mapping (M0)"
```

---

### Task 4: Headless Vulkan bootstrap, manifest wiring, and runnable smoke test

**Files:**
- Create: `test/src/vk_bootstrap.c3`
- Modify: `test/src/main.c3`
- Modify: `manifest.json`

**Interfaces:**
- Consumes: `vma::AllocatorCreateInfo`, `vma::try_create_allocator`, `Allocator.destroy` (Tasks 2–3); `vk` instance/device API.
- Produces: `vma_smoke::HeadlessVk`, `vma_smoke::create_headless_vk() -> HeadlessVk?`, `vma_smoke::destroy_headless_vk(HeadlessVk*)`, `vma_smoke::VK_API_1_0` — the shared headless bootstrap reused by every later milestone's test.

- [ ] **Step 1: Write the headless Vulkan bootstrap**

Create `test/src/vk_bootstrap.c3`:

```c3
module vma_smoke;

import vk;

faultdef NO_PHYSICAL_DEVICE, NO_USABLE_DEVICE;

const uint VK_API_1_0 = 1 << 22;

struct HeadlessVk {
    vk::Instance       instance;
    vk::PhysicalDevice physical_device;
    vk::Device         device;
}

<* Create a headless Vulkan instance + logical device (no window/surface).
   Picks the first physical device whose logical-device creation succeeds,
   which selects a working ICD (e.g. lavapipe) under WSL's multi-ICD setup. *>
fn HeadlessVk? create_headless_vk() {
    HeadlessVk h;

    vk::ApplicationInfo app = {
        .s_type      = vk::StructureType.APPLICATION_INFO,
        .api_version = VK_API_1_0,
    };
    vk::InstanceCreateInfo ici = {
        .s_type             = vk::StructureType.INSTANCE_CREATE_INFO,
        .p_application_info = &app,
    };
    vk::try_create_instance(&ici, null, &h.instance)!;
    defer catch vk::destroy_instance(h.instance, null);

    uint count = 0;
    vk::try_enumerate_physical_devices(h.instance, &count, null)!;
    if (count == 0) return NO_PHYSICAL_DEVICE~;
    if (count > 32) count = 32;
    vk::PhysicalDevice[32] devices;
    vk::try_enumerate_physical_devices(h.instance, &count, &devices[0])!;

    float priority = 1.0;
    vk::DeviceQueueCreateInfo qci = {
        .s_type             = vk::StructureType.DEVICE_QUEUE_CREATE_INFO,
        .queue_family_index = 0,
        .queue_count        = 1,
        .p_queue_priorities = &priority,
    };
    vk::DeviceCreateInfo dci = {
        .s_type                  = vk::StructureType.DEVICE_CREATE_INFO,
        .queue_create_info_count = 1,
        .p_queue_create_infos    = &qci,
    };

    for (uint i = 0; i < count; i++) {
        vk::PhysicalDevice pd = devices[i];
        if (catch err = vk::try_create_device(pd, &dci, null, &h.device)) {
            continue;
        }
        h.physical_device = pd;
        return h;
    }
    return NO_USABLE_DEVICE~;
}

fn void destroy_headless_vk(HeadlessVk* h) {
    vk::destroy_device(h.device, null);
    vk::destroy_instance(h.instance, null);
}
```

- [ ] **Step 2: Write the smoke test**

Replace the entire contents of `test/src/main.c3` with:

```c3
module vma_smoke;

import vma;
import vk;
import std::io;

fn int main() {
    if (catch err = run()) {
        io::printn("vma smoke FAILED");
        return 1;
    }
    io::printn("vma smoke OK: allocator create/destroy");
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
    alloc.destroy();
}
```

- [ ] **Step 3: Wire the manifest**

In `manifest.json`, change the `linux-x64` target block from:
```json
    "linux-x64" : {
      // Extra flags to the linker for this target:
      "link-args" : [],
      // C3 libraries this target depends on:
      "dependencies" : [],
      // The external libraries to link for this target:
      "linked-libraries" : []
    },
```
to:
```json
    "linux-x64" : {
      // Extra flags to the linker for this target:
      "link-args" : [],
      // C3 libraries this target depends on:
      "dependencies" : [ "vk" ],
      // The external libraries to link for this target:
      "linked-libraries" : [ "VulkanMemoryAllocator", "stdc++" ]
    },
```
(`vk` is a real dependency: the binding signatures reference `vk::` types. `stdc++` is required because the VMA implementation is C++. The VMA `.a` is found via `linklib-dir`/`linked-libs/linux-x64/`. `libvulkan` is linked transitively through the `vk` dependency.)

- [ ] **Step 4: Build the smoke executable**

Run:
```sh
cd test && c3c build smoke 2>&1 | tail -20 ; cd ..
```
Expected: `Program linked to executable 'build/smoke'.`, exit 0.
- An undefined reference to `vmaCreateAllocator` means the `.a` is not being found — check `linked-libraries` and that `linked-libs/linux-x64/libVulkanMemoryAllocator.a` exists.
- Undefined `std::` / C++ symbols mean `stdc++` is missing from `linked-libraries`.
- Undefined `vk*` symbols mean the `vk` dependency (libvulkan) is not linked — confirm `dependencies` includes `vk`.

- [ ] **Step 5: Run the smoke test on a software ICD**

Run:
```sh
cd test && VK_LOADER_DRIVERS_SELECT='*lvp*' ./build/smoke ; echo "exit=$?" ; cd ..
```
Expected: prints `vma smoke OK: allocator create/destroy` and `exit=0`.
- If the loader env var is unsupported by the installed loader, retry without it: `./build/smoke` (the device-selection loop already skips ICDs whose device creation fails).
- `vma smoke FAILED` with `exit=1` means bootstrap or allocator creation returned a fault — run under `VK_LOADER_DEBUG=error` to see which ICD/stage failed.

- [ ] **Step 6: Clean build artifacts and commit**

```sh
rm -rf test/build test/obj
git add test/src/vk_bootstrap.c3 test/src/main.c3 manifest.json
git commit -m "test: headless Vulkan allocator smoke test; wire manifest (M0)"
```

---

## Done criteria

- `linked-libs/linux-x64/libVulkanMemoryAllocator.a` exists and exports `vmaCreateAllocator`.
- `vma.c3i` + `vma.c3` compile against `vk`; `$assert(AllocatorCreateInfo::size == 80)` holds.
- `cd test && c3c build smoke` links; `./build/smoke` prints the OK line and exits 0.
- M1 can now build on this: `Allocation`, `AllocationCreateInfo`, buffer create/destroy.
