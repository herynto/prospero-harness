# Sourced by test scripts. Counts failures; call finish at the end.
fails=0
check() { # check <name> <actual> <expected>
  if [ "$2" = "$3" ]; then echo "ok   $1"
  else echo "FAIL $1"; echo "     expected: $3"; echo "     actual:   $2"; fails=$((fails+1)); fi
}
finish() { [ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }; }
