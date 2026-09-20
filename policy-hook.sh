#!/usr/bin/env bash
# SessionStart hook: state the subagent-first policy, so dispatches actually happen and
# the dispatch hook has something to judge. Claude Code otherwise holds the Agent tool
# back unless asked. Opt out with: prospero-config set subagent_first false
set -uo pipefail

[ -n "${PROSPERO_CLASSIFYING:-}" ] && exit 0

dir="$(cd "$(dirname "$0")" && pwd)"
home="${PROSPERO_HOME:-$HOME/.prospero}"
config="${PROSPERO_CONFIG:-$home/config.json}"
policy="${PROSPERO_POLICY:-$dir/policy.md}"

# A missing or broken config.json means: policy on.
[ "$(jq -r '.subagent_first == false' "$config" 2>/dev/null)" = true ] && exit 0
[ -r "$policy" ] || exit 0

jq -Rsn --rawfile p "$policy" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $p}}'
