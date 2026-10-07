"""Strict stateful command doubles. All changes stay in a TemporaryDirectory."""

import json
import os
import sys
from pathlib import Path

sys.stdout.reconfigure(newline="\n")
sys.stderr.reconfigure(newline="\n")
ROOT = Path(os.environ["ANTIMON_FIXTURE"])
STATE_FILE = ROOT / "system.json"
STATE = json.loads(STATE_FILE.read_text(encoding="utf-8"))
TOOL, *ARGS = sys.argv[1:]


def finish(code=0, output="", mutation=False):
    STATE.setdefault("calls", []).append({"tool": TOOL, "args": ARGS, "mutation": mutation})
    STATE_FILE.write_text(json.dumps(STATE), encoding="utf-8")
    if output:
        print(output, file=sys.stderr if code else sys.stdout)
    raise SystemExit(code)


def fail_if_requested(operation):
    if STATE.get("fail") == f"{TOOL}:{operation}":
        finish(1, "simulated operation failure", mutation=True)


def targets():
    return ARGS[ARGS.index("--") + 1 :] if "--" in ARGS else [arg for arg in ARGS[1:] if not arg.startswith("-")]


def remove_packages(names, simulate=False):
    if STATE.get("dependency_error"):
        finish(1, "another package requires this agent")
    fail_if_requested("remove")
    if not simulate and not STATE.get("lie_about_remove"):
        for name in names:
            STATE["packages"].pop(name, None)
    finish(mutation=not simulate)


if TOOL == "uname":
    finish(output=STATE.get("os", "Linux"))
elif TOOL == "id":
    finish(output=str(STATE.get("uid", 0)))
elif TOOL == "stat":
    finish(output="777:1000" if STATE.get("unsafe_state_directory") else "700:0")
elif TOOL == "dpkg-query":
    if STATE.get("inventory_error"):
        finish(1, "broken package database")
    finish(output="\n".join(f"{name}|{status}" for name, status in STATE["packages"].items()))
elif TOOL == "rpm":
    if ARGS == ["--version"]:
        finish(output="RPM version 4.19.1")
    if "-qa" in ARGS:
        if STATE.get("inventory_error"):
            finish(1, "broken RPM database")
        finish(output="\n".join(STATE["packages"]))
    if "-e" in ARGS:
        remove_packages(targets(), "--test" in ARGS)
elif TOOL == "apt-get":
    if "remove" in ARGS:
        if "-s" in ARGS:
            if STATE.get("dependency_error"):
                finish(1, "dependency conflict")
            planned = targets() + STATE.get("extra_removals", [])
            if STATE.get("empty_simulation"):
                planned = []
            lines = [f"Remv {name.split(':')[0]} [1.0]" for name in planned]
            if STATE.get("extra_install"):
                lines.append("Inst unrelated-package [1.0]")
            finish(output="\n".join(lines))
        remove_packages(targets())
elif TOOL == "pacman":
    if "-Qq" in ARGS:
        finish(output="\n".join(STATE["packages"]))
    if "-Rp" in ARGS:
        if STATE.get("dependency_error"):
            finish(1, "could not satisfy dependencies")
        finish(output="\n".join(targets()))
    if "-R" in ARGS:
        remove_packages(targets())
elif TOOL == "apk":
    if ARGS == ["info"]:
        finish(output="\n".join(STATE["packages"]))
    if ARGS[0] == "del":
        if "--simulate" in ARGS:
            if STATE.get("dependency_error"):
                finish(1, "unsatisfied dependencies")
            planned = targets() + STATE.get("extra_removals", [])
            if STATE.get("empty_simulation"):
                planned = []
            finish(output="\n".join(f"({index}/{len(planned)}) Purging {name} (1.0-r0)" for index, name in enumerate(planned, 1)))
        remove_packages(targets())
elif TOOL == "xbps-query":
    finish(output="\n".join(f"ii {name}-1.0_1 fixture package" for name in STATE["packages"]))
elif TOOL == "xbps-remove":
    remove_packages(targets(), "-n" in ARGS)
elif TOOL == "snap":
    if ARGS == ["list"]:
        if STATE.get("snap_error"):
            finish(1, "cannot communicate with snapd")
        finish(output="Name Version Rev Tracking Publisher Notes\n" + "\n".join(f"{name} 1.0 1 latest/stable fixture -" for name in STATE.get("snaps", [])))
    if ARGS[0] == "remove":
        fail_if_requested("remove")
        STATE["snaps"] = [name for name in STATE.get("snaps", []) if name not in ARGS[1:]]
        finish(mutation=True)
