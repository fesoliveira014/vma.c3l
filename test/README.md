# vma test harness

A standalone C3 consumer project that exercises the `vma` bindings against a
real window provider and Vulkan loader. **It is not part of the shipped `vma`
library** — the library manifest (`../manifest.json`) never references anything
under `test/`, so consumers of `vma` never pull these dependencies.

## Layout

```
test/
├── project.json        consumer project: deps [vma, sdl3, vk], search path = libs/
├── src/main.c3         smoke harness (module vma_smoke)
└── libs/
    ├── vma.c3l   ->     symlink to the repo root (the library under test)
    ├── sdl3.c3l        git submodule — module `sdl`, links SDL3
    └── vk.c3l          git submodule — module `vk`, links Vulkan
```

Dependencies resolve by their manifest `provides` name (`vma`, `sdl3`, `vk`),
not by directory name — that is why a single `libs/` search path finds all
three, including the repo root reached through the `vma.c3l` symlink.

## First-time setup

The `sdl3` and `vk` bindings are git submodules. After cloning:

```sh
git submodule update --init test/libs
```

(`git clone --recursive` does this at clone time.)

The `vma.c3l` entry is a committed relative symlink (`-> ../..`); on Windows it
needs `git config core.symlinks true` and either Developer Mode or an elevated
shell at clone time.

## Verify

Compile-check (resolves all deps, no linking — works without system SDL3/Vulkan):

```sh
cd test
c3c compile-only src/main.c3 --libdir libs --lib vma --lib sdl3 --lib vk --target linux-x64
```

Full build (the current stub references only compile-time constants, so it
links with no system libraries):

```sh
cd test
c3c build smoke
```

## Scope

The current harness only proves the three dependencies resolve and compile
together. The real allocator round-trip — SDL window → Vulkan instance/device →
`vma` allocator → buffer alloc/free — lands once:

1. the `vma` surface (create/destroy allocator, create/destroy buffer) is bound
   in `../vma.c3i`, and
2. a compiled VMA static library exists in `../linked-libs/<target>/`.

At that point `src/main.c3` grows the real flow and `c3c build smoke` will need
the system SDL3 and Vulkan loaders present to link and run.

## Note on the syntax-check hook

`.claude/hooks/c3-syntax-check.sh` compile-checks `.c3` files in isolation on
write. Files here `import` external library modules (`vma`, `sdl`, `vk`), which
that isolated check cannot see, so it reports false "No module named …" errors.
Verify these files with the project-aware commands above instead.
