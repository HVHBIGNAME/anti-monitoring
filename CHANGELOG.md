# Changelog

## 2.0.0

### Commands and behavior

- POSIX sh runtime; no Bash-specific arrays, `[[ ... ]]`, `echo -e` or `$EUID`.
- Read-only scan, JSON reports, explicit agent selection, menu, dry-run and restore.
- Package inventory uses exact names and installed status, including Debian multiarch.
- Enabled-but-inactive services are handled; systemd aliases are deduplicated.
- Backends: APT, RPM, pacman, APK, XBPS, Amazon SSM Snap; systemd, OpenRC, runit, SysV.
- PID 1 is checked so installed service-management tools in a container do not imply a running init.
- Package dependency preflight, verified postconditions, nonzero failure codes and root-only journals.
- Reversible service state snapshots and a lock against concurrent operations.

### Installation

- Visible `antimon` command in a standard `bin` directory, root/user/custom prefix.
- Commit-resolved downloads, SHA-256 manifest, syntax check, atomic replacement.
- Offline install, explicit `--run`, downloader timeouts, refusal to overwrite unrelated files.
- Uninstaller preserves state and supports explicit removal of the recognized legacy v1 file.

### Breaking changes from v1

- Installing no longer removes agents. `--force` confirms an explicit action only.
- Broad recursive deletion of vendor directories, crash reports and logs was removed.
- Process-name killing, unconditional `SIGKILL` and unverified vendor uninstallers were removed.
- Blanket APT holds and removal of Ubuntu Pro/shared system packages were removed.
- `restore` restores recorded service states; it does not reinstall packages or recover v1 deletions.

### Documentation and validation

- Accurate guest/hypervisor scope, dependency and provisioning consequences.
- Dark/light README assets matching the author's profile; catalog counts generated from source.
- Local SVG report renderer for actual JSON scans.
- Stateful shell tests, live systemd fixture, disposable-container package integration and CI.
