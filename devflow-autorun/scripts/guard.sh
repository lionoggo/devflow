#!/usr/bin/env bash
# devflow-autorun guard (Claude Code PreToolUse hook).
#
# Enforces an armed run's authorization for the one session that armed it.
# No marker in this repo bound to this session -> exit 0 (does nothing).
# Marker: <repo>/.devflow/<slug>.running, JSON with
#   session_id, branch, commit_allowed, base_sha, write_scope[], protected[], deadline (epoch s)
# Blocks with exit 2; the reason goes to stderr for the agent.
set -u

input=$(cat)
field() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }

sid=$(field .session_id)
cwd=$(field .cwd)
tool=$(field .tool_name)
[ -n "$sid" ] && [ -n "$cwd" ] || exit 0
root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0

marker=""
for m in "$root"/.devflow/*.running; do
    [ -f "$m" ] || continue
    if [ "$(jq -r '.session_id // empty' "$m" 2>/dev/null)" = "$sid" ]; then
        marker=$m
        break
    fi
done
[ -n "$marker" ] || exit 0

block() {
    printf 'devflow-autorun guard: %s\n' "$1" >&2
    printf 'Run marker: %s. If the run has ended or was abandoned, the user removes it with: rm %q\n' "$marker" "$marker" >&2
    exit 2
}

mget() { jq -r "$1" "$marker" 2>/dev/null; }
branch=$(mget '.branch // empty')
commit_allowed=$(mget '.commit_allowed // false')
deadline=$(mget '.deadline // 0')
expired=0
[ "$(date +%s)" -gt "${deadline:-0}" ] && expired=1

# Repo-relative path of an absolute or cwd-relative path ("" when outside the repo).
relpath() {
    local p=$1
    case "$p" in /*) ;; *) p="$cwd/$p" ;; esac
    p=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$p")
    local r
    r=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$root")
    case "$p" in
        "$r") printf '.' ;;
        "$r"/*) printf '%s' "${p#"$r"/}" ;;
        *) printf '' ;;
    esac
}

# True when rel matches any entry of the marker list (dir prefix "x/" or glob).
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

check_write_path() {
    local p=$1 rel
    [ -n "$p" ] || return 0
    rel=$(relpath "$p")
    if [ -z "$rel" ]; then
        case "$p" in
            /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) return 0 ;;
        esac
        block "write outside the repository is not authorized: $p"
    fi
    case "$rel" in
        .devflow/*) block "run files are written only by log.sh (log) or the user (contract): $rel" ;;
    esac
    in_list "$rel" protected && block "protected path (a test, fixture, or check the predicate relies on): $rel. Park this unit and log it."
    in_list "$rel" write_scope || block "outside the contract's write scope: $rel"
    return 0
}

case "$tool" in
    Write|Edit|MultiEdit)
        [ "$expired" = 1 ] && block "the run passed its deadline; only closeout is allowed"
        check_write_path "$(field .tool_input.file_path)"
        exit 0
        ;;
    NotebookEdit)
        [ "$expired" = 1 ] && block "the run passed its deadline; only closeout is allowed"
        check_write_path "$(field .tool_input.notebook_path)"
        exit 0
        ;;
    Bash) ;;
    *) exit 0 ;;
esac

cmd=$(field .tool_input.command)
META='[;&|`]|[$][(]'
[ -n "$cmd" ] || exit 0

# A git invocation: "git", optional global options, then the subcommand.
G='(^|[^[:alnum:]_./-])git([[:space:]]+(-C|-c|--git-dir|--work-tree)[[:space:]]+[^[:space:]]+|[[:space:]]+--[[:alnum:]-]+(=[^[:space:]]+)?)*[[:space:]]+'

# The marker is changed only by the user, or removed at closeout.
if [[ "$cmd" == *".running"* ]]; then
    rel_marker=".devflow/$(basename "$marker")"
    if [[ "$cmd" =~ ^[[:space:]]*rm[[:space:]]+(-f[[:space:]]+)?([^[:space:];|&]+)[[:space:]]*$ ]]; then
        target="${BASH_REMATCH[2]}"
        [ "$(relpath "$target")" = "$rel_marker" ] && exit 0
    fi
    # Reading the marker is fine: one plain read command, no redirection or chaining.
    if ! [[ "$cmd" =~ $META|\>|\<|-i([[:space:]]|$)|--in-place ]] \
        && [[ "$cmd" =~ ^[[:space:]]*(cat|jq|head|tail|ls|stat|wc|test)[[:space:]] ]]; then
        exit 0
    fi
    block "the run marker is not editable from the run; closeout removes it with a plain 'rm $rel_marker'"
fi

if [[ "$cmd" =~ ${G}(push|pull|merge|rebase|reset|clean|stash|tag|worktree|switch|checkout|cherry-pick|revert|am|filter-branch|filter-repo|update-ref|replace|notes)([^[:alnum:]_-]|$) ]]; then
    block "git ${BASH_REMATCH[5]} is not allowed during a run (undo with a scoped 'git restore')"
fi
if [[ "$cmd" =~ ${G}branch[[:space:]]+(-[[:alpha:]]*[dDmMcCf]|--delete|--move|--copy|--force) ]]; then
    block "changing branches is not allowed during a run"
fi
if [[ "$cmd" =~ (^|[^[:alnum:]_-])(gh[[:space:]]+(pr|release|repo|api|workflow)|(npm|pnpm|yarn|bun)[[:space:]]+publish|cargo[[:space:]]+publish|twine[[:space:]]+upload|docker[[:space:]]+push)([^[:alnum:]_-]|$) ]]; then
    block "publishing or remote actions are not allowed during a run: ${BASH_REMATCH[2]}"
fi

if [[ "$cmd" =~ ${G}restore([[:space:]]|$) ]]; then
    [ "$expired" = 1 ] && block "the run passed its deadline; only closeout is allowed"
    if [[ "$cmd" =~ (--source|-s)(=|[[:space:]]+)([^[:space:]]+) ]] && [ "${BASH_REMATCH[3]}" != "HEAD" ]; then
        block "git restore may only restore from HEAD"
    fi
    if [[ "$cmd" =~ $META ]]; then
        block "run git restore as a single command so its paths can be checked"
    fi
    seen=0
    after=0
    # shellcheck disable=SC2086
    set -f
    for tok in $cmd; do
        if [ "$after" = 0 ]; then
            [ "$tok" = "restore" ] && after=1
            continue
        fi
        case "$tok" in
            --) continue ;;
            -s|--source) continue ;;
            -*) continue ;;
            HEAD) continue ;;
        esac
        seen=1
        rel=$(relpath "$tok")
        [ -n "$rel" ] && [ "$rel" != "." ] || block "git restore path is outside the repository or is the whole tree: $tok"
        in_list "$rel" protected && block "git restore on a protected path: $rel"
        in_list "$rel" write_scope || block "git restore outside the write scope: $rel"
    done
    set +f
    [ "$seen" = 1 ] || block "git restore needs explicit paths inside the write scope"
    exit 0
fi

if [[ "$cmd" =~ ${G}commit([[:space:]]|$) ]]; then
    [ "$expired" = 1 ] && block "the run passed its deadline; only closeout is allowed"
    [ "$commit_allowed" = "true" ] || block "the contract does not authorize commits"
    if [[ "$cmd" =~ $META ]]; then
        block "run git commit as its own command, after git add, so the staged files can be checked"
    fi
    [[ "$cmd" =~ --amend|--no-verify|--allow-empty|(^|[[:space:]])-[[:alpha:]]*n[[:alpha:]]*([[:space:]]|$) ]] && block "amend, --no-verify, and empty commits are not allowed"
    [[ "$cmd" =~ (^|[[:space:]])(-[[:alpha:]]*a[[:alpha:]]*|--all)([[:space:]]|$) ]] && block "commit -a is not allowed; stage paths explicitly"
    head_branch=$(git -C "$root" symbolic-ref --short -q HEAD)
    [ "$head_branch" = "$branch" ] || block "HEAD is on '$head_branch', not the contract branch '$branch'"
    staged=$(git -C "$root" diff --cached --name-only)
    [ -n "$staged" ] || exit 0
    while IFS= read -r f; do
        in_list "$f" protected && block "staged file is protected: $f"
        in_list "$f" write_scope || block "staged file is outside the write scope: $f"
    done <<< "$staged"
    exit 0
fi

exit 0
