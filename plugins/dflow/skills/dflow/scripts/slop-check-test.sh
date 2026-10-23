#!/usr/bin/env bash
# Tests for slop-check.sh: positive/negative corpus, code fences, usage errors,
# that references/unslop.md keeps every pstack rule number, and that dflow's own prose is clean.
set -u
here=$(cd "$(dirname "$0")" && pwd)
chk="$here/slop-check.sh"; cases="$here/slop-check-cases"
pass=0; fail=0
ok() { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "FAIL $*"; }

en=0; zh=0
while IFS='|' read -r rule text; do
    case $rule in ''|\#*) continue ;; esac
    if printf '%s\n' "$text" | "$chk" - | grep -q "\[rule $rule\]"; then ok; else bad "positive rule $rule: $text"; fi
    if printf '%s' "$text" | LC_ALL=C grep -q '[a-zA-Z]\{4\}'; then en=$((en+1)); else zh=$((zh+1)); fi
done < "$cases/positive.txt"

while IFS= read -r text; do
    case $text in ''|\#*) continue ;; esac
    if out=$(printf '%s\n' "$text" | "$chk" -); then ok; else bad "negative: $out"; fi
done < "$cases/negative.txt"

fenced=$(printf '```\n赋能\n```\n')
if printf '%s\n' "$fenced" | "$chk" - >/dev/null; then ok; else bad "fenced code block reported"; fi
"$chk" >/dev/null 2>&1; [ $? = 2 ] && ok || bad "no args should exit 2"
"$chk" /nonexistent >/dev/null 2>&1; [ $? = 2 ] && ok || bad "unreadable file should exit 2"
tmpf="$here/slop-check-cases/positive.txt"
"$chk" "$tmpf" >/dev/null; [ $? = 1 ] && ok || bad "file with hits should exit 1"

ref="$here/../references/unslop.md"
have=$(grep -oE '^[0-9]+\. \*\*' "$ref" | grep -oE '^[0-9]+' | sort -n | tr '\n' ' ')
for n in 3 5 7 8 9 10 11 12 13 14 15 16 17 18 19 20 22 23 24 25 26 27 28 29 30 31 32 33; do
    case " $have" in *" $n "*) ok ;; *) bad "unslop.md is missing pstack rule $n" ;; esac
done

# dflow's own prose follows its rules; unslop.md quotes the patterns it bans, so it is exempt.
skill="$here/.."
for f in "$skill"/SKILL.md "$skill"/playbooks/*.md "$skill"/references/*.md "$skill"/principles/*.md "$skill"/../report/SKILL.md; do
    [ "$f" = "$skill/references/unslop.md" ] && continue
    hits=$("$chk" "$f"); [ $? = 0 ] && ok || bad "slop in dflow's own text: $hits"
done

echo "slop-check-test: $pass passed, $fail failed (positive cases: $en English, $zh Chinese)"
[ "$fail" = 0 ]
