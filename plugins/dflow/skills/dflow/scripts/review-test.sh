#!/usr/bin/env bash
# Tests for review.sh: detached start returns at once, wait reports running then ended, exit code kept,
# a lost reviewer and the total limit end the wait.
set -u
here=$(cd "$(dirname "$0")" && pwd); rv="$here/review.sh"; pass=0; fail=0
ok() { pass=$((pass+1)); }; bad() { fail=$((fail+1)); echo "FAIL $*"; }
t=$(mktemp -d "${TMPDIR:-/tmp}/review-test.XXXXXX"); trap 'rm -rf "$t"' EXIT
echo "审查这个" > "$t/prompt"
s=$(date +%s)
pid=$(DFLOW_REVIEW_CMD='sleep 4; echo "got: $(cat)"; exit 5' "$rv" start "$t/prompt" "$t/out")
[ $(( $(date +%s) - s )) -lt 3 ] && ok || bad "start blocked"
[ "$(ps -o pgid= -p "$pid" | tr -d ' ')" = "$pid" ] && ok || bad "reviewer not in its own session"
out=$("$rv" wait "$t/out" 1); [ $? = 3 ] && [ "$out" = running ] && ok || bad "wait while running: $out"
out=$("$rv" wait "$t/out" 40); rc=$?
[ $rc = 0 ] && [ "$out" = "ended exit 5" ] && ok || bad "wait after end: $rc $out; reviewer: $(ps -o pid=,stat=,etime=,command= -p "$pid" 2>&1); files: $(ls -la "$t")"
grep -q '^got: 审查这个$' "$t/out" && ok || bad "prompt not on stdin or output lost: $(cat "$t/out")"
DFLOW_REVIEW_CMD='no-such-reviewer-cmd' "$rv" start "$t/prompt" "$t/out2" >/dev/null
"$rv" wait "$t/out2" 10 >/dev/null; [ "$(cat "$t/out2.exit")" != 0 ] && ok || bad "a reviewer that cannot start reports success"
# the reviewer vanished without an exit code -> "ended lost"; over the total limit -> "ended timeout", stopped
pid=$(DFLOW_REVIEW_CMD='sleep 30' "$rv" start "$t/prompt" "$t/out3"); kill -9 -- -"$pid"; sleep 0.3
out=$("$rv" wait "$t/out3" 10); [ $? = 1 ] && [ "$out" = "ended lost" ] && ok || bad "lost reviewer: $out"
pid=$(DFLOW_REVIEW_CMD='sleep 30' "$rv" start "$t/prompt" "$t/out4"); s=$(date +%s)
out=$("$rv" wait "$t/out4" 20 1); rc=$?
[ $rc = 1 ] && [ "$out" = "ended timeout" ] && [ $(( $(date +%s) - s )) -lt 10 ] && ok || bad "total limit: $rc $out"
sleep 0.3; kill -0 "$pid" 2>/dev/null && { bad "timed-out reviewer still running"; kill -- -"$pid"; } || ok
"$rv" start >/dev/null 2>&1; [ $? = 2 ] && ok || bad "usage"
echo "review-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
