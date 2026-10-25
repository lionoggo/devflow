#!/usr/bin/env bash
# Mechanical steps of dflow parallel implementation (references/parallel.md).
# Unit table: <repo>/.dflow/<slug>.units.tsv, tab-separated, header
#   id deps paths state base agent branch dispatched_at tries landed
# (多线 appends carrier model attempt brief report progress_at; columns are read by header name).
# paths: space-separated globs the unit may write ("*" crosses "/"); "-" alone: it writes nothing
# (a read-only line, such as a verifier), so it takes no part in overlap and scope requires no change.
# Only the coordinating session writes the table; this script only reads it.
#
# Usage: parallel.sh <command> <slug> [id] [sha]
#   prepare  <slug>       exclude .claude/worktrees/ and .dflow/; require a clean tree; create the table
#   overlap  <slug>       unit paths pairwise disjoint, inside the manifest's allow, outside protect.
#                         Needs the manifest .dflow/<slug>.md with an "allow:" line in its leading
#                         key block, else exit 1 naming what is missing; "protect:" may be left out,
#                         and "protect: -" means no protected paths
#   worktree <slug> <id>  for a host whose subagents have no worktree isolation (Codex): create
#                         .dflow/worktrees/<slug>-<id> on branch dflow-unit/<slug>-<id> at the
#                         unit's base; prints the path and branch for the brief and the table.
#                         A sent-back unit (tries > 0) whose worktree is not at the new base is refused
#   scope    <slug> <id> [sha]
#                         base is an ancestor of the unit branch; every changed file is in the unit's paths
#                         (paths "-": the branch must change nothing)
#   land     <slug> <id> [sha]
#                         the scope check (at <sha>, else the branch head), clean tree + ancestor check, then
#                         `cherry-pick -n base..branch`; on conflict abort.
#                         With <sha> (scope too): it must name one commit, and the unit branch's head must be
#                         exactly that commit; a branch that moved after <sha> was verified is refused.
#                         Every changed file must also be inside the manifest's allow and outside its protect
#                         (as overlap reads them; "protect: -" is none). Without a manifest or its allow:, a
#                         plain unit skips this and a 多线 line is refused.
#                         A 多线 line (a carrier column with a value other than "-" or prep) also needs <sha>,
#                         `lines.sh ledger check <slug> <id> <sha>` passing, a state other than stop-unconfirmed,
#                         and a valid receipt of its attempt, done or partial, whose commit is <sha> (full sha
#                         compared); a refusal lists each missing item.
#                         Refused while .dflow/<slug>.landing is pending at the current HEAD.
#                         A land writes .dflow/<slug>.landing: "uid", "head" (HEAD at the land), "source" rows,
#                         then one row per changed file: status (A added, M modified, T type changed, D deleted),
#                         path, and the file's index entry right after the land, "<mode> <blob>" as
#                         `git ls-files -s` gives it (so a symlink is its link text, an executable 100755; "-" for D).
#                         Then it records the source
#                         commit in .dflow/<slug>.landed (id, sha; last row wins). If the marker cannot be
#                         written: exit 1, "FAIL landed <id> into the working tree but could not record
#                         <marker>; undo by hand: <files>", and no .landed row
#   landed   <slug> <id>  close the land of <id> once it is committed: removes .landing only when it is this
#                         unit's, HEAD is no longer the one it records, and every listed file is in HEAD as it
#                         landed (A/M/T: `git ls-tree HEAD` gives the recorded mode and blob; D: not in HEAD) with no change of it
#                         left in the index or working tree; else refused, the paths that differ listed, the
#                         record kept
#   unland   <slug> <id>  undo an uncommitted land: only with a .landing of this unit at the current HEAD
#                         and every listed file still as the land left it (A/M/T: the recorded mode and blob;
#                         D: absent) or already as HEAD has it (nothing to undo), in the working tree and in the
#                         index alike. Index: mode and blob both equal. Working tree: the blob (git hash-object;
#                         a symlink: its link text) and the type and executable bit the mode says (the bit only
#                         when core.fileMode is on). Else refused, nothing touched, the files that differ listed
#                         (the index ones marked 暂存区不符). Restores its M/T/D files
#                         from HEAD, deletes its A files, removes the record. Other changes left are listed
#                         (exit 1), never touched
#   cleanup  <slug> [--ignored-ok]
#                         remove worktrees/branches only of units in state landed, done, dead, stopped
#                         or planned whose worktree has no uncommitted, untracked, or ignored files;
#                         keep and list the rest: any other state (dispatched, stop-unconfirmed, ...),
#                         a non-landed unit with commits past base, and a landed unit whose branch has
#                         commits past the source commit that landed (from .dflow/<slug>.landed, else a
#                         `landed` value on the branch; neither known: kept). Ignored files (build
#                         output, logs, .env) are listed, and removed only with --ignored-ok, after
#                         checking they are this task's own output
# Exit 0 ok, 1 refused or found a problem (details on stdout), 2 usage.
set -u
cmd=${1:-}; slug=${2:-}; uid=${3:-}; want=${4:-}
die() { echo "FAIL $*"; exit 1; }
usage() { sed -n '2,/^set -u/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 2; }
[ -n "$cmd" ] && [ -n "$slug" ] || usage
printf '%s' "$slug" | grep -Eq '^[a-z0-9][a-z0-9-]{0,62}$' || die "bad slug: $slug"
here=$(cd "$(dirname "$0")" && pwd)
root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not in a git repository"
cd "$root" || exit 1
table=".dflow/$slug.units.tsv"; man=".dflow/$slug.md"; landrec=".dflow/$slug.landed"; marker=".dflow/$slug.landing"
set -f   # globs in the table are patterns, never expanded against the disk

wpaths() { local p; p=$(col "$1" paths); [ "$p" = - ] || printf '%s' "$p"; }  # "-": writes nothing
col() { # col <id> <column>
    awk -F'\t' -v id="$1" -v c="$2" 'NR == 1 { for (i = 1; i <= NF; i++) h[$i] = i; next }
        $h["id"] == id { if (c in h) print $h[c]; exit }' "$table"
}
ids() { awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) h[$i] = i; next } $h["id"] != "" { print $h["id"] }' "$table"; }
field() { awk -v k="$2" 'NF == 0 && seen { exit } /^[a-z0-9_]+: / { seen = 1; if (index($0, k ": ") == 1) { print substr($0, length(k) + 3); exit } }' "$1" 2>/dev/null; }
match_any() { # match_any <string> <glob...>
    local s=$1 g; shift
    for g in "$@"; do case $s in $g) return 0 ;; esac; done; return 1
}
lit() { local g=$1; printf '%s' "${g%%[\*\?\[]*}"; }
dirty() { git status --porcelain --untracked-files=all | grep -v ' \.dflow/' | grep -v ' \.claude/worktrees/' || true; }
need_table() { [ -f "$table" ] || die "no unit table $table"; }
need_unit() {
    need_table; [ -n "$uid" ] || usage
    [ -n "$(col "$uid" id)" ] || die "unit $uid not in $table"
    base=$(col "$uid" base); branch=$(col "$uid" branch); paths=$(wpaths "$uid")
    [ -n "$base" ] && [ "$base" != - ] || die "unit $uid has no base"
    [ -n "$branch" ] && [ "$branch" != - ] || die "unit $uid has no branch"
    git rev-parse -q --verify "$branch^{commit}" >/dev/null || die "branch $branch not found"
    git merge-base --is-ancestor "$base" "$branch" || die "base $base is not an ancestor of $branch"
    tip=$branch
    if [ -n "$want" ]; then
        printf '%s' "$want" | grep -Eq '^[0-9a-f]{4,40}$' || die "$want is not a commit sha"
        tip=$(git rev-parse -q --verify "$want^{commit}") || die "commit $want not found (or not unique)"
        case $tip in "$want"*) ;; *) die "$want is not a commit sha" ;; esac
        head=$(git rev-parse "$branch^{commit}")
        [ "$head" = "$tip" ] || die "branch $branch is at $head, not $tip: it changed after $want was verified; its head is a new delivery that needs its own pass"
    fi
}

