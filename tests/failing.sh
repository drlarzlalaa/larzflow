#!/bin/sh
# transform fails (after 2 retry attempts); report (which depends on it)
# is skipped, not run; notify (no dependency on the failing branch)
# still runs. Exit 1 because something failed.
d=$(mktemp -d)
$LARZFLOW run examples/failing.lz failing-1 "$d"; echo "exit $?"
rm -rf "$d"
