# CI cross-build (linux-x64, windows-x64)

The `.github/workflows/build-vma-libs.yml` workflow compiles the VMA static lib
(`scripts/vma_impl.cpp`, the same impl TU used locally) for two targets and uploads
each as a build artifact:

- `libVulkanMemoryAllocator-linux-x64` → `libVulkanMemoryAllocator.a`
- `VulkanMemoryAllocator-windows-x64` → `VulkanMemoryAllocator.lib`

It runs on manual dispatch (Actions → "build-vma-libs" → Run workflow) and on pushes
that touch `scripts/vma_impl.cpp`, `scripts/vma_size_probe.cpp`, or the workflow
itself. It requires a GitHub remote — it does not run from a local-only checkout.

Header versions are pinned via the `VMA_TAG` / `VULKAN_HEADERS_TAG` env vars; bump
them together when updating VMA.

## Enabling the windows target

The `windows-x64` manifest target is already wired (`dependencies: ["vk"]`,
`linked-libraries: ["VulkanMemoryAllocator"]`), but the lib itself is an artifact, not
committed. To make a windows consumer link:

1. Run the workflow and download the `VulkanMemoryAllocator-windows-x64` artifact.
2. Commit `VulkanMemoryAllocator.lib` to `linked-libs/windows-x64/`.
3. Windows consumers of `vma` then link it the same way linux-x64 already does.

The linux-x64 lib is already built and committed (`linked-libs/linux-x64/`); the
workflow can refresh it (download the linux artifact and replace the committed `.a`).

## Binding surface

As of M7 the full VMA `extern "C"` surface is bound, except two functions absent from
the build (`vmaGetMemoryWin32Handle` — needs `VMA_EXTERNAL_MEMORY_WIN32`; and
`vmaImportVulkanFunctionsFromVolk` — volk integration). The other 13 manifest targets
beyond linux-x64/windows-x64 are not yet populated.
