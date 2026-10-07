#!/usr/bin/env python3
"""Turn an `antimon --scan --json` result into a local, self-contained SVG chart."""

import argparse
import json
from collections import Counter
from pathlib import Path

if __package__:
    from .visuals import PALETTES, start_svg, text
else:
    from visuals import PALETTES, start_svg, text


KINDS = {"package", "snap", "service", "manual"}
COUNT_KEYS = {"package": "packages", "snap": "snaps", "service": "services", "manual": "manual"}


def validate(report):
    if not isinstance(report, dict) or type(report.get("schema_version")) is not int or report["schema_version"] != 1:
        raise ValueError("Expected an Anti-Monitoring schema_version=1 report")
    if not isinstance(report.get("complete"), bool):
        raise TypeError("Report must declare whether the inventory is complete")
    system = report.get("system")
    if not isinstance(system, dict) or any(not isinstance(system.get(key), str) for key in ("distribution", "package_manager", "init_system")):
        raise ValueError("Invalid system information")
    agents = report.get("agents")
    if not isinstance(agents, list) or len(agents) > 128:
        raise ValueError("Invalid agent list (maximum 128 groups)")
    seen = set()
    actual = Counter({key: 0 for key in COUNT_KEYS.values()})
    for agent in agents:
        if not isinstance(agent, dict) or not isinstance(agent.get("id"), str) or not isinstance(agent.get("name"), str):
            raise TypeError("Invalid agent identity")
        if agent["id"] in seen:
            raise ValueError("Duplicate agent ID")
        seen.add(agent["id"])
        findings = agent.get("findings")
        if not isinstance(findings, list) or len(findings) > 1024:
            raise ValueError("Invalid findings list")
        for finding in findings:
            if not isinstance(finding, dict) or not isinstance(finding.get("kind"), str) or finding["kind"] not in KINDS:
                raise ValueError("Unknown finding kind")
            if any(not isinstance(finding.get(key), str) for key in ("name", "startup", "active")):
                raise ValueError("Invalid finding fields")
            actual[COUNT_KEYS[finding["kind"]]] += 1
    declared = report.get("counts")
    if not isinstance(declared, dict) or any(type(value) is not int for value in declared.values()) or declared != dict(actual):
        raise ValueError("Summary counts do not match the actual findings")
    return report


def render(report, theme="dark"):
    validate(report)
    p = PALETTES[theme]
    agents = report["agents"]
    system = report["system"]
    height = 272 + len(agents) * 38
    svg = start_svg(1200, height, "Anti-Monitoring / local inventory",
                    "Counts of packages, services and manually installed components from an actual scan. This is an inventory, not a privacy score.", theme)
    svg += text(36, 43, "ANTI-MONITORING / LOCAL INVENTORY", fill=p["fg"], size=22, weight=700)
    complete = report["complete"]
    svg += text(1164, 43, "AVAILABLE BACKENDS CHECKED" if complete else "PARTIAL INVENTORY", fill=p["accent"] if complete else p["warn"], size=14, mono=True, anchor="end")
    caption = f"{system['distribution']} / {system['package_manager']} / {system['init_system']}"
    svg += text(36, 77, caption[:105], fill=p["muted"], size=17)
    detected = sum(bool(agent["findings"]) for agent in agents)
    active = sum(finding["kind"] == "service" and finding["active"] == "active" for agent in agents for finding in agent["findings"])
    stats = (("DETECTED GROUPS", detected), ("PACKAGES + SNAPS", report["counts"]["packages"] + report["counts"]["snaps"]), ("ACTIVE SERVICES", active))
    for index, (label, count) in enumerate(stats):
        x = 36 + index * 389
        svg += f'<rect x="{x}" y="101" width="350" height="69" rx="8" fill="{p["panel"]}"/>'
        svg += text(x + 16, 145, count, fill=p["accent"], size=36, weight=700)
        svg += text(x + 78, 142, label, fill=p["muted"], size=15, mono=True)
    svg += text(36, 208, "AGENT", fill=p["muted"], size=14, mono=True)
    svg += text(310, 208, "PACKAGES + SNAPS / SERVICES / MANUAL", fill=p["muted"], size=14, mono=True)
    svg += text(1157, 208, "TOTAL", fill=p["muted"], size=14, mono=True, anchor="end")
    maximum = max((len(agent["findings"]) for agent in agents), default=1) or 1
    for index, agent in enumerate(agents):
        y = 240 + index * 38
        counts = Counter(finding["kind"] for finding in agent["findings"])
        total = len(agent["findings"])
        svg += text(36, y, agent["id"][:24], fill=p["fg"] if total else p["muted"], size=18, mono=True)
        svg += f'<rect x="310" y="{y - 15}" width="754" height="17" rx="3" fill="{p["panel"]}"/>'
        x = 310.0
        for count, color in ((counts["package"] + counts["snap"], p["accent"]), (counts["service"], p["muted"]), (counts["manual"], p["warn"])):
            width = 754 * count / maximum
            if count:
                svg += f'<rect x="{x:.2f}" y="{y - 15}" width="{width:.2f}" height="17" fill="{color}"/>'
            x += width
        svg += text(1157, y, total, fill=p["fg"], size=18, mono=True, anchor="end")
    svg += text(36, height - 20, "LOCAL DATA / Counts are not a privacy score. Hypervisor access is outside the guest boundary.", fill=p["muted"], size=14)
    return svg + "\n</svg>\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--output", type=Path, default=Path("report.svg"))
    parser.add_argument("--theme", choices=PALETTES, default="dark")
    args = parser.parse_args()
    try:
        report = json.loads(args.input.read_text(encoding="utf-8"))
        svg = render(report, args.theme)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(svg, encoding="utf-8", newline="\n")
    except (OSError, ValueError, TypeError) as error:
        parser.exit(1, f"Cannot render report: {error}\n")
    print(f"Saved {args.output}")


if __name__ == "__main__":
    main()
