# c3vq Style Guide (Agent-Facing)

This guide is the source of truth for code style, conventions, and required tooling in the c3vq codebase. CLAUDE.md links here. When this guide and CLAUDE.md disagree, **this guide wins** and CLAUDE.md should be updated to match.

If you are an agent (Claude Code or otherwise) working in this repo, the rules below are not optional.

**Targets C3 0.8.0.** Syntax keyed to this release (e.g. type properties via `::` — `T::size`, not `T.sizeof`). C3 is pre-1.0; re-verify against release notes when the compiler is bumped.

---

## 1. Required skills

Two skills are mandatory for any non-trivial change. Skipping them is a process violation, not a style preference.

### 1.1 C3 code → `c3-expert`

You **must** invoke the `c3-expert` skill before:

- Writing any new C3 source (`.c3`, `.c3i`) or library bundle (`.c3l`)
- Modifying any existing C3 source
- Reviewing C3 code (other than trivial typo fixes)
- Editing `project.json`, manifest files, or any C3 build configuration
- Diagnosing a C3 compiler error, linker error, or `c3c` warning
- Answering a syntax/semantics question about C3 (the language drifts between releases)

The skill provides version-pinned docs, release notes, and `c3c` verification scripts. C3 is pre-1.0; do **not** rely on memorised syntax.

If you find yourself writing or reading more than ~5 lines of C3 without having consulted `c3-expert` in the current session, stop and invoke it.

### 1.2 Shader code → `shader-dev`

You **must** invoke the `shader-dev` skill before:

- Writing or modifying any GLSL shader (`resources/shaders/**/*.glsl`)
- Designing a compute dispatch, workgroup layout, barrier, or binding map
- Reviewing shader code or diagnosing a shader compile/link/runtime error
- Selecting image formats, sampler configurations, or storage qualifiers for shader-side resources
- Reasoning about DDA, raymarching, atlas indirection, or any other algorithm whose correctness depends on shader semantics

The skill captures the engine's shader conventions, debug-mode patterns, and the binding contracts between CPU `Ubo` structs and GLSL `uniform` blocks.

### 1.3 When both apply

A typical brickmap or renderer task spans CPU C3 (UBO struct, binding, command list) **and** GLSL (shader entry point, samplers, traversal). Invoke **both** skills. Order: `c3-expert` first when authoring CPU-side changes, `shader-dev` first when authoring shader-side changes. Don't guess one side from the other — the binding contract is data, write it down on both sides.

### 1.4 Other skills

- `superpowers:test-driven-development` — for any non-trivial code change, write a failing test first.
- `superpowers:systematic-debugging` — for any compiler error, shader error, GL error, or unexpected runtime behavior.
- `superpowers:verification-before-completion` — before declaring any task complete or committing.

---

## 2. Build and test

```sh
c3c build linux           # build the linux target (default debug, O0)
c3c run linux             # build + execute
c3c test linux            # run all tests under test/** for the linux target
c3c clean                 # wipe build/
c3c build linux -O3       # ad-hoc optimization override
```

`c3c compile-test <files...>` is the **ad-hoc** form for files outside `project.json`; do not use it for the project's own tests.

Verification before commit (every time):

```sh
c3c build linux && c3c test linux
```

If either fails, the change is not done. Do not commit broken builds.

### 2.1 Do not run `c3fmt` (unless explicitly asked)

`c3fmt` is the bundled C3 formatter. It is currently too aggressive for this codebase and **must not be run** — neither in-place nor for whitespace-only sweeps — unless a human collaborator has explicitly asked for it on this specific change. Specifically:

- It joins `faultdef` blocks onto a single line as long as the joined form fits under `max_line_length`, which destroys the one-fault-per-line layout we use everywhere (`src/rdi/rdi_types.c3`, `src/world/faults.c3`).
- It joins function calls with **≥ 4 arguments** onto a single line whenever they fit under `max_line_length`, which violates §6 ("≥ 4 arguments → named parameters, one per line, with a trailing comma"). §6 is a project rule about argument *count*; `c3fmt` only knows about *line length*.
- It rewrites doc-comment indentation in subtle ways that don't round-trip cleanly.
- It rewrites brace style in ways that conflict with §2.2.

