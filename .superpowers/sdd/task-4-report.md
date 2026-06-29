# Task 4 Report: CI cross-build workflow + windows manifest + docs (M7)

**Status: DONE**

---

## Step 2: YAML parse result

```
yaml ok
```

`python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/build-vma-libs.yml')); print('yaml ok')"` → exit 0.

## Step 3: manifest.json windows-x64 edit

Changed `windows-x64` from empty arrays to:
- `"dependencies" : [ "vk" ]`
- `"linked-libraries" : [ "VulkanMemoryAllocator" ]`

Mirrors the `linux-x64` structure (linux also has `"stdc++"` in linked-libraries for GCC; Windows/MSVC links the C++ runtime automatically so that entry is omitted).

## Step 4: Manifest consistency + linux smoke

### json.load (strict) result

```
json.decoder.JSONDecodeError: Expecting property name enclosed in double quotes: line 3 column 3 (char 26)
```

Expected — `manifest.json` uses `//` comments (a c3c extension). Strict JSON parsers reject them.

**Eyeball consistency check:** The `windows-x64` block after the edit is structurally identical to the other 15 target blocks; the only change is the two previously-empty arrays now carry values consistent with the `linux-x64` pattern.

### Linux smoke build+run (verbatim)

```
Program linked to executable 'build/smoke'.
vma smoke OK: virtual + map + image + manual buffer/reqs/image + stats + pool + defrag + misc
exit=0
```

Linux build unaffected. `c3c build smoke` linked cleanly; `./build/smoke` printed the full OK line and exited 0 on lavapipe.

## Files changed

- **Created:** `.github/workflows/build-vma-libs.yml` — two-job workflow (linux-x64 g++, windows-x64 MSVC) with size-probe sanity gate and upload-artifact steps.
- **Modified:** `manifest.json` — `windows-x64` target wired with `vk` dependency and `VulkanMemoryAllocator` library.
- **Created:** `docs/ci-cross-build.md` — enablement doc: workflow trigger, windows enablement steps, binding surface note.

## Commit

`2ffa205` — `ci: build-vma-libs workflow (linux + windows artifacts); wire windows-x64 manifest; enablement docs (M7)`

Branch: `vma-m7-misc-ci`

## Self-review findings

No issues found. The YAML is syntactically valid (python3 yaml.safe_load ok). The manifest edit is structurally consistent with all surrounding targets and does not disturb the linux build. The docs match the brief verbatim.

## Part B note

**Part B is authored, not run.** There is no GitHub remote in this workspace and no Windows toolchain; the `build-vma-libs.yml` workflow has been authored and committed but has not been executed. It will build linux + windows VMA static libs only when pushed to a GitHub remote with Actions enabled.

---

## Final-review fixes

Five post-review edits applied to `.github/workflows/build-vma-libs.yml` and `vma_misc.c3`.

| # | File | Change |
|---|------|--------|
| 1 | `build-vma-libs.yml` | MSVC compile flag: `/Fo:vma_impl.obj` → `/Fovma_impl.obj` (canonical no-colon form; colon form may write to a path literally named `:vma_impl.obj`) |
| 2 | `build-vma-libs.yml` | Added `retention-days: 180` to the linux-x64 `upload-artifact` step |
| 3 | `build-vma-libs.yml` | Added `retention-days: 180` to the windows-x64 `upload-artifact` step |
| 3b | `build-vma-libs.yml` | Extended the "Size-probe sanity" step to also check `AllocationInfo2 == 72` |
| 4 | `vma_misc.c3` | `try_check_corruption` doc-string: replaced "Returns normally on SUCCESS or (accepted) FEATURE_NOT_PRESENT when detection is off" with precise wording clarifying FEATURE_NOT_PRESENT is raised (not returned normally) |
| 5 | `vma_misc.c3` | `try_allocate_memory_pages` doc-string: replaced "same nonzero length" with "same length (an empty batch is a no-op)" to match the actual code |

### Verification results

**YAML parse:**
```
yaml ok
```

**Smoke build + run:**
```
Program linked to executable 'build/smoke'.
vma smoke OK: virtual + map + image + manual buffer/reqs/image + stats + pool + defrag + misc
exit=0
```

**Commit:** `ci+docs: canonical MSVC /Fo, artifact retention, AllocationInfo2 CI probe; precise wrapper doc-strings (M7)`