elif TOOL == "systemctl":
    if ARGS == ["daemon-reload"]:
        fail_if_requested("daemon-reload")
        for path in (ROOT / "rootfs" / "etc" / "systemd" / "system").glob("*.service"):
            if "# anti-monitoring: managed boot entry." in path.read_text(encoding="utf-8"):
                STATE["services"].setdefault(path.stem, {"startup": "disabled", "active": "inactive"})
        finish(mutation=True)
    if ARGS[0] == "is-enabled":
        service = STATE["services"].get(ARGS[-1].removesuffix(".service"), {})
        finish(0 if service.get("startup") in {"enabled", "enabled-runtime"} else 1)
    if "--property=Version" in ARGS:
        finish(0 if STATE["init"] == "systemd" else 1, "Version=256" if STATE["init"] == "systemd" else "no system bus")
    if ARGS[0] in {"list-unit-files", "list-units"}:
        finish(output="\n".join(f"{name}.service enabled" for name in STATE["services"]))
    verbs = {"show", "stop", "start", "mask", "unmask", "disable", "enable"}
    verb = next((arg for arg in ARGS if arg in verbs), None)
    name = ARGS[-1].removesuffix(".service")
    service = STATE["services"].get(name)
    if verb == "show":
        if STATE.get("probe_error") == name:
            finish(1, "bus access denied")
        if service is None:
            # systemctl may return 1 for missing units, but still supplies fields.
            print(f"Id={name}.service\nLoadState=not-found\nUnitFileState=\nActiveState=inactive")
            finish(STATE.get("missing_unit_exit", 0))
        canonical = service.get("canonical", name)
        service = STATE["services"][canonical]
        print(f"Id={canonical}.service\nLoadState={service.get('load', 'loaded')}\nUnitFileState={service['startup']}\nActiveState={service['active']}")
        finish()
    if service is None:
        finish(4, f"unknown service: {name}")
    fail_if_requested(verb)
    if STATE.get("lie_about_service"):
        finish(mutation=True)
    if verb in {"mask", "unmask"}:
        if verb == "mask":
            if service["startup"] not in {"masked", "masked-runtime"}:
                service["before_mask"] = service["startup"]
            service["startup"] = "masked-runtime" if "--runtime" in ARGS else "masked"
        elif service["startup"] in {"masked", "masked-runtime"}:
            service["startup"] = service.get("before_mask", "disabled")
    elif verb == "disable":
        service["startup"] = "disabled"
    elif verb == "enable":
        service["startup"] = "enabled-runtime" if "--runtime" in ARGS else "enabled"
    elif verb in {"stop", "start"}:
        service["active"] = "active" if verb == "start" else "inactive"
    else:
        finish(98, "unsupported systemctl invocation")
    finish(mutation=True)
elif TOOL == "rc-status":
    finish(0 if STATE["init"] == "openrc" else 1, "default")
elif TOOL == "rc-service":
    if ARGS == ["--list"]:
        finish(output="\n".join(STATE["services"]))
    if ARGS[0] == "--exists":
        finish(0 if ARGS[1] in STATE["services"] else 1)
    name, verb = ARGS
    service = STATE["services"].get(name)
    if not service:
        finish(1)
    if verb == "status":
        finish(0 if service["active"] == "active" else 3)
    fail_if_requested(verb)
    service["active"] = "active" if verb == "start" else "inactive"
    finish(mutation=True)
elif TOOL == "rc-update":
    if ARGS[0] == "show":
        finish(output="\n".join(f"{name} | {service['startup'].replace('-', '')}" for name, service in STATE["services"].items()))
    verb, name, level = ARGS
    fail_if_requested(verb)
    service = STATE["services"].setdefault(name, {"startup": "-", "active": "inactive"})
    levels = [] if service["startup"] == "-" else service["startup"].split()
    if verb == "add" and level not in levels:
        levels.append(level)
    elif verb == "del":
        levels.remove(level)
    service["startup"] = " ".join(sorted(levels)) + " " if levels else "-"
    finish(mutation=True)