If `.c3fmt` exists in the repo, treat it as historical configuration only. Hand-format new code per this guide, run `c3c build linux && c3c test linux` to verify, and rely on review (and reviewer subagents) to catch style drift. Revisit when `c3fmt` becomes argument-aware.

### 2.2 Brace style: K&R, not Allman

Opening braces go on the **same line** as the control keyword or signature, separated by one space. Closing braces sit alone at the indent of the opener. Use this style for every brace-bearing construct — functions, methods, `if`/`else`/`while`/`for`/`foreach`/`switch`, `defer`, struct/enum/union bodies, anonymous blocks.

```c3
// Good (K&R):
fn void? generate_all(&self, rdi::Device* device) {
    if (self.chunks.len == 0) {
        return;
    }
    foreach (&c : self.chunks) {
        c.state = ChunkState.GENERATING;
    }
}

struct Window {
    Surface surface;
    uint    width, height;
}
```

```c3
// Bad (Allman — do not write):
fn void? generate_all(&self, rdi::Device* device)
{
    if (self.chunks.len == 0)
    {
        return;
    }
    foreach (&c : self.chunks)
    {
        c.state = ChunkState.GENERATING;
    }
}
```

**Exception:** none. Arrow-body forms (`fn T name(...) => expr;`) and macro-body parameters (`; @body`) are not brace constructs — they keep their natural shape. Match-expression arms and struct literals also stay unchanged (no brace migration).

Existing files in the repo are a mix of K&R and Allman because earlier passes ran `c3fmt`. Don't do a sweep-rewrite — convert opportunistically when touching code for another reason, never as a whitespace-only commit.

---

## 3. Naming

| Kind                                     | Case                   | Examples                                    |
| ---------------------------------------- | ---------------------- | ------------------------------------------- |
| Variables, fields, parameters            | `snake_case`           | `voxel_size`, `next_slot`, `out_voxels`     |
| Functions, methods                       | `snake_case`           | `create_brick_atlas`, `BrickAtlas.destroy`  |
| Structs, enums, typedefs, aliases        | `PascalCase`           | `BrickAtlas`, `TextureUsage`, `Vec3u`       |
| Constants, enum values, bitfield flags   | `SCREAMING_SNAKE_CASE` | `BRICK_DIM`, `TextureUsage.SPARSE`          |
| Module names                             | lowercase, dotted      | `c3vq::world`, `c3vq::rdi::gl`              |
| File names                               | `snake_case.c3`        | `brick.c3`, `scene_format.c3`, `texture.c3` |

This matches the C3 standard library. Earlier drafts of CLAUDE.md mentioned `camelCase` — that was wrong. The codebase is `snake_case` end-to-end.

### 3.1 No milestone tags or planning terminology in code OR comments — and API requirements live in doc-strings, not inline comments

Code identifiers, file names, test names, **AND comments** must not encode development-process milestone tags or any planning terminology. `M4_*`, `M5_ATLAS_BRICKS`, `test_m5_*`, `// M5.8 — ...`, `// M-VK fills this in`, `// M6 streaming will keep ...`, `// ── M5.8 adapter thunks ──`, "regression for the M2.2a bug", "per spec §3", "future VK milestone" — all banned, in identifiers and in comments alike. They leak the project's roadmap into shipped artifacts and force renames / comment rewrites every time a milestone closes. Names and comments describe what the code does and what invariants hold, not when something landed or where the next milestone takes it.

- Bad:
  ```c3
  const Vec3u M5_ATLAS_BRICKS = { 80, 80, 80 };
  fn void test_m5_classify_world_empty() @test { /* ... */ }

  // M5.8 — rdi-local replacements for the old platform::Surface* field.
  PresentFn   present_fn;

  // ── M5.8 RDI adapter thunks ─────────────────────────────────────────
  fn bool surface_make_current_thunk(void* userdata) @private { ... }

  int _reserved;   // M-VK replaces with real init payload.
  ```
