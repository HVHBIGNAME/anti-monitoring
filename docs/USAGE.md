# Advanced usage

[← README](../README.md)

All user operations live in **`antimon.sh`**, installed as `antimon`. There is no
separate installer or uninstaller. Run `antimon --help` for every flag.

## Installation and updates

```sh
# A downloaded standalone file can install itself without network access:
sh antimon.sh --install --prefix "$HOME/.local"

# Verify against the checkout's SHA256SUMS:
sudo sh antimon.sh --install --source "$PWD"

# Download a chosen tag, branch or full commit SHA:
sudo antimon --install --ref main

# Preview uninstall, then remove the command:
antimon --uninstall --dry-run
sudo antimon --uninstall
```

Root defaults to `/usr/local/bin/antimon`; a normal user to `~/.local/bin/antimon`.
An installed command recognizes its own prefix. `--prefix DIR` overrides this.
Downloads require curl/wget with trusted HTTPS and sha256sum/shasum/openssl.
Network installation resolves one commit and checks its SHA-256 manifest and shell
syntax before atomic replacement. Local standalone installation copies the file
you are already running; `--source` adds manifest verification.

Use `--quiet` for reduced installer output. `--legacy` with `--uninstall` removes
the recognized v1 command from the invoking HOME's `~/.cache/system/.antimon`.
Uninstall removes this prefix's autostart registration, but preserves guest-agent
states and recovery snapshots. It does not restore files deleted by v1.

## Autostart

```sh
sudo antimon --autostart --agents qemu,aws-ssm --yes
sudo antimon --no-autostart
sudo sh antimon.sh --install --autostart --agents qemu --yes
```

Autostart runs **once per boot**, using `--disable --yes` with your agent selection,
language and `--state-dir`. It does not run package removal. Registering it does not
immediately change guest agents; `--disable` is the explicit action for that.
`--run` is different: it opens the menu immediately after installing.

Native entries are generated for the running init:

| Init | Boot registration |
| :-- | :-- |
| systemd | `anti-monitoring.service`, wanted by `multi-user.target` |
| OpenRC | `anti-monitoring` in the `default` runlevel |
| runit | `anti-monitoring` service link; skips the boot in which it was registered |
| SysV | `anti-monitoring` init entry via update-rc.d or chkconfig |

Boot execution requires root and a root-owned permanent installation path, with
no symlinks or group/other-writable parents. A user installation under a writable
home directory cannot become a root boot command. Supported boot paths contain
letters, digits, spaces, dots, slashes, underscores and dashes. No autostart is
registered on systems without a supported running init.
On runit, removal unlinks the supervised service; its inactive definition and
supervisor metadata remain available for re-registration.

Disable autostart **before `--restore`** if you want the restored agents to stay
enabled across subsequent boots. A reboot test is separate from verifying native
registration; the CI fixture starts the generated systemd unit explicitly.

## Recovery and reports

```sh
sudo antimon --restore
sudo antimon --restore --snapshot 20261006T120000Z.XXXXXX
antimon --scan --json > report.json
python3 tools/render_report.py report.json --output reports/server.svg --theme light
```

`--state-dir /absolute/path` defaults to `/var/lib/anti-monitoring`, owned by root
with mode 700. Each operation records `metadata`, `inventory` and `output.log`.
Restore defaults to the latest disable snapshot. After `--remove`, reinstall the
packages before restoring the corresponding snapshot. Re-running a provisioning
service can have effects beyond its service state; this is not a full VM backup.

The report renderer runs from the checkout with Python 3.10+ and no extra libraries.
It uses local data, not a privacy score. The catalog diagrams are also available as
theme-aware assets under `assets/`.

Exit codes: `0` success/no-op, `1` execution/verification failure, `2` invalid input,
unsupported capability or partial scan, `3` cancelled; `130`/`143` signal interruption.
For partial JSON scans, check `complete` and `probe_errors`. Older action names
without `--` remain accepted for existing automation.
