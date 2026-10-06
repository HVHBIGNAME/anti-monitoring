#!/bin/sh
# anti-monitoring installer; installs the command, never removes agents.
# SPDX-License-Identifier: MIT
set -uf

REPOSITORY=HVHBIGNAME/anti-monitoring
REF=main
PREFIX=
SOURCE=
QUIET=0
RUN=0
AUTO_DEPS=0
TEMP=
STAGED=

info() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
fail() { printf '[!] %s\n' "$*" >&2; exit 1; }
has() { command -v "$1" >/dev/null 2>&1; }

usage() {
    cat <<'USAGE'
Install Anti-Monitoring (POSIX sh; Linux)

  sh install.sh [--prefix /absolute/path] [--ref COMMIT_OR_TAG]
  sh install.sh --source /path/to/checkout    Offline/local installation

  --prefix DIR      Install DIR/bin/antimon (root: /usr/local; user: ~/.local)
  --source DIR      Verify and install from a local checkout
  --ref REF         Git ref to download (default: main, resolved to one commit)
  --run             Open the menu after installing, or scan without a terminal
  --auto-deps       Install curl and CA certificates if no downloader exists
  --quiet, --silent Reduce output; errors are still shown
  --force, --yes    Compatibility options; NEVER enable agent removal
  --help

Requires sh, awk, sed, mktemp, and sha256sum/shasum/openssl.
Downloads require curl or wget with working HTTPS certificate verification.
USAGE
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --prefix|--ref|--source)
                [ "$#" -ge 2 ] && [ -n "$2" ] || fail "Missing value: $1"
                case "$1" in --prefix) PREFIX=$2 ;; --ref) REF=$2 ;; --source) SOURCE=$2 ;; esac
                shift
                ;;
            --run) RUN=1 ;;
            --auto-deps) AUTO_DEPS=1 ;;
            --quiet|--silent) QUIET=1 ;;
            --yes|--force) ;;
            --help|-h) usage; exit 0 ;;
            *) fail "Unknown argument: $1" ;;
        esac
        shift
    done
    [ "$(uname -s)" = Linux ] || fail 'This installer supports Linux.'
    if [ -z "$PREFIX" ]; then
        if [ "$(id -u)" -eq 0 ]; then PREFIX=/usr/local
        else [ -n "${HOME:-}" ] || fail 'HOME is unset; provide --prefix.'; PREFIX=$HOME/.local
        fi
    fi
    case "$PREFIX" in /*) PREFIX=${PREFIX%/} ;; *) fail '--prefix must be absolute.' ;; esac
    [ -n "$PREFIX" ] || fail 'Do not use / as the installation prefix.'
    case "$REF" in ''|*[!a-zA-Z0-9._/-]*|../*|*/../*|*/..) fail 'Invalid Git ref.' ;; esac
    if [ -n "$SOURCE" ]; then
        case "$SOURCE" in /*) ;; *) fail '--source must be absolute.' ;; esac
        [ -d "$SOURCE" ] || fail 'Source directory does not exist.'
    fi
}

cleanup() {
    [ -z "$STAGED" ] || rm -f "$STAGED"
    [ -z "$TEMP" ] || rm -rf "$TEMP"
}

install_downloader() {
    has curl || has wget || {
        [ "$AUTO_DEPS" -eq 1 ] || fail 'Install curl + ca-certificates, or use --source for an offline installation.'
        [ "$(id -u)" -eq 0 ] || fail '--auto-deps requires root.'
        if has apt-get; then
            if ! apt-get update || ! apt-get install -y curl ca-certificates; then fail 'Dependency installation failed.'; fi
        elif has dnf; then dnf install -y curl ca-certificates || fail 'Dependency installation failed.'
        elif has yum; then yum install -y curl ca-certificates || fail 'Dependency installation failed.'
        elif has zypper; then zypper --non-interactive install curl ca-certificates || fail 'Dependency installation failed.'
        elif has pacman; then pacman -S --needed --noconfirm curl ca-certificates || fail 'Dependency installation failed.'
        elif has apk; then apk add curl ca-certificates || fail 'Dependency installation failed.'
        elif has xbps-install; then xbps-install -Sy curl ca-certificates || fail 'Dependency installation failed.'
        else fail 'Install curl + ca-certificates with your package manager.'
        fi
    }
}

fetch() {
    if has curl; then
        curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 120 --retry 2 "$1" -o "$2"
    else
        wget -T 30 -O "$2" "$1"
    fi
}

resolve_commit() {
    if [ "${#REF}" -eq 40 ]; then
        case "$REF" in *[!0-9a-fA-F]*) ;; *) printf '%s\n' "$REF"; return 0 ;; esac
    fi
    fetch "https://api.github.com/repos/$REPOSITORY/commits/$REF" "$TEMP/commit.json" || return 1
    commit=$(sed -n 's/^[[:space:]]*"sha":[[:space:]]*"\([0-9a-f]*\)".*/\1/p' "$TEMP/commit.json" | sed -n '1p')
    [ "${#commit}" -eq 40 ] || return 1
    printf '%s\n' "$commit"
}

