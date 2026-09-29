#!/bin/sh
$LARZFLOW; echo "exit $?"
$LARZFLOW bogus-command; echo "exit $?"
$LARZFLOW validate; echo "exit $?"
