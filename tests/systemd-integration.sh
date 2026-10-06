#!/bin/sh
# Live test on a disposable, uniquely named service. Never targets a real agent.
set -uf

[ "$(id -u)" -eq 0 ] || { printf '%s\n' 'Run this integration test as root.' >&2; exit 2; }
systemctl --system show --property=Version >/dev/null 2>&1 || exit 2
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
work=$(mktemp -d /tmp/antimon-systemd-test.XXXXXXXX) || exit 1
unit=antimon-selftest-${work##*.}
created=0

cleanup() {
    result=$?
    trap - 0
    if [ "$created" -eq 1 ]; then
        systemctl stop "$unit.service" || result=1
        systemctl disable "$unit.service" || result=1
        systemctl --runtime disable "$unit.service" || result=1
        systemctl unmask "$unit.service" || result=1
        systemctl --runtime unmask "$unit.service" || result=1
        rm -f "/run/systemd/system/$unit.service" || result=1
        systemctl daemon-reload || result=1
        if systemctl is-active --quiet "$unit.service"; then result=1; fi
    fi
    rm -rf "$work" || result=1
    printf 'Fixture cleanup exit: %s\n' "$result"
    exit "$result"
}
trap cleanup 0
trap 'exit 130' INT
trap 'exit 143' HUP TERM

sed '$d' "$root/antimon.sh" > "$work/library.sh" || exit 1
cat > "$work/driver.sh" <<EOF
#!/bin/sh
. '$work/library.sh'
STATE_DIR='$work/state'
catalog() { printf '%s\\n' 'test-agent|Isolated integration fixture||$unit|Test-only sleep process'; }
main "\$@"
EOF
[ ! -e "/run/systemd/system/$unit.service" ] || exit 1
cat > "/run/systemd/system/$unit.service" <<'UNIT'
[Unit]
Description=Anti-Monitoring isolated integration fixture
[Service]
Type=simple
ExecStart=/bin/sleep 300
[Install]
WantedBy=multi-user.target
UNIT
created=1
systemctl daemon-reload || exit 1
systemctl --runtime enable --now "$unit.service" || exit 1

sh "$work/driver.sh" disable --agents test-agent --dry-run || exit 1
[ ! -e "$work/state" ] || exit 1
sh "$work/driver.sh" disable --agents test-agent --yes || exit 1
[ "$(systemctl is-enabled "$unit.service")" = masked ] || exit 1
[ "$(systemctl show --property=ActiveState --value "$unit.service")" = inactive ] || exit 1
before=$(cat "$work/state/latest-disable") || exit 1
sh "$work/driver.sh" disable --agents test-agent --yes || exit 1
[ "$(cat "$work/state/latest-disable")" = "$before" ] || exit 1
sh "$work/driver.sh" restore --yes || exit 1
[ "$(systemctl is-enabled "$unit.service")" = enabled-runtime ] || exit 1
systemctl is-active --quiet "$unit.service" || exit 1
printf '%s\n' 'LIVE SYSTEMD: preview / disable / repeat / restore PASS'
