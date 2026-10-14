#!/usr/bin/env bash
# Tests for scratch.sh: path under the repo, exclude line added once, nothing shows in git status.
set -u
here=$(cd "$(dirname "$0")" && pwd); pass=0; fail=0
ok() { pass=$((pass+1)); }; bad() { fail=$((fail+1)); echo "FAIL $*"; }
t=$(mktemp -d "${TMPDIR:-/tmp}/scratch-test.XXXXXX"); trap 'rm -rf "$t"' EXIT
git init -q "$t/repo" && mkdir -p "$t/repo/sub"
d=$(cd "$t/repo/sub" && "$here/scratch.sh" probe)
case $d in "$(cd "$t/repo" && pwd -P)"/.dflow/tmp/*-probe|"$t/repo"/.dflow/tmp/*-probe) ok ;; *) bad "path $d" ;; esac
[ -d "$d" ] && ok || bad "not created"
(cd "$t/repo" && "$here/scratch.sh" >/dev/null)
[ "$(grep -cx '.dflow/' "$t/repo/.git/info/exclude")" = 1 ] && ok || bad "exclude line count"
touch "$d/x"; [ -z "$(git -C "$t/repo" status --porcelain)" ] && ok || bad "scratch shows in git status"
mkdir "$t/plain"; d2=$(cd "$t/plain" && "$here/scratch.sh"); case $d2 in */plain/.dflow/tmp/*) ok ;; *) bad "outside repo: $d2" ;; esac
echo "scratch-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
