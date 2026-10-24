#!/usr/bin/env bash
# Bookkeeping for dflow 多线 (playbooks/lines.md): it records, it never starts, waits for, or wakes a line.
# Files, under <repo>/.dflow/ and never committed:
#   <slug>.units.tsv  unit table (parallel.sh); 多线 adds the columns
#                     carrier model attempt brief report progress_at; a missing column reads as "-"
#   <slug>.tsv        decision log (log.sh); a gate stays open until a later "gate" row with the same
#                     decision has result "closed"
#   <slug>/           standing.md, briefs/<id>-<attempt>.md, reports/<id>-<attempt>.md, run/,
#                     ledger.tsv (id attempt sha result evidence_type verifier evidence ts), status.md
# A receipt is the first line of reports/<id>-<attempt>.md: RECEIPT <id> <attempt> <done|partial|blocked> <sha|path>.
# The worker writes the whole report to <report>.tmp and then renames it: only the final name counts,
# and once it exists it is the delivery (never edited after).
# Every write holds the write lock <slug>/.lock and replaces the file atomically.
#
# Usage:
#   lines.sh init <slug>                  create <slug>/ with ledger.tsv and an empty standing.md; add the
#                                         six columns to the unit table (created if missing), "-" in old rows
#   lines.sh line set <slug> <id> <col>=<val>...
#                                         set columns by header name; adds the row when <id> is new
#   lines.sh receipt <slug> <id> <attempt>
#                                         print "<state> <sha|path>" of a valid receipt; 1 when missing,
#                                         malformed, or naming another id or attempt
#   lines.sh ledger record <slug> <id> <attempt> <sha> <result> <evidence_type> <verifier> <evidence>
#                                         result: pass fail blocked; evidence_type: behavior test review self.
#                                         <sha> must name exactly one commit (hex, full or a unique prefix);
#                                         the full sha is stored. Anything else is refused
#   lines.sh ledger check <slug> <id> <sha>
#                                         0 when the verdict on that commit (full sha, exact) is a pass:
#                                         the latest behavior/test/review row decides when there is one
#                                         (a review pass never counts); only with none, the latest self
#                                         row decides, and its pass counts only with evidence
#                                         "single-command:..." and the brief of that attempt (the table's
#                                         brief column, or <slug>/briefs/<id>-<attempt>.md) whose first
#                                         line is "dflow 线 <slug>/<id>/<attempt>" and which has a line
#                                         "验证<blanks>单命令验证：<command>" (that line alone allows it;
#                                         the word elsewhere does not). Otherwise "NOT-PASSED ..." and
#                                         exit 2; a sha that names no single commit: exit 1
#   lines.sh status <slug> [--print]      write <slug>/status.md and print "counts:", "changed:", "gates open:"
#                                         (changed: lines whose shown fields differ from the last status).
#                                         The board: per line state, carrier, model, attempt, last progress,
#                                         receipt, verdict (the effective one on the delivered commit, as
#                                         ledger check decides: pass, fail, blocked, or 未验), 原始最新 (the
#                                         attempt's latest raw ledger row, not a verdict); verifier lines
#                                         (ids "v-...", paths "-") in their own table; open gates, and the
#                                         latest decision rows of the log.
#                                         --print: print the board only; no file, no snapshot, no lock
#   lines.sh lock acquire <resource> <slug>/<id>/<attempt> <pid>
#                                         on success print one line, the holder's token (keep it; the
#                                         same attempt and pid get the same token again); messages on stderr
#   lines.sh lock release <resource> <token>
#                                         released only with the holder's token. Acquire, takeover and
#                                         release each run whole under one transaction (a flock on
#                                         .txn/<name> beside the lock dir, dropped by the kernel if its holder dies; waited
#                                         for up to DFLOW_LOCK_TXN_WAIT seconds, default 5, else refused)
#   lines.sh lock show <resource>
#                                         machine-wide resource lock at
#                                         ${DFLOW_LOCK_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dflow/locks}/<resource>/holder
#                                         (attempt, pid, command, since, token; show leaves out the token).
#                                         Taken over only when the holder pid is gone (or now runs another
#                                         command); a live pid whose command ps cannot read keeps it
# Exit 0 ok, 1 refused or found a problem, 2 usage (and NOT-PASSED from ledger check).
set -u
cmd=${1:-}; sub=""
die() { echo "FAIL $*"; exit 1; }
usage() { sed -n '2,/^set -u/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 2; }
case $cmd in line|ledger|lock) sub=${2:-}; shift 2 2>/dev/null || usage ;; "") usage ;; *) shift ;; esac
NEW="carrier model attempt brief report progress_at"
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }
clean() { printf '%s' "$1" | tr '\t\n\r' '   '; }
valid() { printf '%s' "$2" | grep -Eq "$1"; }
ID_RE='^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$'; SLUG_RE='^[a-z0-9][a-z0-9-]{0,62}$'; N_RE='^[1-9][0-9]{0,5}$'

