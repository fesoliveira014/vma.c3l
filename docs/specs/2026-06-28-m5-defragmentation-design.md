# M5 — Defragmentation (design)

Date: 2026-06-28
Status: approved (brainstorming)
Predecessor: [M4 design](2026-06-28-m4-custom-pools-design.md) · [roadmap](2026-06-26-vma-binding-roadmap-design.md)

Bind VMA's defragmentation API — the begin → pass-loop → end lifecycle that
relocates live allocations to reduce fragmentation. After M5 a consumer can drive
a full defragmentation cycle through the binding; the runtime test exercises the
lifecycle headless by choosing the IGNORE move-operation (no GPU copy required).

## Context

M0–M4 shipped the allocator, allocation/buffer/image paths, host-memory access,
statistics & budget, and custom pools. M5 reuses M4's `Pool` (a defragmentation
can target one custom pool via `DefragmentationInfo.pool`) and M1's `Allocation`
(moves reference source/destination allocations). It introduces four new
layout-pinned structs, a handle, two enums, a flags bitstruct, and a callback
function-pointer alias. Defragmentation statistics are their own struct
(`DefragmentationStats`), distinct from M3's `Statistics`.

## The shape — two cruxes

1. **The pass functions return `VK_SUCCESS` or `VK_INCOMPLETE`, both non-error.**
   `vmaBeginDefragmentationPass` returns `VK_SUCCESS` when defragmentation is
   finished (no moves) and `VK_INCOMPLETE` when the pass produced moves to process;
   `vmaEndDefragmentationPass` returns `VK_SUCCESS` when done and `VK_INCOMPLETE`
   when another pass is needed. Routing these through M0's `check()` would map
   `VK_INCOMPLETE` to the catch-all `UNKNOWN` fault — wrong. The idiomatic pass
   wrappers therefore return **`bool?`** meaning "incomplete / more to do": a
   private `check_pass()` maps `SUCCESS`→`false`, `INCOMPLETE`→`true`, and any real
   error through `check()`. The consumer loop reads cleanly:
   ```
   while (alloc.try_begin_defragmentation_pass(ctx, &pass)!) {
       foreach (&m : pass.moves[:pass.move_count]) m.operation = IGNORE;
       if (!alloc.try_end_defragmentation_pass(ctx, &pass)!) break;
   }
   ```

2. **`begin_defragmentation` returns `VkResult`** (→ standard `try_*` + `check()`),
   while **`end_defragmentation` returns `void`** with a stats out-param → used raw
   with no wrapper, matching the `free_memory`/`unmap_memory` precedent for void
   teardowns.

## Settled decisions

1. **Scope: the roadmap M5 surface** — `DefragmentationContext` handle,
   `DefragmentationInfo`/`DefragmentationMove`/`DefragmentationPassMoveInfo`/
   `DefragmentationStats` structs, `DefragmentationFlags` bitstruct,
   `DefragmentationMoveOperation` enum, the break-callback PFN alias, and the four
   begin/end/begin-pass/end-pass functions.
