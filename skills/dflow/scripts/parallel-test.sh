#!/usr/bin/env bash
# Tests for parallel.sh against a throwaway repo with real git worktrees.
set -u
here=$(cd "$(dirname "$0")" && pwd); ps="$here/parallel.sh"; pass=0; fail=0
ok() { pass=$((pass+1)); }; bad() { fail=$((fail+1)); echo "FAIL $*"; }
expect() { local want=$1 desc=$2; shift 2; out=$("$@" 2>&1); got=$?; [ "$got" = "$want" ] && ok || bad "$desc: exit $got, want $want: $out"; }
t=$(mktemp -d "${TMPDIR:-/tmp}/parallel-test.XXXXXX"); trap 'rm -rf "$t"' EXIT
r="$t/repo"; git init -q "$r"; cd "$r"; git config user.email t@t; git config user.name t
mkdir -p app tests; echo base > app/core.py; echo t > tests/t.py; echo readme > README.md
git add -A; git commit -qm base; base=$(git rev-parse HEAD)
mkdir -p .dflow; printf 'slug: demo\nbranch: main\nbase: %s\ndeadline: 2099-01-01T00:00:00Z\nallow: app/* README.md\nprotect: tests/*\n\n# goal\n' "$base" > .dflow/demo.md
row() { printf '%s\t-\t%s\t%s\t%s\t-\t%s\t-\t0\t-\n' "$1" "$2" "$3" "$4" "$5" >> .dflow/demo.units.tsv; }

expect 0 "prepare" "$ps" prepare demo
grep -qx '.claude/worktrees/' "$(git rev-parse --git-path info/exclude)" && ok || bad "exclude line"
[ -z "$(git status --porcelain)" ] && ok || bad "prepare left the tree dirty"

# overlap
row a "app/a.py" planned - -; row b "app/b.py" planned - -
expect 0 "disjoint" "$ps" overlap demo
row c "app/*" planned - -
expect 1 "wildcard overlaps file" "$ps" overlap demo
sed -i '' '/^c	/d' .dflow/demo.units.tsv
row d "tests/x.py" planned - -
out=$("$ps" overlap demo); echo "$out" | grep -q "OUTSIDE-ALLOW d" && echo "$out" | grep -q "PROTECTED d" && ok || bad "allow/protect not checked: $out"
sed -i '' '/^d	/d' .dflow/demo.units.tsv

# two worker worktrees off base
git worktree add -q -b wa "$t/wa" "$base"; git worktree add -q -b wb "$t/wb" "$base"
( cd "$t/wa"; echo A > app/a.py; git add -A; git commit -qm "unit a" )
( cd "$t/wb"; echo B > app/b.py; echo out > README.md; git add -A; git commit -qm "unit b" )
sed -i '' "s/^a	\(.*\)	planned	-	-	/a	\1	dispatched	$base	-	/; s/^b	\(.*\)	planned	-	-	/b	\1	dispatched	$base	-	/" .dflow/demo.units.tsv
awk -F'\t' -v OFS='\t' 'NR>1 && $1=="a"{$7="wa"} NR>1 && $1=="b"{$7="wb"} {print}' .dflow/demo.units.tsv > .dflow/x && mv .dflow/x .dflow/demo.units.tsv

expect 0 "scope ok" "$ps" scope demo a
out=$("$ps" scope demo b); [ $? = 1 ] && echo "$out" | grep -q "OUTSIDE README.md" && ok || bad "scope should flag README: $out"

# land a cleanly, commit it
expect 0 "land a" "$ps" land demo a
[ "$(cat app/a.py)" = A ] && [ -n "$(git diff --cached --name-only)" ] && ok || bad "land a did not stage"
git add app/a.py && git commit -qm "unit a"
# unland: land b then undo it, including the new file
awk -F'\t' -v OFS='\t' 'NR>1 && $1=="b"{$3="app/b.py README.md"} {print}' .dflow/demo.units.tsv > .dflow/x && mv .dflow/x .dflow/demo.units.tsv
expect 0 "land b" "$ps" land demo b
expect 0 "unland b" "$ps" unland demo b
[ ! -e app/b.py ] && [ "$(cat README.md)" = readme ] && [ -z "$(git status --porcelain)" ] && ok || bad "unland left changes"

# refuse to land on a dirty tree
echo user > notes.txt
out=$("$ps" land demo b); [ $? = 1 ] && echo "$out" | grep -q notes.txt && [ "$(cat notes.txt)" = user ] && ok || bad "dirty tree not refused: $out"
rm notes.txt

# conflict: a second unit edits app/a.py from the old base
git worktree add -q -b wc "$t/wc" "$base"; ( cd "$t/wc"; echo C > app/a.py; git add -A; git commit -qm "unit c" )
row c "app/a.py" dispatched "$base" wc
out=$("$ps" land demo c); rc=$?
[ $rc = 1 ] && echo "$out" | grep -q "app/a.py" && [ -z "$(git status --porcelain)" ] && [ "$(cat app/a.py)" = A ] && ok || bad "conflict not restored: $rc $out"

# base not an ancestor
other=$(git commit-tree -m orphan "$(git write-tree)")
awk -F'\t' -v OFS='\t' -v o="$other" 'NR>1 && $1=="c"{$5=o} {print}' .dflow/demo.units.tsv > .dflow/x && mv .dflow/x .dflow/demo.units.tsv
out=$("$ps" scope demo c); [ $? = 1 ] && echo "$out" | grep -q "not an ancestor" && ok || bad "ancestor not checked: $out"

# cleanup: a landed -> removed (with untracked listed); b unlanded with commits -> kept;
# c has uncommitted tracked change -> kept; an unregistered worktree is untouched
awk -F'\t' -v OFS='\t' -v b="$base" 'NR>1 && $1=="a"{$4="landed"} NR>1 && $1=="c"{$5=b} {print}' .dflow/demo.units.tsv > .dflow/x && mv .dflow/x .dflow/demo.units.tsv
echo junk > "$t/wa/scratch.log"; echo edit >> "$t/wc/app/core.py"
git worktree add -q -b other "$t/other" "$base"
mkdir -p .claude/worktrees; git worktree add -q -b worktree-agent-zz .claude/worktrees/agent-zz "$base"
out=$("$ps" cleanup demo); rc=$?
[ $rc = 1 ] && ok || bad "cleanup exit $rc"
[ ! -d "$t/wa" ] && ! git rev-parse -q --verify wa >/dev/null && ok || bad "landed worktree not removed"
echo "$out" | grep -q "scratch.log" && ok || bad "untracked file not listed: $out"
[ -d "$t/wb" ] && echo "$out" | grep -q "KEEP b" && ok || bad "unlanded unit not kept: $out"
[ -d "$t/wc" ] && echo "$out" | grep -q "KEEP c" && ok || bad "dirty unit not kept: $out"
[ -d "$t/other" ] && git rev-parse -q --verify other >/dev/null && ok || bad "unregistered worktree touched"
echo "$out" | grep -q "ORPHAN .*agent-zz" && [ -d .claude/worktrees/agent-zz ] && ok || bad "orphan not listed or removed: $out"
echo "$out" | grep -q "ORPHAN .*other" && bad "non-.claude worktree listed as orphan" || ok

expect 2 "usage" "$ps"
expect 1 "bad slug" "$ps" overlap "../x"
echo "parallel-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