# --- locks: a directory with a holder file, created by one rename so it never exists half-written ---
canps=1; ps -o pid= -p $$ >/dev/null 2>&1 || canps=0
pcmd() { [ $canps = 1 ] && ps -ww -o command= -p "$1" 2>/dev/null || echo "?"; }
hfield() { sed -n "s/^$2: //p" "$1" 2>/dev/null | head -1; }
alive() { # <pid> <command>: that process still runs, with the recorded command when ps can tell
    [ -n "$1" ] && kill -0 "$1" 2>/dev/null || return 1
    [ $canps = 1 ] && [ -n "$2" ] && [ "$2" != "?" ] || return 0
    [ "$(pcmd "$1")" = "$2" ]
}
rename() { python3 -I -c 'import os, sys
try: os.rename(sys.argv[1], sys.argv[2])
except OSError: sys.exit(1)' "$1" "$2"; }
token() { od -An -tx1 -N16 /dev/urandom | tr -d ' \n'; }
lk_install() { # <dir> <attempt> <pid> <token>: fails when <dir> exists
    local tmp="$1.new.$$"; rm -rf "$tmp"; mkdir -p "$tmp" || return 1
    printf 'attempt: %s\npid: %s\ncommand: %s\nsince: %s\ntoken: %s\n' "$2" "$3" "$(pcmd "$3")" "$(now)" "$4" > "$tmp/holder"
    rename "$tmp" "$1" && return 0
    rm -rf "$tmp"; return 1
}
# Every acquire, takeover and release of <dir> runs whole inside one transaction: an exclusive flock on
# the file .txn/<name> next to <dir> (a resource name never starts with ".", so no resource can collide
# with it; the ledger's own lock is .lock, which only it uses), held on fd 9 of this shell. Nobody can see or take the lock while another call is
# between moving it aside, checking it, and putting it back or installing a new holder. The kernel
# drops the flock when its holder dies, so a dead holder never blocks the next call. A call that cannot
# get the transaction within DFLOW_LOCK_TXN_WAIT seconds (default 5) is refused, and touches nothing.
txn_enter() { # <dir>
    local t; t="$(dirname "$1")/.txn"; mkdir -p "$t" || return 1
    exec 9>>"$t/$(basename "$1")" || return 1
    python3 -I -c 'import fcntl, sys, time
end = time.time() + float(sys.argv[1])
while True:
    try:
        fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB); sys.exit(0)
    except OSError:
        if time.time() > end: sys.exit(1)
        time.sleep(0.02)' "${DFLOW_LOCK_TXN_WAIT:-5}" 2>/dev/null && return 0
    exec 9>&-; return 1
}
txn_leave() { exec 9>&-; }
# lk_acquire/lk_release print nothing: they set LK_MSG (one line) and, on a successful acquire, LK_TOKEN
lk_acquire() { # <dir> <attempt> <pid>: 0 held by the caller, 1 refused
    local tok rc; tok=$(token); LK_TOKEN=""
    [ -n "$tok" ] || { LK_MSG="FAIL cannot read /dev/urandom for a token"; return 1; }
    mkdir -p "$(dirname "$1")" || { LK_MSG="FAIL cannot create $(dirname "$1")"; return 1; }
    txn_enter "$1" || { LK_MSG="FAIL $1 is busy (another acquire or release holds its .txn file); retry"; return 1; }
    lk_acquire_txn "$1" "$2" "$3" "$tok"; rc=$?
    txn_leave; return $rc
}
lk_acquire_txn() { # <dir> <attempt> <pid> <token>, inside the transaction
    local dir=$1 ha hp hc ht
    lk_install "$dir" "$2" "$3" "$4" && { LK_TOKEN=$4; LK_MSG="ok acquired $dir"; return 0; }
    [ -f "$dir/holder" ] || [ $(( $(date +%s) - $(mtime "$dir") )) -gt 10 ] || { LK_MSG="FAIL $dir is being created; retry"; return 1; }
    ha=$(hfield "$dir/holder" attempt); hp=$(hfield "$dir/holder" pid)
    hc=$(hfield "$dir/holder" command); ht=$(hfield "$dir/holder" token)
    if [ "$ha" = "$2" ] && [ "$hp" = "$3" ] && [ -n "$ht" ]; then LK_TOKEN=$ht; LK_MSG="ok already held by $2"; return 0; fi
    if alive "$hp" "$hc"; then LK_MSG="FAIL held by ${ha:-?} (pid $hp is alive)"; return 1; fi
    # the holder is gone: move its lock aside and install the caller (no other call runs meanwhile)
    rename "$dir" "$dir.stale.$$" || { LK_MSG="FAIL could not move the stale lock $dir aside"; return 1; }
    rm -rf "$dir.stale.$$"
    lk_install "$dir" "$2" "$3" "$4" || { LK_MSG="FAIL could not install the new holder of $dir"; return 1; }
    LK_TOKEN=$4; LK_MSG="ok took over $dir from ${ha:-?} (pid ${hp:-?} gone)"; return 0
}
lk_release() { # <dir> <token>
    local rc
    [ -d "$1" ] || { LK_MSG="ok not held"; return 0; }
    txn_enter "$1" || { LK_MSG="FAIL $1 is busy (another acquire or release holds its .txn file); not released, retry"; return 1; }
    lk_release_txn "$1" "$2"; rc=$?
    txn_leave; return $rc
}
lk_release_txn() { # <dir> <token>, inside the transaction
    local ht ha
    [ -d "$1" ] || { LK_MSG="ok not held"; return 0; }
    ht=$(hfield "$1/holder" token); ha=$(hfield "$1/holder" attempt)
    [ -n "$2" ] && [ "$ht" = "$2" ] || { LK_MSG="FAIL $1 is held by ${ha:-?} under another token; not released"; return 1; }
    rename "$1" "$1.rel.$$" || { LK_MSG="FAIL could not move $1 aside; not released"; return 1; }
    rm -rf "$1.rel.$$"; LK_MSG="ok released $1"
}

