#!/usr/bin/env bash
# Regression tests for guard.sh. Builds a throwaway repo under $TMPDIR; touches nothing else.
# Usage: guard-test.sh   (exit 0 = all cases pass)
set -u
here=$(cd "$(dirname "$0")" && pwd)
guard="$here/guard.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
mkdir -p "$repo/src" "$repo/tests" "$repo/.devflow"
git -C "$repo" init -q -b main
echo a > "$repo/src/a.py"; echo t > "$repo/tests/test_a.py"; echo r > "$repo/README"
git -C "$repo" add -A && git -C "$repo" -c user.email=t@t -c user.name=t commit -qm init
git -C "$repo" switch -q -c autorun/demo

SID=sess-1
marker="$repo/.devflow/demo.running"
write_marker() {
    jq -n --arg sid "$SID" --argjson dl "$1" --argjson ca "$2" \
        '{session_id:$sid, branch:"autorun/demo", commit_allowed:$ca, base_sha:"x",
          write_scope:["src/"], protected:["tests/","src/fixtures/*"], deadline:$dl}' > "$marker"
}
future=$(( $(date +%s) + 3600 ))
past=$(( $(date +%s) - 10 ))
write_marker "$future" true

pass=0; fail=0
run() { # expect sid tool json-input-fragment description
    local expect=$1 sid=$2 tool=$3 frag=$4 desc=$5 got
    printf '{"session_id":"%s","cwd":"%s","tool_name":"%s","tool_input":%s}' "$sid" "$repo" "$tool" "$frag" \
        | "$guard" >/dev/null 2>"$tmp/err"
    got=$?
    if [ "$got" = "$expect" ]; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL %s: expected %s got %s (%s)\n' "$desc" "$expect" "$got" "$(tr '\n' ' ' < "$tmp/err")"; fi
}
bash_in() { jq -cn --arg c "$1" '{command:$c}'; }
path_in() { jq -cn --arg p "$1" '{file_path:$p}'; }

# Blocked in the bound session
for c in "git push" "git -C $repo push origin x" "cd src && git push" "sh -c 'git push'" "git pull" \
         "git reset --hard" "git clean -fd" "git stash" "git rebase main" "git merge x" "git checkout main" \
         "git switch main" "git worktree add ../x" "git branch -D x" "git tag v1" "gh pr create" \
         "npm publish" "git commit --amend -m x" "git commit --no-verify -m x" "git commit -nm x" \
         "git commit -am x" "git add src/a.py && git commit -m x" "git restore --source=HEAD~1 src/a.py" \
         "git restore tests/test_a.py" "git restore README" "git restore ." "git restore" \
         "jq . $marker > /tmp/m && mv /tmp/m $marker" "echo x >> .devflow/demo.running" \
         "jq '.deadline=9999999999' $marker > $marker.new" "sed -i '' s/x/y/ $marker" "cat $marker | tee $marker.bak" \
         "cp /tmp/m $marker" "mv /tmp/m $marker"; do
    run 2 "$SID" Bash "$(bash_in "$c")" "block: $c"
done
for p in "$repo/tests/test_a.py" "$repo/README" "$repo/.devflow/demo.md" "$repo/.devflow/demo.tsv" "$HOME/.zshrc" "$repo/src/fixtures/f.json"; do
    run 2 "$SID" Write "$(path_in "$p")" "block write: $p"
done

# Allowed in the bound session
for c in "cat .devflow/demo.running" "jq -r .session_id $marker" "ls .devflow/demo.running" \
         "git status" "git diff" "git log --oneline" "git add src/a.py" "git commit -m 'fix(a): x'" \
         "git restore src/a.py" "git restore --source=HEAD src/a.py" "git branch" "pytest -q" \
         "rm .devflow/demo.running" "rm -f $marker"; do
    run 0 "$SID" Bash "$(bash_in "$c")" "allow: $c"
done
for p in "$repo/src/a.py" "src/new.py" "/tmp/scratch.txt"; do
    run 0 "$SID" Write "$(path_in "$p")" "allow write: $p"
done

# Commit checks against real state
echo b > "$repo/tests/test_a.py"; git -C "$repo" add tests/test_a.py
run 2 "$SID" Bash "$(bash_in "git commit -m x")" "block commit with staged protected file"
git -C "$repo" reset -q tests/test_a.py; git -C "$repo" checkout -q -- tests/test_a.py
echo c > "$repo/README"; git -C "$repo" add README
run 2 "$SID" Bash "$(bash_in "git commit -m x")" "block commit with staged out-of-scope file"
git -C "$repo" reset -q README; git -C "$repo" checkout -q -- README
git -C "$repo" switch -q main
run 2 "$SID" Bash "$(bash_in "git commit -m x")" "block commit off the contract branch"
git -C "$repo" switch -q autorun/demo

write_marker "$future" false
run 2 "$SID" Bash "$(bash_in "git commit -m x")" "block commit without authorization"

write_marker "$past" true
run 2 "$SID" Write "$(path_in "$repo/src/a.py")" "block write after deadline"
run 2 "$SID" Bash "$(bash_in "git commit -m x")" "block commit after deadline"
run 0 "$SID" Bash "$(bash_in "rm .devflow/demo.running")" "allow closeout after deadline"

# Other sessions and no marker: no-op
write_marker "$future" true
run 0 other-session Bash "$(bash_in "git push")" "other session unaffected"
run 0 other-session Write "$(path_in "$repo/tests/test_a.py")" "other session write unaffected"
rm -f "$marker"
run 0 "$SID" Bash "$(bash_in "git push")" "no marker: no-op"
run 0 "$SID" Bash "$(bash_in "git rebase main")" "no marker: rebase allowed"
run 0 "$SID" Bash "$(bash_in "git status")" "outside a repo is fine"

printf 'guard-test: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
