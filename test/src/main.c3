module vma_smoke;

import vma;
import sdl;
import vk;

<* Smoke harness for the vma bindings.

   Purpose: prove the three test dependencies — `vma` (the library under test,
   resolved through the `libs/vma.c3l` symlink to the repo root), `sdl3`
   (module `sdl`), and `vk` — resolve and compile together under one project.

   The real allocator round-trip (SDL window -> Vulkan instance/device ->
   vma allocator -> buffer alloc/free) lands once the vma surface
   (create/destroy allocator) is bound and a compiled VMA static lib exists in
   `linked-libs/<target>/`. Until then this only references compile-time
   constants from `sdl` and `vk` so it builds and links with no system libs.

   Verify without linking system libraries:
     c3c compile-only src/main.c3 --libdir libs --lib vma --lib sdl3 --lib vk --target linux-x64 *>
fn int main() {
    int reachable = sdl::MAJOR_VERSION + vk::MAX_MEMORY_TYPES;
    return reachable > 0 ? 0 : 1;
}
