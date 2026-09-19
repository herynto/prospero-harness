#!/usr/bin/env bash
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
. "$root/tests/lib.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

fake() { # fake <name> <body>  -> a stand-in for the claude binary
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$tmp/$1"; chmod +x "$tmp/$1"
}
envelope() { jq -cn --arg r "$1" '{result:$r, is_error:false}'; }

run() { # run <fake> -> sets $out, $err, $rc
  out="$(echo 'rename foo to bar' | HARNESS_CLAUDE="$tmp/$1" HARNESS_TIMEOUT="${2:-30}" \
    "$root/classify" 2>"$tmp/err")"; rc=$?; err="$(cat "$tmp/err")"
}

good='{"model":"haiku","effort":"low","reason":"one file"}'
fake ok "cat >/dev/null; cat <<'EOF'
$(envelope "$good")
EOF"
run ok
check "ok: exit" "$rc" "0"
check "ok: verdict" "$out" "$good"

fake fenced "cat >/dev/null; cat <<'EOF'
$(envelope "$(printf '```json\n%s\n```' "$good")")
EOF"
run fenced
check "fenced: verdict" "$out" "$good"

fake extra "cat >/dev/null; cat <<'EOF'
$(envelope '{"model":"opus","effort":"high","reason":"r","agent":"x"}')
EOF"
run extra
check "extra fields dropped" "$out" '{"model":"opus","effort":"high","reason":"r"}'

fake badmodel "cat >/dev/null; cat <<'EOF'
$(envelope '{"model":"gpt","effort":"low","reason":"r"}')
EOF"
run badmodel
check "bad model: exit" "$rc" "1"
check "bad model: no stdout" "$out" ""
check "bad model: message" "${err%%:*}" "classify"

fake badeffort "cat >/dev/null; cat <<'EOF'
$(envelope '{"model":"haiku","effort":"max","reason":"r"}')
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

out="$(echo 'x' | HARNESS_CLAUDE="$tmp/nope" "$root/classify" 2>"$tmp/err")"; rc=$?
check "missing binary: exit" "$rc" "1"
check "missing binary: message" "$(cat "$tmp/err")" "classify: claude not found"

out="$(printf '  \n' | HARNESS_CLAUDE="$tmp/ok" "$root/classify" 2>"$tmp/err")"
check "empty prompt: message" "$(cat "$tmp/err")" "classify: empty prompt"

fake guard 'cat >/dev/null; jq -cn --arg r "{\"model\":\"haiku\",\"effort\":\"low\",\"reason\":\"guard=$HARNESS_CLASSIFYING\"}" "{result:\$r,is_error:false}"'
run guard
check "guard exported" "$(jq -r .reason <<<"$out")" "guard=1"

finish