if [ "$cmd" = lock ]; then
    res=${1:-}; [ -n "$res" ] || usage
    valid '^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$' "$res" || die "bad resource name: $res"
    ldir="${DFLOW_LOCK_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dflow/locks}/$res"
    case $sub in
    acquire)
        att=${2:-}; pid=${3:-}; [ -n "$att" ] && [ -n "$pid" ] || usage
        valid '^[a-z0-9][a-z0-9-]*/[A-Za-z0-9][A-Za-z0-9._-]*/[1-9][0-9]*$' "$att" || { echo "FAIL attempt must be <slug>/<id>/<n>: $att" >&2; exit 1; }
        valid '^[1-9][0-9]*$' "$pid" && kill -0 "$pid" 2>/dev/null || { echo "FAIL pid $pid is not a running process" >&2; exit 1; }
        lk_acquire "$ldir" "$att" "$pid"; rc=$?
        echo "$LK_MSG" >&2; [ $rc = 0 ] && echo "$LK_TOKEN"; exit $rc ;;
    release)
        [ -n "${2:-}" ] || usage
        lk_release "$ldir" "$2"; rc=$?; echo "$LK_MSG"; exit $rc ;;
    show)
        [ -f "$ldir/holder" ] || { echo "free $res"; exit 0; }
        grep -v '^token: ' "$ldir/holder"
        if alive "$(hfield "$ldir/holder" pid)" "$(hfield "$ldir/holder" command)"; then echo "state: alive"; else echo "state: gone"; fi ;;
    *) usage ;;
    esac
    exit 0
