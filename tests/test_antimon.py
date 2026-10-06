"""Behavioral tests using real POSIX shells and isolated system-command doubles.

No service or package command can reach the host. SYSTEM_ROOT is overridden only
in a sourced test harness; the shipped CLI has no alternate-root/test-mode flag.
"""

import hashlib
import json
import os
import shlex
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SHELL = shlex.split(os.environ.get("ANTIMON_TEST_SHELL", "sh"))
MANAGED_TOOLS = (
    "apt-get", "dpkg-query", "dnf", "dnf5", "yum", "rpm", "zypper", "pacman", "apk",
    "xbps-query", "xbps-remove", "snap", "systemctl", "rc-service", "rc-update",
    "rc-status", "sv", "service", "chkconfig", "update-rc.d", "rpm-ostree",
)


def shell_path(path):
    path = Path(path).resolve()
    if os.name == "nt":
        return f"/{path.drive[0].lower()}{path.as_posix()[2:]}"
    return str(path)


class Fixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="antimon-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.sysroot = self.root / "rootfs"
        (self.sysroot / "etc").mkdir(parents=True)
        (self.sysroot / "proc" / "1").mkdir(parents=True)
        self.write(self.sysroot / "proc" / "1" / "comm", "systemd\n")
        self.state_dir = self.root / "state data"
        self.data = {
            "os": "Linux", "uid": 0, "init": "systemd", "packages": {},
            "services": {}, "snaps": [], "calls": [],
        }
        source = (REPO / "antimon.sh").read_text(encoding="utf-8")
        self.assertTrue(source.endswith('main "$@"\n'))
        self.library = self.root / "library.sh"
        self.write(self.library, source.removesuffix('main "$@"\n'))
        self.driver = self.root / "driver.sh"
        self.write(self.driver, f". {shlex.quote(shell_path(self.library))}\n"
                   f"SYSTEM_ROOT={shlex.quote(shell_path(self.sysroot))}\n"
                   f"STATE_DIR={shlex.quote(shell_path(self.state_dir))}\n"
                   "has() { case \"$1\" in " + "|".join(MANAGED_TOOLS)
                   + ') [ -f "$ANTIMON_TEST_BIN/.available-$1" ] ;; '
                   + '*) command -v "$1" >/dev/null 2>&1 ;; esac; }\n'
                   'main "$@"\n')
        self.env = os.environ.copy()
        self.env.update({
            "ANTIMON_FIXTURE": str(self.root),
            "ANTIMON_MOCK": shell_path(REPO / "tests" / "mock_system.py"),
            "ANTIMON_PYTHON": shell_path(sys.executable),
            "ANTIMON_TEST_BIN": shell_path(self.bin),
            "HOME": shell_path(self.root / "home"),
            "LC_ALL": "C", "LANG": "C", "TERM": "dumb",
            "PYTHONUTF8": "1",
        })
        # Git's shell expects a POSIX PATH; native Windows tools receive it via MSYS.
        if os.name == "nt":
            self.env["PATH"] = f"{shell_path(self.bin)}:/usr/bin:/bin"
        else:
            self.env["PATH"] = f"{self.bin}:{os.environ['PATH']}"
        for name in ("uname", "id", "stat", "systemctl"):
            self.stub(name)
        # Even unavailable backends are shadowed, so an accidental call fails in
        # the double rather than ever reaching an installed host utility.
        for name in MANAGED_TOOLS:
            self.stub(name, available=name == "systemctl")
        self.set_manager("apt")

    @staticmethod
    def write(path, content):
        path.write_text(content, encoding="utf-8", newline="\n")
        path.chmod(0o755)

    def stub(self, name, available=True):
        self.write(self.bin / name, '#!/bin/sh\nexec "$ANTIMON_PYTHON" "$ANTIMON_MOCK" '
                   + shlex.quote(name) + ' "$@"\n')
        marker = self.bin / (".available-" + name)
        if available:
            marker.touch()
        else:
            marker.unlink(missing_ok=True)

    def set_manager(self, manager):
        tools = {
            "apt": ("debian", ["apt-get", "dpkg-query"]),
            "dnf": ("fedora", ["dnf", "rpm"]),
            "dnf5": ("fedora", ["dnf5", "rpm"]),
            "yum": ("centos", ["yum", "rpm"]),
            "zypper": ("opensuse-leap", ["zypper", "rpm"]),
            "pacman": ("arch", ["pacman"]),
            "apk": ("alpine", ["apk"]),
            "xbps": ("void", ["xbps-query", "xbps-remove"]),
            "manual": ("nixos", []),
        }
        for name in ("apt-get", "dpkg-query", "dnf", "dnf5", "yum", "rpm", "zypper", "pacman", "apk", "xbps-query", "xbps-remove"):
            (self.bin / (".available-" + name)).unlink(missing_ok=True)
        distro, names = tools[manager]
        self.write(self.sysroot / "etc" / "os-release", f'ID={distro}\nPRETTY_NAME="Fixture {distro}"\n')
        for name in names:
            self.stub(name)

    def set_init(self, init):
        self.data["init"] = init
        process = {"systemd": "systemd", "openrc": "openrc-init", "runit": "runit", "sysv": "init", "none": "sh"}[init]
        self.write(self.sysroot / "proc" / "1" / "comm", process + "\n")
        if init == "openrc":
            for name in ("rc-service", "rc-update", "rc-status"):
                self.stub(name)
        elif init == "runit":
            self.stub("sv")
            (self.sysroot / "var" / "service").mkdir(parents=True, exist_ok=True)
        elif init == "sysv":
            for name in ("service", "chkconfig"):
                self.stub(name)
            (self.sysroot / "etc" / "init.d").mkdir(parents=True, exist_ok=True)

    def add_qemu(self, startup="enabled", active="active", package="qemu-guest-agent"):
        self.data["packages"][package] = "installed"
        self.data["services"]["qemu-guest-agent"] = {"startup": startup, "active": active}
        if self.data["init"] == "runit":
            service = self.sysroot / "var" / "service" / "qemu-guest-agent"
            service.mkdir(parents=True, exist_ok=True)
            if startup == "disabled":
                (service / "down").write_text("keep this annotation", encoding="utf-8")
        elif self.data["init"] == "sysv":
            self.write(self.sysroot / "etc" / "init.d" / "qemu-guest-agent", "#!/bin/sh\n")

    def execute(self, *args, script=None, expected=0):
        (self.root / "system.json").write_text(json.dumps(self.data), encoding="utf-8")
        # Git's launcher prepends its own tools to PATH. Set it inside the shell
        # as well so the fixture always wins, including on Windows.
        launch = ('PATH="$ANTIMON_TEST_BIN:$PATH"; export PATH; '
                  # Standalone ash applets take precedence over PATH. Functions
                  # are needed for identity/stat doubles even in that mode.
                  'uname() { "$ANTIMON_TEST_BIN/uname" "$@"; }; '
                  'id() { "$ANTIMON_TEST_BIN/id" "$@"; }; '
                  'stat() { "$ANTIMON_TEST_BIN/stat" "$@"; }; '
                  'test_script=$1; shift; . "$test_script"')
        command = [*SHELL, "-c", launch, "antimon-test", shell_path(script or self.driver), *args]
        result = subprocess.run(command, env=self.env, cwd=REPO, capture_output=True,
                                text=True, encoding="utf-8", timeout=90, check=False)
        self.data = json.loads((self.root / "system.json").read_text(encoding="utf-8"))
        self.assertEqual(result.returncode, expected, f"{command}\n{result.stdout}\n{result.stderr}\nFixture calls: {self.data['calls']}")
        self.assertNotIn("Unexpected mock invocation", result.stderr)
        if self.data["os"] == "Linux":
            self.assertNotIn("Linux is required", result.stderr)
            self.assertNotIn("This installer supports Linux", result.stderr)
        return result

    def mutations(self):
        return [call for call in self.data["calls"] if call["mutation"]]

    def checkout(self):
        target = self.root / "checkout"
        target.mkdir(exist_ok=True)
        data = (REPO / "antimon.sh").read_bytes()
        (target / "antimon.sh").write_bytes(data)
        (target / "SHA256SUMS").write_text(f"{hashlib.sha256(data).hexdigest()}  antimon.sh\n", encoding="ascii")
        return target


