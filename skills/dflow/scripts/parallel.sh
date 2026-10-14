#!/usr/bin/env bash
# Mechanical steps of dflow parallel implementation (references/parallel.md).
# Unit table: <repo>/.dflow/<slug>.units.tsv, tab-separated, header
#   id deps paths state base agent branch dispatched_at tries landed
# paths: space-separated globs the unit may write ("*" crosses "/").
# Only the coordinating session writes the table; this script only reads it.
#
# Usage: parallel.sh <command> <slug> [id]
#   prepare  <slug>       exclude .claude/worktrees/ and .dflow/; require a clean tree; create the table
#   overlap  <slug>       unit paths pairwise disjoint, inside the manifest's allow, outside protect
#   scope    <slug> <id>  base is an ancestor of the unit branch; every changed file is in the unit's paths
#   land     <slug> <id>  clean tree + ancestor check, then `cherry-pick -n base..branch`; on conflict abort
#   unland   <slug> <id>  undo an uncommitted land: unstage and restore changed files, delete added ones
#   cleanup  <slug>       remove worktrees/branches of landed (or empty) units; keep and list the rest
# Exit 0 ok, 1 refused or found a problem (details on stdout), 2 usage.
set -u
cmd=${1:-}; slug=${2:-}; uid=${3:-}
die() { echo "FAIL $*"; exit 1; }
usage() { sed -n '2,/^set -u/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 2; }
[ -n "$cmd" ] && [ -n "$slug" ] || usage
printf '%s' "$slug" | grep -Eq '^[a-z0-9][a-z0-9-]{0,62}$' || die "bad slug: $slug"
root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not in a git repository"
cd "$root" || exit 1
table=".dflow/$slug.units.tsv"; man=".dflow/$slug.md"
set -f   # globs in the table are patterns, never expanded against the disk

col() { # col <id> <column>
    awk -F'\t' -v id="$1" -v c="$2" 'NR == 1 { for (i = 1; i <= NF; i++) h[$i] = i; next }
        $h["id"] == id { print $h[c]; exit }' "$table"
}
ids() { awk -F'\t' 'NR > 1 && $1 != "" { print $1 }' "$table"; }
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
    base=$(col "$uid" base); branch=$(col "$uid" branch); paths=$(col "$uid" paths)
    [ -n "$base" ] && [ "$base" != - ] || die "unit $uid has no base"
    [ -n "$branch" ] && [ "$branch" != - ] || die "unit $uid has no branch"
    git rev-parse -q --verify "$branch^{commit}" >/dev/null || die "branch $branch not found"
    git merge-base --is-ancestor "$base" "$branch" || die "base $base is not an ancestor of $branch"
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
    allow=$(field "$man" allow); protect=$(field "$man" protect)
    all=$(ids)
    for a in $all; do
        pa=$(col "$a" paths)
        for g in $pa; do
            if [ -n "$allow" ] && ! match_any "$g" $allow; then echo "OUTSIDE-ALLOW $a $g"; bad=1; fi
            if [ -n "$protect" ]; then
                for p in $protect; do
                    case $g in $p) echo "PROTECTED $a $g"; bad=1 ;; esac
                    case $p in $g) echo "PROTECTED $a $g"; bad=1 ;; esac
                done
            fi
        done
        for b in $all; do
            [ "$a" \< "$b" ] || continue
            pb=$(col "$b" paths)
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
    need_unit; bad=0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        match_any "$f" $paths || { echo "OUTSIDE $f"; bad=1; }
    done <<< "$(git diff --name-only "$base" "$branch")"
    [ $bad = 0 ] && echo "ok scope $uid"; exit $bad ;;
land)
    need_unit
    d=$(dirty); [ -z "$d" ] || { echo "FAIL working tree not clean; refusing to land:"; echo "$d"; exit 1; }
    if err=$(git cherry-pick -n "$base..$branch" 2>&1 >/dev/null); then
        echo "ok landed $uid into the working tree; changed:"; git diff --cached --name-status
    else
        conflicts=$(git diff --name-only --diff-filter=U)
        git cherry-pick --abort 2>/dev/null || git reset -q --merge 2>/dev/null
        echo "FAIL conflict landing $uid; working tree restored. Conflicting files:"
        echo "${conflicts:-$err}"
        exit 1
    fi ;;
unland)
    need_table; [ -n "$uid" ] || usage
    added=$(git diff --cached --name-only --diff-filter=A)
    changed=$(git diff --cached --name-only --diff-filter=MDR; git diff --name-only)
    [ -n "$added$changed" ] || { echo "ok nothing to undo"; exit 0; }
    if [ -n "$added" ]; then
        while IFS= read -r f; do git rm -q --cached -- "$f" && rm -f -- "$f"; done <<< "$added"
    fi
    if [ -n "$changed" ]; then
        printf '%s\n' "$changed" | sort -u | while IFS= read -r f; do
            [ -n "$f" ] && git restore --source=HEAD --staged --worktree -- "$f"; done
    fi
    echo "ok undid land of $uid"; [ -n "$added" ] && echo "deleted: $added"; [ -z "$(dirty)" ] || { echo "FAIL tree still dirty:"; dirty; exit 1; } ;;
cleanup)
    need_table; wl=$(git worktree list --porcelain); bad=0
    for id in $(ids); do
        br=$(col "$id" branch); st=$(col "$id" state); bs=$(col "$id" base)
        [ -n "$br" ] && [ "$br" != - ] || continue
        wt=$(printf '%s\n' "$wl" | awk -v b="refs/heads/$br" '/^worktree /{w=substr($0,10)} $0=="branch "b{print w; exit}')
        left=""; tracked=""
        if [ -n "$wt" ]; then
            left=$(git -C "$wt" status --porcelain --untracked-files=all)
            tracked=$(printf '%s\n' "$left" | grep -v '^??' || true)
        fi
        commits=0; git rev-parse -q --verify "$br^{commit}" >/dev/null && [ -n "$bs" ] && commits=$(git rev-list --count "$bs..$br" 2>/dev/null || echo 0)
        if [ -n "$tracked" ]; then echo "KEEP $id $br: uncommitted tracked changes in $wt:"; echo "$tracked"; bad=1; continue; fi
        if [ "$st" != landed ] && [ "$commits" != 0 ]; then echo "KEEP $id $br: $commits unlanded commit(s)"; bad=1; continue; fi
        [ -z "$left" ] || { echo "DELETING untracked files in $wt:"; echo "$left"; }
        [ -z "$wt" ] || git worktree remove --force "$wt"
        git branch -D -q "$br" 2>/dev/null
        echo "ok removed $id ($br${wt:+, $wt})"
    done
    git worktree prune; exit $bad ;;
*) usage ;;
esac
