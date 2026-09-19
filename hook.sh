#!/usr/bin/env bash
# UserPromptSubmit hook: classify every prompt into log.jsonl. Ordinary prompts are
# classified in the background and run as usual; "cx:" prompts show the verdict and block.
set -uo pipefail

# classify runs `claude -p`, which fires this hook again. Stay out of its way.
[ -n "${HARNESS_CLASSIFYING:-}" ] && exit 0

dir="$(cd "$(dirname "$0")" && pwd)"
classify="${HARNESS_CLASSIFY:-$dir/classify}"
log="${HARNESS_LOG:-$dir/log.jsonl}"

prompt="$(jq -r '.prompt // ""' 2>/dev/null)"
# Trim leading whitespace of the whole prompt only; later lines keep their indentation.
prompt="${prompt#"${prompt%%[![:space:]]*}"}"
[ -n "$prompt" ] || exit 0

now_ms() { perl -MTime::HiRes=time -e 'printf "%d", time*1000'; }

# classify_and_log <source> <text>: runs the classifier, appends one log line, sets $reason.
classify_and_log() {
  local source="$1" text="$2" start errfile verdict rc err ms ts
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
    jq -cn --arg ts "$ts" --arg source "$source" --arg prompt "$text" --argjson v "$verdict" --argjson ms "$ms" \
      '{ts:$ts, source:$source, prompt:$prompt, ok:true} + ($v | {model,effort,reason}) + {ms:$ms}' >> "$log"
    reason="$(jq -r '"\(.model) · \(.effort) — \(.reason)"' <<<"$verdict")"
  else
    [ -n "$err" ] || err="classifier exited $rc"
    jq -cn --arg ts "$ts" --arg source "$source" --arg prompt "$text" --arg error "$err" --argjson ms "$ms" \
      '{ts:$ts, source:$source, prompt:$prompt, ok:false, error:$error, ms:$ms}' >> "$log"
    reason="classification failed: $err"
  fi
}

case "$prompt" in
  cx:*) ;;
  *)
    # Ordinary prompt: classify in the background for the log only, never delay or block it.
    ( classify_and_log auto "$prompt" ) </dev/null >/dev/null 2>&1 &
    exit 0 ;;
esac

text="${prompt#cx:}"
text="${text#"${text%%[![:space:]]*}"}"
classify_and_log cx "$text"

jq -cn --arg r "$reason" '{decision:"block", reason:$r}'
