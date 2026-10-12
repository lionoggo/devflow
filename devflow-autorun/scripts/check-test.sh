#!/usr/bin/env bash
# Regression tests for check.sh. Builds a throwaway repo under $TMPDIR; touches nothing else.
set -u
here=$(cd "$(dirname "$0")" && pwd)
check="$here/check.sh"
log="$here/log.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
r="$tmp/r"
mkdir -p "$r/src" "$r/tests" "$r/.devflow"
git -C "$r" init -q -b main
echo a > "$r/src/a.py"; echo t > "$r/tests/t.py"
git -C "$r" add -A && git -C "$r" -c user.email=t@t -c user.name=t commit -qm init
git -C "$r" switch -q -c autorun/d
echo "contract" > "$r/.devflow/d.md"
base=$(git -C "$r" rev-parse HEAD)
hash=$(shasum -a 256 "$r/.devflow/d.md" | cut -d' ' -f1)
jq -n --arg b "$base" --arg h "$hash" --argjson dl $(( $(date +%s) + 600 )) \
    '{session_id:"s", branch:"autorun/d", commit_allowed:true, base_sha:$b, contract_sha256:$h,
      write_scope:["src/"], protected:["tests/"], deadline:$dl}' > "$r/.devflow/d.running"

pass=0; fail=0
expect() { # expected-exit description [mode]
    local out got
    out=$("$check" "$r" d ${3:-}); got=$?
    if [ "$got" = "$1" ]; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL %s: expected %s got %s (%s)\n' "$2" "$1" "$got" "$(echo "$out" | tr '\n' ' ')"; fi
}
reset_tree() { git -C "$r" checkout -q -- . ; git -C "$r" clean -qfd -e .devflow; }

expect 0 "clean armed run"
echo b > "$r/src/a.py";            expect 0 "in-scope edit mid-iteration"
                                   expect 1 "in-scope uncommitted edit at closeout" closeout
reset_tree
echo x > "$r/tests/t.py";          expect 1 "protected test edited through any tool"
reset_tree
echo y > "$r/README";              expect 1 "out-of-scope file"
reset_tree
echo "relaxed" >> "$r/.devflow/d.md"; expect 1 "contract changed after arming"
echo "contract" > "$r/.devflow/d.md"; expect 0 "contract restored"
echo c > "$r/src/a.py"; git -C "$r" add src/a.py; git -C "$r" -c user.email=t@t -c user.name=t commit -qm c
                                   expect 1 "unlogged commit"
"$log" "$r/.devflow/d.tsv" A1 fix why "commit $(git -C "$r" rev-parse --short HEAD)" ok
                                   expect 0 "logged commit"
                                   expect 0 "clean tree at closeout" closeout
echo z > "$r/tests/t.py"; git -C "$r" add tests/t.py; git -C "$r" -c user.email=t@t -c user.name=t commit -qm z
"$log" "$r/.devflow/d.tsv" A1 bad why "commit $(git -C "$r" rev-parse --short HEAD)" ok
                                   expect 1 "protected file in commits since base"

printf 'check-test: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
