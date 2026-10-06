#!/bin/sh
# Remove the Anti-Monitoring command; preserve journals and agent state.
# SPDX-License-Identifier: MIT
set -uf

PREFIX=
LEGACY=0
DRY_RUN=0

fail() { printf '[!] %s\n' "$*" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix)
            [ "$#" -ge 2 ] && [ -n "$2" ] || fail 'Missing --prefix value.'
            PREFIX=$2
            shift
            ;;
        --legacy) LEGACY=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --yes|--force) ;;
        --help|-h)
            printf '%s\n' 'Usage: sh uninstall.sh [--prefix /path] [--legacy] [--dry-run]' \
                'Root prefix: /usr/local; user prefix: ~/.local.' \
                '--legacy also removes ~/.cache/system/.antimon for the invoking HOME.' \
                'Journals, service states and installed agents are preserved.'
            exit 0
            ;;
        *) fail "Unknown argument: $1" ;;
    esac
    shift
done

if [ -z "$PREFIX" ]; then
    if [ "$(id -u)" -eq 0 ]; then PREFIX=/usr/local
    else [ -n "${HOME:-}" ] || fail 'HOME is unset; provide --prefix.'; PREFIX=$HOME/.local
    fi
fi
case "$PREFIX" in /*) PREFIX=${PREFIX%/} ;; *) fail '--prefix must be absolute.' ;; esac
[ -n "$PREFIX" ] || fail 'Do not use / as the prefix.'

remove_command() {
    [ ! -L "$1" ] || fail "Refusing to remove a symlink: $1"
    if [ ! -e "$1" ]; then printf 'Not installed: %s\n' "$1"; return 0; fi
    [ -f "$1" ] || fail "Not a regular file: $1"
    grep -q "$2" "$1" || fail "Not an Anti-Monitoring script: $1"
    if [ "$DRY_RUN" -eq 1 ]; then printf 'Would remove: %s\n' "$1"
    else rm -f "$1" || fail "Cannot remove: $1"; printf 'Removed: %s\n' "$1"
    fi
}

remove_command "$PREFIX/bin/antimon" '^# anti-monitoring: managed guest-agent inventory and service control\.$'
if [ "$LEGACY" -eq 1 ]; then
    [ -n "${HOME:-}" ] || fail 'HOME is unset.'
    remove_command "$HOME/.cache/system/.antimon" 'Anti-Monitoring Tool'
fi
printf '%s\n' 'Service states and journals were preserved. To undo a disable operation, run antimon restore before uninstalling.'