class CliTests(Fixture):
    def test_help_and_version_work_without_linux(self):
        self.data["os"] = "Darwin"
        self.assertIn("scan", self.execute("--help").stdout)
        self.assertEqual(self.execute("--version").stdout.strip(), "2.0.0")
        self.assertIn("cloud-init", self.execute("list").stdout)

    def test_unsupported_os_is_rejected_before_probing(self):
        self.data["os"] = "MINGW64_NT"
        self.assertIn("Linux is required", self.execute("scan", expected=2).stderr)
        self.assertFalse(self.mutations())

    def test_noninteractive_default_is_read_only(self):
        self.add_qemu()
        self.execute()
        self.assertFalse(self.mutations())
        self.assertFalse(self.state_dir.exists())

    def test_force_does_not_select_a_destructive_action(self):
        self.add_qemu()
        self.execute("--force")
        self.assertFalse(self.mutations())

    def test_bad_arguments_are_rejected(self):
        cases = [("--agents",), ("--wat",), ("remove",), ("disable", "remove"),
                 ("scan", "--lang", "xx"), ("scan", "--all", "--agents", "qemu"),
                 ("scan", "--agents", "qemu,"), ("scan", "--agents", "qemu;id"),
                 ("scan", "--agents", "missing"), ("remove", "--all", "--json"),
                 ("scan", "--state-dir", "relative"), ("scan", "--snapshot", "../x")]
        for args in cases:
            with self.subTest(args=args):
                self.execute(*args, expected=2)
        self.assertFalse(self.mutations())

    def test_russian_language(self):
        self.assertIn("управление", self.execute("--lang", "ru", "--help").stdout)

    def test_root_is_only_required_for_writes(self):
        self.add_qemu()
        self.data["uid"] = 1000
        self.execute("scan")
        self.execute("plan", "--agents", "qemu")
        self.execute("disable", "--agents", "qemu", "--yes", expected=2)
        self.assertFalse(self.mutations())
        self.assertFalse(self.state_dir.exists())

    @unittest.skipIf(os.name == "nt", "controlling terminal availability differs in Windows")
    def test_piped_action_does_not_consume_stdin_as_confirmation(self):
        self.add_qemu()
        # execute() receives pipes, but a CI runner may still have /dev/tty.
        if Path("/dev/tty").exists():
            try:
                with open("/dev/tty", "rb"):
                    self.skipTest("interactive test runner has a controlling terminal")
            except OSError:
                pass
        self.execute("disable", "--agents", "qemu", expected=2)
        self.assertFalse(self.mutations())


