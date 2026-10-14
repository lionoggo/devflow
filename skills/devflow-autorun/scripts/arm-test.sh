#!/usr/bin/env bash
# Regression tests for arm.sh. Builds throwaway repos under $TMPDIR; touches nothing else.
set -u
here=$(cd "$(dirname "$0")" && pwd)
arm="$here/arm.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export DEVFLOW_NO_CAFFEINATE=1 CLAUDE_CODE_SESSION_ID=sess-arm-test
good="$tmp/settings.json"
jq -n '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"$HOME/.agents/skills/devflow-autorun/scripts/guard.sh"}]}]}}' > "$good"
echo '{}' > "$tmp/empty.json"
export DEVFLOW_SETTINGS="$good"

pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL %s\n' "$1"; fi; }

contract() { # repo slug [extra lines replacing the defaults]
    cat > "$1/.devflow/$2.md" <<EOF
# 自动运行契约：$2

- 目标：make a.txt say done
- 完成条件：
  - P1：\`grep -qx done src/a.txt\` → exit 0
- 写入范围：${3:-\`src/\`}
- 受保护路径：${4:-\`tests/\`、\`docs/\`}
- 分支：autorun/$2；允许本地提交：是（push、合并、发布始终禁止）
- 预算：最长 2 小时，最多 10 轮
- 基线：P1 FAIL
EOF
}
repo() {
    local r="$tmp/$1"
    mkdir -p "$r/src" "$r/tests" "$r/.devflow"
    git -C "$r" init -q -b main
    echo a > "$r/src/a.txt"; echo t > "$r/tests/t.txt"
    git -C "$r" add -A && git -C "$r" -c user.email=t@t -c user.name=t commit -qm init
    echo "$r"
}

# success
r=$(repo ok)
contract "$r" demo
out=$("$arm" "$r" demo 2>&1); code=$?
m="$r/.devflow/demo.running"
ok "arms a clean repo" '[ "$code" = 0 ]'
ok "switches to the contract branch" '[ "$(git -C "$r" symbolic-ref --short HEAD)" = autorun/demo ]'
ok "marker binds this session" '[ "$(jq -r .session_id "$m")" = sess-arm-test ]'
ok "marker base is HEAD" '[ "$(jq -r .base_sha "$m")" = "$(git -C "$r" rev-parse HEAD)" ]'
ok "marker scope and protected" '[ "$(jq -c "[.write_scope,.protected]" "$m")" = "[[\"src/\"],[\"tests/\",\"docs/\"]]" ]'
ok "marker contract hash" '[ "$(jq -r .contract_sha256 "$m")" = "$(shasum -a 256 "$r/.devflow/demo.md" | cut -d" " -f1)" ]'
ok "deadline from budget" '[ $(( $(jq .deadline "$m") - $(date +%s) )) -gt 7000 ] && [ $(( $(jq .deadline "$m") - $(date +%s) )) -le 7200 ]'
ok "commit allowed" '[ "$(jq .commit_allowed "$m")" = true ]'
ok "exclude has .devflow/" 'grep -qxF .devflow/ "$r/.git/info/exclude"'
ok "start row logged" 'tail -1 "$r/.devflow/demo.tsv" | grep -q "start	armed	make a.txt say done	session sess-arm-test, base .*guard self-test ok	baseline: P1 FAIL"'
ok "check.sh accepts the armed state" '"$here/check.sh" "$r" demo >/dev/null'
ok "summary printed" 'printf "%s" "$out" | grep -q "^armed demo"'
"$arm" "$r" demo >/dev/null 2>&1; code=$?
ok "refuses when a marker exists" '[ "$code" != 0 ] && [ -f "$m" ]'

# refusals leave no marker
r=$(repo missing)
contract "$r" demo
sed -i '' '/^- 预算/d' "$r/.devflow/demo.md"
"$arm" "$r" demo >/dev/null 2>&1; code=$?
ok "missing field refused" '[ "$code" != 0 ] && [ ! -e "$r/.devflow/demo.running" ]'
ok "missing field leaves branch alone" '[ "$(git -C "$r" symbolic-ref --short HEAD)" = main ]'

r=$(repo overlap)
contract "$r" demo '`src/`' '`src/a.txt`'
"$arm" "$r" demo >/dev/null 2>&1; code=$?
ok "writable and protected overlap refused" '[ "$code" != 0 ] && [ ! -e "$r/.devflow/demo.running" ]'

r=$(repo untick)
contract "$r" demo 'src/' '`tests/`'
"$arm" "$r" demo >/dev/null 2>&1; code=$?
ok "scope without backticks refused" '[ "$code" != 0 ] && [ ! -e "$r/.devflow/demo.running" ]'

r=$(repo dirty)
contract "$r" demo
echo x > "$r/src/b.txt"
"$arm" "$r" demo >/dev/null 2>&1; code=$?
ok "dirty worktree refused" '[ "$code" != 0 ] && [ ! -e "$r/.devflow/demo.running" ]'

r=$(repo noguard)
contract "$r" demo
DEVFLOW_SETTINGS="$tmp/empty.json" "$arm" "$r" demo >/dev/null 2>&1; code=$?
ok "unregistered guard refused and marker removed" '[ "$code" != 0 ] && [ ! -e "$r/.devflow/demo.running" ] && [ ! -e "$r/.devflow/demo.tsv" ]'

r=$(repo nosession)
contract "$r" demo
CLAUDE_CODE_SESSION_ID= "$arm" "$r" demo >/dev/null 2>&1; code=$?
ok "no session id refused" '[ "$code" != 0 ] && [ ! -e "$r/.devflow/demo.running" ]'

# existing branches
r=$(repo ahead)
contract "$r" demo
git -C "$r" switch -q -c autorun/demo && echo b > "$r/src/a.txt" && git -C "$r" -c user.email=t@t -c user.name=t commit -qam step && git -C "$r" switch -q main
"$arm" "$r" demo >/dev/null 2>&1; code=$?
ok "descendant branch is reused" '[ "$code" = 0 ] && [ "$(jq -r .base_sha "$r/.devflow/demo.running")" = "$(git -C "$r" rev-parse autorun/demo)" ]'

r=$(repo diverged)
contract "$r" demo
git -C "$r" switch -q -c autorun/demo && echo b > "$r/src/a.txt" && git -C "$r" -c user.email=t@t -c user.name=t commit -qam step && git -C "$r" switch -q main
echo c > "$r/src/c.txt" && git -C "$r" add -A && git -C "$r" -c user.email=t@t -c user.name=t commit -qm other
"$arm" "$r" demo >/dev/null 2>&1; code=$?
ok "diverged branch refused" '[ "$code" != 0 ] && [ ! -e "$r/.devflow/demo.running" ] && [ "$(git -C "$r" symbolic-ref --short HEAD)" = main ]'

printf 'arm-test: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
