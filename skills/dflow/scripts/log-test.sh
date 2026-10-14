#!/usr/bin/env bash
# Tests for log.sh: header once, six columns, single-line cells, formula quoting, usage error.
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
echo "log-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