fi

slug=${1:-}; [ -n "$slug" ] || usage
valid "$SLUG_RE" "$slug" || die "bad slug: $slug"
root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not in a git repository"
cd "$root" || exit 1
table=".dflow/$slug.units.tsv"; d=".dflow/$slug"; ledger="$d/ledger.tsv"; dlog=".dflow/$slug.tsv"
set -f

wlock() { # the write lock, retried for up to 10 seconds; released on exit
    local i
    for i in $(seq 1 100); do
        lk_acquire "$d/.lock" "lines/$slug/$$" "$$" && { wtok=$LK_TOKEN; trap 'lk_release "$d/.lock" "$wtok"' EXIT; return 0; }
        sleep 0.1
    done
    die "write lock $d/.lock: $LK_MSG"
}
replace() { mv -f "$1" "$2"; }  # <tmp> <file>: atomic within one directory
need_init() { [ -f "$ledger" ] || die "no $ledger; run lines.sh init $slug"; }
header() { head -1 "$table" 2>/dev/null; }
has_col() { header | tr '\t' '\n' | grep -qxF "$1"; }
tcol() { # <id> <col>: the value, "-" when the column or the value is missing; nothing when no such row
    awk -F'\t' -v id="$1" -v c="$2" 'NR == 1 { for (i = 1; i <= NF; i++) h[$i] = i; next }
        $h["id"] == id { v = (c in h) ? $h[c] : ""; print (v == "" ? "-" : v); exit }' "$table"
}
ids() { awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) h[$i] = i; next } $h["id"] != "" { print $h["id"] }' "$table"; }
receipt_of() { # <id> <attempt>: "<state> <ref>", or the reason (return 1)
    local f="$d/reports/$1-$2.md" r
    [ -f "$f" ] || { echo "no receipt $f"; return 1; }
    r=$(head -1 "$f" | tr -d '\r' | awk -v id="$1" -v a="$2" '
        NF == 5 && $1 == "RECEIPT" && $2 == id && $3 == a && ($4 == "done" || $4 == "partial" || $4 == "blocked") { print $4, $5; exit }
        { print "BAD" }')
    case $r in BAD|"") echo "bad receipt $f: first line must be RECEIPT $1 $2 <done|partial|blocked> <sha|path>"; return 1 ;; esac
    echo "$r"
}
resolve() { # <sha>: the one full commit id it names (hex, full or a unique prefix); nothing and 1 otherwise
    local f
    valid '^[0-9a-f]{4,40}$' "$1" || return 1
    f=$(git rev-parse -q --verify "$1^{commit}" 2>/dev/null) || return 1
    case $f in "$1"*) echo "$f" ;; *) return 1 ;; esac
}
brief_of() { # <id> <attempt>: the brief file of that attempt
    local b="-"
    [ -f "$table" ] && [ "$(tcol "$1" attempt)" = "$2" ] && b=$(tcol "$1" brief)
    [ -n "$b" ] && [ "$b" != - ] && echo "$b" || echo "$d/briefs/$1-$2.md"
}
verdict_raw() { # <id> <full sha>: "<effective>\t<reason>"; effective: pass fail blocked none
    local v b
    v=$(awk -F'\t' -v id="$1" -v s="$2" '
        NR == 1 { for (i = 1; i <= NF; i++) h[$i] = i; next }
        $h["id"] != id { next }
        $h["sha"] != s { if ($h["result"] == "pass") other = other " " $h["sha"]; next }
        $h["evidence_type"] == "review" && $h["result"] == "pass" { next }  # a reading can fail a sha, never pass it
        $h["evidence_type"] != "self" { nr = $h["result"]; nt = $h["evidence_type"]; nv = $h["verifier"]; next }
        { sr = $h["result"]; sv = $h["verifier"]; sa = $h["attempt"]; se = (index($h["evidence"], "single-command:") == 1) }
        END { if (nr != "") {
                  if (nr == "pass" && (nt == "behavior" || nt == "test")) print "pass\tok"
                  else if (nr == "pass") print "none\tlatest verdict on this sha is a " nt " pass, which never counts"
                  else print nr "\tlatest verdict on this sha is " nr " (" nt ", " nv ")" }
              else if (sr != "") {
                  if (sr != "pass") print sr "\tlatest verdict on this sha is " sr " (self, " sv ")"
                  else if (!se) print "none\tonly a self pass without single-command: evidence on this sha"
                  else print "SELF\t" sa }
              else if (other != "") print "none\tno verdict on this sha; pass recorded on" other " only"
              else print "none\tno verdict on this sha" }' "$ledger")
    case $v in
    SELF$'\t'*)
        b=$(brief_of "$1" "${v#SELF?}")
        if self_allowed "$b" "$1" "${v#SELF?}"; then printf 'pass\tok\n'
        else printf 'none\tonly a self pass on this sha, and brief %s does not allow it (it needs its first line "dflow 线 %s/%s/%s" and a line "验证 单命令验证：<命令>")\n' "$b" "$slug" "$1" "${v#SELF?}"; fi ;;
    *) printf '%s\n' "$v" ;;
    esac
}
self_allowed() { # <brief> <id> <attempt>: the brief is that attempt's, and has the line "验证<blanks>单命令验证：<command>"
    [ -f "$1" ] || return 1
    [ "$(head -1 "$1" | tr -d '\r')" = "dflow 线 $slug/$2/$3" ] || return 1
    tr -d '\r' < "$1" | LC_ALL=C grep -Eq '^验证[[:space:]]+单命令验证：[[:space:]]*[^[:space:]]'
}
verdict() { local v; v=$(verdict_raw "$@"); printf '%s\n' "${v#*$'\t'}"; }    # "ok" or the reason
effective() { local v; v=$(verdict_raw "$@"); printf '%s\n' "${v%%$'\t'*}"; } # pass fail blocked none
line_rows() { # one row per line, tab-separated: id state carrier model attempt progress_at receipt verdict raw
    local id st att rc vd raw r ref full e
    for id in $(ids); do
        st=$(tcol "$id" state); att=$(tcol "$id" attempt); rc="-"; vd="未验"; raw="-"; ref=""
        if valid "$N_RE" "$att"; then
            if r=$(receipt_of "$id" "$att"); then rc=$r; ref=${r#* }; else rc="无"; fi
            # the verdict column is the effective verdict (as ledger check decides it) on the delivered
            # commit: the receipt's sha, else the sha of this attempt's latest ledger row
            full=$(resolve "$ref") || { full=$(awk -F'\t' -v id="$id" -v a="$att" 'NR > 1 && $1 == id && $2 == a { s = $3 } END { print s }' "$ledger"); ref=${full:0:12}; }
            if [ -n "$full" ]; then
                e=$(effective "$id" "$full")
                [ "$e" = none ] || vd="$e @$ref"
            fi
            raw=$(awk -F'\t' -v id="$id" -v a="$att" 'NR > 1 && $1 == id && $2 == a { v = $4 " " $5 " @" substr($3, 1, 12) } END { print (v == "" ? "-" : v) }' "$ledger")
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$st" "$(tcol "$id" carrier)" "$(tcol "$id" model)" "$att" "$(tcol "$id" progress_at)" "$rc" "$vd" "$raw"
    done
}
board() { # <rows from line_rows>: the board in Markdown; sets GATES_OPEN
    local rows=$1 ng=0 nd=0 ts q why gates dec
    md_table() { # <awk filter on the id>
        echo "| 线 | 状态 | 载体 | 模型 | 尝试 | 最近进展 | 回执 | 验收 | 原始最新 |"
        echo "|---|---|---|---|---|---|---|---|---|"
        printf '%s\n' "$rows" | awk -F'\t' "NF && $1"' { for (i = 1; i <= NF; i++) gsub(/\|/, "/", $i); printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6, $7, $8, $9 }'
    }
    echo "# 多线看板 $slug"
    echo
    echo "生成于 $(now)，取自单元表、ledger.tsv、回执和决策日志；进程和 git 状态以现场核对为准。"
    echo "验收：交付提交上的有效结论（同 ledger check：pass、fail、blocked，无有效结论为未验）；原始最新：本尝试最后一条 ledger 原始记录，不是结论。"
    echo
    md_table '$1 !~ /^v-/'
    if printf '%s\n' "$rows" | grep -q '^v-'; then echo; echo "## 验收线"; echo; md_table '$1 ~ /^v-/'; fi
    gates=$(awk -F'\t' 'NR > 1 && $2 == "gate" { if ($6 == "closed") delete open[$3]; else { open[$3] = $1 "\t" $3 "\t" $4; if (!($3 in seen)) { seen[$3] = 1; order[++n] = $3 } } }
        END { for (i = 1; i <= n; i++) if (order[i] in open) print open[order[i]] }' "$dlog" 2>/dev/null)
    echo; echo "## 等你定"; echo
    while IFS=$'\t' read -r ts q why; do
        [ -n "$q" ] || continue; ng=$((ng + 1)); echo "- ${q}（${why}；${ts}，见 ${dlog}）"
    done <<< "$gates"
    [ $ng -gt 0 ] || echo "- 无"
    dec=$(awk -F'\t' 'NR > 1 && $2 == "decision" { print $1 "\t" $3 "\t" $4 }' "$dlog" 2>/dev/null | tail -5)
    echo; echo "## 最近决定"; echo
    while IFS=$'\t' read -r ts q why; do
        [ -n "$q" ] || continue; nd=$((nd + 1)); echo "- ${q}（${why}；${ts}）"
    done <<< "$dec"
    [ $nd -gt 0 ] || echo "- 无"
    GATES_OPEN=$ng
}

case $cmd:$sub in
init:)
    ex=$(git rev-parse --git-path info/exclude); case $ex in /*) ;; *) ex="$root/$ex" ;; esac
    mkdir -p "$(dirname "$ex")" "$d/briefs" "$d/reports" "$d/run" || die "cannot create $d"
    grep -qxF .dflow/ "$ex" 2>/dev/null || echo .dflow/ >> "$ex"
    wlock
    [ -f "$d/standing.md" ] || : > "$d/standing.md"
    if [ ! -f "$ledger" ]; then printf 'id\tattempt\tsha\tresult\tevidence_type\tverifier\tevidence\tts\n' > "$ledger.tmp.$$" && replace "$ledger.tmp.$$" "$ledger"; fi
    if [ ! -f "$table" ]; then
        printf 'id\tdeps\tpaths\tstate\tbase\tagent\tbranch\tdispatched_at\ttries\tlanded\t%s\n' "$(echo $NEW | tr ' ' '\t')" > "$table.tmp.$$"
        replace "$table.tmp.$$" "$table"
    else
        add=""; for c in $NEW; do has_col "$c" || add="$add $c"; done
        if [ -n "$add" ]; then
            awk -F'\t' -v OFS='\t' -v add="$add" 'NR == 1 { n = split(add, a, " "); for (i = 1; i <= n; i++) $(NF + 1) = a[i]; nf = NF; print; next }
                { for (i = NF + 1; i <= nf; i++) $i = "-"; print }' "$table" > "$table.tmp.$$" && replace "$table.tmp.$$" "$table"
        fi
    fi
    echo "ok init $d" ;;
line:set)
    id=${2:-}; shift 2 2>/dev/null; [ -n "$id" ] && [ $# -gt 0 ] || usage
    valid "$ID_RE" "$id" || die "bad id: $id"
    [ -f "$table" ] || die "no unit table $table; run lines.sh init $slug"
    wlock
    a="$d/.set.$$"; : > "$a"
    for kv in "$@"; do
        case $kv in *=*) ;; *) rm -f "$a"; usage ;; esac
        k=${kv%%=*}; v=$(clean "${kv#*=}")
        [ "$k" != id ] || { rm -f "$a"; die "id cannot be set"; }
        has_col "$k" || { rm -f "$a"; die "no column $k in $table (run lines.sh init $slug)"; }
        printf '%s\t%s\n' "$k" "${v:--}" >> "$a"
    done
    awk -F'\t' -v OFS='\t' -v id="$id" 'FNR == NR { set[$1] = $2; next }
        FNR == 1 { for (i = 1; i <= NF; i++) h[$i] = i; nf = NF; print; next }
        $h["id"] == id { for (k in set) $h[k] = set[k]; for (i = 1; i <= nf; i++) if ($i == "") $i = "-"; f = 1 }
        { print }
        END { if (!f) { for (i = 1; i <= nf; i++) $i = "-"; $h["id"] = id; for (k in set) $h[k] = set[k]; print; print "added" > "/dev/stderr" } }' \
        "$a" "$table" > "$table.tmp.$$" 2> "$a.err" || { rm -f "$a" "$a.err" "$table.tmp.$$"; die "could not update $table"; }
    replace "$table.tmp.$$" "$table"
    grep -q added "$a.err" && echo "ok added $id" || echo "ok set $id"; rm -f "$a" "$a.err" ;;
receipt:)
    id=${2:-}; att=${3:-}; [ -n "$id" ] && [ -n "$att" ] || usage
    valid "$ID_RE" "$id" && valid "$N_RE" "$att" || die "bad id or attempt: $id $att"
    out=$(receipt_of "$id" "$att") || { echo "FAIL $out"; exit 1; }
    echo "$out" ;;
ledger:record)
    [ $# = 8 ] || usage
    id=$2; att=$3; sha=$4; res=$5; et=$6; who=$7; ev=$8
    valid "$ID_RE" "$id" && valid "$N_RE" "$att" || die "bad id or attempt: $id $att"
    case $res in pass|fail|blocked) ;; *) die "result must be pass, fail or blocked: $res" ;; esac
    case $et in behavior|test|review|self) ;; *) die "evidence_type must be behavior, test, review or self: $et" ;; esac
    [ -n "$sha" ] && [ -n "$who" ] && [ -n "$ev" ] || usage
    full=$(resolve "$sha") || die "$sha does not name exactly one commit (give a full or unique sha)"
    need_init; wlock
    cp "$ledger" "$ledger.tmp.$$" || die "cannot copy $ledger"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$att" "$full" "$res" "$et" "$(clean "$who")" "$(clean "$ev")" "$(now)" >> "$ledger.tmp.$$"
    replace "$ledger.tmp.$$" "$ledger"
    echo "ok recorded $id/$att $res ($et) at $full" ;;
ledger:check)
    id=${2:-}; sha=${3:-}; [ -n "$id" ] && [ -n "$sha" ] || usage
    need_init
    full=$(resolve "$sha") || die "$sha does not name exactly one commit (give a full or unique sha)"
    v=$(verdict "$id" "$full")
    [ "$v" = ok ] && { echo "ok passed $id at $full"; exit 0; }
    echo "NOT-PASSED $id at $full: $v"; exit 2 ;;
status:)
    case ${2:-} in ""|--print) ;; *) usage ;; esac
    [ -f "$table" ] || die "no unit table $table"
    need_init
    if [ "${2:-}" = --print ]; then # read only: nothing written, no lock
        board "$(line_rows)"; exit 0
    fi
    wlock
    snap="$d/.status.snap"; new="$d/.status.snap.tmp.$$"; md="$d/status.md.tmp.$$"
    line_rows > "$new"
    board "$(cat "$new")" > "$md"; ng=$GATES_OPEN
    replace "$md" "$d/status.md"
    if [ -f "$snap" ]; then changed=$(awk -F'\t' 'FNR == NR { old[$1] = $0; next } old[$1] != $0 { printf "%s ", $1 }' "$snap" "$new")
    else changed=$(cut -f1 "$new" | tr '\n' ' '); fi
    total=$(grep -c . "$new"); recs=$(awk -F'\t' '$7 != "-" && $7 != "无"' "$new" | grep -c .); passed=$(awk -F'\t' '$8 ~ /^pass @/' "$new" | grep -c .)
    sc=$(cut -f2 "$new" | sort | uniq -c | awk '{ printf "%s%s %s", (NR > 1 ? ", " : ""), $2, $1 }')
    replace "$new" "$snap"
    echo "counts: $total lines${sc:+; $sc}; receipts $recs; passed $passed"
    changed=${changed% }; echo "changed: ${changed:-none}"
    echo "gates open: $ng" ;;
*) usage ;;
esac