scope_check() { # prints OUTSIDE lines; 1 when any
    local f bad=0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if [ -z "$paths" ]; then echo "OUTSIDE $f (read-only unit, paths -: it may change nothing)"; bad=1
        elif ! match_any "$f" $paths; then echo "OUTSIDE $f"; bad=1; fi
    done <<< "$(git diff --name-only "$base" "$tip")"
    return $bad
}
manifest_check() { # changed files base..tip against the manifest's allow and protect; prints OUTSIDE-ALLOW/PROTECTED lines; 1 when any
    local f p bad=0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        match_any "$f" $allow || { echo "OUTSIDE-ALLOW $f"; bad=1; }
        for p in $protect; do case $f in $p) echo "PROTECTED $f"; bad=1; break ;; esac; done
    done <<< "$(git diff --name-only "$base" "$tip")"
    return $bad
}
mval() { awk -F'\t' -v k="$1" '$1 == k { print $2; exit }' "$marker" 2>/dev/null; }
# Entries are "<mode> <blob>" as git records them, "-" when absent, "?" when they cannot be read
idxent() { # idxent <path>: its stage-0 entry in the index; "?" when unmerged or unreadable
    local l n
    l=$(git ls-files -s -z -- ":(literal)$1" 2>/dev/null | tr '\0' '\n') || { echo "?"; return; }
    [ -n "$l" ] || { echo -; return; }
    n=$(printf '%s\n' "$l" | wc -l | tr -d ' ')
    case $n:$l in 1:*" 0	$1") l=${l%%	*}; echo "${l% 0}" ;; *) echo "?" ;; esac
}
headent() { # headent <path>: its entry in HEAD
    local l
    l=$(git ls-tree -z --full-tree HEAD -- "$1" 2>/dev/null | tr '\0' '\n') || { echo "?"; return; }
    [ -n "$l" ] || { echo -; return; }
    case $l in *"	$1") l=${l%%	*}; set -- $l; [ $# = 3 ] && echo "$1 $3" || echo "?" ;; *) echo "?" ;; esac
}
wtis() { # wtis <path> <entry>: 0 when the working tree holds <entry> there (type, executable bit, blob)
    local f=$1 m b
    [ "$2" != "?" ] || return 1
    if [ "$2" = - ]; then [ ! -e "$f" ] && [ ! -L "$f" ]; return; fi
    m=${2%% *}; b=${2#* }
    case $m in
    120000) [ -L "$f" ] && [ "$(python3 -I -c 'import os, sys; sys.stdout.buffer.write(os.readlink(os.fsencode(sys.argv[1])))' "$f" | git hash-object --stdin 2>/dev/null)" = "$b" ] ;;  # raw bytes: $(readlink) would drop trailing newlines
    100644|100755)
        [ -f "$f" ] && [ ! -L "$f" ] && [ "$(git hash-object -- "$f" 2>/dev/null)" = "$b" ] || return 1
        [ "$(git config --bool core.fileMode 2>/dev/null)" != false ] || return 0
        if [ "$m" = 100755 ]; then [ -x "$f" ]; else [ ! -x "$f" ]; fi ;;
    160000) [ -d "$f" ] && [ ! -L "$f" ] && [ "$(git -C "$f" rev-parse -q --verify HEAD 2>/dev/null)" = "$b" ] ;;
    *) return 1 ;;
    esac
}

