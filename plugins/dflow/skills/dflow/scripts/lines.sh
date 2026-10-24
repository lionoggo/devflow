#!/usr/bin/env bash
# Bookkeeping for dflow 多线 (playbooks/lines.md): it records, it never starts, waits for, or wakes a line.
# Files, under <repo>/.dflow/ and never committed:
#   <slug>.units.tsv  unit table (parallel.sh); 多线 adds the columns
#                     carrier model attempt brief report progress_at; a missing column reads as "-"
#   <slug>.tsv        decision log (log.sh); a gate stays open until a later "gate" row with the same
#                     decision has result "closed"
#   <slug>/           standing.md, briefs/<id>-<attempt>.md, reports/<id>-<attempt>.md, run/,
#                     ledger.tsv (id attempt sha result evidence_type verifier evidence ts), status.md
# A receipt is the first line of reports/<id>-<attempt>.md: RECEIPT <id> <attempt> <done|partial|blocked> <sha|path>
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
#                                         result: pass fail blocked; evidence_type: behavior test review self
#   lines.sh ledger check <slug> <id> <sha>
#                                         0 when that sha has a pass of type behavior or test (or self with
#                                         evidence "single-command:...") and no later fail or blocked;
#                                         otherwise "NOT-PASSED ..." and exit 2. A review pass never counts
#   lines.sh status <slug>                write <slug>/status.md; print "counts:", "changed:", "gates open:"
#   lines.sh lock acquire <resource> <slug>/<id>/<attempt> <pid>
#   lines.sh lock release <resource> <slug>/<id>/<attempt>
#   lines.sh lock show <resource>
#                                         machine-wide resource lock at
#                                         ${DFLOW_LOCK_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dflow/locks}/<resource>/holder
#                                         (attempt, pid, command, since). Taken over only when the holder pid
#                                         is gone (or now runs another command); released only by its attempt
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
lk_install() { # <dir> <attempt> <pid>: fails when <dir> exists
    local tmp="$1.new.$$"; rm -rf "$tmp"; mkdir -p "$tmp" || return 1
    printf 'attempt: %s\npid: %s\ncommand: %s\nsince: %s\n' "$2" "$3" "$(pcmd "$3")" "$(now)" > "$tmp/holder"
    rename "$tmp" "$1" && return 0
    rm -rf "$tmp"; return 1
}
lk_acquire() { # <dir> <attempt> <pid>: prints one line; 0 held by the caller, 1 refused
    local dir=$1 snap ha hp hc tk="$1.takeover"
    mkdir -p "$(dirname "$dir")" || { echo "FAIL cannot create $(dirname "$dir")"; return 1; }
    lk_install "$dir" "$2" "$3" && { echo "ok acquired $dir"; return 0; }
    [ -f "$dir/holder" ] || [ $(( $(date +%s) - $(mtime "$dir") )) -gt 10 ] || { echo "FAIL $dir is being created; retry"; return 1; }
    snap=$(cat "$dir/holder" 2>/dev/null); ha=$(hfield "$dir/holder" attempt); hp=$(hfield "$dir/holder" pid); hc=$(hfield "$dir/holder" command)
    if [ "$ha" = "$2" ] && [ "$hp" = "$3" ]; then echo "ok already held by $2"; return 0; fi
    if alive "$hp" "$hc"; then echo "FAIL held by ${ha:-?} (pid $hp is alive)"; return 1; fi
    # The holder is gone. Takers queue on <dir>.takeover; then rename, and check the renamed holder is
    # still the one judged gone (a newer holder is put back and the takeover refused).
    if ! mkdir "$tk" 2>/dev/null; then
        [ $(( $(date +%s) - $(mtime "$tk") )) -gt 10 ] && rename "$tk" "$tk.dead.$$" && rm -rf "$tk.dead.$$"
        mkdir "$tk" 2>/dev/null || { echo "FAIL another takeover of $dir is in progress; retry"; return 1; }
    fi
    if [ "$(cat "$dir/holder" 2>/dev/null)" != "$snap" ]; then rmdir "$tk"; echo "FAIL holder of $dir changed; retry"; return 1; fi
    if ! rename "$dir" "$dir.stale.$$"; then rmdir "$tk"; echo "FAIL lost the race for $dir; retry"; return 1; fi
    if [ "$(cat "$dir.stale.$$/holder" 2>/dev/null)" != "$snap" ]; then
        rename "$dir.stale.$$" "$dir" || echo "FAIL could not put back $dir (left at $dir.stale.$$)"
        rmdir "$tk"; echo "FAIL holder of $dir changed during takeover; put back, not taken"; return 1
    fi
    rm -rf "$dir.stale.$$"
    if ! lk_install "$dir" "$2" "$3"; then rmdir "$tk"; echo "FAIL lost the race for $dir; retry"; return 1; fi
    rmdir "$tk"; echo "ok took over $dir from ${ha:-?} (pid ${hp:-?} gone)"; return 0
}
lk_release() { # <dir> <attempt>
    [ -d "$1" ] || { echo "ok not held"; return 0; }
    local ha; ha=$(hfield "$1/holder" attempt)
    [ "$ha" = "$2" ] || { echo "FAIL $1 is held by ${ha:-?}, not $2"; return 1; }
    rename "$1" "$1.rel.$$" && rm -rf "$1.rel.$$" && echo "ok released $1"
}

