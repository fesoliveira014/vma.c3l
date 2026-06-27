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
trap 'rm -f "$OUT/vma_impl.o"' EXIT
echo "Building VMA static lib -> $OUT/libVulkanMemoryAllocator.a"
"$CXX" -std=c++17 -O2 -fPIC -c "$ROOT/scripts/vma_impl.cpp" \
    -I"$VULKAN_SDK/include" \
    -o "$OUT/vma_impl.o"
ar rcs "$OUT/libVulkanMemoryAllocator.a" "$OUT/vma_impl.o"
sz=$("$CXX" -std=c++17 -I"$VULKAN_SDK/include" "$ROOT/scripts/vma_size_probe.cpp" -o "$OUT/vma_size_probe" && "$OUT/vma_size_probe")
rm -f "$OUT/vma_size_probe"
if [ "$sz" != "80" ]; then
    echo "ERROR: sizeof(VmaAllocatorCreateInfo) = $sz, expected 80 (VMA_EXTERNAL_MEMORY must be 0). vma.c3i \$assert will mismatch." >&2
    exit 1
fi
echo "Done."
