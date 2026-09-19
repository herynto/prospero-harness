#!/usr/bin/env bash
# UserPromptSubmit hook: classify every prompt into log.jsonl. Ordinary prompts are
# classified in the background and run as usual; "cx:" prompts show the verdict and block.
set -uo pipefail

# classify runs `claude -p`, which fires this hook again. Stay out of its way.
[ -n "${HARNESS_CLASSIFYING:-}" ] && exit 0

dir="$(cd "$(dirname "$0")" && pwd)"
classify="${HARNESS_CLASSIFY:-$dir/classify}"
log="${HARNESS_LOG:-$dir/log.jsonl}"

payload="$(cat)"
prompt="$(jq -r '.prompt // ""' 2>/dev/null <<<"$payload")"
session="$(jq -r '.session_id // "none"' 2>/dev/null <<<"$payload" | tr -cd 'A-Za-z0-9_-')"
state="${HARNESS_STATE:-$dir/state}/${session:-none}.json"
# Trim leading whitespace of the whole prompt only; later lines keep their indentation.
prompt="${prompt#"${prompt%%[![:space:]]*}"}"
[ -n "$prompt" ] || exit 0

now_ms() { perl -MTime::HiRes=time -e 'printf "%d", time*1000'; }

# inherit_and_log <source> <text> <ms>: a follow-up carries no work of its own, so it
# reuses the session's last real verdict. No model call.
inherit_and_log() {
  local source="$1" text="$2" ms="$3" ts last
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if last="$(jq -ce 'select(.model and .effort)' "$state" 2>/dev/null)"; then
    jq -cn --arg ts "$ts" --arg source "$source" --arg prompt "$text" --argjson l "$last" --argjson ms "$ms" \
      '{ts:$ts, source:$source, prompt:$prompt, ok:true, model:$l.model, effort:$l.effort,
        reason:"follow-up, inherited", inherited_from:$l.prompt, ms:$ms}' >> "$log"
    reason="$(jq -r '"\(.model) · \(.effort) — follow-up, inherited from: \(.prompt[0:80])"' <<<"$last")"
  else
    jq -cn --arg ts "$ts" --arg source "$source" --arg prompt "$text" --argjson ms "$ms" \
      '{ts:$ts, source:$source, prompt:$prompt, ok:true, skipped:"follow-up, nothing to inherit", ms:$ms}' >> "$log"
    reason="follow-up with nothing to inherit in this session"
  fi
}

# Background only: three words or fewer ("ok continue", "yes go on") is treated as a
# follow-up without paying for a model call. "cx:" always asks the model.
is_short() { [ "$(printf '%s' "$1" | wc -w)" -le 3 ]; }

# classify_and_log <source> <text>: runs the classifier, appends one log line, sets $reason.
classify_and_log() {
  local source="$1" text="$2" start errfile verdict rc err ms ts
  if [ "$source" = auto ] && is_short "$text"; then inherit_and_log "$source" "$text" 0; return; fi
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
    if [ "$(jq -r '.followup // false' <<<"$verdict")" = "true" ]; then
      inherit_and_log "$source" "$text" "$ms"
      return
    fi
    verdict="$(jq -c '{model,effort,reason}' <<<"$verdict")"
    mkdir -p "$(dirname "$state")"
    jq -cn --arg prompt "$text" --argjson v "$verdict" '$v + {prompt:$prompt}' > "$state"
    jq -cn --arg ts "$ts" --arg source "$source" --arg prompt "$text" --argjson v "$verdict" --argjson ms "$ms" \
      '{ts:$ts, source:$source, prompt:$prompt, ok:true} + $v + {ms:$ms}' >> "$log"
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
  \<*) exit 0 ;;  # harness-generated turns (agent reports, notifications), not typed prompts
  *)
    # Ordinary prompt: classify in the background for the log only, never delay or block it.
    ( classify_and_log auto "$prompt" ) </dev/null >/dev/null 2>&1 &
    exit 0 ;;
esac

text="${prompt#cx:}"
text="${text#"${text%%[![:space:]]*}"}"
classify_and_log cx "$text"

jq -cn --arg r "$reason" '{decision:"block", reason:$r}'
