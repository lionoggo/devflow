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

# cleanup: a landed with an untracked file -> kept and listed; b unlanded with commits -> kept;
# c has uncommitted tracked change -> kept; an unregistered worktree is untouched
awk -F'\t' -v OFS='\t' -v b="$base" 'NR>1 && $1=="a"{$4="landed"} NR>1 && $1=="c"{$5=b} {print}' .dflow/demo.units.tsv > .dflow/x && mv .dflow/x .dflow/demo.units.tsv
echo junk > "$t/wa/scratch.log"; echo edit >> "$t/wc/app/core.py"
git worktree add -q -b other "$t/other" "$base"
mkdir -p .claude/worktrees; git worktree add -q -b worktree-agent-zz .claude/worktrees/agent-zz "$base"
out=$("$ps" cleanup demo); rc=$?
[ $rc = 1 ] && ok || bad "cleanup exit $rc"
[ -f "$t/wa/scratch.log" ] && echo "$out" | grep -q "KEEP a" && echo "$out" | grep -q "scratch.log" && ok || bad "untracked file in a landed unit not kept and listed: $out"
rm "$t/wa/scratch.log"
echo '*.out' >> "$(git -C "$t/wa" rev-parse --git-path info/exclude)"; echo sample > "$t/wa/user.out"
out2=$("$ps" cleanup demo)
[ -f "$t/wa/user.out" ] && echo "$out2" | grep -q "KEEP a .*ignored" && echo "$out2" | grep -q "user.out" && ok || bad "ignored file in a landed unit not kept and listed: $out2"
out3=$("$ps" cleanup demo --ignored); [ $? = 1 ] && echo "$out3" | grep -q "unknown cleanup option" && [ -f "$t/wa/user.out" ] && ok || bad "unknown option not refused: $out3"
out3=$("$ps" cleanup demo --ignored-ok); echo "$out3" | grep -q "DELETING ignored" && echo "$out3" | grep -q "user.out" && ok || bad "deleted ignored files not listed: $out3"
[ ! -d "$t/wa" ] && ! git rev-parse -q --verify wa >/dev/null && ok || bad "landed worktree not removed"
[ -d "$t/wb" ] && echo "$out" | grep -q "KEEP b" && ok || bad "unlanded unit not kept: $out"
[ -d "$t/wc" ] && echo "$out" | grep -q "KEEP c" && ok || bad "dirty unit not kept: $out"
[ -d "$t/other" ] && git rev-parse -q --verify other >/dev/null && ok || bad "unregistered worktree touched"
echo "$out" | grep -q "ORPHAN .*agent-zz" && [ -d .claude/worktrees/agent-zz ] && ok || bad "orphan not listed or removed: $out"
echo "$out" | grep -q "ORPHAN .*other" && bad "non-.claude worktree listed as orphan" || ok

# worktree: a Codex-style unit gets its own worktree at its base, idempotent, and cleanup removes it
printf 'w1\t-\tapp/w.py\tdispatched\t%s\t-\t-\t-\t0\t-\n' "$base" >> .dflow/demo.units.tsv
printf 'w2\t-\tapp/v.py\tplanned\t-\t-\t-\t-\t0\t-\n' >> .dflow/demo.units.tsv
out=$("$ps" worktree demo w1); rc=$?
wt="$r/.dflow/worktrees/demo-w1"
[ $rc = 0 ] && [ -d "$wt" ] && [ "$(git -C "$wt" rev-parse HEAD)" = "$base" ] && [ "$(git -C "$wt" branch --show-current)" = dflow-unit/demo-w1 ] && ok || bad "worktree not created at base: $out"
expect 0 "worktree again is a no-op" "$ps" worktree demo w1
expect 1 "worktree without a base" "$ps" worktree demo w2
[ -z "$(git status --porcelain --untracked-files=all | grep -v ' \.dflow/' | grep -v ' \.claude/worktrees/')" ] && ok || bad "worktree left the main tree dirty"
( cd "$wt"; echo W > app/w.py; git add -A; git commit -qm "unit w1" )
awk -F'\t' -v OFS='\t' 'NR>1 && $1=="w1"{$7="dflow-unit/demo-w1"} {print}' .dflow/demo.units.tsv > .dflow/x && mv .dflow/x .dflow/demo.units.tsv
expect 0 "scope w1" "$ps" scope demo w1
git worktree add -q -b dflow-unit/demo-zz .dflow/worktrees/demo-zz "$base"
out=$("$ps" cleanup demo)
echo "$out" | grep -q "KEEP w1" && ok || bad "unlanded codex unit not kept: $out"
echo "$out" | grep -q "ORPHAN .*demo-zz" && ok || bad "orphan under .dflow/worktrees not listed: $out"
"$ps" land demo w1 >/dev/null && "$ps" unland demo w1 >/dev/null   # land records the source commit
awk -F'\t' -v OFS='\t' 'NR>1 && $1=="w1"{$4="landed"} {print}' .dflow/demo.units.tsv > .dflow/x && mv .dflow/x .dflow/demo.units.tsv
"$ps" cleanup demo >/dev/null
[ ! -d "$wt" ] && ! git rev-parse -q --verify dflow-unit/demo-w1 >/dev/null && ok || bad "landed codex unit not removed"

