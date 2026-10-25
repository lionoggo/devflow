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
# R6: no manifest, or one without allow:, fails (it is not read as "nothing to check"); protect may be
# left out, and "protect: -" means none
cp .dflow/demo.md "$t/man"
rm .dflow/demo.md
out=$("$ps" overlap demo); [ $? = 1 ] && echo "$out" | grep -q "no manifest" && ok || bad "overlap without a manifest: $out"
printf 'slug: demo\nbase: %s\nprotect: tests/*\n\n# goal\nallow: app/*\n' "$base" > .dflow/demo.md
out=$("$ps" overlap demo); [ $? = 1 ] && echo "$out" | grep -q "no allow:" && ok || bad "overlap without allow: $out"
printf 'slug: demo\nbase: %s\nallow: app/* tests/*\n\n# goal\n' "$base" > .dflow/demo.md
row d "tests/x.py" planned - -
expect 0 "manifest without protect:" "$ps" overlap demo
printf 'slug: demo\nbase: %s\nallow: app/* tests/*\nprotect: -\n\n# goal\n' "$base" > .dflow/demo.md
expect 0 "protect: - means none" "$ps" overlap demo
sed -i '' '/^d	/d' .dflow/demo.units.tsv; cp "$t/man" .dflow/demo.md
# R8: read-only lines (paths "-", as lines.sh line set paths=- writes it) take no part in overlap
row v-a "-" planned - -; row v-b "-" planned - -
expect 0 "read-only lines (paths -) pass overlap" "$ps" overlap demo
sed -i '' '/^v-a	/d; /^v-b	/d' .dflow/demo.units.tsv

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
# R8: a verifier line registered as the playbook says (paths=-) keeps overlap passing, and its scope
# requires a branch that changes nothing
printf 'slug: ro\nbase: %s\nallow: app/* README.md\nprotect: tests/*\n\n# goal\n' "$head" > .dflow/ro.md
"$here/lines.sh" init ro >/dev/null
"$here/lines.sh" line set ro w paths="app/w.py app/v.py" state=dispatched >/dev/null
"$here/lines.sh" line set ro v-w paths=- state=dispatched base="$head" branch=wv carrier=headless attempt=1 >/dev/null
[ "$(awk -F'\t' '$1 == "v-w" { print $3 }' .dflow/ro.units.tsv)" = - ] && ok || bad "line set paths=- not stored as -"
expect 0 "a paths=- verifier line next to a writing line passes overlap" "$ps" overlap ro
git worktree add -q -b wv "$t/wv" "$head"
expect 0 "scope of a read-only line with no change" "$ps" scope ro v-w
( cd "$t/wv"; echo V > app/v.py; git add -A; git commit -qm "verifier wrote" )
out=$("$ps" scope ro v-w); [ $? = 1 ] && echo "$out" | grep -q "OUTSIDE app/v.py (read-only" && ok || bad "a read-only line that changed a file: $out"
# orphan scan reads the branch column by name, wherever it sits
git worktree add -q -b dflow-unit/re-x .dflow/worktrees/re-x "$head"; ( cd .dflow/worktrees/re-x; echo X > app/x.py; git add -A; git commit -qm x )
printf 'branch\tid\tpaths\tstate\tbase\ndflow-unit/re-x\tx\tapp/x.py\tdispatched\t%s\n' "$head" > .dflow/re.units.tsv
out=$("$ps" cleanup re); echo "$out" | grep -q "KEEP x" && ! echo "$out" | grep -q "ORPHAN .*re-x" && ok || bad "orphan scan by header name: $out"

# S1: land writes .dflow/<slug>.landing (uid, HEAD, the files it changed, added ones marked A); unland
# undoes only those files, only for that unit and only while HEAD is unchanged; otherwise it refuses
# and touches nothing
h0=$(git rev-parse HEAD)
[ -z "$(git status --porcelain --untracked-files=all | grep -v ' \.dflow/' | grep -v ' \.claude/worktrees/')" ] && ok || bad "test setup: main tree not clean"
printf 'id\tdeps\tpaths\tstate\tbase\tagent\tbranch\tdispatched_at\ttries\tlanded\n' > .dflow/ld.units.tsv
git worktree add -q -b ld-x "$t/ldx" "$h0"; ( cd "$t/ldx"; echo X > app/ldx.py; echo X2 >> app/core.py; git add -A; git commit -qm ldx )
git worktree add -q -b ld-y "$t/ldy" "$h0"; ( cd "$t/ldy"; echo Y > app/ldy.py; git add -A; git commit -qm ldy )
git worktree add -q -b ld-o "$t/ldo" "$h0"; ( cd "$t/ldo"; echo O > app/o.py; echo O > tests/o.py; git add -A; git commit -qm ldo )
for u in "x app/ldx.py app/core.py" "y app/ldy.py" "o app/o.py"; do set -- $u; id=$1; shift
    printf '%s\t-\t%s\tdispatched\t%s\t-\tld-%s\t-\t0\t-\n' "$id" "$*" "$h0" "$id" >> .dflow/ld.units.tsv; done