case $cmd in
prepare)
    ex=$(git rev-parse --git-path info/exclude); case $ex in /*) ;; *) ex="$root/$ex" ;; esac
    mkdir -p "$(dirname "$ex")" .dflow
    for line in .dflow/ .claude/worktrees/; do grep -qxF "$line" "$ex" 2>/dev/null || echo "$line" >> "$ex"; done
    d=$(dirty); [ -z "$d" ] || { echo "FAIL working tree not clean; parallel needs a clean tree:"; echo "$d"; exit 1; }
    [ -f "$table" ] || printf 'id\tdeps\tpaths\tstate\tbase\tagent\tbranch\tdispatched_at\ttries\tlanded\n' > "$table"
    echo "ok prepared $table" ;;
overlap)
    need_table; bad=0; files=$(git ls-files)
    [ -f "$man" ] || die "no manifest $man: overlap checks the paths against its allow and protect (write it first: a leading key block with allow: <globs> and, if any, protect: <globs>)"
    allow=$(field "$man" allow); protect=$(field "$man" protect)
    [ -n "$allow" ] || die "manifest $man has no allow: line in its leading key block (allow: <globs> the units may write)"
    [ "$protect" != - ] || protect=""
    all=$(ids)
    for a in $all; do
        pa=$(wpaths "$a")
        for g in $pa; do
            if ! match_any "$g" $allow; then echo "OUTSIDE-ALLOW $a $g"; bad=1; fi
            if [ -n "$protect" ]; then
                for p in $protect; do
                    case $g in $p) echo "PROTECTED $a $g"; bad=1 ;; esac
                    case $p in $g) echo "PROTECTED $a $g"; bad=1 ;; esac
                done
            fi
        done
        for b in $all; do
            [ "$a" \< "$b" ] || continue
            pb=$(wpaths "$b")
            for ga in $pa; do for gb in $pb; do
                la=$(lit "$ga"); lb=$(lit "$gb"); hit=""
                if [ "$ga" = "$gb" ]; then hit=1
                elif [ "$la" != "$ga" ] && [ "${lb#"$la"}" != "$lb" ]; then hit=1   # ga is a wildcard covering lb's prefix
                elif [ "$lb" != "$gb" ] && [ "${la#"$lb"}" != "$la" ]; then hit=1
                else
                    while IFS= read -r f; do
                        [ -n "$f" ] || continue
                        case $f in $ga) case $f in $gb) hit=1; break ;; esac ;; esac
                    done <<< "$files"
                fi
                [ -z "$hit" ] || { echo "OVERLAP $a:$ga $b:$gb"; bad=1; }
            done; done
        done
    done
    [ $bad = 0 ] && echo "ok disjoint"; exit $bad ;;
scope)
    need_unit
    scope_check && { echo "ok scope $uid"; exit 0; }; exit 1 ;;
land)
    need_unit; now=$(git rev-parse HEAD)
    if [ -f "$marker" ] && [ "$(mval head)" = "$now" ]; then
        die "the land of unit $(mval uid) at HEAD $now is still pending ($marker): commit it, or parallel.sh unland $slug $(mval uid), first"
    fi
    out=$(scope_check) || { echo "FAIL $uid changes files outside its paths; not landed:"; echo "$out"; exit 1; }
    car=$(col "$uid" carrier); multi=""
    [ -n "$car" ] && [ "$car" != - ] && [ "$car" != prep ] && multi=1
    allow=""; [ -f "$man" ] && allow=$(field "$man" allow); protect=$(field "$man" protect); [ "$protect" != - ] || protect=""
    if [ -n "$allow" ]; then
        out=$(manifest_check) || { echo "FAIL $uid changes files the manifest $man does not allow; not landed:"; echo "$out"; exit 1; }
    fi
    if [ -n "$multi" ]; then # a 多线 line: manifest, verified sha, a receipt of that very commit, not stop-unconfirmed
        miss=""
        [ -n "$allow" ] || miss="$miss
  manifest: $man with an allow: line in its leading key block, to check the line's files against"
        st=$(col "$uid" state)
        [ "$st" != stop-unconfirmed ] || miss="$miss
  state: $uid is stop-unconfirmed (its stop is not confirmed; reconcile it first, it does not land)"
        if [ -z "$want" ]; then miss="$miss
  <sha>: a 多线 line (carrier $car) lands only at the verified commit; parallel.sh land $slug $uid <sha>"
        else
            v=$("$here/lines.sh" ledger check "$slug" "$uid" "$tip" 2>&1) || miss="$miss
  ledger pass: $v"
        fi
        att=$(col "$uid" attempt)
        if r=$("$here/lines.sh" receipt "$slug" "$uid" "$att" 2>&1); then
            rs=${r%% *}; rf=${r#* }; rc=""
            printf '%s' "$rf" | grep -Eq '^[0-9a-f]{4,40}$' && rc=$(git rev-parse -q --verify "$rf^{commit}" 2>/dev/null)
            case $rs in done|partial) ;; *) miss="$miss
  receipt done or partial: reports/$uid-$att.md delivers \"$r\" (a blocked delivery does not land)" ;; esac
            if [ -z "$rc" ]; then miss="$miss
  receipt of a commit: reports/$uid-$att.md delivers \"$r\", not a commit (a read-only delivery does not land)"
            elif [ -n "$want" ] && [ "$rc" != "$tip" ]; then miss="$miss
  receipt of this commit: reports/$uid-$att.md delivers $rc, not $tip that would land"
            fi
        else miss="$miss
  receipt: attempt ${att:-?}: $r"; fi
        [ -z "$miss" ] || { echo "FAIL 多线 line $uid not landed; missing:$miss"; exit 1; }
    fi
    d=$(dirty); [ -z "$d" ] || { echo "FAIL working tree not clean; refusing to land:"; echo "$d"; exit 1; }
    if err=$(git cherry-pick -n "$base..$tip" 2>&1 >/dev/null); then
        src=$(git rev-parse "$tip^{commit}")
        # each A/M/T file with its index entry right after the land, "<mode> <blob>" (unland undoes only
        # that); D "-"
        { printf 'uid\t%s\nhead\t%s\nsource\t%s\n' "$uid" "$now" "$src"
          git diff --cached --no-renames --name-status | while IFS=$'\t' read -r st f; do
              if [ "$st" = D ]; then h=-; else h=$(idxent "$f"); case $h in -|"?") exit 1 ;; esac; fi
              printf '%s\t%s\t%s\n' "$st" "$f" "$h"
          done; } 2>/dev/null > "$marker.tmp.$$" && [ ! -d "$marker" ] && mv -f "$marker.tmp.$$" "$marker" 2>/dev/null || {
            rm -f "$marker.tmp.$$" 2>/dev/null
            echo "FAIL landed $uid into the working tree but could not record $marker; undo by hand: $(git diff --cached --name-only | tr '\n' ' ' | sed 's/ $//')"
            exit 1; }
        printf '%s\t%s\n' "$uid" "$src" >> "$landrec"
        echo "ok landed $uid into the working tree; changed:"; git diff --cached --name-status
    else
        conflicts=$(git diff --name-only --diff-filter=U)
        git cherry-pick --abort 2>/dev/null || git reset -q --merge 2>/dev/null
        echo "FAIL conflict landing $uid; working tree restored. Conflicting files:"
        echo "${conflicts:-$err}"
        exit 1
    fi ;;
worktree)
    need_table; [ -n "$uid" ] || usage
    [ -n "$(col "$uid" id)" ] || die "unit $uid not in $table"
    base=$(col "$uid" base); [ -n "$base" ] && [ "$base" != - ] || die "unit $uid has no base; set it to the current HEAD first"
    git rev-parse -q --verify "$base^{commit}" >/dev/null || die "base $base not found"
    wt="$root/.dflow/worktrees/$slug-$uid"; br="dflow-unit/$slug-$uid"
    have=$(git worktree list --porcelain | awk -v w="$wt" '$0=="worktree "w{f=1;next} f&&/^branch /{print substr($0,19);exit} /^$/{f=0}')
    tries=$(col "$uid" tries); redo="remove the old worktree and branch first (git worktree remove $wt; git branch -D $br), after checking they hold nothing you need"
    if [ -n "$have" ]; then
        [ "$have" = "$br" ] || die "$wt exists on branch $have"
        at=$(git -C "$wt" rev-parse HEAD)
        case ${tries:-0} in 0|-) ;; *) [ "$at" = "$(git rev-parse "$base^{commit}")" ] || die "unit $uid was sent back and $wt is at $at, not base $base; $redo" ;; esac
        echo "ok worktree $wt branch $br (already there)"; exit 0
    fi
    git rev-parse -q --verify "refs/heads/$br" >/dev/null && die "branch $br already exists; $redo"
    mkdir -p "$root/.dflow/worktrees"
    git worktree add -q -b "$br" "$wt" "$base" || die "git worktree add failed"
    echo "ok worktree $wt branch $br" ;;
unland)
    need_table; [ -n "$uid" ] || usage
    [ -f "$marker" ] || die "no record of a land to undo ($marker): nothing touched (it is written by a land that succeeded; the tree's changes are not a land's)"
    mu=$(mval uid); mh=$(mval head); now=$(git rev-parse HEAD)
    [ "$mu" = "$uid" ] || die "the pending land belongs to unit ${mu:-?}, not $uid; nothing touched"
    [ "$mh" = "$now" ] || die "HEAD is $now, not $mh where $uid landed: it was committed (or HEAD moved) since; nothing touched. 提交后请运行 landed 关闭 (parallel.sh landed $slug $uid)"
    files=$(awk -F'\t' '$1 ~ /^[AMDT]$/ { print $1 "\t" $2 "\t" $3 }' "$marker")
    # every file still holds what the land put there, or is already back as HEAD has it (undoing it
    # changes nothing); anything else is someone's later change, and then nothing is undone
    changed=""
    while IFS=$'\t' read -r st f h; do
        [ -n "$f" ] || continue
        case $st:$h in D:-|[AMT]:1[0-9][0-9][0-9][0-9][0-9]" "[0-9a-f]*) ;; *) h="" ;; esac   # an unreadable record matches nothing
        was=$(headent "$f")
        # the index: the landed entry, or already back as HEAD has it (D: absent, or HEAD's); mode and blob both
        idx=$(idxent "$f")
        if [ -z "$h" ] || [ "$was" = "?" ] || { [ "$idx" != "$h" ] && [ "$idx" != "$was" ]; }; then changed="$changed
  $f (暂存区不符: the index holds $idx, not the landed ${h:-?} nor HEAD's $was)"; fi
        [ -n "$h" ] && { wtis "$f" "$h" || wtis "$f" "$was"; } && continue
        cur=-; { [ -e "$f" ] || [ -L "$f" ]; } && cur=present
        case $st:$cur in
        D:-) ;;
        D:*) changed="$changed
  $f (deleted by the land, now there again)" ;;
        *:-) changed="$changed
  $f (gone since the land)" ;;
        *) changed="$changed
  $f (changed since the land: content, type or executable bit${h:+; landed $h})" ;;
        esac
    done <<< "$files"
    [ -z "$changed" ] || { echo "FAIL not undoing the land of $uid: these files no longer hold what it landed (nothing touched):$changed"; exit 1; }
    added=""
    while IFS=$'\t' read -r st f h; do
        [ -n "$f" ] || continue
        if [ "$st" = A ]; then git rm -q --cached --ignore-unmatch -- "$f"; rm -f -- "$f"; added="$added $f"
        else git restore --source=HEAD --staged --worktree -- "$f"; fi
    done <<< "$files"
    rm -f "$marker"
    echo "ok undid land of $uid"; [ -z "$added" ] || echo "deleted:$added"
    left=$(dirty)
    [ -z "$left" ] || { echo "FAIL tree still dirty with files the land did not change (left in place):"; echo "$left"; exit 1; } ;;
landed)
    need_table; [ -n "$uid" ] || usage
    [ -f "$marker" ] || die "no pending land record ($marker); nothing to close"
    mu=$(mval uid); mh=$(mval head); now=$(git rev-parse HEAD)
    [ "$mu" = "$uid" ] || die "the pending land belongs to unit ${mu:-?}, not $uid; not closed"
    [ "$mh" != "$now" ] || die "HEAD is still $mh where $uid landed: commit the land first; not closed"
    # the land's content must be in HEAD (A/M: the recorded blob; D: gone) with nothing of it left to commit
    miss=""
    while IFS=$'\t' read -r st f h; do
        [ -n "$f" ] || continue
        hb=$(headent "$f")
        if [ "$st" = D ]; then [ "$hb" = - ] || miss="$miss
  $f (deleted by the land, still in HEAD)"
        elif [ -z "$h" ] || [ "$hb" != "$h" ]; then miss="$miss
  $f (HEAD has ${hb}, not the landed ${h:-?})"; fi
        p=$(git status --porcelain --untracked-files=all -- ":(literal)$f" 2>/dev/null)
        [ -z "$p" ] || miss="$miss
  $f (uncommitted in the index or working tree: ${p%%$'\n'*})"
    done <<< "$(awk -F'\t' '$1 ~ /^[AMDT]$/ { print $1 "\t" $2 "\t" $3 }' "$marker")"
    [ -z "$miss" ] || { echo "FAIL the land of $uid is not committed as it landed; not closed, $marker kept:$miss"; exit 1; }
    rm -f "$marker" || die "could not remove $marker"
    echo "ok closed the land of $uid (HEAD $mh -> $now)" ;;
cleanup)
    [ -z "$uid" ] || [ "$uid" = --ignored-ok ] || die "unknown cleanup option: $uid"
    need_table; wl=$(git worktree list --porcelain); bad=0
    for id in $(ids); do
        br=$(col "$id" branch); st=$(col "$id" state); bs=$(col "$id" base)
        [ -n "$br" ] && [ "$br" != - ] || continue
        wt=$(printf '%s\n' "$wl" | awk -v b="refs/heads/$br" '/^worktree /{w=substr($0,10)} $0=="branch "b{print w; exit}')
        left=""; ign=""
        if [ -n "$wt" ]; then
            left=$(git -C "$wt" status --porcelain --untracked-files=all)
            ign=$(git -C "$wt" status --porcelain --ignored | grep '^!!' || true)
        fi
        commits=0; git rev-parse -q --verify "$br^{commit}" >/dev/null && [ -n "$bs" ] && commits=$(git rev-list --count "$bs..$br" 2>/dev/null || echo 0)
        case $st in
        landed|done|dead|stopped|planned) ;;
        *) echo "KEEP $id $br: state ${st:-?} (only landed, done, dead, stopped or planned units are removed)"; bad=1; continue ;;
        esac
        if [ -n "$left" ]; then echo "KEEP $id $br: uncommitted or untracked files in $wt:"; echo "$left"; bad=1; continue; fi
        if [ -n "$ign" ] && [ "$uid" != --ignored-ok ]; then echo "KEEP $id $br: ignored files in $wt (not removed; see cleanup in references/parallel.md):"; echo "$ign"; bad=1; continue; fi
        if [ "$st" != landed ] && [ "$commits" != 0 ]; then echo "KEEP $id $br: $commits unlanded commit(s)"; bad=1; continue; fi
        if [ "$st" = landed ] && git rev-parse -q --verify "$br^{commit}" >/dev/null; then
            src=$(awk -F'\t' -v id="$id" '$1 == id { s = $2 } END { print s }' "$landrec" 2>/dev/null)
            if [ -z "$src" ]; then
                lv=$(col "$id" landed); lv=$(git rev-parse -q --verify "$lv^{commit}" 2>/dev/null) &&
                    git merge-base --is-ancestor "$lv" "$br" && src=$lv
            fi
            if [ -z "$src" ]; then echo "KEEP $id $br: landed, but no record of which commit landed (parallel.sh land writes $landrec)"; bad=1; continue; fi
            past=$(git rev-list --count "$src..$br" 2>/dev/null || echo "?")
            if [ "$past" != 0 ]; then echo "KEEP $id $br: $past commit(s) past the landed $src"; bad=1; continue; fi
        fi
        [ -z "$ign" ] || { echo "DELETING ignored files in $wt:"; echo "$ign"; }
        [ -z "$wt" ] || git worktree remove --force "$wt"
        git branch -D -q "$br" 2>/dev/null
        echo "ok removed $id ($br${wt:+, $wt})"
    done
    git worktree prune
    reg=$(awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == "branch") c = i; next } c { print $c }' "$table")
    printf '%s\n' "$(git worktree list --porcelain)" | awk '/^worktree /{w=substr($0,10)} /^branch /{print w"\t"substr($0,19)}' |
    while IFS=$'\t' read -r w b; do
        case $w in */.claude/worktrees/*|*/.dflow/worktrees/*) ;; *) continue ;; esac
        printf '%s\n' "$reg" | grep -qxF "$b" && continue
        echo "ORPHAN $w ($b): not in the unit table; left in place, $(git -C "$w" status --porcelain | wc -l | tr -d ' ') uncommitted path(s)"
    done
    exit $bad ;;
*) usage ;;
esac
