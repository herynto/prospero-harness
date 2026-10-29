#!/usr/bin/env bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/tests/lib.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export PROSPERO_CONFIG="$tmp/c.json"
cfg="$root/bin/prospero-config"
json() { "$cfg" show --json | jq -r "$1" 2>/dev/null; }
nofile() { rm -f "$PROSPERO_CONFIG"; json "$1"; }

check "json: no file: mode" "$(nofile .mode)" "balanced"
check "json: no file: switches" "$(nofile '.switches | tojson')" '{"override_chosen":false,"swap_agents":true,"subagent_first":true}'
check "json: no file: pair count" "$(nofile '.pairs | length')" "12"
check "json: no file: first pair" "$(nofile '.pairs | keys_unsorted | first')" "haiku/low"
check "json: no file: last pair" "$(nofile '.pairs | keys_unsorted | last')" "fable/high"
check "json: no file: identity pair" "$(nofile '.pairs["opus/low"]')" "opus/low"

echo '{"pairs":{},"mode":"cheap","swap_agents":false}' > "$PROSPERO_CONFIG"
check "json: missing key: mode" "$(json .mode)" "cheap"
check "json: missing key: subagent_first" "$(json .switches.subagent_first)" "true"
check "json: missing key: swap_agents" "$(json .switches.swap_agents)" "false"
check "json: missing key: override_chosen" "$(json .switches.override_chosen)" "false"

"$cfg" set fable/low opus/medium >/dev/null
check "json: custom pair: changed" "$(json '.pairs["fable/low"]')" "opus/medium"
check "json: custom pair: untouched" "$(json '.pairs["fable/high"]')" "fable/high"

check "json: modes" "$(json '.modes | join(",")')" "balanced,cheap,quality"

"$cfg" show --json | jq -e type >/dev/null 2>&1
check "json: valid" "$?" "0"

echo '{"pairs":{"fable/low":"opus/medium"},"mode":"cheap","swap_agents":false}' > "$PROSPERO_CONFIG"
"$cfg" show > "$tmp/plain"
cmp -s "$tmp/plain" "$root/tests/config_show.golden"
check "show: plain unchanged" "$?" "0"

finish