class InventoryTests(Fixture):
    def test_json_has_no_ansi_and_counts_actual_findings(self):
        self.add_qemu(startup="disabled", active="inactive")
        result = self.execute("scan", "--json")
        report = json.loads(result.stdout)
        self.assertTrue(report["complete"])
        self.assertEqual(report["counts"], {"packages": 1, "snaps": 0, "services": 1, "manual": 0})
        self.assertEqual(len(report["agents"]), 16)
        self.assertNotIn("\x1b", result.stdout)
        self.assertFalse(self.mutations())

    def test_package_matching_is_exact(self):
        self.data["packages"] = {"not-qemu-guest-agent": "installed", "qemu-guest-agent-doc": "installed", "cloud-init": "config-files"}
        report = json.loads(self.execute("scan", "--json").stdout)
        self.assertEqual(report["counts"]["packages"], 0)

    def test_multiarch_name_is_preserved(self):
        self.add_qemu(package="qemu-guest-agent:amd64")
        report = json.loads(self.execute("scan", "--json", "--agents", "qemu").stdout)
        self.assertEqual(report["agents"][0]["findings"][0]["name"], "qemu-guest-agent:amd64")

    def test_agent_filter_and_alias_deduplication(self):
        self.add_qemu()
        self.data["services"]["qemu-ga"] = {"canonical": "qemu-guest-agent"}
        self.data["packages"]["amazon-ssm-agent"] = "installed"
        report = json.loads(self.execute("scan", "--json", "--agents", "qemu").stdout)
        self.assertEqual(len(report["agents"]), 1)
        self.assertEqual(report["counts"]["services"], 1)
        self.assertEqual(report["counts"]["packages"], 1)

    def test_missing_systemd_unit_exit_one_is_not_a_probe_failure(self):
        self.data["missing_unit_exit"] = 1
        self.execute("scan", "--json")

    def test_database_failure_marks_scan_incomplete_and_blocks_actions(self):
        self.add_qemu()
        self.data["inventory_error"] = True
        report = json.loads(self.execute("scan", "--json", expected=2).stdout)
        self.assertFalse(report["complete"])
        self.execute("disable", "--all", "--yes", expected=2)
        self.assertFalse(self.mutations())

    def test_failed_service_probe_is_not_reported_as_absent(self):
        self.add_qemu()
        self.data["probe_error"] = "qemu-guest-agent"
        report = json.loads(self.execute("scan", "--json", expected=2).stdout)
        self.assertGreater(report["probe_errors"], 0)

    def test_snap_ssm_is_found(self):
        self.stub("snap")
        self.data["snaps"] = ["amazon-ssm-agent"]
        report = json.loads(self.execute("scan", "--json").stdout)
        self.assertEqual(report["counts"]["snaps"], 1)

    def test_dead_snapd_is_reported(self):
        self.stub("snap")
        self.data["snap_error"] = True
        report = json.loads(self.execute("scan", "--json", expected=2).stdout)
        self.assertFalse(report["complete"])

    def test_real_virtualbox_glob_reports_vendor_install(self):
        (self.sysroot / "opt" / "VBoxGuestAdditions-7.2.0").mkdir(parents=True)
        report = json.loads(self.execute("scan", "--json").stdout)
        self.assertEqual(report["counts"]["manual"], 1)
        self.execute("remove", "--agents", "virtualbox", "--yes", expected=2)
        self.assertFalse(self.mutations())

    def test_container_without_init_is_explicitly_partial(self):
        self.set_init("none")
        self.data["packages"]["qemu-guest-agent"] = "installed"
        report = json.loads(self.execute("scan", "--json", expected=2).stdout)
        self.assertEqual(report["system"]["init_system"], "none")
        self.execute("disable", "--all", "--yes", expected=2)
        self.data["packages"] = {}
        self.execute("disable", "--all", "--yes", expected=2)
        self.assertFalse(self.mutations())

    def test_json_escapes_untrusted_display_text(self):
        self.write(self.sysroot / "etc" / "os-release", 'ID=debian\nPRETTY_NAME=Host "quoted" \\ path\tvalue\n')
        report = json.loads(self.execute("scan", "--json").stdout)
        self.assertIn('"quoted"', report["system"]["distribution"])
        self.assertIn("\\ path\tvalue", report["system"]["distribution"])


