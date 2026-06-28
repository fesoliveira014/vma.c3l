# Task 4 Report — Pool Round-Trip Smoke (M4)

## Status: DONE

---

## Final-review fixes

### Fix 1 — Corruption result mapping (correctness)

VMA 3.3.0 returns `VK_ERROR_UNKNOWN` (not `VK_ERROR_VALIDATION_FAILED_EXT`) when
corruption is detected. The previous `check()` case for `ERROR_VALIDATION_FAILED_EXT`
was dead code. Changes:

- `vma_pool.c3`: replaced `try_check_pool_corruption` to handle `ERROR_UNKNOWN` →
  `CORRUPTION_DETECTED~` locally, with a doc-string explaining the VMA behavior.
- `vma.c3`: removed the dead `ERROR_VALIDATION_FAILED_EXT` case from `check()`.
  `CORRUPTION_DETECTED` remains in the `faultdef` block.

### Fix 2 — Drop unused `device` parameter

`pool_round_trip` in `test/src/main.c3` never used its `vk::Device device` parameter.
Removed from both the function signature (`fn void? pool_round_trip(vma::Allocator alloc)`)
and the call site in `run()` (`pool_round_trip(alloc)!;`).

### Fix 3 — Doc-comments on find-memtype wrappers

Added `<* ... *>` doc-strings to the three `try_find_memory_type_index*` wrappers in
`vma_memory.c3`:
- `try_find_memory_type_index`
- `try_find_memory_type_index_for_buffer_info`
- `try_find_memory_type_index_for_image_info`

### Fix 4 — Spec sync

Updated decision #4 and the `check()` extension section in
`docs/specs/2026-06-28-m4-custom-pools-design.md` to reflect that VMA 3.3.0 reports
detected corruption as `VK_ERROR_UNKNOWN`, handled locally in `try_check_pool_corruption`,
not via a `check()` case for `ERROR_VALIDATION_FAILED_EXT`.

### Smoke build + run

```sh
cd /home/fesol/source/repos/c3vma.c3l/test && c3c build smoke 2>&1 | tail -3 && VK_LOADER_DRIVERS_SELECT='*lvp*' ./build/smoke ; echo "exit=$?" ; cd ..
```

Output:
```
Program linked to executable 'build/smoke'.
vma smoke OK: map + image + manual buffer/reqs/image + stats + pool
exit=0
```

---

## Build output (Step 5)

```
Program linked to executable 'build/smoke'.
exit=0
```

## Run output (Step 6)

Command:
```sh
cd /home/fesol/source/repos/c3vma.c3l/test && VK_LOADER_DRIVERS_SELECT='*lvp*' ./build/smoke ; echo "exit=$?"
```

Output:
```
vma smoke OK: map + image + manual buffer/reqs/image + stats + pool
exit=0
```

Lavapipe ICD (`VK_LOADER_DRIVERS_SELECT='*lvp*'`). Printed the exact OK line, exit 0.

---

## Files changed

- `test/src/main.c3` (+38 lines, -2 lines)
  - `faultdef` block: added `POOL_NAME_MISMATCH` and `POOL_STATS_EMPTY`
  - `run()`: added `pool_round_trip(alloc, h.device)!;` after `stats_round_trip`
  - `main()`: updated success string to include `+ pool`
  - Appended `pool_round_trip` function (doc-comment + body)

---

## Commit

`476f89d` — `test: pool round-trip (find type, create, allocate-from, stats, name) (M4)`

---

## Self-review findings

- All four edits match the brief verbatim.
- `pool_round_trip` exercises the full path: `try_find_memory_type_index_for_buffer_info` → `try_create_pool` → `set_pool_name`/`pool_name` round-trip → `try_create_buffer` from pool → `pool_statistics`/`pool_detailed_statistics` non-zero check → `try_check_pool_corruption` accepting `FEATURE_NOT_PRESENT`.
- Hook fired twice during intermediate edits (call site existed before the definition was appended) — expected, the hook validates syntax per-edit and the function was not yet defined at that point.
- No style violations: K&R braces, `snake_case`, doc-string on the new function, no milestone tags in identifiers/inline comments, no runtime `assert`, `defer` for all resource cleanup.

## Concerns

None.

---

*(Previous milestone task-4 reports follow for archival reference.)*

---

# Task 4 Report (M3) — Vulkan 1.1 bump + full headless smoke

## Files changed

