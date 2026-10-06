# Compatibility & validation

[← README](../README.md)

## What “supported” means

There are three separate boundaries:

1. **Shell/runtime:** POSIX sh with standard GNU or BusyBox utilities.
2. **Package database:** APT/dpkg, RPM, pacman, APK or XBPS; Amazon SSM may also be a Snap.
3. **Running init:** systemd, OpenRC, runit or conventional SysV with `update-rc.d`/`chkconfig`.

A supported package database does not imply that a service manager is running.
The tool checks PID 1 as well as capabilities. A minimal container can have a valid
package inventory and still return `complete: false` / exit `2` because it has no init.

Package names and service names vary by distribution and by vendor installation
method. The catalog is a curated set of exact names, not a general-purpose process
scanner. No matches means no matches in the available sources, not proof that a VM
contains no management software.

## Package behavior

| Backend | Inventory | Removal contract |
| :-- | :-- | :-- |
| APT | `dpkg-query`, installed status, multiarch names | Simulate, reject extra removals/installs, remove without autoremove or purge |
| RPM | `rpm -qa` | `rpm -e --test`, then exact `rpm -e`; dependencies enforced, scriptlets run normally |
| pacman | `pacman -Qq` | Print transaction, then `-R`; no recursive/cascade flags |
| APK | `apk info` | Simulate, reject an expanded removal set, then `apk del` |
| XBPS | `xbps-query -l` | `xbps-remove -n`, then non-recursive removal |
| Snap | `snap list` | Exact `amazon-ssm-agent` removal; no `--purge` |

APK normally cleans dependencies that become unused. If that expands the requested
transaction, Anti-Monitoring refuses it. Review that transaction using APK's own
tools, or choose service disabling. The real APK removal fixture marks dependencies
explicit in its disposable container to test the exact-package path as well.

RPM uses the low-level transaction tool deliberately: DNF/YUM/Zypper dependency
cleanup settings cannot expand that exact removal set. RPM config/scriptlet behavior
still applies; this is not a universal configuration backup.

Declarative/source/immutable systems (NixOS, Guix, Gentoo, rpm-ostree) keep their native
package workflow. Recognized services can be controlled, but a rebuild or deployment
may reinstate their declarative configuration. Slackware-style `rc.*`, s6, dinit,
Upstart and vendor-specific installers do not currently have dedicated adapters.

## Service restoration

| Init | Recorded state | Disable operation |
| :-- | :-- | :-- |
| systemd | Startup state, including runtime enable/mask; active/inactive | Disable existing enable links, persistent mask, stop |
| OpenRC | Runlevels and activity | Remove registered runlevels, stop |
| runit | `down` marker presence and activity | Preserve/create marker, supervised down |
| SysV | Enabled runlevels and activity | `update-rc.d disable` or `chkconfig off`, stop |

Systemd aliases are resolved to canonical IDs and deduplicated. Local regular unit
files under `/etc/systemd/system` and linked units are refused when masking/restoring
would require moving or reconstructing user files. Kernel integration drivers are
outside this service catalog.

Restoration is verified and errors remain visible. It is not a VM snapshot:
package versions, applications, network state and effects of re-running a oneshot
provisioning service are not undone. After removing packages, reinstall them before
restoring the relevant snapshot. Avoid concurrent edits by other management tools;
the tool's lock serializes Anti-Monitoring runs, not every system administration tool.

## Validation layers

### Observed verification — 2026-10-06

The following checks were executed on an authorized x86-64 Ubuntu 24.04.4 LTS
test host during the v2 work:

- **69 tests passed under each of dash, Bash and BusyBox ash.**
- **10/10 native container checks passed:** inventory, offline install/uninstall,
  dry-run and actual guest-agent package removal.
- **Live systemd round trip passed:** preview → disable → repeat → restore;
  the uniquely named test unit and its temporary state were cleaned up.
- ShellCheck, Python Ruff checks and generated-file verification passed locally.
- README assets were rendered in Chrome in dark/light themes and at 390px width;
  a local SVG report was also generated from a real server scan.

| Native image | Result | Observed image ID prefix |
| :-- | :-- | :-- |
| `debian:12-slim` | PASS | `7c7b2c966bc9` |
| `debian:13-slim` | PASS | `a29215f6a35e` |
| `ubuntu:22.04` | PASS | `5ec03bb3441e` |
| `ubuntu:24.04` | PASS | `534baea6a22c` |
| `fedora:43` | PASS | `a651ddf48ea2` |
| `rockylinux:9` | PASS | `d7be1c094cc5` |
| `opensuse/leap:16.0` | PASS | `7f3aeccb6a61` |
| `archlinux:base` | PASS | `4e77cf2ea5f4` |
| `alpine:3.22` | PASS | `5291449c3df7` |
| `ghcr.io/void-linux/void-glibc-full:latest` | PASS | `9533af64ff46` |

These are dated observations, not a promise about every derivative, version or
future image. The CI workflow reruns the matrix for the current PR revision and
publishes logs and full image IDs as artifacts.

### Automated contracts

The stateful suite runs under dash, Bash and BusyBox ash in CI. It covers native
backend argument contracts and service-state transitions, plus failed commands,
malformed input, package dependency expansion, snapshot validation, install integrity
and idempotency. CI also smoke-tests the real network installer using the PR's
exact commit SHA and a temporary installation prefix. Contract tests are not a
substitute for native OS tests.

### Native package integration

`tests/run_containers.py` defines pinned distribution-series images for Debian,
Ubuntu, Fedora, Rocky, openSUSE, Arch, Alpine and Void. It performs syntax checks, an actual
package inventory, verified offline installation/uninstallation, and a real QEMU
Guest Agent removal in each disposable container. See the CI job logs for the exact
image ID and result of a particular run; rolling tags and repositories change over time.

### Live init integration

`tests/systemd-integration.sh` verifies a real, uniquely named systemd service:
preview creates no journal, disable stops/masks it, a repeated run preserves the
recovery snapshot, and restore returns its original runtime enable/activity state.
The fixture cleans up its units, links and temporary files.

OpenRC, runit and SysV restoration have stateful contract coverage. They should not
be described as live-VM-tested until those separate environments are tested.

## Platform limits

- Tests in this repository target Linux. Windows, macOS and BSD receive a clear
  unsupported-platform response for system operations.
- The script has no CPU-architecture-specific code. Native package availability,
  init behavior and shell utilities still need verification on each target image.
- Old/EOL distributions, unusual package-manager versions, masked custom aliases,
  custom vendor daemons and shared package bundles may require manual handling.
- HTTPS access to GitHub and trusted CA certificates are needed for network install.
  Offline install from a matching checkout and checksum manifest is supported.
- Guest agents do not define the provider's trust boundary: hypervisor control,
  storage access, memory access and out-of-band consoles remain outside the guest.
