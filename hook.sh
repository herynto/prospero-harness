#!/usr/bin/env bash
# UserPromptSubmit hook: classify "cx:" prompts, log the verdict, block the prompt.
set -uo pipefail

# classify runs `claude -p`, which fires this hook again. Stay out of its way.
[ -n "${HARNESS_CLASSIFYING:-}" ] && exit 0

dir="$(cd "$(dirname "$0")" && pwd)"
classify="${HARNESS_CLASSIFY:-$dir/classify}"
log="${HARNESS_LOG:-$dir/log.jsonl}"

prompt="$(jq -r '.prompt // ""')"
case "$prompt" in
  cx:*) ;;
  *) exit 0 ;;
esac
text="$(printf '%s' "${prompt#cx:}" | sed -e 's/^[[:space:]]*//')"

now_ms() { perl -MTime::HiRes=time -e 'printf "%d", time*1000'; }
start="$(now_ms)"
errfile="$(mktemp)"
verdict="$(printf '%s' "$text" | "$classify" 2>"$errfile")"
rc=$?
err="$(head -1 "$errfile")"; rm -f "$errfile"
ms=$(( $(now_ms) - start ))
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ "$rc" -eq 0 ] && ! jq -e 'type == "object" and has("model") and has("effort") and has("reason")' \
    >/dev/null 2>&1 <<<"$verdict"; then
  rc=1; err="classifier printed no valid verdict"
fi

if [ "$rc" -eq 0 ]; then
  jq -cn --arg ts "$ts" --arg prompt "$text" --argjson v "$verdict" --argjson ms "$ms" \
    '{ts:$ts, prompt:$prompt, ok:true} + ($v | {model,effort,reason}) + {ms:$ms}' >> "$log"
  reason="$(jq -r '"\(.model) · \(.effort) — \(.reason)"' <<<"$verdict")"
else
  [ -n "$err" ] || err="classifier exited $rc"
  jq -cn --arg ts "$ts" --arg prompt "$text" --arg error "$err" --argjson ms "$ms" \
    '{ts:$ts, prompt:$prompt, ok:false, error:$error, ms:$ms}' >> "$log"
  reason="classification failed: $err"
fi

jq -cn --arg r "$reason" '{decision:"block", reason:$r}'