- Good:
  ```c3
  const Vec3u ATLAS_BRICKS = { 80, 80, 80 };
  fn void test_classify_world_empty() @test { /* ... */ }

  PresentFn   present_fn;   // self-describing field name — no comment needed

  // ── RDI adapter thunks ──────────────────────────────────────────────  (or drop the divider entirely)

  int _reserved;   // placeholder: structs must be non-empty in C3 0.8.0

Specs, plans, milestone documents, and commit messages **may** reference milestones — that's their job. The boundary is: anything the compiler or linker sees is milestone-free; anything the user sees in `docs/` may use the tag. Screenshot filenames in `docs/screenshots/` follow whatever existing convention is established (M4 used `m04_*.png` for archival ordering); new milestones may continue that pattern or drop it.

When porting older code that violates this rule, rename in the next change that touches the file.

**API contracts go in doc-strings.** Non-obvious preconditions, invariants, or expected ordering for a function or method live in the `<* ... *>` doc-comment immediately above the declaration — never as a `//` inline comment in the body or above a struct field. If C3 doesn't accept a doc-string on a particular construct (struct fields, enum variants), the code itself is the documentation: pick a clearer name or restructure so the constraint is enforceable rather than annotated.

```c3
// Bad — inline contract:
fn Device? install_gl_backend(GlInitArgs init, DeviceHooks hooks) {
    // Caller must have a current GL context OR pass a non-null make_current.
    // proc_loader is required.
    ...
}

// Good — doc-string contract:
<* Install the OpenGL backend.
   Preconditions: `init.proc_loader` non-null. `init.make_current` may be
   null only if the caller has already bound a context on this thread;
   otherwise it is invoked once during install. *>
fn Device? install_gl_backend(GlInitArgs init, DeviceHooks hooks) { ... }
```

---

## 4. Definition order

Within a single source file, declarations appear in this order:

1. Typedefs
2. Aliases
3. Constants
4. Enums / `constdef` / `bitstruct`
5. Structs
6. Struct methods (`fn ... Type.method(...)`)
7. Pure / free functions

Methods always come **before** pure functions, even if a pure function is the constructor. The constructor is a free function placed last in its struct's section.

Why: this puts domain names and type shims before values that use them, keeps the type's API surface (struct + methods) contiguous for readers, and pushes module-level helpers below it.

---

## 5. Types

- Avoid raw primitive types where a domain meaning exists. Define a typedef or alias instead of passing `int`/`uint` for handles, IDs, indices, etc.
  - Bad: `fn void destroy(int handle)`
  - Good: `fn void destroy(TextureHandle handle)` with `typedef TextureHandle = inline ulong;`
- Use the math aliases from `src/types.c3` (`Vec2f`, `Vec3f`, `Vec4f`, `Mat3f`, `Mat4f`, `Quatf`, `Vec2i`, `Vec3i`, `Vec4i`, `Vec3u`, `Vec4u`) instead of raw `float[N]` / `int[<N>]` / `float[N][N]`.
- For C ABI interop, use `ZString` (null-terminated `char*`) at the boundary; convert to `String` (slice) for engine-side processing via `.str_view()`.
- For shader-shared structs (UBO, SSBO), match `std140` / `std430` layout exactly. Add `$assert MyUbo::size == N;` immediately after the struct so layout drift is caught at compile time.

### 5.1 Named constants over magic numbers

