#!/usr/bin/env bash
# Link each skill in this repo into the agent skill directories. Idempotent.
# Never overwrites a real directory or a link that points elsewhere; reports it instead.
# Usage: install.sh [--check]   (--check reports only, changes nothing)
set -u
repo=$(cd "$(dirname "$0")" && pwd)
check=${1:-}
problems=0

# devflow-* is retired (sources kept for reference) and is not linked.
# dflow-report goes to Codex and Claude Code; everything else goes to the
# shared dir (read by Codex) and Claude Code.
targets_for() {
    case "$1" in
        devflow-*) ;;
        dflow-report) echo "$HOME/.codex/skills $HOME/.claude/skills" ;;
        *) echo "$HOME/.agents/skills $HOME/.claude/skills" ;;
    esac
}

link() { # src dest
    local src=$1 dest=$2
    if [ -L "$dest" ] || [ -e "$dest" ]; then
        if [ "$(cd "$dest" 2>/dev/null && pwd -P)" = "$(cd "$src" && pwd -P)" ]; then
            echo "ok       $dest"
        else
            echo "CONFLICT $dest (exists and does not resolve to $src)"; problems=$((problems+1))
        fi
        return
    fi
    if [ "$check" = --check ]; then echo "MISSING  $dest"; problems=$((problems+1)); return; fi
    mkdir -p "$(dirname "$dest")" && ln -s "$src" "$dest" && echo "linked   $dest -> $src"
}

for src in "$repo"/skills/*/; do
    src=${src%/}; name=$(basename "$src")
    for dir in $(targets_for "$name"); do link "$src" "$dir/$name"; done
done

[ "$problems" = 0 ]