elif TOOL == "sv":
    name = Path(ARGS[-1]).name
    service = STATE["services"].get(name)
    if not service and (ROOT / "rootfs" / "etc" / "sv" / name / "run").is_file():
        service = {"startup": "enabled", "active": "inactive"}
        STATE["services"][name] = service
    if not service:
        finish(1, "unknown service")
    verb = ARGS[0] if ARGS[0] != "-w" else ARGS[2]
    if verb == "status":
        finish(output=("run: " if service["active"] == "active" else "down: ") + name)
    fail_if_requested(verb)
    service["active"] = "active" if verb == "up" else "inactive"
    finish(mutation=True)
elif TOOL == "service":
    name, verb = ARGS
    service = STATE["services"].get(name)
    if service is None:
        finish(1)
    if verb == "status":
        finish(0 if service["active"] == "active" else 3)
    fail_if_requested(verb)
    service["active"] = "active" if verb == "start" else "inactive"
    finish(mutation=True)
elif TOOL == "chkconfig":
    if ARGS[0] == "--add":
        STATE["services"].setdefault(ARGS[1], {"startup": "-", "active": "inactive"})
        finish(mutation=True)
    if ARGS[0] == "--del":
        STATE["services"][ARGS[1]]["startup"] = "-"
        finish(mutation=True)
    if ARGS[0] == "--list":
        service = STATE["services"][ARGS[1]]
        levels = service["startup"].split()
        finish(output=ARGS[1] + " " + " ".join(f"{i}:{'on' if str(i) in levels else 'off'}" for i in range(7)))
    if ARGS[0] == "--level":
        levels, name, action = ARGS[1:]
        STATE["services"][name]["startup"] = " ".join(levels) + " " if action == "on" else "-"
    else:
        name, action = ARGS
        STATE["services"][name]["startup"] = "-" if action == "off" else "2 3 4 5 "
    finish(mutation=True)
elif TOOL == "update-rc.d":
    if ARGS[0] == "-f":
        name, action = ARGS[1:]
        if action != "remove":
            finish(99, "unsupported update-rc.d operation")
        etc = ROOT / "rootfs" / "etc"
        for link in etc.glob(f"rc?.d/[SK][0-9][0-9]{name}"):
            link.unlink()
        STATE["services"][name]["startup"] = "-"
        finish(mutation=True)
    name, action, *levels = ARGS
    if action == "defaults":
        for level in (2, 3, 4, 5):
            directory = ROOT / "rootfs" / "etc" / f"rc{level}.d"
            directory.mkdir(exist_ok=True)
            link = directory / f"S99{name}"
            if not link.is_symlink():
                link.symlink_to(f"../init.d/{name}")
        STATE["services"].setdefault(name, {"startup": "2 3 4 5 ", "active": "inactive"})
        finish(mutation=True)
    if action not in {"disable", "enable"}:
        finish(99, "unsupported update-rc.d operation")
    fail_if_requested(action)
    levels = levels or ["S", "2", "3", "4", "5"]
    etc = ROOT / "rootfs" / "etc"
    old_prefix, new_prefix = ("S", "K") if action == "disable" else ("K", "S")
    for level in levels:
        directory = etc / f"rc{level}.d"
        for link in directory.glob(f"{old_prefix}[0-9][0-9]{name}"):
            priority = 100 - int(link.name[1:3])
            link.rename(directory / f"{new_prefix}{priority:02}{name}")
    enabled = [directory.name[2] for directory in sorted(etc.glob("rc?.d"))
               if any(directory.glob(f"S[0-9][0-9]{name}"))]
    STATE["services"][name]["startup"] = " ".join(enabled) + " " if enabled else "-"
    finish(mutation=True)
elif TOOL in {"curl", "wget"}:
    if STATE.get("download_error"):
        finish(22, "HTTP download failed")
    output_flag = "-o" if TOOL == "curl" else "-O"
    output = Path(ARGS[ARGS.index(output_flag) + 1])
    url = next(arg for arg in ARGS if arg.startswith("https://"))
    if "/commits/" in url:
        output.write_text(json.dumps({"sha": "a" * 40}, indent=2), encoding="utf-8")
    else:
        source = Path(STATE["download_source"]) / url.rsplit("/", 1)[1]
        output.write_bytes(source.read_bytes())
    finish()

finish(99, f"Unexpected mock invocation: {TOOL} {ARGS!r}")
