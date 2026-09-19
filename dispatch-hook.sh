#!/usr/bin/env bash
# PreToolUse hook for subagent dispatches: when the session named no model, fill in the
# classifier's choice. A model the session did choose is kept; the classifier's opinion
# is only logged. Never blocks a dispatch: on any failure the call runs unchanged.
set -uo pipefail

[ -n "${HARNESS_CLASSIFYING:-}" ] && exit 0

dir="$(cd "$(dirname "$0")" && pwd)"
classify="${HARNESS_CLASSIFY:-$dir/classify}"
log="${HARNESS_LOG:-$dir/log.jsonl}"

payload="$(cat)"
input="$(jq -ce '.tool_input | select(type == "object")' 2>/dev/null <<<"$payload")" || exit 0
brief="$(jq -r '.prompt // ""' <<<"$input")"
chosen="$(jq -r '.model // ""' <<<"$input")"
[ -n "$brief" ] || exit 0

now_ms() { perl -MTime::HiRes=time -e 'printf "%d", time*1000'; }

# judge: runs the classifier, appends one log line, prints the verdict's model on success.
judge() {
  local start errfile verdict rc err ms ts
  start="$(now_ms)"
  errfile="$(mktemp)"
  verdict="$(printf '%s' "$brief" | "$classify" 2>"$errfile")"
  rc=$?
  err="$(head -1 "$errfile")"; rm -f "$errfile"
  ms=$(( $(now_ms) - start ))
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [ "$rc" -eq 0 ] && ! jq -e 'type == "object" and has("model") and has("effort")' >/dev/null 2>&1 <<<"$verdict"; then
    rc=1; err="classifier printed no valid verdict"
  fi
  if [ "$rc" -eq 0 ]; then
    jq -cn --arg ts "$ts" --arg prompt "$brief" --arg chosen "$chosen" --argjson v "$verdict" --argjson ms "$ms" \
      '{ts:$ts, source:"dispatch", prompt:$prompt[0:2000], ok:true} + ($v | {model,effort,reason})
       + {chosen:(if $chosen == "" then null else $chosen end), applied:($chosen == ""), ms:$ms}' >> "$log"
    jq -r .model <<<"$verdict"
  else
    [ -n "$err" ] || err="classifier exited $rc"
    jq -cn --arg ts "$ts" --arg prompt "$brief" --arg chosen "$chosen" --arg error "$err" --argjson ms "$ms" \
      '{ts:$ts, source:"dispatch", prompt:$prompt[0:2000], ok:false, error:$error,
        chosen:(if $chosen == "" then null else $chosen end), applied:false, ms:$ms}' >> "$log"
    return 1
  fi
}

if [ -n "$chosen" ]; then
  ( judge ) </dev/null >/dev/null 2>&1 &
  exit 0
fi

model="$(judge)" || exit 0
jq -cn --argjson input "$input" --arg model "$model" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow",
    permissionDecisionReason: ("harness: model " + $model),
    updatedInput: ($input + {model: $model})}}'