| File | Action |
|---|---|
| `test/src/vk_bootstrap.c3` | Added `VK_API_1_1` constant; changed `ApplicationInfo.api_version` to `VK_API_1_1` |
| `test/src/main.c3` | Full replacement — expanded smoke: batch flush/invalidate, manual_reqs_bind, manual_image_bind, stats_round_trip |

## Build output (`c3c build smoke`)

```
Program linked to executable 'build/smoke'.
exit=0
```

## Smoke run

Command:
```
cd /home/fesol/source/repos/c3vma.c3l/test && VK_LOADER_DRIVERS_SELECT='*lvp*' ./build/smoke ; echo "exit=$?"
```

Output:
```
vma smoke OK: map + image + manual buffer/reqs/image + stats
exit=0
```

Lavapipe ICD (`VK_LOADER_DRIVERS_SELECT='*lvp*'`). Printed the exact OK line, exit 0.

## Commit

SHA: `132766c`
Subject: `test: stats round-trip + deferred runtime coverage on a 1.1 device (M3)`

## Self-review findings

- Code transcribed verbatim from the brief (compile-checked during planning). No deviations.
- K&R brace style maintained throughout; no `c3fmt` run.
- No milestone tags in identifiers or inline comments.
- `defer` used for all resource cleanup; no goto-cleanup chains.
- `VK_API_1_1` used in both `vk_bootstrap.c3` (instance creation) and `main.c3` (`AllocatorCreateInfo.vulkan_api_version`).
- `stats_round_trip` validates all M3 accessors: `statistics()`, `heap_budgets()`, `info()`, `physical_device_properties()`, `memory_properties()`, `memory_type_properties()`, `stats_string()`.
- `manual_reqs_bind` exercises `try_allocate_memory` + `try_bind_buffer_memory2`.
- `manual_image_bind` exercises `try_allocate_memory_for_image` + `try_bind_image_memory2`.
- Batch flush/invalidate (`try_flush_allocations`, `try_invalidate_allocations`) exercised in `map_round_trip` over a one-element set.
- M2 paths (`try_allocate_memory_for_buffer` + v1 `try_bind_buffer_memory`) kept in `manual_alloc_bind`.

## Concerns

None. All six sub-test functions pass on lavapipe. The two by-design out-of-scope paths (non-null `pNext` on `bind_*2`; v1 `bind_image_memory`) remain unexercised, as noted in the brief's done criteria.

---

## Final-review fix: GPU_ONLY rationale

Commit: `3852ed8` — `test: restore GPU_ONLY-over-AUTO rationale in manual-path doc-strings (M3)`

Two doc-strings amended (no code body changes):
- `manual_alloc_bind`: notes that `AUTO*` usage is invalid for `vmaAllocateMemoryForBuffer` (no buffer-usage context — VMA hard-asserts).
- `manual_reqs_bind`: notes that `AUTO*` usage is invalid for `vmaAllocateMemory` from raw requirements (no buffer/image-usage context — VMA hard-asserts).

---

# Task 4 Report (M2) — Three-path round-trip test

## Files Changed

| File | Action |
|---|---|
| `test/src/main.c3` | Replaced entirely — three-path smoke: map+flush+copy, image, manual alloc/bind |

## Build output (`c3c build smoke`)

```
Program linked to executable 'build/smoke'.
```

Exit 0. No undefined symbols, no warnings. Linked on first attempt.

## Smoke run

```
VK_LOADER_DRIVERS_SELECT='*lvp*' ./build/smoke
vma smoke OK: buffer + map + image + manual alloc/bind
exit=0
```

## Issue encountered and fix

First run crashed with a VMA hard assertion:

```
smoke: /home/fesol/opt/vulkan/x86_64/include/vma/vk_mem_alloc.h:4053:
bool FindMemoryPreferences(...): Assertion `0 && "VMA_MEMORY_USAGE_AUTO*
values can only be used with functions like vmaCreateBuffer, vmaCreateImage
so that the details of the created resource are known."` failed.
exit=134
```

Fix: in `manual_alloc_bind`, `MemoryUsage.AUTO` → `MemoryUsage.GPU_ONLY`.

## Commit

SHA: `8020166`
Subject: `test: map/flush/copy + image + manual alloc/bind round-trips (M2)`

## Review-fix pass

Commit `3e9aa0e`: `test: fix manual-path teardown order, map/unmap balance; tidy M2 smoke (M2)`

Fixes: LIFO teardown order in `manual_alloc_bind`; map/unmap balance via scoped `defer`; named `MAP_CHECK_BYTES` constant; dropped dead null checks in `image_round_trip`.