# user changes in the main tree: land refuses, and a following unland keeps every one of them
echo user >> README.md; echo note > notes.txt; echo st > staged.txt; git add staged.txt
snap() { git status --porcelain --untracked-files=all | grep -v ' \.dflow/' | grep -v ' \.claude/worktrees/'; cat README.md notes.txt staged.txt; }
before=$(snap)
expect 1 "land over user changes" "$ps" land ld x
out=$("$ps" unland ld x); rc=$?
[ $rc = 1 ] && echo "$out" | grep -q "no record" && [ "$(snap)" = "$before" ] && ok || bad "unland after a refused land touched user changes: $rc $out; now $(snap)"
git rm -q --cached staged.txt; rm -f staged.txt notes.txt; git checkout -q README.md
# a normal land, then unland: the marker names the unit, HEAD and the files; unland restores a clean tree
out=$("$ps" land ld x); rc=$?
mk=.dflow/ld.landing
[ $rc = 0 ] && grep -qx "$(printf 'uid\tx')" "$mk" && grep -qx "$(printf 'head\t%s' "$h0")" "$mk" && grep -qx "$(printf 'A\tapp/ldx.py')" "$mk" && grep -qx "$(printf 'M\tapp/core.py')" "$mk" && ok || bad "land marker: $rc $out; $(cat "$mk" 2>/dev/null)"
# unland of another unit, or a second land while this one is pending, is refused and touches nothing
out=$("$ps" unland ld y); [ $? = 1 ] && echo "$out" | grep -q "unit x" && [ -f app/ldx.py ] && [ -f "$mk" ] && ok || bad "unland of another unit: $out"
out=$("$ps" unland ld x); rc=$?
[ $rc = 0 ] && [ ! -e app/ldx.py ] && [ -z "$(git status --porcelain --untracked-files=all | grep -v ' \.dflow/' | grep -v ' \.claude/worktrees/')" ] && [ ! -e "$mk" ] && ok || bad "unland: $rc $out; $(git status --porcelain)"
"$ps" land ld x >/dev/null; git reset -q --hard
out=$("$ps" land ld y); [ $? = 1 ] && echo "$out" | grep -q "pending" && [ ! -e app/ldy.py ] && ok || bad "land while another land is pending at the same HEAD: $out"
expect 0 "unland of a land undone by hand clears its record" "$ps" unland ld x
# land, then commit: unland refuses (HEAD moved), the commit and tree stay
"$ps" land ld x >/dev/null; git commit -qm "land x"; hx=$(git rev-parse HEAD)
out=$("$ps" unland ld x); [ $? = 1 ] && echo "$out" | grep -q "committed" && [ "$(git rev-parse HEAD)" = "$hx" ] && [ -f app/ldx.py ] && [ -z "$(git status --porcelain | grep -v ' \.dflow/')" ] && ok || bad "unland after a commit: $out"
git reset -q --hard "$h0"; rm -f "$mk"
# a file a check made after the land is not the land's: unland leaves it and names it
"$ps" land ld x >/dev/null; echo gen > app/gen.txt
out=$("$ps" unland ld x); rc=$?
[ $rc = 1 ] && [ -f app/gen.txt ] && echo "$out" | grep -q "app/gen.txt" && [ ! -e app/ldx.py ] && [ "$(git diff HEAD --name-only)" = "" ] && [ ! -e "$mk" ] && ok || bad "unland with a file the land did not make: $rc $out"
rm -f app/gen.txt
# S4: land runs the scope check itself: a change outside the unit's paths is refused without scope
out=$("$ps" land ld o); [ $? = 1 ] && echo "$out" | grep -q "OUTSIDE tests/o.py" && [ ! -e app/o.py ] && [ ! -e "$mk" ] && ok || bad "land outside scope: $out"
# S4: a 多线 unit (carrier set, not prep) lands only at a <sha> that ledger check passes, with a valid
# receipt for its attempt that names a commit
"$here/lines.sh" init ml >/dev/null
git worktree add -q -b ml-m "$t/mlm" "$h0"; ( cd "$t/mlm"; echo M > app/m.py; git add -A; git commit -qm mlm ); sm=$(git -C "$t/mlm" rev-parse HEAD)
"$here/lines.sh" line set ml m paths=app/m.py state=dispatched base="$h0" branch=ml-m carrier=headless attempt=1 >/dev/null
out=$("$ps" land ml m); [ $? = 1 ] && echo "$out" | grep -q "^  <sha>: " && [ ! -e app/m.py ] && ok || bad "多线 land without a sha: $out"
out=$("$ps" land ml m "$sm"); [ $? = 1 ] && echo "$out" | grep -q "ledger" && echo "$out" | grep -q "receipt" && [ ! -e app/m.py ] && ok || bad "多线 land without a ledger pass or receipt: $out"
echo "RECEIPT m 1 done $sm" > .dflow/ml/reports/m-1.md
out=$("$ps" land ml m "$sm"); [ $? = 1 ] && echo "$out" | grep -q "ledger" && ! echo "$out" | grep -q "receipt" && [ ! -e app/m.py ] && ok || bad "多线 land without a ledger pass: $out"
"$here/lines.sh" ledger record ml m 1 "$sm" pass behavior claude repro.log >/dev/null
out=$("$ps" land ml m "$sm"); [ $? = 0 ] && [ "$(cat app/m.py)" = M ] && ok || bad "多线 land with a pass and a receipt: $out"
"$ps" unland ml m >/dev/null
echo "RECEIPT m 1 done docs/audit.md" > .dflow/ml/reports/m-1.md
out=$("$ps" land ml m "$sm"); [ $? = 1 ] && echo "$out" | grep -q "receipt" && [ ! -e app/m.py ] && ok || bad "多线 land on a read-only receipt: $out"
"$here/lines.sh" line set ml m carrier=prep >/dev/null
expect 0 "a prep line lands like a plain unit" "$ps" land ml m
"$ps" unland ml m >/dev/null

expect 2 "usage" "$ps"
expect 1 "bad slug" "$ps" overlap "../x"
echo "parallel-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
