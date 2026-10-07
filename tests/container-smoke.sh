#!/bin/sh
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' 0
trap 'exit 130' INT
trap 'exit 143' HUP TERM

sh -n "$root/antimon.sh"
sh "$root/antimon.sh" --help
sh "$root/antimon.sh" --list
status=0
sh "$root/antimon.sh" --scan --json > "$work/scan.json" || status=$?
case "$status" in 0|2) ;; *) exit "$status" ;; esac
grep -q '"schema_version":1' "$work/scan.json"
grep -q '"probe_errors":0' "$work/scan.json"
cat "$work/scan.json"
sh "$root/antimon.sh" --install --source "$root" --prefix "$work/install"
[ "$(sh "$work/install/bin/antimon" --version)" = "$(sh "$root/antimon.sh" --version)" ]
sh "$root/antimon.sh" --uninstall --prefix "$work/install" --dry-run
[ -f "$work/install/bin/antimon" ]
sh "$work/install/bin/antimon" --uninstall
sh "$root/antimon.sh" --uninstall --prefix "$work/install"
[ ! -e "$work/install/bin/antimon" ]
printf '%s\n' 'CONTAINER SMOKE: PASS'
