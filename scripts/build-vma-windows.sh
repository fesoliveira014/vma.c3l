#!/usr/bin/env sh
# Build the VMA static library for windows-x64 with MSVC (cl/lib on PATH via
# vcvars, msvc-dev-cmd, or a VS developer shell; run from git-bash). Vulkan
# core headers come from VULKAN_HEADERS or VULKAN_SDK; the VMA header dir
# (containing vma/vk_mem_alloc.h) from VMA_INCLUDE or VULKAN_SDK/include.
# cl/lib options use the '-' prefix so git-bash performs no path conversion.
set -eu
: "${VULKAN_HEADERS:=${VULKAN_SDK:-}}"
[ -n "$VULKAN_HEADERS" ] || { echo "set VULKAN_HEADERS or VULKAN_SDK" >&2; exit 1; }
: "${VMA_INCLUDE:=${VULKAN_SDK:+$VULKAN_SDK/include}}"
[ -n "$VMA_INCLUDE" ] || { echo "set VMA_INCLUDE to a dir containing vma/vk_mem_alloc.h" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/linked-libs/windows-x64"
mkdir -p "$OUT"
# cl -Fo/-Fe and lib -out need Windows-form paths; MSYS only auto-converts
# whole arguments that start with '/'.
WOUT="$(cygpath -w "$OUT")"
trap 'rm -f "$OUT/vma_impl.obj" "$OUT/vma_size_probe.exe" "$OUT/vma_size_probe.obj"' EXIT

echo "Building VMA static lib -> $OUT/VulkanMemoryAllocator.lib"
cl -nologo -std:c++17 -O2 -MD -EHsc -c "$ROOT/scripts/vma_impl.cpp" \
    -I"$VULKAN_HEADERS/include" -I"$VMA_INCLUDE" \
    -Fo"$WOUT\\vma_impl.obj"
lib -nologo -out:"$WOUT\\VulkanMemoryAllocator.lib" "$WOUT\\vma_impl.obj"

cl -nologo -std:c++17 -EHsc "$ROOT/scripts/vma_size_probe.cpp" \
    -I"$VULKAN_HEADERS/include" -I"$VMA_INCLUDE" \
    -Fo"$WOUT\\vma_size_probe.obj" -Fe"$WOUT\\vma_size_probe.exe"
sizes=$("$OUT/vma_size_probe.exe")
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
expect_size DefragmentationInfo 48
expect_size DefragmentationMove 24
expect_size DefragmentationPassMoveInfo 16
expect_size DefragmentationStats 24
expect_size VirtualBlockCreateInfo 24
expect_size VirtualAllocationCreateInfo 32
expect_size VirtualAllocationInfo 24
expect_size AllocationInfo2 72
echo "Done."
