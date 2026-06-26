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
