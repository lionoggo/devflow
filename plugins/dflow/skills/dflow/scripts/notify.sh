#!/usr/bin/env bash
# Desktop notification for a host without a push tool (Codex); Claude Code uses PushNotification.
# Usage: notify.sh <message>. Exit 0 sent, 1 no way to send (say so in the closeout instead).
set -u
msg=${1:-}; [ -n "$msg" ] || { echo "usage: notify.sh <message>" >&2; exit 2; }
if command -v terminal-notifier >/dev/null; then
    terminal-notifier -title dflow -message "$msg" >/dev/null 2>&1 && { echo "ok sent (terminal-notifier)"; exit 0; }
fi
if command -v osascript >/dev/null; then
    osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "dflow"' -e 'end run' "$msg" >/dev/null 2>&1 \
        && { echo "ok sent (osascript)"; exit 0; }
fi
echo "FAIL no notifier worked"; exit 1
