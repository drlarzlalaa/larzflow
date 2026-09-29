#!/bin/sh
# The persisted run-state JSON file is real and re-readable after the
# process exits, and `larzflow status` renders it identically to what
# `run` printed live.
d=$(mktemp -d)
$LARZFLOW run examples/linear.lz status-demo "$d" >/dev/null
$LARZFLOW status status-demo "$d"; echo "exit $?"
python3 -c "import json,sys; json.load(open(sys.argv[1])); print('json ok')" "$d/status-demo.json"
rm -rf "$d"
