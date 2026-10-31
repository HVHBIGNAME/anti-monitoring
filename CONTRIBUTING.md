# Contributing

## Local checks

Development tools: Python 3.10+, ShellCheck, and the shells you want to verify.
Runtime users do not need Python or ShellCheck.

```sh
shellcheck -s sh antimon.sh tests/*.sh
ANTIMON_TEST_SHELL=dash python3 -m unittest discover -s tests -v
ANTIMON_TEST_SHELL=bash python3 -m unittest discover -s tests -v
ANTIMON_TEST_SHELL='busybox ash' python3 -m unittest discover -s tests -v
python3 tools/checksums.py --check
python3 tools/generate_assets.py --check
```

After changing `antimon.sh`, regenerate `SHA256SUMS`:

```sh
python3 tools/checksums.py
```

After changing catalog groups or SVG templates:

```sh
python3 tools/generate_assets.py
```

Use LF line endings. Generated assets and the checksum manifest belong in the same
change as their sources. Python helpers use only the standard library.

## Testing model

`tests/test_antimon.py` executes the actual shell functions through a sourced test
harness. It replaces the filesystem root and command-discovery boundary only in
that harness. Stateful command doubles record requests and emulate postconditions.
Sensitive host commands are shadowed even when their backend is unavailable.

Tests cover failed probes, exact package matching, dependency expansion, service
state round trips, false-success commands, idempotency, snapshots, installation
integrity and unrelated-file preservation. Add a regression case for a bug fix.

Real package transactions run in **disposable containers**:

```sh
python3 tests/run_containers.py --only debian12
python3 tests/run_containers.py --jobs 2 --cleanup-images
```

These commands download distribution images and install/remove QEMU Guest Agent
inside them. The repository mount is read-only. Logs and image identities go to
`reports/containers/`; these generated reports are ignored by Git.

To test a real systemd service on an authorized Linux test host:

```sh
sudo sh tests/systemd-integration.sh
```

The fixture creates a uniquely named sleep service, tests preview/disable/repeat/
restore, then removes that service and its temporary state. Real agents are not
selected by this fixture. Other init adapters currently have stateful contract tests.

## Adding support

1. Add **specific** package and service names to `catalog()` in `antimon.sh`.
   Shared bundles, kernels and network packages are not agent removal targets.
2. Describe the component's actual responsibilities, especially provisioning effects.
3. Add exact-match and state-transition tests. Failed discovery must not become
   a successful “not installed” result.
4. Update `tools/generate_assets.py` grouping, compatibility documentation and hashes.
5. For a new backend, test the native package format in a disposable container and
   label contract-tested versus live-tested support accurately.

Snapshots are **data**, never sourced shell code. Keep external arguments quoted;
lists expanded as words must originate from the validated catalog or validated
runlevels. Keep errors visible and verify changes before claiming success.