digest() {
    if has sha256sum; then sha256sum "$1" | awk '{print $1}'
    elif has shasum; then shasum -a 256 "$1" | awk '{print $1}'
    elif has openssl; then openssl dgst -sha256 "$1" | awk '{print $NF}'
    else return 1
    fi
}

verify_payload() {
    [ -s "$TEMP/antimon.sh" ] && [ -s "$TEMP/SHA256SUMS" ] || fail 'Empty download or missing checksum manifest.'
    expected=$(awk '$2 == "antimon.sh" {print $1}' "$TEMP/SHA256SUMS")
    [ "${#expected}" -eq 64 ] || fail 'Invalid checksum manifest.'
    case "$expected" in *[!0-9a-f]*) fail 'Invalid SHA-256 digest.' ;; esac
    actual=$(digest "$TEMP/antimon.sh") || fail 'Install sha256sum, shasum or openssl.'
    [ "$actual" = "$expected" ] || fail 'SHA-256 mismatch; the installed command was not replaced.'
    sh -n "$TEMP/antimon.sh" || fail 'Downloaded script failed shell syntax validation.'
    grep -q '^# anti-monitoring: managed guest-agent inventory and service control\.$' "$TEMP/antimon.sh" || fail 'Unexpected script identity.'
}

main() {
    parse_args "$@"
    for tool in awk sed mktemp sh grep chmod mkdir mv cp; do has "$tool" || fail "Required tool not found: $tool"; done
    has sha256sum || has shasum || has openssl || fail 'Install sha256sum, shasum or openssl.'
    umask 077
    TEMP=$(mktemp -d) || fail 'Cannot create a temporary directory.'
    trap 'cleanup' 0
    trap 'exit 130' INT
    trap 'exit 143' HUP TERM
    if [ -n "$SOURCE" ]; then
        if ! cp "$SOURCE/antimon.sh" "$TEMP/antimon.sh" || ! cp "$SOURCE/SHA256SUMS" "$TEMP/SHA256SUMS"; then fail 'Incomplete local checkout. Generate SHA256SUMS first.'; fi
        info "Source: $SOURCE"
    else
        install_downloader
        commit=$(resolve_commit) || fail 'Cannot resolve Git ref. Check connectivity/GitHub rate limits, or provide a full commit SHA.'
        info "Source: $REPOSITORY@$commit"
        base=https://raw.githubusercontent.com/$REPOSITORY/$commit
        if ! fetch "$base/antimon.sh" "$TEMP/antimon.sh" || ! fetch "$base/SHA256SUMS" "$TEMP/SHA256SUMS"; then fail 'Download failed; installation was not changed.'; fi
    fi
    verify_payload
    destination=$PREFIX/bin/antimon
    [ ! -L "$destination" ] || fail "Refusing to replace a symlink: $destination"
    if [ -e "$destination" ]; then
        if [ ! -f "$destination" ] || ! grep -q '^# anti-monitoring: managed guest-agent inventory and service control\.$' "$destination"; then fail "Refusing to overwrite an unrelated file: $destination"; fi
    fi
    (umask 022; mkdir -p "$PREFIX/bin") || fail "Cannot create $PREFIX/bin. Choose a writable prefix or run as root."
    STAGED=$(mktemp "$PREFIX/bin/.antimon.XXXXXX") || fail 'Cannot stage the installation.'
    if ! cp "$TEMP/antimon.sh" "$STAGED" || ! chmod 755 "$STAGED"; then fail 'Cannot prepare executable.'; fi
    mv -f "$STAGED" "$destination" || fail 'Cannot atomically install executable.'
    STAGED=
    info "Installed: $destination"
    info "Start: $destination"
    case ":${PATH:-}:" in *":$PREFIX/bin:"*) ;; *) info "Add $PREFIX/bin to PATH, or use the full path above." ;; esac
    if [ "$RUN" -eq 1 ]; then
        if [ -t 1 ] && (exec 3<>/dev/tty) 2>/dev/null; then sh "$destination" menu
        else sh "$destination" scan
        fi
    fi
}

main "$@"
