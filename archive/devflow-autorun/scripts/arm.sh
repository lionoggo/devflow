#!/usr/bin/env bash
# Arm a devflow-autorun run after the user's explicit go.
# Usage: arm.sh <repo-root> <slug>
# Checks the contract and the worktree, prepares the branch, writes the marker, self-tests the guard,
# logs the start row, and keeps the Mac awake until the deadline.
# On any failure it removes the marker it wrote and exits non-zero; nothing else is undone.
# Env: CLAUDE_CODE_SESSION_ID (required); DEVFLOW_SETTINGS (default ~/.claude/settings.json);
#      DEVFLOW_NO_CAFFEINATE=1 (tests only).
set -u
here=$(cd "$(dirname "$0")" && pwd)
fail() { printf 'arm: %s\n' "$1" >&2; exit 1; }

[ "$#" -eq 2 ] || fail "usage: arm.sh <repo-root> <slug>"
root=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || fail "not a git repository: $1"
slug=$2
sid=${CLAUDE_CODE_SESSION_ID:-}
[ -n "$sid" ] || fail "CLAUDE_CODE_SESSION_ID is not set; run this from the Claude Code session that will run the loop"
contract="$root/.devflow/$slug.md"
marker="$root/.devflow/$slug.running"
log="$root/.devflow/$slug.tsv"
[ -f "$contract" ] || fail "no contract: $contract"
[ -e "$marker" ] && fail "a marker already exists: $marker"

# 1. Contract fields (strict, fixed prefixes).
fields=$(python3 -I - "$contract" <<'PY'
import json, re, sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
if not lines or not lines[0].startswith("# 自动运行契约："):
    sys.exit("first line must start with # 自动运行契约：")
out = {}
def ticked(v):
    return re.findall(r"`([^`]+)`", v)
for line in lines[1:]:
    if m := re.match(r"^- 目标：\s*(.+)$", line):
        out.setdefault("目标", m.group(1).strip())
    elif m := re.match(r"^- 写入范围：(.*)$", line):
        out["写入范围"] = ticked(m.group(1))
    elif m := re.match(r"^- 受保护路径：(.*)$", line):
        out["受保护路径"] = ticked(m.group(1))
    elif m := re.match(r"^- 分支：\s*`?([^`；;\s]+)`?\s*[；;]\s*允许本地提交：\s*(是|否)", line):
        out["分支"], out["允许本地提交"] = m.group(1), m.group(2) == "是"
    elif m := re.match(r"^- 预算：\s*最长\s*([0-9.]+)\s*小时", line):
        out["小时"] = float(m.group(1))
    elif m := re.match(r"^- 基线：\s*(.*)$", line):
        out["基线"] = m.group(1).strip()
missing = [k for k in ("写入范围", "受保护路径", "分支", "小时") if not out.get(k)]
if missing:
    sys.exit("contract is missing or malformed: " + ", ".join(missing)
             + " (see references/contract.md for the exact form)")
for w in out["写入范围"]:
    for p in out["受保护路径"]:
        a, b = w.rstrip("/") + "/", p.rstrip("/") + "/"
        if a.startswith(b) or b.startswith(a):
            sys.exit(f"a path is both writable and protected: {w} / {p}")
print(json.dumps(out, ensure_ascii=False))
PY
) || fail "contract check failed (see above)"
get() { printf '%s' "$fields" | jq -r "$1"; }
branch=$(get '.["分支"]')
hours=$(get '.["小时"]')

# 2. Worktree clean outside .devflow/.
dirty=$(git -C "$root" status --porcelain --untracked-files=all | awk '{ p=substr($0,4) } p !~ /^"?\.devflow\// { print p }')
[ -z "$dirty" ] || fail "worktree is not clean outside .devflow/:
$dirty"

# 3. Branch: create from HEAD, or switch to an existing one that is HEAD or its descendant.
head=$(git -C "$root" rev-parse HEAD)
cur=$(git -C "$root" symbolic-ref --short -q HEAD || true)
if [ "$cur" != "$branch" ]; then
    if git -C "$root" rev-parse -q --verify "refs/heads/$branch" >/dev/null; then
        git -C "$root" merge-base --is-ancestor "$head" "refs/heads/$branch" \
            || fail "branch $branch exists but is not HEAD or a descendant of it; resolve it by hand"
        git -C "$root" switch -q "$branch" || fail "cannot switch to $branch"
    else
        git -C "$root" switch -q -c "$branch" || fail "cannot create $branch"
    fi
fi
base=$(git -C "$root" rev-parse HEAD)

# 4. Keep run files out of git.
exclude="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
mkdir -p "$(dirname "$exclude")"
grep -qxF '.devflow/' "$exclude" 2>/dev/null || printf '.devflow/\n' >> "$exclude"

# 5. Marker.
now=$(date +%s)
deadline=$(python3 -I -c 'import sys; print(int(float(sys.argv[1]) + float(sys.argv[2]) * 3600))' "$now" "$hours")
printf '%s' "$fields" | jq --arg sid "$sid" --arg base "$base" --argjson dl "$deadline" \
    --arg sha "$(shasum -a 256 "$contract" | cut -d' ' -f1)" \
    '{session_id:$sid, branch:.["分支"], commit_allowed:(.["允许本地提交"] // false), base_sha:$base,
      contract_sha256:$sha, write_scope:.["写入范围"], protected:.["受保护路径"], deadline:$dl}' > "$marker" \
    || fail "cannot write the marker"
undo() { rm -f "$marker"; fail "$1"; }

# 6. Guard self-test: registered in settings, and blocks a tag listing for this session in this repo.
settings=${DEVFLOW_SETTINGS:-$HOME/.claude/settings.json}
guard_cmd='$HOME/.agents/skills/devflow-autorun/scripts/guard.sh'
jq -e --arg g "$guard_cmd" '[.hooks.PreToolUse[]?.hooks[]?.command] | index($g)' "$settings" >/dev/null 2>&1 \
    || undo "the guard hook is not registered in $settings (run install.sh --check)"
jq -n --arg s "$sid" --arg c "$root" '{session_id:$s, cwd:$c, tool_name:"Bash", tool_input:{command:"git tag --list"}}' \
    | "$here/guard.sh" >/dev/null 2>&1
[ "$?" -eq 2 ] || undo "guard self-test did not block 'git tag --list'"

# 7. Start row.
"$here/log.sh" "$log" start "armed" "$(get '.["目标"] // ""')" \
    "session $sid, base $base, guard self-test ok" "baseline: $(get '.["基线"] // "see contract"')" \
    || undo "cannot write the start row"

# 8. Keep the Mac awake until the deadline.
if [ "${DEVFLOW_NO_CAFFEINATE:-}" != 1 ] && command -v caffeinate >/dev/null; then
    nohup caffeinate -i -t $((deadline - now)) >/dev/null 2>&1 &
fi

# 9. Summary.
printf 'armed %s\n  branch %s, base %s\n  deadline %s\n  write %s\n  protected %s\n  log %s\n' \
    "$slug" "$branch" "${base:0:7}" "$(date -r "$deadline" '+%Y-%m-%d %H:%M')" \
    "$(get '.["写入范围"] | join(" ")')" "$(get '.["受保护路径"] | join(" ")')" "$log"
