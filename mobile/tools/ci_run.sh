#!/usr/bin/env bash
# Runs a command; on failure publishes the tail of its output as a GitHub annotation so the failure
# can be read without downloading logs. Usage: ci_run.sh <label> <command...>
label="$1"; shift
log="$(mktemp)"
set +e
"$@" 2>&1 | tee "$log"
code=${PIPESTATUS[0]}
set -e
if [ "$code" -ne 0 ]; then
  { grep -a -m3 -A22 -e '\[E\]' -e 'EXCEPTION CAUGHT' "$log" | head -c 2600; echo '-----'; tail -c 1000 "$log"; } > "$log.short" || true
  msg="$(cat "$log.short" | sed -e 's/%/%25/g' -e ':a;N;$!ba;s/\r//g;s/\n/%0A/g')"
  echo "::error title=${label} failed::${msg}"
fi
exit "$code"
