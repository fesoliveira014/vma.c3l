#!/bin/sh
# Assemble a minimal Vulkan SDK-shaped include tree for building the VMA static lib:
#   <outdir>/include/vulkan/...      (Vulkan-Headers, VULKAN_HEADERS_TAG)
#   <outdir>/include/vma/vk_mem_alloc.h (VMA, VMA_TAG)
# Point VULKAN_SDK at <outdir> and run scripts/build-vma.sh (or the windows variant).
set -eu
OUT="${1:?usage: fetch-vma-headers.sh <outdir>}"
: "${VMA_TAG:=v3.3.0}"
: "${VULKAN_HEADERS_TAG:=v1.3.296}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git clone -q --depth 1 --branch "$VULKAN_HEADERS_TAG" https://github.com/KhronosGroup/Vulkan-Headers.git "$TMP/vh"
git clone -q --depth 1 --branch "$VMA_TAG" https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator.git "$TMP/vma"
mkdir -p "$OUT/include/vma"
cp -R "$TMP/vh/include/." "$OUT/include/"
cp "$TMP/vma/include/vk_mem_alloc.h" "$OUT/include/vma/"
echo "headers: VMA $VMA_TAG, Vulkan-Headers $VULKAN_HEADERS_TAG -> $OUT/include"
