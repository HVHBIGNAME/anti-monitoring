#!/bin/sh
# A real package transaction, only in an explicitly disposable container.
set -eu

[ "${ANTIMON_DISPOSABLE_TEST:-}" = 1 ] || { printf '%s\n' 'Set ANTIMON_DISPOSABLE_TEST=1 in a disposable container.' >&2; exit 2; }
[ -e /.dockerenv ] || [ -e /run/.containerenv ] || { printf '%s\n' 'A container is required.' >&2; exit 2; }
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' 0
trap 'exit 130' INT
trap 'exit 143' HUP TERM

status=0
sh "$root/antimon.sh" scan --agents qemu --json > "$work/before.json" || status=$?
case "$status" in 0|2) ;; *) exit "$status" ;; esac
grep -q '"packages":1' "$work/before.json"
sh "$root/antimon.sh" remove --agents qemu --dry-run --state-dir "$work/state"
[ ! -e "$work/state" ]
sh "$root/antimon.sh" remove --agents qemu --yes --state-dir "$work/state"
status=0
sh "$root/antimon.sh" scan --agents qemu --json > "$work/after.json" || status=$?
case "$status" in 0|2) ;; *) exit "$status" ;; esac
grep -q '"packages":0' "$work/after.json"
grep -q '"probe_errors":0' "$work/after.json"
cat "$work/after.json"
printf '%s\n' 'REAL PACKAGE REMOVE: PASS'
