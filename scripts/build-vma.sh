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
"$CXX" -std=c++17 -I"$VULKAN_SDK/include" "$ROOT/scripts/vma_size_probe.cpp" -o "$OUT/vma_size_probe"
sizes=$("$OUT/vma_size_probe")
rm -f "$OUT/vma_size_probe"
echo "$sizes"
expect_size() {
    got=$(printf '%s\n' "$sizes" | awk -v n="$1" '$1 == n { print $2 }')
    if [ "$got" != "$2" ]; then
        echo "ERROR: sizeof(Vma$1) = $got, expected $2 (VMA_EXTERNAL_MEMORY must be 0). \$assert in the binding will mismatch." >&2
        exit 1
    fi
}
expect_size AllocatorCreateInfo 80
expect_size Statistics 24
expect_size DetailedStatistics 64
expect_size TotalStatistics 3136
expect_size Budget 40
expect_size AllocatorInfo 24
expect_size PoolCreateInfo 56
echo "Done."