if [ "$cmd" = lock ]; then
    res=${1:-}; [ -n "$res" ] || usage
    valid '^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$' "$res" || die "bad resource name: $res"
    ldir="${DFLOW_LOCK_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dflow/locks}/$res"
    case $sub in
    acquire)
        att=${2:-}; pid=${3:-}; [ -n "$att" ] && [ -n "$pid" ] || usage
        valid '^[a-z0-9][a-z0-9-]*/[A-Za-z0-9][A-Za-z0-9._-]*/[1-9][0-9]*$' "$att" || die "attempt must be <slug>/<id>/<n>: $att"
        valid '^[1-9][0-9]*$' "$pid" && kill -0 "$pid" 2>/dev/null || die "pid $pid is not a running process"
        lk_acquire "$ldir" "$att" "$pid"; exit $? ;;
    release) [ -n "${2:-}" ] || usage; lk_release "$ldir" "$2"; exit $? ;;
    show)
        [ -f "$ldir/holder" ] || { echo "free $res"; exit 0; }
        cat "$ldir/holder"
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

wlocked=""
wlock() { # the write lock, retried for up to 10 seconds; released on exit
    local i out
    for i in $(seq 1 100); do
        out=$(lk_acquire "$d/.lock" "lines/$slug/$$" "$$") && { wlocked=1; trap 'lk_release "$d/.lock" "lines/$slug/$$" >/dev/null' EXIT; return 0; }
        sleep 0.1
    done
    die "write lock $d/.lock: $out"
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
full_sha() { git rev-parse -q --verify "$1^{commit}" 2>/dev/null || printf '%s\n' "$1"; }
verdict() { # <id> <sha>: "ok" or the reason
    awk -F'\t' -v id="$1" -v s="$2" '
        function same(a, b) { if (a == b) return 1
            if (a ~ /^[0-9a-f]+$/ && b ~ /^[0-9a-f]+$/ && length(a) >= 7 && length(b) >= 7) return index(a, b) == 1 || index(b, a) == 1
            return 0 }
        NR == 1 { for (i = 1; i <= NF; i++) h[$i] = i; next }
        $h["id"] != id { next }
        !same($h["sha"], s) { if ($h["result"] == "pass") other = other " " $h["sha"]; next }
        { r = $h["result"]; t = $h["evidence_type"]; n++
          if (r == "pass" && (t == "behavior" || t == "test" || (t == "self" && index($h["evidence"], "single-command:") == 1))) ok = 1
          else if (r == "pass") weak = t
          else { ok = 0; last = r " (" t ", " $h["verifier"] ")" } }
        END { if (ok) print "ok"
              else if (last != "") print "latest verdict on this sha is " last
              else if (weak != "") print "only a " weak " pass on this sha (review never counts; self needs single-command: evidence)"
              else if (other != "") print "no verdict on this sha; pass recorded on" other " only"
              else print "no verdict on this sha" }' "$ledger"
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
    need_init; wlock
    cp "$ledger" "$ledger.tmp.$$" || die "cannot copy $ledger"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$att" "$(clean "$(full_sha "$sha")")" "$res" "$et" "$(clean "$who")" "$(clean "$ev")" "$(now)" >> "$ledger.tmp.$$"
    replace "$ledger.tmp.$$" "$ledger"
    echo "ok recorded $id/$att $res ($et)" ;;
ledger:check)
    id=${2:-}; sha=${3:-}; [ -n "$id" ] && [ -n "$sha" ] || usage
    need_init
    v=$(verdict "$id" "$(full_sha "$sha")")
    [ "$v" = ok ] && { echo "ok passed $id at $sha"; exit 0; }
    echo "NOT-PASSED $id at $sha: $v"; exit 2 ;;
status:)
    [ -f "$table" ] || die "no unit table $table"
    need_init; wlock
    snap="$d/.status.snap"; new="$d/.status.snap.tmp.$$"; md="$d/status.md.tmp.$$"; : > "$new"
    total=0; recs=0; passed=0; states=""
    {
        echo "# 多线看板 $slug"
        echo
        echo "生成于 $(now)，取自单元表、ledger.tsv 和回执；进程和 git 状态以现场核对为准。"
        echo
        echo "| 线 | 状态 | 载体 | 模型 | 尝试 | 最近进展 | 回执 | 验收 |"
        echo "|---|---|---|---|---|---|---|---|"
    } > "$md"
    for id in $(ids); do
        total=$((total + 1))
        st=$(tcol "$id" state); att=$(tcol "$id" attempt); states="$states $st"
        rc="-"; vd="-"
        if valid "$N_RE" "$att"; then
            if r=$(receipt_of "$id" "$att"); then rc=$r; recs=$((recs + 1))
                set -- $r
                if [ "$(verdict "$id" "$(full_sha "$2")")" = ok ]; then vd="pass @$2"; passed=$((passed + 1)); fi
            else rc="无"; fi
        fi
        if [ "$vd" = - ]; then
            vd=$(awk -F'\t' -v id="$id" -v a="$att" 'NR > 1 && $1 == id && $2 == a { v = $4 " " $5 " @" substr($3, 1, 12) } END { print (v == "" ? "-" : v) }' "$ledger")
        fi
        printf '| %s | %s | %s | %s | %s | %s | %s | %s |\n' "$id" "$st" "$(tcol "$id" carrier)" "$(tcol "$id" model)" "$att" \
            "$(tcol "$id" progress_at)" "$(printf '%s' "$rc" | tr '|' '/')" "$(printf '%s' "$vd" | tr '|' '/')" >> "$md"
        printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$st" "$att" "$rc" "$vd" >> "$new"
    done
    gates=$(awk -F'\t' 'NR > 1 && $2 == "gate" { if ($6 == "closed") delete open[$3]; else { open[$3] = $1 "\t" $3 "\t" $4; if (!($3 in seen)) { seen[$3] = 1; order[++n] = $3 } } }
        END { for (i = 1; i <= n; i++) if (order[i] in open) print open[order[i]] }' "$dlog" 2>/dev/null)
    ng=0; { echo; echo "## 等你定"; echo; } >> "$md"
    while IFS=$'\t' read -r ts q why; do
        [ -n "$q" ] || continue; ng=$((ng + 1)); echo "- ${q}（${why}；${ts}，见 ${dlog}）" >> "$md"
    done <<< "$gates"
    [ $ng -gt 0 ] || echo "- 无" >> "$md"
    replace "$md" "$d/status.md"
    changed=$(awk -F'\t' 'FNR == NR { old[$1] = $0; next } old[$1] != $0 { printf "%s ", $1 }' "$snap" "$new" 2>/dev/null || cut -f1 "$new" | tr '\n' ' ')
    [ -f "$snap" ] || changed=$(cut -f1 "$new" | tr '\n' ' ')
    replace "$new" "$snap"
    sc=$(printf '%s\n' $states | sort | uniq -c | awk '{ printf "%s%s %s", (NR > 1 ? ", " : ""), $2, $1 }')
    echo "counts: $total lines${sc:+; $sc}; receipts $recs; passed $passed"
    changed=${changed% }; echo "changed: ${changed:-none}"
    echo "gates open: $ng" ;;
*) usage ;;
esac
