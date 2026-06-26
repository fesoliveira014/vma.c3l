---
name: add-binding
description: Add a VMA C-API binding to the vma module following docs/bindings_guidelines.md and docs/style.md. Use when binding a new VMA function, handle, struct, or enum (e.g. "bind vmaCreateAllocator", "/add-binding vmaAllocateMemory"). Reads the real vk_mem_alloc.h for exact signatures, then applies the project's naming, opaque-vs-declared, @extern, and compile-check rules.
---

# Add a VMA binding

Bind the requested VMA symbol(s) into the `vma` module. Input: `$ARGUMENTS` (a C symbol, a feature, or a description of what to bind). If empty, ask what to bind.

## 1. Read the real signature — never bind from memory

The VMA C header is the source of truth. Transcribing a parameter or return type wrong corrupts memory silently across the ABI — the worst and hardest-to-find binding bug — so always read the actual declaration before writing any C3.

- Header: `$VULKAN_SDK/include/vma/vk_mem_alloc.h` (on this machine: `/home/fesol/opt/vulkan/x86_64/include/vma/vk_mem_alloc.h`). If `$VULKAN_SDK` is unset, `find / -iname vk_mem_alloc.h` or ask the user where it is.
- It is ~19k lines — grep for the specific symbol, never read the whole file:
  - function → `grep -nA12 'VMA_CALL_POST vmaCreateAllocator' "$VULKAN_SDK/include/vma/vk_mem_alloc.h"`
  - handle → `grep -n 'VK_DEFINE_HANDLE(VmaAllocator)'` (a `VK_DEFINE_HANDLE` means an opaque pointer handle)
  - struct/enum → `grep -nA30 'typedef struct VmaAllocatorCreateInfo'`
- Copy the exact parameter list and return type out of the header. Do not paraphrase from memory.

Before writing C3: invoke the `c3-expert` skill (C3 is pre-1.0; this repo targets 0.8.0), and read `docs/bindings_guidelines.md` plus the naming / C-binding sections of `docs/style.md`. Those are the source of truth and override anything here.

## 2. Vulkan types are not VMA's to define

VMA signatures lean on core Vulkan types — `VkResult`, `VkDevice`, `VkBuffer`, `VkDeviceMemory`, `VkBufferCreateInfo`, and so on. These belong to Vulkan, not VMA. Pull them from the project's Vulkan binding (a dependency) if one exists. If none exists yet, declare only the minimal handles/enums the signature needs, alongside the VMA binding, and flag that they should migrate to a real Vulkan binding later. Never redefine a type the project already provides.

## 3. Translate (per bindings_guidelines.md)

Strip the `Vma` prefix on the C3 side; keep the real symbol verbatim in `@extern`:

- **Functions** → `snake_case`, prefix stripped. Most of VMA acts on a handle (`vmaCreateAllocator`, `vmaDestroyAllocator`, `vmaAllocateMemory` all take or produce `VmaAllocator`), so use method syntax `fn Ret Type.method(...)`. Keep the C return type faithful — VMA returns `VkResult`; do NOT fault-wrap inside the extern, that is an engine-side helper's job.
  ```c3
  extern fn VkResult Allocator.create(AllocatorCreateInfo* info, Allocator* out) @extern("vmaCreateAllocator");
  extern fn void     Allocator.destroy(&self) @extern("vmaDestroyAllocator");
  ```
  (`VkResult` here resolves to the Vulkan binding's type — see §2.)
- **Types** → `PascalCase`, strip `Vma` and any `_t`. Use `@opaque` when C3 only holds and passes the pointer — every `VK_DEFINE_HANDLE` handle (`Allocator`, `Allocation`, `Pool`, `DefragmentationContext`). Fully declare a struct ONLY when C3 reads its fields, matching the C layout field-for-field.
- **Constants / enum values** → `SCREAMING_SNAKE_CASE`, prefix stripped. Group into a C3 `enum` (or `bitstruct` for flag bits) where the C set is closed — VMA's `Vma*FlagBits` are the case in point.
- **No `@builtin`** on any declaration — it promotes the symbol to global scope and defeats the `vma` namespace.

## 4. Verify

- Layout-pin every fully-declared struct: add `$assert T::size == N;` immediately after it. This is 0.8.0 syntax (`::size`, not `.sizeof`). Get `N` from the C side — a 3-line C probe that prints `sizeof(VmaAllocatorCreateInfo)` compiled against the header. A mismatch is exactly the silent-corruption bug the assert exists to catch.
- Syntax-check the edited file in isolation (there is no `project.json` in this library package):
  ```sh
  c3c compile-only --no-obj <file.c3i>
  ```
  Fix any error before finishing, and remove any `obj/` directory it leaves behind. (The repo's PostToolUse hook runs this same check on every edit, so a clean manual run should match.)

## 5. Scope

Bind only what was asked plus the types those signatures require to compile. VMA is large — do not mirror it wholesale; the binding grows incrementally across changes. When done, report which symbols you added, which Vulkan types you pulled in or stubbed, and any struct sizes you pinned with `$assert`.
