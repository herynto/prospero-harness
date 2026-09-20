#!/usr/bin/env bash
# PreToolUse hook for subagent dispatches: when the session named no model, fill in the
# classifier's choice. A model the session did choose is kept; the classifier's opinion
# is only logged. Effort cannot be passed per dispatch, so general-purpose dispatches are
# retargeted to agents/ariel-<effort>, whose definition carries it. Other agent types
# are left alone. Never blocks a dispatch: on any failure the call runs unchanged.
set -uo pipefail

[ -n "${PROSPERO_CLASSIFYING:-}" ] && exit 0

dir="$(cd "$(dirname "$0")" && pwd)"
classify="${PROSPERO_CLASSIFY:-$dir/classify}"
# Data lives outside the install dir: a plugin update replaces that directory.
home="${PROSPERO_HOME:-$HOME/.prospero}"
log="${PROSPERO_LOG:-$home/log.jsonl}"
config="${PROSPERO_CONFIG:-$home/config.json}"
# Agents shipped by a plugin are namespaced with the plugin name.
prefix=""; [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && prefix="prospero:"
mkdir -p "$home" 2>/dev/null || exit 0

# Preferences. A missing or broken config.json means: use the verdict as is.
cfg() { jq -r "$1" "$config" 2>/dev/null || true; }
override="$(cfg '.override_chosen == true')"; [ "$override" = true ] || override=false
swap_agents="$(cfg '.swap_agents != false')"; [ "$swap_agents" = false ] || swap_agents=true

payload="$(cat)"
input="$(jq -ce '.tool_input | select(type == "object")' 2>/dev/null <<<"$payload")" || exit 0
brief="$(jq -r '.prompt // ""' <<<"$input")"
chosen="$(jq -r '.model // ""' <<<"$input")"
agent="$(jq -r '.subagent_type // ""' <<<"$input")"
case "$agent" in ""|general-purpose) swap=1 ;; *) swap=0 ;; esac
[ "$swap_agents" = true ] || swap=0
[ "$override" = true ] && chosen_kept="" || chosen_kept="$chosen"
[ -n "$brief" ] || exit 0

now_ms() { perl -MTime::HiRes=time -e 'printf "%d", time*1000'; }

# judge: runs the classifier, maps the verdict through config.json "pairs", appends one
# log line, prints the final "<model> <effort>" on success.
judge() {
  local start errfile verdict rc err ms ts target final cfgerr=""
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
    final="$(jq -r '"\(.model)/\(.effort)"' <<<"$verdict")"
    target="$(jq -r --arg k "$final" '.pairs[$k] // "" | tostring' "$config" 2>/dev/null || true)"
    if [[ "$target" =~ ^(haiku|sonnet|opus|fable)/(low|medium|high)$ ]]; then final="$target"
    elif [ -n "$target" ]; then cfgerr="ignored pairs[\"$final\"] = \"$target\""; fi
    jq -cn --arg ts "$ts" --arg prompt "$brief" --arg chosen "$chosen" --arg kept "$chosen_kept" --argjson swap "$swap" --arg prefix "$prefix" \
       --arg final "$final" --arg cfgerr "$cfgerr" --argjson v "$verdict" --argjson ms "$ms" \
      '($final | split("/")) as $f
       | {ts:$ts, source:"dispatch", prompt:$prompt[0:2000], ok:true} + ($v | {model,effort,reason} + (if .mode then {mode} else {} end))
       + {final_model:(if $kept == "" then $f[0] else $kept end), final_effort:(if $swap == 1 then $f[1] else null end),
          chosen:(if $chosen == "" then null else $chosen end), applied:($kept == ""),
          agent:(if $swap == 1 then $prefix + "ariel-" + $f[1] else null end), ms:$ms}
       + (if $cfgerr == "" then {} else {config_error:$cfgerr} end)' >> "$log"
    printf '%s\n' "${final/\// }"
  else
    [ -n "$err" ] || err="classifier exited $rc"
    jq -cn --arg ts "$ts" --arg prompt "$brief" --arg chosen "$chosen" --arg error "$err" --argjson ms "$ms" \
      '{ts:$ts, source:"dispatch", prompt:$prompt[0:2000], ok:false, error:$error,
        chosen:(if $chosen == "" then null else $chosen end), applied:false, ms:$ms}' >> "$log"
    return 1
  fi
}

if [ -n "$chosen_kept" ] && [ "$swap" -eq 0 ]; then
  ( judge ) </dev/null >/dev/null 2>&1 &
  exit 0
fi

read -r model effort <<<"$(judge)" || exit 0
[ -n "$model" ] && [ -n "$effort" ] || exit 0
jq -cn --argjson input "$input" --arg model "$model" --arg effort "$effort" \
    --arg chosen "$chosen_kept" --argjson swap "$swap" --arg prefix "$prefix" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow",
    permissionDecisionReason: ("prospero: " + (if $chosen == "" then $model else $chosen end) + " · " + $effort),
    updatedInput: ($input
      + (if $chosen == "" then {model: $model} else {} end)
      + (if $swap == 1 then {subagent_type: ($prefix + "ariel-" + $effort)} else {} end))}}'
