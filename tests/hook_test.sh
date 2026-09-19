#!/usr/bin/env bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/tests/lib.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

stub() { # stub <name> <body>
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$tmp/$1"; chmod +x "$tmp/$1"
}
stub good 'cat >/dev/null; echo "{\"model\":\"sonnet\",\"effort\":\"medium\",\"reason\":\"two files\"}"'
stub echoer 'cat > "'"$tmp"'/seen"; echo "{\"model\":\"haiku\",\"effort\":\"low\",\"reason\":\"r\"}"'
stub bad 'cat >/dev/null; echo "classify: timed out after 30s" >&2; exit 1'
stub garbage 'cat >/dev/null; echo "not json"'

run() { # run <stub> <prompt>  -> prints hook stdout
  jq -cn --arg p "$2" '{prompt:$p}' |
    HARNESS_CLASSIFY="$tmp/$1" HARNESS_LOG="$tmp/log.jsonl" "$root/hook.sh"
}

# 1. no cx: prefix -> silent pass-through
out="$(run good 'fix the login bug')"
check "no prefix: no output" "$out" ""
check "no prefix: no log" "$([ -e "$tmp/log.jsonl" ] && echo yes || echo no)" "no"

# 2. recursion guard
out="$(jq -cn '{prompt:"cx: anything"}' |
  HARNESS_CLASSIFYING=1 HARNESS_CLASSIFY="$tmp/good" HARNESS_LOG="$tmp/log.jsonl" "$root/hook.sh")"
check "guard: no output" "$out" ""

# 3. valid verdict -> block + log
out="$(run good 'cx: fix the login bug')"
check "good: decision" "$(jq -r .decision <<<"$out")" "block"
check "good: reason" "$(jq -r .reason <<<"$out")" "sonnet · medium — two files"
check "good: log ok" "$(tail -1 "$tmp/log.jsonl" | jq -c '[.ok,.model,.effort,.reason,.prompt]')" \
  '[true,"sonnet","medium","two files","fix the login bug"]'
check "good: log has ts and ms" "$(tail -1 "$tmp/log.jsonl" | jq -r '(.ts|type)+","+(.ms|type)')" "string,number"

# 4. prefix is stripped before classifying
run echoer 'cx:   rename foo' >/dev/null
check "prefix stripped" "$(cat "$tmp/seen")" "rename foo"

# 5. classifier fails -> block carries the error, log ok:false
out="$(run bad 'cx: something')"
check "bad: decision" "$(jq -r .decision <<<"$out")" "block"
check "bad: reason" "$(jq -r .reason <<<"$out")" "classification failed: classify: timed out after 30s"
check "bad: log" "$(tail -1 "$tmp/log.jsonl" | jq -c '[.ok,.error,has("model")]')" \
  '[false,"classify: timed out after 30s",false]'

# 6. classifier exits 0 with garbage -> treated as failure
out="$(run garbage 'cx: something')"
check "garbage: reason" "$(jq -r .reason <<<"$out")" "classification failed: classifier printed no valid verdict"
check "garbage: log" "$(tail -1 "$tmp/log.jsonl" | jq -r .ok)" "false"

finish
