#!/usr/bin/env bash
# Tests for log.sh: header once, six columns, single-line cells, formula quoting, usage error,
# .dflow/ excluded in a repo.
set -u
here=$(cd "$(dirname "$0")" && pwd); pass=0; fail=0
ok() { pass=$((pass+1)); }; bad() { fail=$((fail+1)); echo "FAIL $*"; }
t=$(mktemp -d "${TMPDIR:-/tmp}/log-test.XXXXXX"); trap 'rm -rf "$t"' EXIT
f="$t/.dflow/run.tsv"
"$here/log.sh" "$f" start "开始" "用户说开始" "base abc" ok && ok || bad "first append"
"$here/log.sh" "$f" round "改 greet" "$(printf 'two\nlines\twith tab')" "=1+1" ok && ok || bad "second append"
[ "$(head -1 "$f")" = "$(printf 'ts\tphase\tdecision\twhy\tevidence\tresult')" ] && ok || bad "header"
[ "$(grep -c '^ts' "$f")" = 1 ] && ok || bad "header repeated"
[ "$(wc -l < "$f" | tr -d ' ')" = 3 ] && ok || bad "row count"
awk -F'\t' 'NF != 6 { exit 1 }' "$f" && ok || bad "six columns"
grep -q "	'=1+1	" "$f" && ok || bad "formula not quoted"
"$here/log.sh" "$f" only-two args >/dev/null 2>&1; [ $? = 1 ] && ok || bad "usage error"
r="$t/repo"; git init -q "$r"
"$here/log.sh" "$r/.dflow/run.tsv" start a b c d && "$here/log.sh" "$r/.dflow/run.tsv" round a b c d && ok || bad "repo append"
[ "$(grep -cx '.dflow/' "$r/.git/info/exclude")" = 1 ] && ok || bad "exclude line missing or repeated"
[ -z "$(git -C "$r" status --porcelain --untracked-files=all)" ] && ok || bad "log shows in git status"
mkdir -p "$r/sub" && "$here/log.sh" "$r/sub/.dflow/x.tsv" start a b c d && ok || bad "nested append"
[ "$(grep -cx '.dflow/' "$r/.git/info/exclude")" = 1 ] && ok || bad "nested .dflow touched exclude"
w="$t/wt"; git -C "$r" commit -q --allow-empty -m init && git -C "$r" worktree add -q "$w" 2>/dev/null
"$here/log.sh" "$w/.dflow/run.tsv" start a b c d && [ -z "$(git -C "$w" status --porcelain --untracked-files=all)" ] && ok || bad "linked worktree: $(git -C "$w" status --porcelain)"
echo "log-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
