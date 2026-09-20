#!/usr/bin/env bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/tests/lib.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$tmp/$1"; chmod +x "$tmp/$1"; }
stub good 'cat >/dev/null; echo "{\"model\":\"sonnet\",\"effort\":\"medium\",\"reason\":\"two files\",\"followup\":false}"'
stub bad 'cat >/dev/null; echo "classify: timed out after 45s" >&2; exit 1'

run() { # run <stub> <tool_input json>
  jq -cn --argjson i "$2" '{tool_name:"Agent", tool_input:$i}' |
    HARNESS_CLASSIFY="$tmp/$1" HARNESS_LOG="$tmp/log.jsonl" HARNESS_CONFIG="$tmp/config.json" "$root/dispatch-hook.sh"
}
wait_log() { for _ in 1 2 3 4 5 6 7 8 9 10; do [ "$(wc -l < "$tmp/log.jsonl" 2>/dev/null || echo 0)" -gt "$1" ] && break; perl -e 'select(undef,undef,undef,0.2)'; done; }

# 1. no model -> classifier's model filled in, other fields kept
out="$(run good '{"prompt":"implement task 1","description":"Task 1","subagent_type":"general-purpose"}')"
check "fill: decision" "$(jq -r .hookSpecificOutput.permissionDecision <<<"$out")" "allow"
check "fill: updated input" "$(jq -c .hookSpecificOutput.updatedInput <<<"$out")" \
  '{"prompt":"implement task 1","description":"Task 1","subagent_type":"harness-medium","model":"sonnet"}'
check "fill: log" "$(tail -1 "$tmp/log.jsonl" | jq -c '[.source,.ok,.model,.chosen,.applied,.agent]')" '["dispatch",true,"sonnet",null,true,"harness-medium"]'

# 1b. other agent types keep their type, only the model is filled in
out="$(run good '{"prompt":"find the routes","subagent_type":"Explore"}')"
check "other type: updated input" "$(jq -c .hookSpecificOutput.updatedInput <<<"$out")" \
  '{"prompt":"find the routes","subagent_type":"Explore","model":"sonnet"}'

# 1c. general-purpose with a chosen model: model kept, agent swapped for effort
out="$(run good '{"prompt":"implement task 3","model":"haiku"}')"
check "effort only: updated input" "$(jq -c .hookSpecificOutput.updatedInput <<<"$out")" \
  '{"prompt":"implement task 3","model":"haiku","subagent_type":"harness-medium"}'
check "effort only: log" "$(tail -1 "$tmp/log.jsonl" | jq -c '[.chosen,.applied,.agent]')" '["haiku",false,"harness-medium"]'

# 2. model already chosen -> no output, opinion logged in the background
before="$(wc -l < "$tmp/log.jsonl")"
out="$(run good '{"prompt":"review the branch","model":"opus","subagent_type":"Plan"}')"
check "kept: no output" "$out" ""
wait_log "$before"
check "kept: log" "$(tail -1 "$tmp/log.jsonl" | jq -c '[.model,.chosen,.applied]')" '["sonnet","opus",false]'

# 3. classifier fails -> dispatch runs unchanged, failure logged
out="$(run bad '{"prompt":"implement task 2"}')"
check "fail open: no output" "$out" ""
check "fail open: log" "$(tail -1 "$tmp/log.jsonl" | jq -c '[.ok,.error,.applied]')" '[false,"classify: timed out after 45s",false]'

# 4. recursion guard and junk stdin stay silent
out="$(jq -cn '{tool_input:{prompt:"x"}}' | HARNESS_CLASSIFYING=1 HARNESS_CLASSIFY="$tmp/good" HARNESS_LOG="$tmp/log.jsonl" "$root/dispatch-hook.sh")"
check "guard: no output" "$out" ""
out="$(printf 'not json' | HARNESS_CLASSIFY="$tmp/good" HARNESS_LOG="$tmp/log.jsonl" "$root/dispatch-hook.sh" 2>&1)"
check "junk stdin: silent" "$out" ""

# 5. config.json pairs remap the verdict; a chosen model is still kept
echo '{"pairs":{"sonnet/medium":"fable/low"}}' > "$tmp/config.json"
out="$(run good '{"prompt":"implement task 4"}')"
check "pairs: remapped" "$(jq -c .hookSpecificOutput.updatedInput <<<"$out")" \
  '{"prompt":"implement task 4","model":"fable","subagent_type":"harness-low"}'
