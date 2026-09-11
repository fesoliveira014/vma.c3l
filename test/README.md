# vma test harness

A standalone C3 consumer project that exercises the `vma` bindings end to end
against a real Vulkan device. It is **headless** — no window or surface — so it
runs against any Vulkan loader, including a software ICD such as Mesa's lavapipe,
with no GPU required.

**It is not part of the shipped `vma` library.** The library manifest
(`../manifest.json`) never references anything under `test/`, so consumers of
`vma` never pull these dependencies.

## Layout

```
test/
├── project.json          consumer project: deps [vma, vk], search path = libs/
├── src/
│   ├── vk_bootstrap.c3   creates a headless Vulkan instance + logical device
│   └── main.c3           the smoke harness (module vma_smoke)
└── libs/
    ├── vma.c3l   ->       symlink to the repo root (the library under test)
    └── vk.c3l            opt-in git submodule — module `vk`, Vulkan types/loader
```

Dependencies resolve by their manifest `provides` name (`vma`, `vk`), not by
directory name — a single `libs/` search path finds both, including the repo root
reached through the `vma.c3l` symlink.

## First-time setup

The Vulkan binding is pinned as an opt-in test submodule. Recursive consumer
clones skip it. Initialize it explicitly before working on this harness:

```sh
git submodule update --init --checkout test/libs/vk.c3l
```

The `vma.c3l` entry is a committed relative symlink (`-> ../..`); on Windows it
needs `git config core.symlinks true` and either Developer Mode or an elevated
shell at clone time.

## Build and run

Compile-check (resolves all deps, no linking):

```sh
cd test
c3c compile-only src/main.c3 src/vk_bootstrap.c3 \
  --libdir libs --lib vma --lib vk --target linux-x64
```

Build and run the smoke. Linking needs the VMA static lib in
`../linked-libs/linux-x64/` (not tracked in git: build it with
`../scripts/build-vma.sh` or take it from a release) and a `libvulkan`; running
needs a working ICD on the loader's path:

```sh
cd test
c3c build smoke
VK_LOADER_DRIVERS_SELECT='*lvp*' ./build/smoke   # select the lavapipe software ICD
```

On success it prints a single `vma smoke OK: …` line and exits 0.

The `smoke-windows` target is the same program for `windows-x64`. CI builds it
with the MSVC-built `../linked-libs/windows-x64/VulkanMemoryAllocator.lib` and
runs it against lavapipe from
[mesa-dist-win](https://github.com/pal1000/mesa-dist-win) with the LunarG
Vulkan runtime as loader; see the `windows` job in `.github/workflows/ci.yml`.

## What it covers

`main.c3` drives the full binding surface in one run: the virtual allocator
(device-free), buffer/image create + map/flush/copy, manual allocate + bind, the
statistics and budget queries, custom pools, a defragmentation pass, and the misc
calls (allocation naming, memory pages, aliasing, …). The virtual-allocator path
runs first, before any Vulkan device exists, to show it needs none.

## Note on isolated syntax checks

`c3c compile-only --no-obj <file>` on a single file here reports false
"No module named …" errors, because these files `import` external library
modules (`vma`, `vk`) that an isolated check cannot see. Verify them with the
project-aware commands above instead.
