# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

C3 language bindings for the Vulkan Memory Allocator (VMA) C library, packaged as a C3 **library** (`.c3l`), not a standalone program.

- `manifest.json` — library manifest; `provides` the `vma` module, `linklib-dir` is `linked-libs`. (The package directory is `c3vma.c3l`, but C3 resolves a dependency by its `provides` name, so the module — and the consumer's dependency entry — is `vma`, not `c3vma`.)
- `vma.c3i` — binding declarations (`module vma`). Currently a stub.
- `linked-libs/<target>/` — per-platform compiled VMA libs (16 targets, currently empty).
- `test/` — a standalone consumer project used only to exercise the bindings locally (SDL3 window provider + `vk` Vulkan loader). It is **not** part of the shipped library: `manifest.json` never references it, so consumers of `vma` never pull `sdl3`/`vk`. See `test/README.md`.

The library package itself has no `project.json` and no standalone build — it is consumed by another project that lists `vma` under its `dependencies` and runs `c3c build`. Do not assume the build/test commands in `docs/style.md` (`c3c build linux`, `c3c test linux`) run in *this* repo; they describe the consuming project. To syntax-check a binding file in isolation, use `c3c compile-only --no-obj <file>`. To compile-check the binding *in use* against the test deps, run from `test/`: `c3c compile-only src/main.c3 --libdir libs --lib vma --lib sdl3 --lib vk --target linux-x64`.

## Authoring rules — read before writing any C3

These two guides are the source of truth and override this file where they conflict:

@docs/style.md
@docs/bindings_guidelines.md

Load-bearing points:

- **Invoke the `c3-expert` skill** before writing, editing, or reviewing any C3, or diagnosing a c3c error. C3 is pre-1.0; syntax drifts. This repo targets **C3 0.8.0** (e.g. `T::size`, not `T.sizeof`).
- **Do not run `c3fmt`** — it is too aggressive for this codebase. Hand-format per `docs/style.md` (K&R braces, naming, one-fault-per-line).
- **Namespace isolates the library.** The C prefix never appears on the C3 side: `vma::create_allocator`, not `vmaCreateAllocator`. Functions `snake_case`, types `PascalCase`, constants `SCREAMING_SNAKE_CASE` — all with the C prefix stripped. No `@builtin`.
- **`@extern("...")` holds the real C symbol verbatim** (keep `vma` prefix, exact casing): `extern fn ... Allocator.create(...) @extern("vmaCreateAllocator");`.
- **Bind incrementally** — only the surface actually used; the binding grows over time.
