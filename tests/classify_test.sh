#!/usr/bin/env bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/tests/lib.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export PROSPERO_HOME="$tmp/home"; unset CLAUDE_PLUGIN_ROOT

fake() { # fake <name> <body>  -> a stand-in for the claude binary
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$tmp/$1"; chmod +x "$tmp/$1"
}
envelope() { jq -cn --arg r "$1" '{result:$r, is_error:false}'; }

run() { # run <fake> -> sets $out, $err, $rc
  out="$(echo 'rename foo to bar' | PROSPERO_CLAUDE="$tmp/$1" PROSPERO_TIMEOUT="${2:-30}" \
    PROSPERO_CONFIG="$tmp/config.json" \
    "$root/classify" 2>"$tmp/err")"; rc=$?; err="$(cat "$tmp/err")"
}

good='{"model":"haiku","effort":"low","reason":"one file","followup":false}'
fake ok "cat >/dev/null; cat <<'EOF'
$(envelope "$good")
EOF"
run ok
check "ok: exit" "$rc" "0"
check "ok: verdict" "$out" "${good%\}},\"mode\":\"balanced\"}"

fake fenced "cat >/dev/null; cat <<'EOF'
$(envelope "$(printf '```json\n%s\n```' "$good")")
EOF"
run fenced
check "fenced: verdict" "$out" "${good%\}},\"mode\":\"balanced\"}"

fake extra "cat >/dev/null; cat <<'EOF'
$(envelope '{"model":"opus","effort":"high","reason":"r","agent":"x"}')
EOF"
run extra
check "extra fields dropped" "$out" '{"model":"opus","effort":"high","reason":"r","followup":false,"mode":"balanced"}'

fake badmodel "cat >/dev/null; cat <<'EOF'
$(envelope '{"model":"gpt","effort":"low","reason":"r","followup":false}')
EOF"
run badmodel
check "bad model: exit" "$rc" "1"
check "bad model: no stdout" "$out" ""
check "bad model: message" "${err%%:*}" "classify"

fake badeffort "cat >/dev/null; cat <<'EOF'
$(envelope '{"model":"haiku","effort":"max","reason":"r","followup":false}')
EOF"
run badeffort
check "bad effort: exit" "$rc" "1"

fake prose "cat >/dev/null; cat <<'EOF'
$(envelope 'Sure! I would use sonnet.')
EOF"
run prose
check "prose: exit" "$rc" "1"

fake apierror "cat >/dev/null; echo '{\"result\":\"overloaded\",\"is_error\":true}'"
run apierror
check "api error: exit" "$rc" "1"
check "api error: message" "$err" "classify: claude returned an error"

fake crash "cat >/dev/null; exit 3"
run crash
check "crash: message" "$err" "classify: claude exited 3"

fake slow "cat >/dev/null; sleep 5"
run slow 1
check "timeout: message" "$err" "classify: timed out after 1s"

out="$(echo 'x' | PROSPERO_CLAUDE="$tmp/nope" "$root/classify" 2>"$tmp/err")"; rc=$?
check "missing binary: exit" "$rc" "1"
check "missing binary: message" "$(cat "$tmp/err")" "classify: claude not found"

out="$(printf '  \n' | PROSPERO_CLAUDE="$tmp/ok" "$root/classify" 2>"$tmp/err")"
check "empty prompt: message" "$(cat "$tmp/err")" "classify: empty prompt"

fake guard 'cat >/dev/null; jq -cn --arg r "{\"model\":\"haiku\",\"effort\":\"low\",\"reason\":\"guard=$PROSPERO_CLASSIFYING\"}" "{result:\$r,is_error:false}"'
run guard
check "guard exported" "$(jq -r .reason <<<"$out")" "guard=1"

# modes: the fake reports which "## Mode:" heading its rules file carries
fake rules 'cat >/dev/null; while [ $# -gt 0 ]; do [ "$1" = --system-prompt-file ] && f="$2"; shift; done
h="$(grep -m1 "^## Mode:" "$f" || echo none)"
jq -cn --arg r "{\"model\":\"haiku\",\"effort\":\"low\",\"reason\":\"$h\",\"followup\":false}" "{result:\$r,is_error:false}"'
run rules
check "mode: default adds nothing" "$(jq -c '[.reason,.mode]' <<<"$out")" '["none","balanced"]'
echo '{"mode":"quality"}' > "$tmp/config.json"
run rules
check "mode: from config" "$(jq -c '[.reason,.mode]' <<<"$out")" '["## Mode: quality","quality"]'
out="$(echo 'x' | PROSPERO_MODE=cheap PROSPERO_CLAUDE="$tmp/rules" PROSPERO_CONFIG="$tmp/config.json" "$root/classify")"
check "mode: env wins" "$(jq -c '[.reason,.mode]' <<<"$out")" '["## Mode: cheap","cheap"]'
echo '{"mode":"../prompt"}' > "$tmp/config.json"
run rules
check "mode: unknown falls back" "$(jq -c '[.reason,.mode]' <<<"$out")" '["none","balanced"]'
rm -f "$tmp/config.json"

# token: hooks get no CLAUDE_CODE_OAUTH_TOKEN, so classify loads it from a file
fake token 'cat >/dev/null; jq -cn --arg r "{\"model\":\"haiku\",\"effort\":\"low\",\"reason\":\"tok=${CLAUDE_CODE_OAUTH_TOKEN:-none}\"}" "{result:\$r,is_error:false}"'
echo 'CLAUDE_CODE_OAUTH_TOKEN=from-file' > "$tmp/token.env"
tok() { echo 'x' | PROSPERO_CLAUDE="$tmp/token" PROSPERO_CONFIG="$tmp/config.json" "$@" "$root/classify" | jq -r .reason; }
check "token: loaded from file" "$(tok env -u CLAUDE_CODE_OAUTH_TOKEN PROSPERO_TOKEN_FILE="$tmp/token.env")" "tok=from-file"
check "token: env wins" "$(tok env CLAUDE_CODE_OAUTH_TOKEN=from-env PROSPERO_TOKEN_FILE="$tmp/token.env")" "tok=from-env"
check "token: missing file is fine" "$(tok env -u CLAUDE_CODE_OAUTH_TOKEN PROSPERO_TOKEN_FILE="$tmp/nope.env")" "tok=none"

finish
