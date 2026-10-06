# Anti-Monitoring

**Inspect Linux guest agents, review a plan, apply selected changes and verify the result.**

[Русский / full visual README ↗](../README.md)

The runtime is a single POSIX `sh` script. It needs standard GNU/BusyBox utilities,
not Bash, Python or a language package manager. Python is optional for development
tests and rendering local SVG reports.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/HVHBIGNAME/anti-monitoring/main/install.sh | sudo sh -s -- --run
```

Omit `sudo` when already root. Root installs to `/usr/local/bin/antimon`; a normal
user installs to `~/.local/bin/antimon`. `--prefix DIR` selects `DIR/bin/antimon`.
The installer resolves a commit, checks SHA-256 and shell syntax, and atomically
replaces the command. Installation itself never removes agents.

Offline installation from a checkout:

```sh
sudo sh install.sh --source "$PWD"
```

## Use

```sh
antimon scan
antimon plan --agents qemu,aws-ssm
sudo antimon disable --agents qemu,aws-ssm
sudo antimon restore

antimon remove --agents aws-cloudwatch --dry-run
sudo antimon remove --agents aws-cloudwatch --yes
```

Run `antimon` for the terminal menu or `antimon list` for IDs and responsibilities.
`--all` explicitly selects every catalog group. `--yes` confirms an explicit
action. `--lang en|ru|auto` controls the interface. Redirected output has no ANSI codes.

Prefer **disable** before package removal. Service startup/activity states and
command output are recorded under `/var/lib/anti-monitoring` (root-only, mode 700).
`restore` defaults to the latest disable snapshot. Repeated no-op disables preserve
the previous recovery snapshot. After package removal, reinstall the packages first
and use `restore --snapshot ID` to restore their recorded service states.

## Scope and compatibility

The supported native package families are APT/dpkg, RPM (DNF/DNF5/YUM/Zypper),
pacman, APK and XBPS, plus the Amazon SSM Snap. Service adapters cover systemd,
OpenRC, runit and conventional SysV init. Missing capabilities are reported rather
than silently treated as successful removal.

On RPM systems, exact removal uses `rpm -e --test` followed by `rpm -e` without
dependency expansion. APT/APK transactions that would remove extra packages are
refused. Immutable/declarative systems retain their native package-management
workflow. Containers without init receive a partial inventory.

See [compatibility and validation](COMPATIBILITY.md) for details.

This controls **software inside the guest OS**. It cannot revoke a provider's
hypervisor, disk, memory or out-of-band console access. Guest agents can also
provide networking, SSH provisioning, filesystem freeze and coordinated backups;
the plan identifies each component's responsibilities.

## Local reports

```sh
antimon scan --json > report.json
python3 tools/render_report.py report.json --output reports/server.svg
```

The second command runs from a checkout, needs Python 3.10+, and uses only the
standard library. It renders actual findings locally; no data is uploaded.

Exit codes: `0` success/no-op, `1` action or verification failure, `2` invalid
arguments/unsupported capability/partial scan/preflight refusal, `3` cancellation.
Partial JSON scans remain machine-readable with `complete: false`.

## Uninstall

```sh
sudo sh uninstall.sh
```

Uninstallation preserves service state and journals. Restore before uninstalling
if you want to undo a disable operation. `--legacy` also removes the recognized
v1 command from the invoking user's `~/.cache/system/.antimon`.

[Contributing](../CONTRIBUTING.md) · [Changelog](../CHANGELOG.md) · [MIT](../LICENSE)