class ActionTests(Fixture):
    def test_preview_writes_nothing(self):
        self.add_qemu()
        self.execute("remove", "--agents", "qemu", "--dry-run")
        self.assertFalse(self.mutations())
        self.assertFalse(self.state_dir.exists())

    def test_inactive_but_enabled_service_is_disabled(self):
        self.add_qemu(active="inactive")
        self.execute("disable", "--agents", "qemu", "--yes")
        self.assertEqual(self.data["services"]["qemu-guest-agent"]["startup"], "masked")
        self.assertTrue(list(self.state_dir.glob("*/inventory")))

    def test_disable_is_idempotent_and_restore_is_exact(self):
        self.add_qemu()
        self.execute("disable", "--agents", "qemu", "--yes")
        first_snapshot = next(self.state_dir.glob("20*"))
        self.execute("disable", "--agents", "qemu", "--yes")
        self.assertEqual(len(list(self.state_dir.glob("20*"))), 1)
        self.execute("restore", "--snapshot", first_snapshot.name, "--yes")
        service = self.data["services"]["qemu-guest-agent"]
        self.assertEqual((service["startup"], service["active"]), ("enabled", "active"))

    def test_restore_does_not_start_previously_stopped_service(self):
        self.add_qemu(startup="disabled", active="inactive")
        self.execute("disable", "--agents", "qemu", "--yes")
        self.execute("restore", "--yes")
        self.assertEqual(self.data["services"]["qemu-guest-agent"]["active"], "inactive")

    def test_runtime_enable_state_round_trips(self):
        self.add_qemu(startup="enabled-runtime")
        self.execute("disable", "--agents", "qemu", "--yes")
        self.execute("restore", "--yes")
        self.assertEqual(self.data["services"]["qemu-guest-agent"]["startup"], "enabled-runtime")

    def test_command_failure_propagates_and_preserves_journal(self):
        self.add_qemu()
        self.data["fail"] = "systemctl:mask"
        self.execute("disable", "--agents", "qemu", "--yes", expected=1)
        log = next(self.state_dir.glob("*/output.log")).read_text(encoding="utf-8")
        self.assertIn("simulated operation failure", log)
        self.assertFalse((self.state_dir / ".lock").exists())

    def test_false_success_from_service_command_is_detected(self):
        self.add_qemu()
        self.data["lie_about_service"] = True
        self.execute("disable", "--agents", "qemu", "--yes", expected=1)

    def test_local_systemd_unit_is_not_overwritten(self):
        self.add_qemu()
        directory = self.sysroot / "etc" / "systemd" / "system"
        directory.mkdir(parents=True)
        unit = directory / "qemu-guest-agent.service"
        unit.write_text("local unit", encoding="ascii")
        self.execute("disable", "--all", "--yes", expected=2)
        self.assertEqual(unit.read_text(encoding="ascii"), "local unit")
        self.assertFalse(self.mutations())

    def test_unrestorable_linked_unit_is_rejected(self):
        self.add_qemu(startup="linked")
        self.execute("disable", "--agents", "qemu", "--yes", expected=2)
        self.assertFalse(self.mutations())

    def test_no_packages_and_no_services_is_noop(self):
        self.execute("disable", "--all", "--yes")
        self.assertFalse(self.state_dir.exists())

    def test_unmanaged_service_requires_disable_instead_of_remove(self):
        self.add_qemu()
        self.data["packages"] = {}
        self.execute("remove", "--agents", "qemu", "--yes", expected=2)
        self.assertFalse(self.mutations())

    def test_apt_reverse_dependency_removal_is_blocked(self):
        self.add_qemu()
        self.data["extra_removals"] = ["important-server"]
        self.execute("remove", "--all", "--yes", expected=2)
        self.assertFalse(self.mutations())

    def test_apt_extra_install_is_blocked(self):
        self.add_qemu()
        self.data["extra_install"] = True
        self.execute("remove", "--all", "--yes", expected=2)
        self.assertFalse(self.mutations())

    def test_apk_dependency_cleanup_is_blocked(self):
        self.set_manager("apk")
        self.add_qemu()
        self.data["extra_removals"] = ["glib"]
        self.execute("remove", "--all", "--yes", expected=2)
        self.assertFalse(self.mutations())

    def test_unrecognized_simulation_output_fails_closed(self):
        self.add_qemu()
        self.data["empty_simulation"] = True
        self.execute("remove", "--all", "--yes", expected=2)
        self.assertFalse(self.mutations())

    def test_package_removal_failure_is_not_success(self):
        self.add_qemu()
        self.data["fail"] = "apt-get:remove"
        self.execute("remove", "--all", "--yes", expected=1)
        self.assertIn("qemu-guest-agent", self.data["packages"])

    def test_false_success_from_package_manager_is_detected(self):
        self.add_qemu()
        self.data["lie_about_remove"] = True
        self.execute("remove", "--all", "--yes", expected=1)

    def test_remove_multiarch_exactly(self):
        self.add_qemu(package="qemu-guest-agent:amd64")
        self.execute("remove", "--agents", "qemu", "--yes")
        self.assertFalse(self.data["packages"])

    def test_snap_removal(self):
        self.stub("snap")
        self.data["snaps"] = ["amazon-ssm-agent", "other-snap"]
        self.execute("remove", "--agents", "aws-ssm", "--yes")
        self.assertEqual(self.data["snaps"], ["other-snap"])

    def test_remove_snapshot_requires_reinstallation_before_restore(self):
        self.add_qemu()
        self.execute("remove", "--agents", "qemu", "--yes")
        snapshot = next(self.state_dir.glob("20*"))
        before = len(self.mutations())
        self.execute("restore", "--snapshot", snapshot.name, "--yes", expected=2)
        self.assertEqual(len(self.mutations()), before)

    def test_lock_prevents_concurrent_mutation(self):
        self.add_qemu()
        (self.state_dir / ".lock").mkdir(parents=True)
        self.execute("disable", "--all", "--yes", expected=2)
        self.assertFalse(self.mutations())

    def test_untrusted_state_directory_is_rejected(self):
        self.add_qemu()
        self.state_dir.mkdir()
        self.data["unsafe_state_directory"] = True
        self.execute("disable", "--all", "--yes", expected=2)
        self.assertFalse(self.mutations())

    def test_snapshot_path_traversal_is_rejected(self):
        self.execute("restore", "--snapshot", "../../etc", "--yes", expected=2)
        self.assertFalse(self.mutations())

    def test_snapshot_cannot_execute_shell_code(self):
        snapshot = self.state_dir / "20260101.fixture"
        snapshot.mkdir(parents=True)
        self.write(snapshot / "metadata", "version=1\noperation=disable\ninit=systemd\n")
        self.write(snapshot / "inventory", "service|qemu|$(touch hacked)|enabled|active\n")
        self.execute("restore", "--snapshot", snapshot.name, "--yes", expected=2)
        self.assertFalse(self.mutations())
        self.assertFalse((REPO / "hacked").exists())


