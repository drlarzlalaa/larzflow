#!/bin/sh
# A fully successful linear ETL workflow: every step runs, exit 0.
d=$(mktemp -d)
$LARZFLOW run examples/linear.lz linear-1 "$d"; echo "exit $?"
rm -rf "$d"
