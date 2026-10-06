#!/usr/bin/env python3
"""Generate or verify the installer's reproducible SHA-256 manifest."""

import argparse
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ("antimon.sh", "install.sh", "uninstall.sh")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    lines = []
    for name in SCRIPTS:
        data = (ROOT / name).read_bytes()
        if b"\r" in data:
            raise SystemExit(f"{name}: use LF line endings before hashing")
        lines.append(f"{hashlib.sha256(data).hexdigest()}  {name}\n")
    expected = "".join(lines)
    manifest = ROOT / "SHA256SUMS"
    if args.check:
        if not manifest.exists() or manifest.read_text(encoding="ascii") != expected:
            raise SystemExit("SHA256SUMS is stale. Run: python3 tools/checksums.py")
        print("SHA256SUMS: OK")
    else:
        manifest.write_text(expected, encoding="ascii", newline="\n")
        print("Updated SHA256SUMS")


if __name__ == "__main__":
    main()
