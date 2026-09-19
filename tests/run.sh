#!/usr/bin/env bash
# Scores the real classifier against tests/cases.jsonl. Calls the model 15 times.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tier() { case "$1" in haiku) echo 0;; sonnet) echo 1;; opus) echo 2;; fable) echo 3;; *) echo 99;; esac; }

total=0 model_ok=0 effort_ok=0 both_ok=0 far=0 errors=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  total=$((total+1))
  prompt="$(jq -r .prompt <<<"$line")"
  want_m="$(jq -r .model <<<"$line")"; want_e="$(jq -r .effort <<<"$line")"
  if ! got="$(printf '%s' "$prompt" | "$root/classify" 2>&1)"; then
    errors=$((errors+1)); far=$((far+1))
    printf 'ERR  %-7s %-7s %s\n     %s\n' "$want_m" "$want_e" "${prompt:0:60}" "$got"; continue
  fi
  got_m="$(jq -r .model <<<"$got")"; got_e="$(jq -r .effort <<<"$got")"
  m=0; e=0
  [ "$got_m" = "$want_m" ] && m=1 && model_ok=$((model_ok+1))
  [ "$got_e" = "$want_e" ] && e=1 && effort_ok=$((effort_ok+1))
  [ $((m+e)) -eq 2 ] && both_ok=$((both_ok+1))
  d=$(( $(tier "$got_m") - $(tier "$want_m") )); [ "${d#-}" -gt 1 ] && far=$((far+1))
  mark="ok  "; [ $((m+e)) -eq 2 ] || mark="MISS"
  printf '%s want %-6s/%-6s got %-6s/%-6s %s\n' "$mark" "$want_m" "$want_e" "$got_m" "$got_e" "${prompt:0:50}"
done < "$root/tests/cases.jsonl"

echo "---"
echo "model  $model_ok/$total"
echo "effort $effort_ok/$total"
echo "both   $both_ok/$total"
echo "more than one tier off (or errored): $far"
[ "$model_ok" -ge 12 ] && [ "$far" -eq 0 ] && { echo "PASS"; exit 0; }
echo "BELOW BAR (need model >= 12/$total and none more than one tier off)"; exit 1
