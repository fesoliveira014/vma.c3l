#!/bin/sh
# PostToolUse(Write|Edit) hook: syntax/semantic-check an edited C3 file with c3c.
# Exit 2 + stderr feeds the compiler error back to Claude so it can fix immediately.
#
# Two modes:
#  - File under a consumer project (an ancestor dir has project.json, e.g. test/):
#    compile it WITH that project's dependency-search-paths (--libdir) and
#    dependencies (--lib) so external `import`s resolve. Without this the isolated
#    check reports false "No module named …" for every library import.
#  - Bare library file (no ancestor project.json, e.g. the root vma.c3i): compile
#    in isolation. Pure syntax and self-contained declarations are checked
#    accurately; cross-file type references in a multi-file module may report
#    unresolved-symbol false positives — the consuming project's full build is the
#    source of truth for those.
f=$(python3 -c 'import sys,json;print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' 2>/dev/null)
case "$f" in
  *.c3|*.c3i) ;;
  *) exit 0 ;;
esac
command -v c3c >/dev/null 2>&1 || exit 0

# Walk up from the file's directory looking for the nearest project.json.
proj_dir=""
d=$(dirname "$f")
while [ "$d" != "/" ] && [ -n "$d" ]; do
  if [ -f "$d/project.json" ]; then
    proj_dir="$d"
    break
  fi
  d=$(dirname "$d")
done

if [ -n "$proj_dir" ]; then
  # Project-aware check: build --libdir/--lib args from project.json.
  lib_args=$(python3 - "$proj_dir/project.json" <<'PY' 2>/dev/null
import sys, json, re
try:
    raw = open(sys.argv[1]).read()
    raw = re.sub(r'//[^\n]*', '', raw)              # strip // comments
    raw = re.sub(r',(\s*[}\]])', r'\1', raw)        # strip trailing commas
    cfg = json.loads(raw)
except Exception:
    sys.exit(0)
out = []
for p in cfg.get("dependency-search-paths", []):
    out += ["--libdir", p]
for d in cfg.get("dependencies", []):
    out += ["--lib", d]
print("\n".join(out))
PY
)
  # shellcheck disable=SC2086
  set --
  IFS='
'
  for a in $lib_args; do set -- "$@" "$a"; done
  unset IFS
  out=$(cd "$proj_dir" && c3c compile-only --no-obj "$@" "$f" 2>&1)
  rc=$?
  rm -rf "$proj_dir/obj" 2>/dev/null
else
  out=$(c3c compile-only --no-obj "$f" 2>&1)
  rc=$?
  rm -rf obj 2>/dev/null
fi

if [ "$rc" -ne 0 ]; then
  printf 'c3c compile-only failed for %s:\n%s\n' "$f" "$out" >&2
  exit 2
fi
