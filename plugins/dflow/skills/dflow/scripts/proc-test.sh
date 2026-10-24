#!/usr/bin/env bash
# Tests for proc.sh beyond what review-test.sh covers: a second start while the run is alive is refused
# and overwrites nothing (also when started concurrently), stdin reaches the command, stop and wait
# check identity (exact lstart and command, never a substring) before any signal, peek never signals.
set -u
here=$(cd "$(dirname "$0")" && pwd); . "$here/proc.sh"; pass=0; fail=0
ok() { pass=$((pass+1)); }; bad() { fail=$((fail+1)); echo "FAIL $*"; }
t=$(mktemp -d "${TMPDIR:-/tmp}/proc-test.XXXXXX"); mine=()
trap 'for p in "${mine[@]}"; do kill -9 -- -"$p" 2>/dev/null; kill -9 "$p" 2>/dev/null; done; rm -rf "$t"' EXIT
echo "输入" > "$t/in"
pid=$(proc_start "$t/out" sh -c 'echo "got $(cat)"; sleep 30' < "$t/in"); mine+=("$pid")
sleep 0.5; grep -qx "got 输入" "$t/out" && ok || bad "stdin not passed: $(cat "$t/out")"
rec=$(cat "$t/out.pid")
out=$(proc_start "$t/out" sh -c 'echo second' < /dev/null 2>&1); rc=$?
[ $rc = 1 ] && [ "$(cat "$t/out.pid")" = "$rec" ] && grep -qx "got 输入" "$t/out" && ok || bad "second start while running: $rc $out"
out=$(proc_wait "$t/out" 1); [ $? = 3 ] && [ "$out" = running ] && ok || bad "wait running: $out"
out=$(proc_stop "$t/out"); [ $? = 0 ] && [ "$out" = "ok stopped" ] && ! kill -0 -- -"$pid" 2>/dev/null && ok || bad "stop: $out"
out=$(proc_stop "$t/out"); [ $? = 0 ] && [ "$out" = "ok not running" ] && ok || bad "stop again: $out"
# after the run ended, the same out may start again (callers that want one file per attempt refuse it themselves)
pid=$(proc_start "$t/out" sh -c 'exit 4' < /dev/null); mine+=("$pid")
out=$(proc_wait "$t/out" 10); [ "$out" = "ended exit 4" ] && ok || bad "restart after end: $out"
# TERM-proof run: stop still ends the whole group
pid=$(proc_start "$t/out2" sh -c 'trap "" TERM; sleep 30 & wait; sleep 30' < /dev/null); mine+=("$pid"); sleep 0.3
out=$(proc_stop "$t/out2"); [ "$out" = "ok stopped" ] && ! kill -0 -- -"$pid" 2>/dev/null && ok || bad "TERM-proof stop: $out"
# a pid record that is not this run (someone else's group) is never signalled
python3 -I -c 'import os, time; os.setsid(); time.sleep(30)' & other=$!; disown "$other"; mine+=("$other"); sleep 0.3
echo "$other $(date +%s)" > "$t/out3.pid"
out=$(proc_stop "$t/out3"); [ $? = 1 ] && case $out in "not stopped: "*) true ;; *) false ;; esac && kill -0 "$other" 2>/dev/null && ok || bad "foreign pid stopped: $out"
out=$(proc_start "$t/out3" sh -c 'echo x' < /dev/null 2>&1); [ $? = 0 ] && kill -0 "$other" 2>/dev/null && ok || bad "a foreign pid record blocked start or was signalled: $out"
proc_wait "$t/out3" 10 >/dev/null
# no pid record, and no ps: nothing signalled
out=$(proc_stop "$t/none"); [ $? = 1 ] && [ "${out#not stopped}" != "$out" ] && ok || bad "stop without record: $out"
mkdir -p "$t/nops"; printf '#!/bin/sh\necho "ps: operation not permitted" >&2; exit 1\n' > "$t/nops/ps"; chmod +x "$t/nops/ps"
pid=$(proc_start "$t/out4" sleep 30 < /dev/null); mine+=("$pid"); sleep 0.3
out=$(PATH="$t/nops:$PATH" proc_stop "$t/out4"); [ $? = 1 ] && kill -0 "$pid" 2>/dev/null && ok || bad "no ps: $out"
out=$(proc_stop "$t/out4"); [ "$out" = "ok stopped" ] && ok || bad "stop with ps: $out"
[ "$(proc_canon "$t/./out4")" = "$(cd "$t" && pwd -P)/out4" ] && ok || bad "canon"
# identity is exact: a process whose command merely contains <out> (another line's longer output path)
# is never signalled, nor one with the recorded command but another start time (pid reused)
o5=$(proc_canon "$t/out5")
python3 -I -c 'import os, sys, time; os.setsid(); time.sleep(30)' "$o5-b-1.out" & f5=$!; disown "$f5"; mine+=("$f5"); sleep 0.3
printf '%s %s\nlstart: %s\ncommand: python3 -I - %s\n' "$f5" "$(( $(date +%s) - 100 ))" "$(_proc_ps lstart "$f5")" "$o5" > "$o5.pid"
out=$(proc_stop "$t/out5"); [ $? = 1 ] && kill -0 "$f5" 2>/dev/null && ok || bad "substring identity: stopped $out"
out=$(proc_wait "$t/out5" 3 1); [ "$out" = "ended lost" ] && kill -0 "$f5" 2>/dev/null && ok || bad "substring identity at the limit: $out"
printf '%s %s\nlstart: Mon Jan  1 00:00:00 2001\ncommand: %s\n' "$f5" "$(( $(date +%s) - 100 ))" "$(_proc_ps command "$f5")" > "$o5.pid"
out=$(proc_stop "$t/out5"); [ $? = 1 ] && kill -0 "$f5" 2>/dev/null && ok || bad "other start time: stopped $out"
# peek: one look, never a signal, even long past any limit
pid=$(proc_start "$t/out6" sleep 30 < /dev/null); mine+=("$pid"); sleep 0.3
sed -i '' "1s/ .*/ 1/" "$t/out6.pid"
out=$(proc_peek "$t/out6"); [ $? = 3 ] && [ "$out" = running ] && kill -0 "$pid" 2>/dev/null && ok || bad "peek: $out"
proc_stop "$t/out6" >/dev/null; out=$(proc_peek "$t/out6"); [ $? = 1 ] && [ "$out" = "ended lost" ] && ok || bad "peek after stop: $out"
# concurrent starts on one <out>: exactly one runs, the record and output are the winner's
: > "$t/won"; rp=()
for i in 1 2 3 4 5 6; do ( p=$(proc_start "$t/out7" sh -c "echo starter-$i; sleep 30" < /dev/null 2>/dev/null) && echo "$i $p" >> "$t/won" ) & rp+=($!); done; wait "${rp[@]}"
read -r wi wp < "$t/won"; [ -n "${wp:-}" ] && mine+=("$wp"); sleep 0.5
[ "$(wc -l < "$t/won" | tr -d ' ')" = 1 ] && [ "$(head -1 "$t/out7.pid" | cut -d' ' -f1)" = "$wp" ] && [ "$(cat "$t/out7")" = "starter-$wi" ] && [ ! -e "$t/out7.starting" ] && ok || bad "concurrent starts: winners $(tr '\n' ';' < "$t/won"); out $(cat "$t/out7")"
echo "proc-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
