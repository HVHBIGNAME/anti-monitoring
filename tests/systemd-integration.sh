#!/bin/sh
# Live test on a disposable, uniquely named service. Never targets a real agent.
set -uf

[ "$(id -u)" -eq 0 ] || { printf '%s\n' 'Run this integration test as root.' >&2; exit 2; }
systemctl --system show --property=Version >/dev/null 2>&1 || exit 2
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
work=$(mktemp -d /tmp/antimon-systemd-test.XXXXXXXX) || exit 1
unit=antimon-selftest-${work##*.}
policy=$unit-policy
prefix=/root/$unit
created=0
policy_created=0
prefix_created=0

cleanup() {
    result=$?
    trap - 0
    if [ "$policy_created" -eq 1 ] && [ -f "/etc/systemd/system/$policy.service" ]; then
        systemctl stop "$policy.service" || result=1
        systemctl disable "$policy.service" || result=1
        rm -f "/etc/systemd/system/$policy.service" || result=1
    fi
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
    if [ "$prefix_created" -eq 1 ]; then rm -rf "$prefix" || result=1; fi
    printf 'Fixture cleanup exit: %s\n' "$result"
    exit "$result"
}
trap cleanup 0
trap 'exit 130' INT
trap 'exit 143' HUP TERM

sed '$d' "$root/antimon.sh" > "$work/library.sh" || exit 1
cat > "$work/driver.sh" <<EOF
#!/bin/sh
# anti-monitoring: managed guest-agent inventory and service control.
. '$work/library.sh'
STATE_DIR='$work/state'
BOOT_SERVICE='$policy'
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

# Exercise the actual single-file installer and native boot entry, with the
# fixture-only catalog above. No real guest agent is selected.
[ ! -e "$prefix" ] || exit 1
[ ! -e "/etc/systemd/system/$policy.service" ] || exit 1
policy_created=1
prefix_created=1
sh "$work/driver.sh" --install --prefix "$prefix" --autostart --agents test-agent --yes || exit 1
systemctl is-enabled --quiet "$policy.service" || exit 1
systemctl is-active --quiet "$unit.service" || exit 1
systemd-analyze verify "/etc/systemd/system/$policy.service" || exit 1
systemctl start "$policy.service" || exit 1
[ "$(systemctl show --property=ActiveState --value "$unit.service")" = inactive ] || exit 1
systemctl stop "$policy.service" || exit 1
"$prefix/bin/antimon" --no-autostart || exit 1
[ ! -e "/etc/systemd/system/$policy.service" ] || exit 1
policy_created=0
"$prefix/bin/antimon" --restore --yes || exit 1
systemctl is-active --quiet "$unit.service" || exit 1
"$prefix/bin/antimon" --uninstall || exit 1
[ ! -e "$prefix/bin/antimon" ] || exit 1
printf '%s\n' 'LIVE AUTOSTART: install / register / invoke / unregister / restore / uninstall PASS'