check "pairs: log" "$(tail -1 "$tmp/log.jsonl" | jq -c '[.model,.effort,.final_model,.final_effort]')" '["sonnet","medium","fable","low"]'
out="$(run good '{"prompt":"implement task 5","model":"haiku"}')"
check "pairs: chosen model kept" "$(jq -c .hookSpecificOutput.updatedInput <<<"$out")" \
  '{"prompt":"implement task 5","model":"haiku","subagent_type":"harness-low"}'

# 6. override_chosen replaces the session's model, for every agent type
echo '{"pairs":{"sonnet/medium":"fable/low"},"override_chosen":true}' > "$tmp/config.json"
out="$(run good '{"prompt":"find the routes","model":"haiku","subagent_type":"Explore"}')"
check "override: updated input" "$(jq -c .hookSpecificOutput.updatedInput <<<"$out")" \
  '{"prompt":"find the routes","model":"fable","subagent_type":"Explore"}'

# 7. swap_agents off -> type untouched; bad pair ignored and noted in the log
echo '{"pairs":{"sonnet/medium":"opus/medum"},"swap_agents":false}' > "$tmp/config.json"
out="$(run good '{"prompt":"implement task 6","subagent_type":"general-purpose"}')"
check "no swap: updated input" "$(jq -c .hookSpecificOutput.updatedInput <<<"$out")" \
  '{"prompt":"implement task 6","subagent_type":"general-purpose","model":"sonnet"}'
check "bad pair: noted" "$(tail -1 "$tmp/log.jsonl" | jq -r .config_error)" 'ignored pairs["sonnet/medium"] = "opus/medum"'

# 8. broken config file -> behaves as with no config
echo 'not json' > "$tmp/config.json"
out="$(run good '{"prompt":"implement task 7"}')"
check "broken config: defaults" "$(jq -c .hookSpecificOutput.updatedInput <<<"$out")" \
  '{"prompt":"implement task 7","model":"sonnet","subagent_type":"harness-medium"}'

# 9. config CLI
export HARNESS_CONFIG="$tmp/cli.json"
"$root/config" set opus/medium fable/low >/dev/null
check "cli: set" "$(jq -r '.pairs["opus/medium"]' "$tmp/cli.json")" "fable/low"
check "cli: show marks change" "$("$root/config" show | grep -c '\*')" "1"
check "cli: bad pair rejected" "$("$root/config" set opus/medum fable/low 2>&1; echo $?)" "$(printf "config: bad pair 'opus/medum', want <model>/<effort>, e.g. opus/medium\n1")"
"$root/config" switch override_chosen true >/dev/null
check "cli: switch" "$(jq -r .override_chosen "$tmp/cli.json")" "true"
"$root/config" mode quality >/dev/null
check "cli: mode" "$(jq -r .mode "$tmp/cli.json")" "quality"
check "cli: mode list" "$("$root/config" mode | tr '\n' ',')" "  balanced,  cheap,* quality,"
check "cli: unknown mode rejected" "$("$root/config" mode turbo >/dev/null 2>&1; echo $?)" "1"
"$root/config" reset >/dev/null
check "cli: reset" "$(jq -c '[.pairs["opus/medium"],.override_chosen,.mode]' "$tmp/cli.json")" '["opus/medium",false,"balanced"]'

# 10. config edit, keys fed on stdin: down x7 -> opus/medium, Enter, down x3 -> fable, Enter,
#     Enter -> low, then q. Then: up x4 from the top wraps to override_chosen, Enter, q.
D=$'\033[B'; U=$'\033[A'
printf '%s' "$D$D$D$D$D$D$D" $'\n' "$D$D$D" $'\n' $'\n' q | HARNESS_MENU_TEST=1 "$root/config" edit 2>/dev/null
check "edit: pair set" "$(jq -r '.pairs["opus/medium"]' "$tmp/cli.json")" "fable/low"
printf '%s' "$U$U$U$U" $'\n' q | HARNESS_MENU_TEST=1 "$root/config" edit 2>/dev/null
check "edit: switch toggled" "$(jq -r .override_chosen "$tmp/cli.json")" "true"
# down x12 -> mode row, Enter, down x2 -> quality, Enter, q
printf '%s' "$D$D$D$D$D$D$D$D$D$D$D$D" $'\n' "$D$D" $'\n' q | HARNESS_MENU_TEST=1 "$root/config" edit 2>/dev/null
check "edit: mode set" "$(jq -r .mode "$tmp/cli.json")" "quality"
check "edit: needs a terminal" "$("$root/config" edit </dev/null 2>&1 | head -1)" \
  "config: edit needs a terminal; from Claude Code use: config set <from> <to>"

finish
