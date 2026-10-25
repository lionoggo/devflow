#!/usr/bin/env bash
# Tests for proc.sh beyond what review-test.sh covers: a second start while the run is alive is refused
# and overwrites nothing (also when started concurrently), stdin reaches the command, stop and wait
# check identity (exact lstart and command, never a substring) before any signal, peek never signals;
# an identity that cannot be checked (ps fails for the pid, or the record lacks it) is "running
# (identity unverified)": never restarted over, never lost, never signalled.
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
# that record has no lstart or command, so the live pid's identity is unknown: no restart over it, not lost
rec3=$(cat "$t/out3.pid")
out=$(proc_start "$t/out3" sh -c 'echo x' < /dev/null 2>&1); [ $? = 1 ] && [ "$(cat "$t/out3.pid")" = "$rec3" ] && kill -0 "$other" 2>/dev/null && ok || bad "start over a live pid of unknown identity: $out"
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
# R1: ps answers for this shell but fails for the run's pid (pgid, lstart, command unreadable): the
# identity is unknown, not "another process": start refused with the record and output kept, wait and
# peek say "running (identity unverified)", never "ended lost", and nothing is signalled
mkdir -p "$t/denyps"; printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = "$DENY_PID" ] && { echo "ps: operation not permitted" >&2; exit 1; }; done\nexec /bin/ps "$@"\n' > "$t/denyps/ps"; chmod +x "$t/denyps/ps"
pid=$(proc_start "$t/out8" sh -c 'echo first; sleep 30' < /dev/null); mine+=("$pid"); sleep 0.3
rec=$(cat "$t/out8.pid")
out=$(DENY_PID=$pid PATH="$t/denyps:$PATH" proc_start "$t/out8" sh -c 'echo second' < /dev/null 2>&1); rc=$?
case $out in [0-9]*) mine+=("$out") ;; esac
[ $rc = 1 ] && [ "$(cat "$t/out8.pid")" = "$rec" ] && [ "$(cat "$t/out8")" = first ] && ok || bad "target ps fails: start overwrote the record: $rc $out"
out=$(DENY_PID=$pid PATH="$t/denyps:$PATH" proc_peek "$t/out8"); rc=$?
[ $rc = 3 ] && [ "$out" = "running (identity unverified)" ] && kill -0 "$pid" 2>/dev/null && ok || bad "target ps fails: peek $rc $out"
out=$(DENY_PID=$pid PATH="$t/denyps:$PATH" proc_wait "$t/out8" 1); rc=$?
[ $rc = 3 ] && [ "$out" = "running (identity unverified)" ] && kill -0 "$pid" 2>/dev/null && ok || bad "target ps fails: wait $rc $out"
out=$(DENY_PID=$pid PATH="$t/denyps:$PATH" proc_stop "$t/out8"); [ $? = 1 ] && kill -0 "$pid" 2>/dev/null && ok || bad "target ps fails: stopped $out"
proc_stop "$t/out8" >/dev/null
# R1: started where ps was refused (the record has no lstart or command), looked at later with ps: the
# pid is alive and its identity unknown, so the same: no restart over it, not lost
pid=$(PATH="$t/nops:$PATH" proc_start "$t/out9" sh -c 'echo first; sleep 30' < /dev/null); mine+=("$pid"); sleep 0.3
rec=$(cat "$t/out9.pid")
[ -z "$(sed -n 's/^lstart: //p' "$t/out9.pid")" ] && ok || bad "test setup: a start without ps recorded an lstart"
out=$(proc_start "$t/out9" sh -c 'echo second' < /dev/null 2>&1); rc=$?
case $out in [0-9]*) mine+=("$out") ;; esac
[ $rc = 1 ] && [ "$(cat "$t/out9.pid")" = "$rec" ] && [ "$(cat "$t/out9")" = first ] && ok || bad "record without identity: start overwrote it: $rc $out"
out=$(proc_peek "$t/out9"); rc=$?
[ $rc = 3 ] && [ "$out" = "running (identity unverified)" ] && ok || bad "record without identity: peek $rc $out"
out=$(proc_wait "$t/out9" 1); rc=$?
[ $rc = 3 ] && [ "$out" = "running (identity unverified)" ] && kill -0 "$pid" 2>/dev/null && ok || bad "record without identity: wait $rc $out"
out=$(proc_stop "$t/out9"); [ $? = 1 ] && kill -0 "$pid" 2>/dev/null && ok || bad "record without identity: stopped $out"
kill -9 -- -"$pid" 2>/dev/null; sleep 0.3
out=$(proc_peek "$t/out9"); [ "$out" = "ended lost" ] && ok || bad "record without identity, pid gone: $out"
# S5: DFLOW_PROC_LIMIT is enforced by the session leader itself, with no proc_wait: past the limit the
# output gets "timeout after <N>s", <out>.exit is 124, and the whole group is stopped (TERM, then KILL
# for what ignores TERM); the identity record is the usual one
waitexit() { local i; for i in $(seq 1 "$2"); do [ -f "$1.exit" ] && return 0; sleep 0.5; done; return 1; }
gone() { local i; for i in $(seq 1 "$2"); do kill -0 -- -"$1" 2>/dev/null || return 0; sleep 0.5; done; return 1; }
s=$(date +%s); pid=$(DFLOW_PROC_LIMIT=2 proc_start "$t/lim" sh -c 'echo started; sleep 30' < /dev/null); mine+=("$pid")
sed -n 2p "$t/lim.pid" | grep -q '^lstart: .' && sed -n 3p "$t/lim.pid" | grep -qF -- "-I - $(proc_canon "$t/lim") sh -c echo started"  && ok || bad "limit run: identity record: $(cat "$t/lim.pid")"
sleep 1; [ ! -f "$t/lim.exit" ] && ok || bad "limit run ended before its limit"
waitexit "$t/lim" 12; el=$(( $(date +%s) - s ))
[ "$(cat "$t/lim.exit" 2>/dev/null)" = 124 ] && [ $el -ge 2 ] && [ $el -le 5 ] && ok || bad "limit 2: exit $(cat "$t/lim.exit" 2>/dev/null) after ${el}s"
grep -qx "started" "$t/lim" && grep -qx "timeout after 2s" "$t/lim" && ok || bad "limit 2: output $(cat "$t/lim")"
gone "$pid" 16 && ok || bad "limit 2: process group $pid still there"
pid=$(DFLOW_PROC_LIMIT=1 proc_start "$t/lim2" sh -c 'trap "" TERM; sleep 30 & wait; sleep 30' < /dev/null); mine+=("$pid")
waitexit "$t/lim2" 30 && [ "$(cat "$t/lim2.exit")" = 124 ] && gone "$pid" 20 && ok || bad "limit on a TERM-proof run: exit $(cat "$t/lim2.exit" 2>/dev/null), group $(kill -0 -- -"$pid" 2>/dev/null && echo alive || echo gone)"
out=$(DFLOW_PROC_LIMIT=soon proc_start "$t/lim3" sleep 1 < /dev/null 2>&1); [ $? = 2 ] && [ ! -e "$t/lim3.pid" ] && [ ! -e "$t/lim3.starting" ] && ok || bad "bad DFLOW_PROC_LIMIT accepted: $out"
# T2: .exit appears only after the group is stopped. A run that ignores TERM and forks: the moment
# .exit is there, the group holds no process but the leader (its last step is to write .exit and exit)
others() { /bin/ps -A -o pid=,pgid=,stat= | awk -v g="$1" '$2 == g && $1 != g && $3 !~ /^Z/ { print $1 }' | tr '\n' ' '; }
pid=$(DFLOW_PROC_LIMIT=1 proc_start "$t/lim4" sh -c 'trap "" TERM; (sleep 30; echo late) & sleep 30 & wait; sleep 30' < /dev/null); mine+=("$pid")
left="never"; for i in $(seq 1 400); do [ -f "$t/lim4.exit" ] && { left=$(others "$pid"); break; }; sleep 0.05; done
[ "$left" = "" ] && [ "$(cat "$t/lim4.exit")" = 124 ] && grep -qx "timeout after 1s" "$t/lim4" && ok || bad "timeout: .exit written while the group still had [$left]"
gone "$pid" 10 && ok || bad "timeout: group $pid left after .exit"
# T2: a group that cannot be confirmed stopped (a ps that keeps reporting one more member): no .exit,
# <out>.timeout names it, the leader stays; wait and peek say "running (timeout, not stopped)" (3); stop still works
mkdir -p "$t/stuckps"; printf '#!/bin/sh\n/bin/ps "$@"; rc=$?\n[ "$1" = -A ] && echo "99999999 1 $(/bin/ps -o pgid= -p $$ | tr -d " ") S"\nexit $rc\n' > "$t/stuckps/ps"; chmod +x "$t/stuckps/ps"
pid=$(PATH="$t/stuckps:$PATH" DFLOW_PROC_LIMIT=1 proc_start "$t/lim5" sleep 60 < /dev/null); mine+=("$pid")
for i in $(seq 1 60); do [ -f "$t/lim5.timeout" ] && break; sleep 0.5; done
[ "$(cat "$t/lim5.timeout" 2>/dev/null)" = "timeout after 1s, not stopped: 99999999" ] && [ ! -e "$t/lim5.exit" ] && kill -0 "$pid" 2>/dev/null && ok || bad "unconfirmed stop: timeout $(cat "$t/lim5.timeout" 2>/dev/null), exit $(cat "$t/lim5.exit" 2>/dev/null)"
out=$(proc_peek "$t/lim5"); [ $? = 3 ] && [ "$out" = "running (timeout, not stopped)" ] && ok || bad "peek on an unconfirmed stop: $out"
out=$(proc_wait "$t/lim5" 1); [ $? = 3 ] && [ "$out" = "running (timeout, not stopped)" ] && ok || bad "wait on an unconfirmed stop: $out"
out=$(proc_start "$t/lim5" sh -c 'echo again' < /dev/null 2>&1); [ $? = 1 ] && ok || bad "start over an unconfirmed stop: $out"
out=$(proc_stop "$t/lim5"); [ "$out" = "ok stopped" ] && ! kill -0 -- -"$pid" 2>/dev/null && ok || bad "stop after an unconfirmed stop: $out"
# V2: a confirmed stop keeps <out>.timeout: wait and peek still say "ended timeout, stopped late"
[ -f "$t/lim5.timeout" ] && grep -qx stopped "$t/lim5.timeout" && ok || bad "stop removed or did not mark $t/lim5.timeout: $(cat "$t/lim5.timeout" 2>/dev/null)"
out=$(proc_peek "$t/lim5"); [ $? = 1 ] && [ "$out" = "ended timeout, stopped late" ] && ok || bad "peek after a confirmed stop of a timed-out run: $out"
out=$(proc_wait "$t/lim5" 1); [ $? = 1 ] && [ "$out" = "ended timeout, stopped late" ] && ok || bad "wait after a confirmed stop of a timed-out run: $out"
# U2: <out>.timeout, no .exit, and the leader gone: while its process group still has a member (a group
# whose leader exited and left a child), wait and peek say "running (timeout, not stopped)" (3) and
# start is refused, keeping .pid and .timeout; once the group is empty, "ended timeout, stopped late"
# (1, not lost), start may go ahead, and stop says ok and removes .timeout
lp=$(python3 -I -c '
import os, sys, time
r, w = os.pipe()
if os.fork():
    os.close(w); print(os.read(r, 32).decode()); os.wait(); sys.exit(0)
os.setsid()
if os.fork() == 0:
    n = os.open(os.devnull, os.O_RDWR)
    for fd in (0, 1, 2): os.dup2(n, fd)
    os.close(w); time.sleep(60); os._exit(0)
os.write(w, str(os.getpid()).encode()); os._exit(0)'); mine+=("$lp")
printf '%s %s\nlstart: gone\ncommand: gone\n' "$lp" "$(date +%s)" > "$t/orph.pid"; echo "timeout after 1s, not stopped: x" > "$t/orph.timeout"
! kill -0 "$lp" 2>/dev/null && kill -0 -- -"$lp" 2>/dev/null && ok || bad "test setup: leader $lp gone with its group left"
out=$(proc_peek "$t/orph"); [ $? = 3 ] && [ "$out" = "running (timeout, not stopped)" ] && ok || bad "peek: leader gone, group left: $out"
out=$(proc_wait "$t/orph" 1); [ $? = 3 ] && [ "$out" = "running (timeout, not stopped)" ] && ok || bad "wait: leader gone, group left: $out"
rec=$(cat "$t/orph.pid")
out=$(proc_start "$t/orph" sh -c 'echo again' < /dev/null 2>&1); [ $? = 1 ] && [ "$(cat "$t/orph.pid")" = "$rec" ] && [ -f "$t/orph.timeout" ] && ok || bad "start over a group left behind: $out"
out=$(proc_stop "$t/orph"); [ $? = 1 ] && [ -f "$t/orph.timeout" ] && ok || bad "stop: leader gone, group left: $out"
kill -9 -- -"$lp" 2>/dev/null; gone "$lp" 10 || bad "test setup: group $lp not gone"
out=$(proc_peek "$t/orph"); [ $? = 1 ] && [ "$out" = "ended timeout, stopped late" ] && ok || bad "peek: leader gone, group empty: $out"
out=$(proc_wait "$t/orph" 1); [ $? = 1 ] && [ "$out" = "ended timeout, stopped late" ] && ok || bad "wait: leader gone, group empty: $out"
cp "$t/orph.pid" "$t/orph2.pid"; cp "$t/orph.timeout" "$t/orph2.timeout"
out=$(proc_stop "$t/orph2"); [ $? = 0 ] && [ "$out" = "ok not running" ] && grep -qx stopped "$t/orph2.timeout" 2>/dev/null && ok || bad "stop: leader gone, group empty: $out"
out=$(proc_peek "$t/orph2"); [ $? = 1 ] && [ "$out" = "ended timeout, stopped late" ] && ok || bad "peek after stop: leader gone, group empty: $out"
pid=$(proc_start "$t/orph" sh -c 'echo again' < /dev/null); mine+=("$pid")
out=$(proc_wait "$t/orph" 10); [ "$out" = "ended exit 0" ] && [ ! -e "$t/orph.timeout" ] && grep -qx again "$t/orph" && ok || bad "start once the group is empty: $out"
# V2: the leader is alive and passes the identity check, but kill on its process group is refused
# (EPERM, a stub of the builtin; no signal reaches the group): the group cannot be checked, so stop is
# "not stopped: cannot check the process group", exit 1, and the run is still there
pid=$(proc_start "$t/eperm" sleep 30 < /dev/null); mine+=("$pid"); sleep 0.3
out=$( kill() { case "$*" in *" -- -"*) echo "kill: ($3) - Operation not permitted" >&2; return 1 ;; esac; builtin kill "$@"; }
       proc_stop "$t/eperm" ); rc=$?
