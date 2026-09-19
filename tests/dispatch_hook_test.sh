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
    HARNESS_CLASSIFY="$tmp/$1" HARNESS_LOG="$tmp/log.jsonl" "$root/dispatch-hook.sh"
}
wait_log() { for _ in 1 2 3 4 5 6 7 8 9 10; do [ "$(wc -l < "$tmp/log.jsonl" 2>/dev/null || echo 0)" -gt "$1" ] && break; perl -e 'select(undef,undef,undef,0.2)'; done; }

# 1. no model -> classifier's model filled in, other fields kept
out="$(run good '{"prompt":"implement task 1","description":"Task 1","subagent_type":"general-purpose"}')"
check "fill: decision" "$(jq -r .hookSpecificOutput.permissionDecision <<<"$out")" "allow"
check "fill: updated input" "$(jq -c .hookSpecificOutput.updatedInput <<<"$out")" \
  '{"prompt":"implement task 1","description":"Task 1","subagent_type":"general-purpose","model":"sonnet"}'
check "fill: log" "$(tail -1 "$tmp/log.jsonl" | jq -c '[.source,.ok,.model,.chosen,.applied]')" '["dispatch",true,"sonnet",null,true]'

# 2. model already chosen -> no output, opinion logged in the background
out="$(run good '{"prompt":"review the branch","model":"opus"}')"
check "kept: no output" "$out" ""
wait_log 1
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

finish