class BackendTests(Fixture):
    def test_package_manager_matrix(self):
        for manager in ("apt", "dnf", "dnf5", "yum", "zypper", "pacman", "apk", "xbps"):
            with self.subTest(manager=manager):
                self.set_manager(manager)
                self.data["packages"] = {"qemu-guest-agent": "installed"}
                self.data["services"] = {}
                report = json.loads(self.execute("scan", "--json").stdout)
                self.assertEqual(report["system"]["package_manager"], manager)
                self.assertEqual(report["counts"]["packages"], 1)
                self.execute("remove", "--agents", "qemu", "--yes")
                self.assertFalse(self.data["packages"])

    def test_rpm_dependency_failure_is_detected_before_stopping(self):
        self.set_manager("dnf")
        self.add_qemu()
        self.data["dependency_error"] = True
        self.execute("remove", "--all", "--yes", expected=2)
        self.assertFalse(self.mutations())

    def test_openrc_runlevels_and_activity_round_trip(self):
        self.set_init("openrc")
        self.add_qemu(startup="boot default ")
        self.execute("disable", "--agents", "qemu", "--yes")
        self.assertEqual(self.data["services"]["qemu-guest-agent"]["startup"], "-")
        self.execute("restore", "--yes")
        self.assertEqual(self.data["services"]["qemu-guest-agent"]["startup"], "boot default ")
        self.assertEqual(self.data["services"]["qemu-guest-agent"]["active"], "active")

    def test_runit_down_marker_and_activity_round_trip(self):
        self.set_init("runit")
        self.add_qemu()
        marker = self.sysroot / "var" / "service" / "qemu-guest-agent" / "down"
        self.execute("disable", "--agents", "qemu", "--yes")
        self.assertTrue(marker.exists())
        self.execute("restore", "--yes")
        self.assertFalse(marker.exists())
        self.assertEqual(self.data["services"]["qemu-guest-agent"]["active"], "active")

    def test_runit_existing_down_marker_is_preserved(self):
        self.set_init("runit")
        self.add_qemu(startup="disabled", active="active")
        marker = self.sysroot / "var" / "service" / "qemu-guest-agent" / "down"
        self.execute("disable", "--agents", "qemu", "--yes")
        self.execute("restore", "--yes")
        self.assertEqual(marker.read_text(encoding="utf-8"), "keep this annotation")

    def test_sysv_runlevels_and_activity_round_trip(self):
        self.set_init("sysv")
        self.add_qemu(startup="2 3 5 ")
        self.execute("disable", "--agents", "qemu", "--yes")
        self.execute("restore", "--yes")
        self.assertEqual(self.data["services"]["qemu-guest-agent"]["startup"], "2 3 5 ")

    @unittest.skipIf(os.name == "nt", "native symlink fixture is exercised on Linux")
    def test_sysv_update_rc_preserves_runlevels_and_priorities(self):
        self.set_init("sysv")
        self.stub("update-rc.d")
        self.add_qemu(startup="2 3 ")
        etc = self.sysroot / "etc"
        for level, priority in ((2, 12), (3, 73)):
            directory = etc / f"rc{level}.d"
            directory.mkdir()
            (directory / f"S{priority:02}qemu-guest-agent").symlink_to("../init.d/qemu-guest-agent")
        self.execute("disable", "--agents", "qemu", "--yes")
        self.assertTrue((etc / "rc2.d" / "K88qemu-guest-agent").is_symlink())
        self.assertTrue((etc / "rc3.d" / "K27qemu-guest-agent").is_symlink())
        self.execute("restore", "--yes")
        self.assertTrue((etc / "rc2.d" / "S12qemu-guest-agent").is_symlink())
        self.assertTrue((etc / "rc3.d" / "S73qemu-guest-agent").is_symlink())
        self.assertEqual(self.data["services"]["qemu-guest-agent"]["startup"], "2 3 ")

    def test_immutable_system_allows_services_but_not_package_removal(self):
        self.set_manager("manual")
        self.add_qemu()
        self.execute("remove", "--all", "--yes", expected=2)
        self.assertFalse(self.mutations())
        self.execute("disable", "--all", "--yes")