[ $rc = 1 ] && [ "$out" = "not stopped: cannot check the process group $pid" ] && kill -0 "$pid" 2>/dev/null && ok || bad "stop with the group not checkable (EPERM): $rc $out"
out=$(proc_stop "$t/eperm"); [ "$out" = "ok stopped" ] && ok || bad "stop once the group can be checked: $out"
# without DFLOW_PROC_LIMIT: no deadline of its own, as before
pid=$(proc_start "$t/nolim" sh -c 'sleep 4; exit 5' < /dev/null); mine+=("$pid")
sleep 3; [ ! -f "$t/nolim.exit" ] && kill -0 "$pid" 2>/dev/null && ok || bad "a run without a limit ended early"
out=$(proc_wait "$t/nolim" 10); [ "$out" = "ended exit 5" ] && ! grep -q timeout "$t/nolim" && ok || bad "a run without a limit: $out"
# the command sees DFLOW_HOLDER_PID, the session leader's pid (the recorded pid), and not the limit
pid=$(DFLOW_PROC_LIMIT=30 proc_start "$t/hp" sh -c 'echo "holder=$DFLOW_HOLDER_PID limit=${DFLOW_PROC_LIMIT:-none}"' < /dev/null); mine+=("$pid")
proc_wait "$t/hp" 10 >/dev/null; grep -qx "holder=$pid limit=none" "$t/hp" && ok || bad "DFLOW_HOLDER_PID: $(cat "$t/hp") (leader $pid)"
echo "proc-test: $pass passed, $fail failed"
[ "$fail" = 0 ]