2. **Pass wrappers return `bool?`** (true = incomplete / more to do); a private
   `check_pass()` does the `SUCCESS`/`INCOMPLETE`/error mapping (crux #1).
3. **Runtime test uses `DefragmentationMoveOperation.IGNORE`.** The harness has no
   command-buffer/queue infrastructure, so the test never physically moves data
   (which would need `vkCmdCopyBuffer` + sync). Setting every move to `IGNORE`
   drives the full pass loop with no GPU work and leaves the source buffer handles
   valid. Real GPU-copy defragmentation (`operation = COPY`) is out of scope.
4. **The test fragments a small-block custom pool** so the pass loop actually
   iterates: a `Pool` with a small `block_size` spreads a few buffers across
   several blocks; freeing a subset fragments it; defragmenting that pool is likely
   to produce moves. Producing moves is *best-effort* (lavapipe-dependent) — the
   loop is structural and handles a zero-move result correctly.
5. **`end_defragmentation` is used raw** (void + stats out-param); only
   `begin_defragmentation` and the two pass functions get idiomatic wrappers.
6. **Four new layout-pinned structs**, each `$assert`-pinned with `N` from the size
   probe.

## Binding surface

All signatures below are illustrative; exact forms are re-read from
`vk_mem_alloc.h` and verified with `c3-expert` at plan time per `add-binding`.

### New types — layout-pinned (`vma_defrag.c3i`)

```
typedef DefragmentationContext = inline void*;

enum DefragmentationMoveOperation : int {
    COPY,      // 0 — default; app recreated+copied, srcAllocation will point to new place
    IGNORE,    // 1 — app cannot move it; reserved dst freed, src unchanged
    DESTROY,   // 2 — app abandoned it; dst freed and src destroyed
}

bitstruct DefragmentationFlags : uint {
    bool algorithm_fast      : 0;   // 0x1
    bool algorithm_balanced  : 1;   // 0x2 (default algorithm)
    bool algorithm_full      : 2;   // 0x4
    bool algorithm_extensive : 3;   // 0x8
}

alias CheckDefragmentationBreakFunc = fn vk::Bool32(void* user_data);

struct DefragmentationInfo {
    DefragmentationFlags          flags;
    Pool                          pool;                     // null = default pools
    vk::DeviceSize                max_bytes_per_pass;       // 0 = no limit
    uint                          max_allocations_per_pass; // 0 = no limit
    CheckDefragmentationBreakFunc pfn_break_callback;       // optional, may be null
    void*                         break_callback_user_data;
}
$assert(DefragmentationInfo::size == 48);

struct DefragmentationMove {
    DefragmentationMoveOperation operation;          // mutable: app sets COPY/IGNORE/DESTROY
    Allocation                   src_allocation;
    Allocation                   dst_tmp_allocation;  // temporary; valid only during the pass
}
$assert(DefragmentationMove::size == 24);

struct DefragmentationPassMoveInfo {
    uint                 move_count;
    DefragmentationMove* moves;   // VMA-owned array of move_count, valid for the pass
}
$assert(DefragmentationPassMoveInfo::size == 16);

struct DefragmentationStats {
    vk::DeviceSize bytes_moved;
    vk::DeviceSize bytes_freed;
    uint           allocations_moved;
    uint           device_memory_blocks_freed;
}
$assert(DefragmentationStats::size == 24);
```

`DefragmentationFlagBits`' `ALGORITHM_MASK` / `MAX_ENUM` entries are not flags and
are not bound. `DefragmentationInfo.pool` is M4's `Pool`; `*_allocation` fields are
M1's `Allocation`.

### Raw externs (`vma_defrag.c3i`)

```
fn vk::Result Allocator.begin_defragmentation(self, DefragmentationInfo* info, DefragmentationContext* out_ctx) @cname("vmaBeginDefragmentation");
fn void       Allocator.end_defragmentation(self, DefragmentationContext ctx, DefragmentationStats* out_stats) @cname("vmaEndDefragmentation");
fn vk::Result Allocator.begin_defragmentation_pass(self, DefragmentationContext ctx, DefragmentationPassMoveInfo* pass_info) @cname("vmaBeginDefragmentationPass");
fn vk::Result Allocator.end_defragmentation_pass(self, DefragmentationContext ctx, DefragmentationPassMoveInfo* pass_info) @cname("vmaEndDefragmentationPass");
```

### Idiomatic (`vma_defrag.c3`)

```
fn DefragmentationContext? Allocator.try_begin_defragmentation(self, DefragmentationInfo* info);
fn bool? Allocator.try_begin_defragmentation_pass(self, DefragmentationContext ctx, DefragmentationPassMoveInfo* pass_info);  // true = moves to process
fn bool? Allocator.try_end_defragmentation_pass(self, DefragmentationContext ctx, DefragmentationPassMoveInfo* pass_info);    // true = another pass needed
fn bool? check_pass(vk::Result r) @private;   // SUCCESS->false, INCOMPLETE->true, else check(r)!
```

`end_defragmentation` is used raw (void + out-param). The move array is read/written
through `pass_info.moves[:pass_info.move_count]`; setting `.operation` writes back
into VMA's array, which `end_defragmentation_pass` reads.

## Testing

Extend the headless smoke (`test/src/main.c3`) with one path, `defrag_round_trip`,
exit 0 on lavapipe:

1. `idx = try_find_memory_type_index_for_buffer_info(&bi, &ai)` (M4); create a
   `Pool { memory_type_index = idx, block_size = SMALL_BLOCK }` so each block holds
   only a couple of buffers.
2. Create `DEFRAG_BUFFERS` buffers from the pool (`ai.pool = pool`), tracked in an
   array with a parallel `live[]` flag; a single `defer` destroys every still-live
   buffer (safe under fault — `destroy_buffer` tolerates the zero handles of any
   not-yet-created slot).
3. Fragment: destroy every other buffer, clearing its `live[]` flag.
4. `ctx = try_begin_defragmentation({ .flags = { .algorithm_balanced = true }, .pool = pool })`.
5. Run the pass loop, bounded by `MAX_DEFRAG_PASSES` (exceeding it returns
   `DEFRAG_RUNAWAY`): each pass sets every move's `operation = IGNORE`, then
   `try_end_defragmentation_pass`; break when either pass call reports done (false).
6. `end_defragmentation(ctx, &stats)`; the `defer` frees the surviving buffers;
   destroy the pool.

**Assertions:** the lifecycle completes without fault; the loop terminates within
the bound; `ctx` is non-null. Because moves are IGNORE-d, `stats.allocations_moved`
stays 0, so a non-zero move count is *best-effort* (encouraged by the small-block
fragmentation, not required). New smoke fault: `DEFRAG_RUNAWAY`. Named constants:
`SMALL_BLOCK`, `DEFRAG_BUFFERS`, `MAX_DEFRAG_PASSES`.

## File layout

```
vma_defrag.c3i   (new)  context handle, 2 enums, flags bitstruct, PFN alias, 4 structs + $asserts, 4 raw externs
vma_defrag.c3    (new)  try_begin_defragmentation, try_begin/end_defragmentation_pass (bool?), private check_pass
scripts/vma_size_probe.cpp (+)  4 defrag struct sizes (48/24/16/24)
scripts/build-vma.sh       (+)  4 expect_size entries
test/src/main.c3           (+)  defrag_round_trip path; updated success message
```

`vma.c3` is unchanged — `check()` is reused and `check_pass` lives in
`vma_defrag.c3`. No struct retypes.

## Out of scope (later milestones)

- Real GPU-move defragmentation (`operation = COPY` with `vkCmdCopyBuffer` and a
  command pool / command buffer / queue / fence) — the headless harness has none;
  the IGNORE path is the only one exercised.
- Runtime use of the break callback (`pfn_break_callback` is passed null).
- `algorithm_fast` / `algorithm_full` / `algorithm_extensive` flags are bound but
  not runtime-exercised (the test uses `balanced`).
- Virtual allocator (M6); M7 misc (`vmaSetCurrentFrameIndex`, aliasing,
  `vmaCreateBufferWithAlignment`, memory pages, allocation name/user-data setters,
  `vmaGetAllocationMemoryProperties`) and cross-target `linked-libs/` population.