# worktree: a sent-back unit (tries > 0) is refused while its old worktree is not at the new base
printf 'w3\t-\tapp/u.py\tdispatched\t%s\t-\t-\t-\t0\t-\n' "$base" >> .dflow/demo.units.tsv
"$ps" worktree demo w3 >/dev/null; wt3="$r/.dflow/worktrees/demo-w3"
( cd "$wt3"; echo U > app/u.py; git add -A; git commit -qm "unit w3 try 1" )
head=$(git rev-parse HEAD); [ "$head" != "$base" ] || bad "test setup: HEAD should have moved past base"
awk -F'\t' -v OFS='\t' -v h="$head" 'NR>1 && $1=="w3"{$5=h; $9=1} {print}' .dflow/demo.units.tsv > .dflow/x && mv .dflow/x .dflow/demo.units.tsv
out=$("$ps" worktree demo w3); [ $? = 1 ] && echo "$out" | grep -q "sent back" && ok || bad "stale worktree of a sent-back unit not refused: $out"
git worktree remove --force "$wt3"; git branch -D -q dflow-unit/demo-w3
out=$("$ps" worktree demo w3); [ $? = 0 ] && [ "$(git -C "$wt3" rev-parse HEAD)" = "$head" ] && ok || bad "sent-back unit not recreated at the new base: $out"
expect 0 "sent-back worktree at the new base is reused" "$ps" worktree demo w3

# land by sha: the branch moved on after the sha was verified -> refused, nothing landed
head=$(git rev-parse HEAD)
git worktree add -q -b ws "$t/ws" "$head"
( cd "$t/ws"; echo S1 > app/s.py; git add -A; git commit -qm s1 ); s1=$(git -C "$t/ws" rev-parse HEAD)
( cd "$t/ws"; echo S2 > app/s2.py; git add -A; git commit -qm s2 ); s2=$(git -C "$t/ws" rev-parse HEAD)
printf 's\t-\tapp/s.py app/s2.py\tdispatched\t%s\t-\tws\t-\t0\t-\n' "$head" >> .dflow/demo.units.tsv
out=$("$ps" scope demo s "$s1"); [ $? = 1 ] && echo "$out" | grep -q "changed after" && ok || bad "scope at a sha the branch moved past: $out"
out=$("$ps" land demo s "${s1:0:12}"); rc=$?
[ $rc = 1 ] && echo "$out" | grep -q "changed after" && [ ! -e app/s.py ] && [ -z "$(git status --porcelain)" ] && ok || bad "land at a sha the branch moved past: $rc $out"
notonbr=$(git commit-tree -p "$head" -m stray "$(git write-tree)")
out=$("$ps" land demo s "$notonbr"); [ $? = 1 ] && [ -z "$(git status --porcelain)" ] && ok || bad "sha off the branch: $out"
expect 1 "unknown sha" "$ps" land demo s abcdef0
expect 1 "a branch name is not a sha" "$ps" land demo s ws
expect 0 "scope at the branch head" "$ps" scope demo s "$s2"
expect 0 "land at the branch head" "$ps" land demo s "${s2:0:12}"
[ "$(cat app/s.py)" = S1 ] && [ -f app/s2.py ] && ok || bad "land at the branch head did not land both commits"
[ "$(tail -1 .dflow/demo.landed)" = "$(printf 's\t%s' "$s2")" ] && ok || bad "land did not record the source: $(cat .dflow/demo.landed)"
"$ps" unland demo s >/dev/null
# cleanup keeps a landed unit whose branch moved past what landed
awk -F'\t' -v OFS='\t' 'NR>1 && $1=="s"{$4="landed"} {print}' .dflow/demo.units.tsv > .dflow/x && mv .dflow/x .dflow/demo.units.tsv
( cd "$t/ws"; echo S3 > app/s2.py; git commit -qam s3 )
out=$("$ps" cleanup demo); echo "$out" | grep -q "KEEP s ws: 1 commit(s) past the landed $s2" && [ -d "$t/ws" ] && ok || bad "landed unit with later commits removed: $out"
# cleanup keeps every non-final state, even an empty clean branch: stop-unconfirmed, dispatched, unknown
for st in stop-unconfirmed dispatched weird; do
    git worktree add -q -b "e-$st" "$t/e-$st" "$head"
    printf 'e-%s\t-\tapp/e.py\t%s\t%s\t-\te-%s\t-\t0\t-\n' "$st" "$st" "$head" "$st" >> .dflow/demo.units.tsv
done
git worktree add -q -b e-done "$t/e-done" "$head"; printf 'e-done\t-\tapp/e.py\tdone\t%s\t-\te-done\t-\t0\t-\n' "$head" >> .dflow/demo.units.tsv
out=$("$ps" cleanup demo)
for st in stop-unconfirmed dispatched weird; do
    echo "$out" | grep -q "KEEP e-$st e-$st: state $st" && [ -d "$t/e-$st" ] && git rev-parse -q --verify "e-$st" >/dev/null && ok || bad "empty $st unit removed: $out"
done
[ ! -d "$t/e-done" ] && echo "$out" | grep -q "ok removed e-done" && ok || bad "empty done unit kept: $out"
# the widened 多线 table (lines.sh init) is read by header name
"$here/lines.sh" init demo >/dev/null
expect 0 "scope on the widened table" "$ps" scope demo s "$(git -C "$t/ws" rev-parse HEAD)"
# orphan scan reads the branch column by name, wherever it sits
git worktree add -q -b dflow-unit/re-x .dflow/worktrees/re-x "$head"; ( cd .dflow/worktrees/re-x; echo X > app/x.py; git add -A; git commit -qm x )
printf 'branch\tid\tpaths\tstate\tbase\ndflow-unit/re-x\tx\tapp/x.py\tdispatched\t%s\n' "$head" > .dflow/re.units.tsv
out=$("$ps" cleanup re); echo "$out" | grep -q "KEEP x" && ! echo "$out" | grep -q "ORPHAN .*re-x" && ok || bad "orphan scan by header name: $out"

expect 2 "usage" "$ps"
expect 1 "bad slug" "$ps" overlap "../x"
echo "parallel-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