class InstallerTests(Fixture):
    def test_offline_install_and_uninstall_with_spaces(self):
        source = self.checkout()
        prefix = self.root / "my tools"
        self.execute("--source", shell_path(source), "--prefix", shell_path(prefix), script=REPO / "install.sh")
        installed = prefix / "bin" / "antimon"
        self.assertEqual(installed.read_bytes(), (REPO / "antimon.sh").read_bytes())
        self.execute("--version", script=installed)
        self.execute("--prefix", shell_path(prefix), "--dry-run", script=REPO / "uninstall.sh")
        self.assertTrue(installed.exists())
        self.execute("--prefix", shell_path(prefix), script=REPO / "uninstall.sh")
        self.assertFalse(installed.exists())
        self.assertFalse(self.mutations())

    def test_bad_checksum_preserves_previous_installation(self):
        source = self.checkout()
        prefix = self.root / "prefix"
        args = ("--source", shell_path(source), "--prefix", shell_path(prefix))
        self.execute(*args, script=REPO / "install.sh")
        installed = prefix / "bin" / "antimon"
        before = installed.read_bytes()
        (source / "antimon.sh").write_text("echo corrupted\n", encoding="ascii")
        self.execute(*args, script=REPO / "install.sh", expected=1)
        self.assertEqual(installed.read_bytes(), before)
        self.assertFalse(list((prefix / "bin").glob(".antimon.*")))

    def test_unrelated_command_is_never_overwritten_or_uninstalled(self):
        source = self.checkout()
        prefix = self.root / "prefix"
        installed = prefix / "bin" / "antimon"
        installed.parent.mkdir(parents=True)
        installed.write_text("important user file", encoding="ascii")
        self.execute("--source", shell_path(source), "--prefix", shell_path(prefix), script=REPO / "install.sh", expected=1)
        self.execute("--prefix", shell_path(prefix), script=REPO / "uninstall.sh", expected=1)
        self.assertEqual(installed.read_text(encoding="ascii"), "important user file")

    def test_legacy_force_flag_only_installs(self):
        self.add_qemu()
        source = self.checkout()
        self.execute("--source", shell_path(source), "--prefix", shell_path(self.root / "prefix"),
                     "--silent", "--force", script=REPO / "install.sh")
        self.assertFalse(self.mutations())

    def test_download_resolves_and_uses_one_commit(self):
        self.stub("curl")
        self.data["download_source"] = str(self.checkout())
        self.execute("--prefix", shell_path(self.root / "prefix"), script=REPO / "install.sh")
        calls = [call for call in self.data["calls"] if call["tool"] == "curl"]
        self.assertEqual(len(calls), 3)
        for call in calls[1:]:
            url = next(arg for arg in call["args"] if arg.startswith("https://"))
            self.assertIn("/" + "a" * 40 + "/", url)
        self.assertFalse(self.mutations())

    def test_download_failure_does_not_install(self):
        self.stub("curl")
        self.data["download_error"] = True
        prefix = self.root / "prefix"
        self.execute("--prefix", shell_path(prefix), script=REPO / "install.sh", expected=1)
        self.assertFalse((prefix / "bin" / "antimon").exists())

    def test_no_bash_required_by_scripts(self):
        for name in ("antimon.sh", "install.sh", "uninstall.sh"):
            self.assertTrue((REPO / name).read_text(encoding="utf-8").startswith("#!/bin/sh\n"))


if __name__ == "__main__":
    unittest.main()
