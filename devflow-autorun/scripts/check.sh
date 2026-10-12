#!/usr/bin/env bash
# Start-of-iteration state check for an armed run.
# Usage: check.sh <repo-root> <slug> [closeout]
# Prints one problem per line and exits 1 when the run must stop; prints "ok" and exits 0 otherwise.
# With "closeout", any uncommitted change outside .devflow/ is also a problem, so the final
# evidence describes exactly the committed range.
set -u
root=$1
slug=$2
mode=${3:-}
marker="$root/.devflow/$slug.running"
log="$root/.devflow/$slug.tsv"
problems=()

[ -f "$marker" ] || { echo "no marker: $marker (run not armed, already closed, or removed by the user)"; exit 1; }

in_list() {
    local rel=$1 key=$2 pat
    while IFS= read -r pat; do
        [ -n "$pat" ] || continue
        case "$pat" in
            */) [[ "$rel" == "$pat"* ]] && return 0 ;;
            *) [[ "$rel" == $pat ]] && return 0 ;;
        esac
    done < <(jq -r ".${key}[]? // empty" "$marker")
    return 1
}

branch=$(jq -r '.branch // empty' "$marker")
base=$(jq -r '.base_sha // empty' "$marker")
deadline=$(jq -r '.deadline // 0' "$marker")
want_hash=$(jq -r '.contract_sha256 // empty' "$marker")
contract="$root/.devflow/$slug.md"
if [ -z "$want_hash" ]; then
    problems+=("marker has no contract_sha256")
elif [ "$(shasum -a 256 "$contract" 2>/dev/null | cut -d' ' -f1)" != "$want_hash" ]; then
    problems+=("contract $contract changed since arming (only the user edits it, then re-arms or resumes)")
fi
head_branch=$(git -C "$root" symbolic-ref --short -q HEAD)
head_sha=$(git -C "$root" rev-parse HEAD)

[ "$head_branch" = "$branch" ] || problems+=("HEAD is on '$head_branch', not '$branch'")
[ "$(date +%s)" -le "$deadline" ] || problems+=("deadline passed: close out now")

# HEAD must be the base or the last commit the log recorded; anything else moved under the run.
last=$(awk -F'\t' 'NR>1 && $5 ~ /commit [0-9a-f]{7,40}/ { match($5, /commit [0-9a-f]{7,40}/); s=substr($5, RSTART+7, RLENGTH-7) } END { print s }' "$log" 2>/dev/null)
expected=${last:-$base}
if [ -n "$expected" ] && [ "${head_sha#"$expected"}" = "$head_sha" ]; then
    problems+=("HEAD $head_sha is neither the base nor the last logged commit ($expected)")
fi
if [ -n "$base" ] && ! git -C "$root" merge-base --is-ancestor "$base" HEAD 2>/dev/null; then
    problems+=("base $base is not an ancestor of HEAD")
fi

if [ -n "$base" ]; then
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if in_list "$f" protected; then problems+=("protected file changed in commits since base: $f")
        elif ! in_list "$f" write_scope; then problems+=("commits since base touch a path outside the write scope: $f"); fi
    done < <(git -C "$root" diff --name-only "$base" HEAD 2>/dev/null)
fi

while IFS= read -r line; do
    [ -n "$line" ] || continue
    f=${line:3}
    f=${f#\"}; f=${f%\"}
    case "$f" in *" -> "*) f=${f##* -> } ;; esac
    case "$f" in .devflow/*) continue ;; esac
    [ "$mode" = closeout ] && { problems+=("uncommitted change at closeout: $f"); continue; }
    if in_list "$f" protected; then
        problems+=("protected file changed: $f")
    elif ! in_list "$f" write_scope; then
        problems+=("change outside the write scope: $f")
    fi
done < <(git -C "$root" status --porcelain --untracked-files=all)

if [ "${#problems[@]}" -gt 0 ]; then
    printf '%s\n' "${problems[@]}"
    exit 1
fi
echo ok