A bare numeric literal in code body is a smell — the reader has to guess what `<< 10`, `512`, `0x3FFu`, or `1.0e30` means. Lift any literal that carries semantic meaning into a `const` (file-scope, `@private` if it's an implementation detail). The constant's name is the documentation.

- Bad:
  ```c3
  uint packed = ax | (ay << 10) | (az << 20);  // why 10? why 20?
  ```
- Good:
  ```c3
  const uint BRICK_HANDLE_AXIS_BITS = 10;
  uint packed = ax
      | (ay << BRICK_HANDLE_AXIS_BITS)
      | (az << (2 * BRICK_HANDLE_AXIS_BITS));
  ```

When a literal appears in **both** C3 and a shader (UBO field count, brick dim, handle bit-pack), declare the constant on **both** sides with matching names. The shader's `const uint BRICK_HANDLE_AXIS_BITS = 10u;` mirrors the C3 `const uint BRICK_HANDLE_AXIS_BITS = 10;`. Keeps the wire contract grep-able.

Exemptions — these are not "magic":

- `0` and `1` in their natural roles (loop init, increment, "first", null, false-as-zero).
- Powers of 2 used as bit positions in a `bitstruct` field declaration — the position **is** the name.
- Mathematical constants whose meaning is unambiguous in context (`2.0 * PI`, `0.5` for a midpoint).
- Test fixtures where the literal is the test data itself (`assert(parse("0042") == 42)`).
- One-shot debug values being temporarily probed; commit the named constant once the value is settled.

If you find yourself adding a comment to explain what a number means, that's the signal to convert it to a constant instead. The comment will rot; the named constant won't.

### 5.2 Construction is a free function, not a method

C3 is not object-oriented. A `Type.create(...)` constructor method imports OO ergonomics the language doesn't actually have — it's just a free function with `Type.` prepended, and the prefix invites caller code that reads as if there's an inheritance hierarchy or an implicit `this`-receiver protocol. There isn't.

Construction belongs in a free function:

- `create_brick_atlas(device, ...)` — produces a fresh `BrickAtlas`.
- `default_persp_camera(aspect)` — produces a `Camera` from default parameters.
- `build_diagnostic_scene_desc()` — produces a `SceneDesc` from procedurally generated content.
- `parse_scene_file(path)` — produces a `SceneDesc` by parsing.

Pick the verb that matches the work the function actually does (`create_*`, `default_*`, `build_*`, `parse_*`, `load_*`, `make_*`). Don't reach for `Type.create(...)` just because the result happens to be a `Type`.

- Bad:
  ```c3
  fn BrickAtlas? BrickAtlas.create(rdi::Device* device, /* ... */) { /* ... */ }
  fn Scene?      Scene.load_file(rdi::Device* device, String path)  { /* ... */ }

  // Caller — looks like OO, isn't:
  BrickAtlas atlas = BrickAtlas.create(&device, ...);
  Scene      scene = Scene.load_file(&device, path);
  ```
- Good:
  ```c3
  fn BrickAtlas? create_brick_atlas(rdi::Device* device, /* ... */) { /* ... */ }
  fn Scene?      load_file(rdi::Device* device, String path)        { /* ... */ }

  // Caller — namespaced free function, the C3 way:
  world::BrickAtlas atlas = world::create_brick_atlas(&device, ...);
  world::Scene      scene = world::load_file(&device, path);
  ```

Methods (`fn Ret Type.method(&self, ...)`) are the right tool when there's a clear `&self` receiver and the operation is naturally "an action *on* an existing instance" — e.g. `BrickAtlas.alloc_brick(&self)`, `BrickAtlas.commit_brick_pages(&self, ...)`. The `&self` parameter is the test: if the function reads or mutates an instance, method syntax is fine. If it produces a new instance from raw inputs, it's a free function.

**Lifecycle methods (`Type.destroy(&self)`) are tolerated but discouraged.** They scan as OO and they couple the type's destruction surface to method-call ergonomics, which the codebase doesn't otherwise lean on. Free `destroy_*(handle, device)` is the preferred form (see `destroy_palette`, `destroy_mesh`, `destroy_gizmo` for the established pattern). Existing `Type.destroy(&self)` methods are kept where they already exist for now; new code should prefer free destructors, and over time the existing ones should migrate.

The C library binding rules in §8 / CLAUDE.md Appendix make a deliberate exception for `Class_Method`-style C APIs (Jolt) where method syntax is the cleanest way to lift the C structure into C3. That exception is about wire-format mapping, not about modeling our own engine types — engine code stays free-function-first.

---

## 6. Function calls

- Calls with **≥ 4 arguments** OR a single-line form **> 120 characters** use named parameters, **one per line**, with a **trailing comma** after the last argument.
- Calls with ≤ 3 args that fit under 120 chars stay positional, no trailing comma.
- This applies to **call sites only**, not function definitions or `extern fn` declarations. Struct-literal field-inits already use named fields and are unaffected.

Examples:

```c3
// 3 positional args, fits — leave alone
load_palette(&device, "resources/palette.png", "main_palette");

// 4 args → named, one per line, trailing comma
load_shader(
    device:     &device,
    stage:      rdi::ShaderStage.FRAGMENT,
    path:       "resources/shaders/triangle.frag.glsl",
    debug_name: "triangle_frag",
);
```

The trailing comma keeps diffs minimal when arguments are added or reordered.

---

## 7. Module layout

- `src/main.c3` declares `module c3vq;` (root namespace).
- Sub-modules nest under that namespace and live in named subdirectories: `src/world/*.c3` declares `module c3vq::world;`, `src/rdi/gl/*.c3` declares `module c3vq::rdi::gl;`, etc.
- One module per directory. Multiple files in the same directory share the module name.
- Vendored C3 libraries go in `lib/<name>.c3l/` and are listed under `dependencies` in `project.json`.

---

## 8. C library bindings (`lib/<name>.c3l/`)

The full set of conventions for binding C libraries lives in CLAUDE.md, Appendix. Summary of the load-bearing rules:

- The **module namespace** isolates the library; the original C prefix never appears on the C3 side. `sdl::create_window`, not `sdl::SDL_CreateWindow`.
- No `@builtin` on binding declarations — that defeats the namespace.
- Functions/methods → `snake_case`. Types → `PascalCase`. Constants → `SCREAMING_SNAKE_CASE`. Always strip the C prefix.
- Strip multi-word prefixes too (`SDL_GL_*` → `sdl::gl::*` sub-module).
- For `Class_Method`-style C APIs (Jolt), use C3 method syntax: `fn Ret Type.method(&self, ...)`.
- For backend-pluggable libraries (ImGui), put each backend in its own sub-module (`imgui::gl`, `imgui::sdl`).
- The `@cname("...")` string is the real C symbol — keep prefix, casing, and punctuation verbatim. (`@extern`-as-a-rename-attribute was removed in C3 0.8.0; `@cname` replaces it.)
- Bind only the surface you actually use. The binding grows across milestones.

---

## 9. Memory

- Trust the engine allocator (`mem`) for heap allocations: `mem::new(T)`, `mem::new_array(T, n)`, paired with `defer free(p)`.
- Use `@pool() { ... }` for scope-bound temp allocations (e.g., parsers that return temp-allocated trees). Anything that must outlive the pool gets copied out before the block exits.
- `defer free(...)` on the next line after allocation, where possible. Cleanup that lives at the bottom of a function is a goto-cleanup C-ism in disguise.
- `defer catch destroy_X(handle);` on resources that must be released only on failure paths (when the success path transfers ownership to the caller).
- Never write `goto cleanup` chains. Use `defer`.

---

## 10. Error handling

C3 has optionals (`T?`) and faults (`faultdef`). The codebase uses them consistently — do not add `null` returns, sentinel values (`-1`, `0`, `INT_MIN`), `bool ok` out-params, or errno-style globals.

- Lift a fault into an optional with the **`~`** suffix: `return rdi::SLOT_TABLE_FULL~;`. (Not `?` — that's a different operator.)
- Propagate with `!`: `TextureHandle h = device.create_texture(&desc)!;`
- Catch and inspect: `if (catch err = thing) { ... }` (note the `err =` binding form — bare `if (catch thing)` is not the syntax used here).
- Force-unwrap (panics on fault): `!!`. Use sparingly; prefer `!` propagation.
- Group related faults under one `faultdef` block per module (`src/rdi/rdi_types.c3` is the canonical example).

Use **specific** faults, not a generic catch-all. `SCENE_PARSE_FAILED` / `SCENE_VALIDATION_FAILED` / `SCENE_VOXEL_DECODE_FAILED` is better than one umbrella `INVALID_SCENE`. Granular faults aid log diagnosis.

### 10.1 Runtime `assert` is for tests, not production

Runtime `assert(cond)` belongs in test code (`test/**/*.c3`), not in shipped engine code. If a production function has a precondition, postcondition, or invariant whose violation is recoverable, return a fault. If the violation is genuinely unrecoverable (the program cannot continue safely), use `unreachable()` for branches that should be impossible by construction — but reach for faults first.

- Bad (production code):
  ```c3
  fn void BrickAtlas.upload_brick(&self, /* ... */, ushort[] voxels) {
      assert(voxels.len == BRICK_VOXEL_COUNT);
      assert(!is_empty_brick_handle(handle));
      // ... record upload ...
  }
  ```
- Good:
  ```c3
  fn void? BrickAtlas.upload_brick(&self, /* ... */, ushort[] voxels) {
      if (voxels.len != BRICK_VOXEL_COUNT) return rdi::INVALID_BRICK_PAYLOAD~;
      if (is_empty_brick_handle(handle)) return rdi::INVALID_HANDLE~;
      // ... record upload ...
  }
  ```

Caller sites then propagate (`!`) or catch (`if (catch err = ...)`) — same machinery as any other fallible call. The signal is structured, the fault name appears in logs, and tests can drive the failure paths deterministically.

Why not asserts in production:

- Asserts disappear in release builds (or stop the world in debug builds), neither of which is what an engine should do when scene data is malformed.
- They bypass the project's optional/fault discipline (§10) — callers can't `catch` an assert, so no recovery path is possible.
- They mix two distinct categories — "this should never happen" vs "the caller passed something invalid". The latter is data validation and belongs in the type system or in returned faults.

Exceptions:

- **Compile-time** asserts (`$assert`) are required — they pin layout and constants at build time and never run at runtime. Use them freely (UBO `@sizeof` matches, enum cardinality, etc.).
- **Tests** (`test/**/*.c3`) use `assert(cond)` and `unreachable()` as the primary failure mechanism. The whole point of a test is to make assertion failures the visible signal.
- **`unreachable()` for exhaustive switches** over closed enums is fine — it documents that all cases are handled and gives the compiler a narrowing hint.

When porting older code that still uses `assert` for preconditions, convert to a returned fault as part of the next change that touches the function. Don't leave a mixed regime in a single module.

---

## 11. Testing

- Tests live under `test/`, one file per topic, declared `module c3vq::test;`.
- Each test function is annotated `@test` and named `test_<what_it_checks>` in `snake_case`.
- Follow TDD: write the failing test first, run `c3c test linux` to confirm failure, implement, re-run to confirm pass.
- Tests for fault paths assert the **specific** fault returned, not just "some error":
  ```c3
  if (catch err = atlas.alloc_brick()) {
      assert(err == rdi::ATLAS_FULL);
      return;
  }
  unreachable();
  ```
- Pure-CPU tests (handle math, validation, allocator slot math) need no GL context and should be exhaustive.
- Tests requiring a GL context (texture upload, sparse commit) are deferred to manual verification — flag them in the milestone plan rather than mocking the device.

---

## 12. Comments

Default to **none**. Only write a comment when:

- The code is genuinely non-obvious (unusual algorithm, workaround for a specific bug, hidden invariant, layout requirement that can't be encoded as `$assert`).
- The comment explains **why**, not what. Well-named identifiers handle "what".

Things never to comment:

- The current task, ticket, PR, or "added for X" — that belongs in commit messages.
- Language features (`// optional return type`, `// foreach over slice`).
- What well-named code already says.

Doc comments (`<* ... *>`) on public functions are welcome when they document **preconditions, side effects, or ownership** the signature can't express. Don't paraphrase the function name.

---

## 13. RDI / GL backend conventions

The render device interface (`src/rdi/`) is a vtable with a single GL backend (`src/rdi/gl/`). When extending it:

- Add a `Fn` alias in `src/rdi/rdi.c3` for any new vtable entry.
- Add the field to the `Device` struct, **grouped with related operations** (create_*, cmd_*, destroy_*).
- Wire the field in `install_gl_backend` in the matching position.
- Implement the function `@private` in the appropriate `src/rdi/gl/<topic>.c3` file.

The GL backend is **DSA throughout** (`glCreateTextures`, `glTextureStorage3D`, `glTextureParameteri`, `glTexturePageCommitmentEXT`, etc.). Do **not** introduce bound-target GL calls (`glBindTexture` + `glTexParameteri`) unless absolutely no DSA equivalent exists. When a non-DSA fallback is unavoidable, save and restore the previous binding.

Slot-table pattern: every GPU resource lives in a fixed-size `MAX_X` array of `XSlot @private` structs with `gl_name`, `desc`, `generation`, `used`, and any backend-specific metadata. Handles pack `(slot_index, generation)` into a `ulong`. `unpack(handle, &idx, &generation)` validates against `used` and `generation` mismatch.

---

## 14. Shader conventions

(See the `shader-dev` skill for the full version. This is the high-level summary.)

- `resources/shaders/<stage>/<name>.<stage>.glsl` (`rt/primary_brickmap.comp.glsl`, `blit/blit.frag.glsl`).
- `#version 460 core` minimum; rely on GL 4.6 features.
- Compute workgroup default: `local_size_x = 8, local_size_y = 8, local_size_z = 1` for 2D-pixel kernels. Adjust only with measured reason.
- Bindings are explicit and stable: `layout(binding = N, std140) uniform Foo`, `layout(binding = N) uniform sampler...`, `layout(binding = N, format) uniform image2D ...`. The CPU-side `cmd_bind_*` calls must use the same indices.
- UBO struct field order on the GLSL side mirrors the C3 struct exactly. Layout is `std140`. Any padding needed for `vec3`-followed-by-scalar is encoded as `vecN` types where the last component carries the scalar (see `BrickmapUbo.world_size.w = voxel_size`).
- Debug visualizations branch **once per pixel** at the end of the shader, not inside hot loops. Step counters returned via a result struct.
- Defensive shader checks should be cheap; CPU-side validation owns data-shape guarantees.
- Zero-vector / zero-direction safety: handle `dir == 0` explicitly (set `step = 0`, `t_delta = INF`) — never let `0 * INF` or `0 / 0` reach the math.

---

## 15. Resources

- `resources/shaders/` — GLSL source, organized by stage.
- `resources/scenes/` — `.scene` JSON assets for milestone diagnostics.
- `resources/palettes/`, `resources/textures/`, `resources/models/` — runtime assets.
- Scene file format is documented in the M4 spec (`docs/specs/2026-05-01-m4-brickmap-indirection-design-ds4p.md` §6); the parser is `src/world/scene_format.c3`. Do not invent ad-hoc on-disk formats — extend the documented one.

---

## 16. Documentation

- Specs go in `docs/specs/` as `YYYY-MM-DD-<slug>-design.md` (or `-design-<variant>.md` for alternative designs).
- Plans go in `docs/plans/` as `YYYY-MM-DD-<slug>.md` (or `-<variant>.md`).
- Milestones live in `docs/milestones/`.
- Every plan links its spec; every spec links its predecessor's spec/plan.
- Plans are executable checklists (`- [ ]` per step). Use `superpowers:executing-plans` or `superpowers:subagent-driven-development` to work through one.

---

## 17. Commits

- Conventional Commits format: `<scope>: <imperative summary>` (e.g. `world: add brick handle helpers (M4 ds4p)`).
- One logical change per commit. Don't bundle unrelated edits.
- Body explains the **why** when not obvious from the diff.
- Run the build + tests before committing. A green commit is a contract with future readers.

---

## 18. Anti-patterns to flag on sight

If you see any of these in existing code or are tempted to write them, stop:

- `null` as an error signal (use optional + fault).
- Runtime `assert(...)` for preconditions, postconditions, or invariants in production code (use a returned fault — see §10.1).
- Sentinel return values (`-1`, `0xFFFFFFFF`) outside of clearly-documented "invalid handle" constants like `NULL_TEXTURE = 0`.
- Bare numeric literals in code body where a named constant would explain the meaning (see §5.1).
- `Type.create(...)` / `Type.load_*(...)` constructor methods — use a free function instead (see §5.2). Lifecycle `Type.destroy(&self)` methods are tolerated but should migrate to free `destroy_*` over time.
- Raw `malloc` / `free` without going through `mem::new*`.
- `sizeof(T)` C-style — use `T::size` (type property) or `@sizeof(expr)` (value macro). Pre-0.8.0 `T.sizeof` / `$sizeof(expr)` are removed.
- Arrow `->` for pointer access — C3 uses `.` for both value and pointer.
- Goto-cleanup chains — use `defer`.
- Bound-target GL calls in the DSA backend.
- `if (catch foo)` without binding the error name — write `if (catch err = foo)`.
- Comments restating identifier names or explaining well-known C3 syntax.
- Camel-case identifiers in any role.
- Manual layout calculation for stdlib math types — use `Vec3f` etc. and let the compiler align.

---

## 19. When in doubt

1. Invoke `c3-expert` (for C3) or `shader-dev` (for GLSL).
2. Grep the existing codebase for similar patterns. The repo is small enough that a 3-second `rg` settles most "how do we do X here" questions.
3. Read the relevant milestone spec — design decisions are usually written down.
4. If the answer still isn't clear, ask before writing speculative code.
