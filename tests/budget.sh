#!/bin/sh
# cheap_call fits the $1.00 category limit; pricey_call would push it
# over and is blocked before it runs. Exit 1 because something failed.
d=$(mktemp -d)
$LARZFLOW run examples/budget_gate.lz budget-1 "$d"; echo "exit $?"
rm -rf "$d"
