#!/usr/bin/env python3
"""Run real scan/install/remove checks inside disposable Linux containers."""

import argparse
import json
import os
import subprocess
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IMAGES = {
    "debian12": ("debian:12-slim", "apt-get update && apt-get install -y --no-install-recommends qemu-guest-agent ca-certificates"),
    "debian13": ("debian:13-slim", "apt-get update && apt-get install -y --no-install-recommends qemu-guest-agent ca-certificates"),
    "ubuntu22": ("ubuntu:22.04", "apt-get update && apt-get install -y --no-install-recommends qemu-guest-agent ca-certificates"),
    "ubuntu24": ("ubuntu:24.04", "apt-get update && apt-get install -y --no-install-recommends qemu-guest-agent ca-certificates"),
    "fedora": ("fedora:43", "dnf install -y qemu-guest-agent"),
    "rocky": ("rockylinux:9", "dnf install -y qemu-guest-agent"),
    "opensuse": ("opensuse/leap:16.0", "zypper --non-interactive install qemu-guest-agent"),
    "arch": ("archlinux:base", "pacman -Syu --noconfirm qemu-guest-agent"),
    # Mark dependencies explicitly in this disposable image so apk's removal
    # set is exactly the agent. Extra dependency removals are separately tested.
    "alpine": ("alpine:3.22", "apk add --no-cache qemu-guest-agent && apk add --no-cache $(apk info)"),
    "void": ("ghcr.io/void-linux/void-glibc-full:latest", "xbps-install -Sy xbps && xbps-install -Sy qemu-ga"),
}


def docker(*args, **kwargs):
    return subprocess.run(["docker", *args], text=True, encoding="utf-8", check=False, **kwargs)


def check_image(name, logs, cleanup_images):
    image, setup = IMAGES[name]
    existed = docker("image", "inspect", image, capture_output=True).returncode == 0
    container = f"antimon-check-{os.getpid()}-{uuid.uuid4().hex[:8]}-{name}"
    log = logs / f"{name}.log"
    command = f"{setup} && sh tests/container-smoke.sh && sh tests/package-integration.sh"
    print(f"[{name}] testing {image}", flush=True)
    result = {"image": image, "passed": False, "log": log.name}
    try:
        with log.open("w", encoding="utf-8") as output:
            run = docker("run", "--rm", "--name", container, "-e", "ANTIMON_DISPOSABLE_TEST=1",
                         "-e", "DEBIAN_FRONTEND=noninteractive", "-v", f"{ROOT}:/project:ro",
                         "-w", "/project", image, "sh", "-c", command,
                         stdout=output, stderr=subprocess.STDOUT, timeout=900)
        result["passed"] = run.returncode == 0
        result["exit_code"] = run.returncode
        identity = docker("image", "inspect", "--format", "{{.Id}}", image, capture_output=True)
        result["image_id"] = identity.stdout.strip()
        if not result["passed"]:
            print(log.read_text(encoding="utf-8"), flush=True)
    except subprocess.TimeoutExpired:
        result["error"] = "container test exceeded 15 minutes"
    finally:
        # This name was generated for this test only; --rm normally removed it.
        docker("rm", "-f", container, capture_output=True)
        if cleanup_images and not existed:
            cleaned = docker("image", "rm", image, capture_output=True)
            result["image_cleanup"] = cleaned.returncode == 0
            if cleaned.returncode:
                print(f"[{name}] image retained: {cleaned.stderr.strip()}", flush=True)
    print(f"[{name}] {'PASS' if result['passed'] else 'FAIL'}", flush=True)
    return name, result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", choices=IMAGES)
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--cleanup-images", action="store_true", help="Remove images fetched by this run if unused")
    args = parser.parse_args()
    if not 1 <= args.jobs <= 4:
        parser.error("--jobs must be 1–4")
    logs = ROOT / "reports" / "containers"
    logs.mkdir(parents=True, exist_ok=True)
    selected = [args.only] if args.only else list(IMAGES)
    results = {}
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        jobs = [pool.submit(check_image, name, logs, args.cleanup_images) for name in selected]
        for job in as_completed(jobs):
            name, result = job.result()
            results[name] = result
    summary = {"tested_at": datetime.now(timezone.utc).isoformat(), "results": results}
    summary_name = f"results-{args.only}.json" if args.only else "results.json"
    (logs / summary_name).write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    passed = sum(result["passed"] for result in results.values())
    print(f"Containers passed: {passed}/{len(results)}")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
