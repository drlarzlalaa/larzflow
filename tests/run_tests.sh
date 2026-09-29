#!/bin/sh
# Runs each tests/*.sh scenario and diffs its normalized output against
# tests/<name>.expected. Same discipline as sibling projects
# (larzscript-regex etc.), with one addition: LarzFlow's own output has
# wall-clock durations and JSON `duration_s`/`started_at`/`finished_at`
# fields that vary run to run, so normalize() replaces those with a fixed
# placeholder before comparing.
#
# Env override: LARZFLOW="larzscript /path/to/bin/larzflow.lz" to test
# another copy (used by CI).
set -e
cd "$(dirname "$0")/.."
LARZFLOW="${LARZFLOW:-larzscript bin/larzflow.lz}"
export LARZFLOW

normalize() {
  sed -E \
    -e 's/\([0-9]+(\.[0-9]+)?s\)/(Xs)/g' \
    -e 's/"duration_s":[0-9.]+/"duration_s":X/g' \
    -e 's/"started_at":[0-9]+/"started_at":X/g' \
    -e 's/"finished_at":(null|[0-9]+)/"finished_at":X/g'
}

pass=0; fail=0
for t in tests/*.sh; do
  case "$t" in *run_tests.sh) continue ;; esac
  exp="${t%.sh}.expected"
  got="$(sh "$t" 2>&1 | normalize || true)"
  if [ "$got" = "$(cat "$exp")" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); echo "FAIL $t"; echo "--- expected ---"; cat "$exp"; echo "--- got ---"; echo "$got"
  fi
done
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
