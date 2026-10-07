#!/usr/bin/env python3
"""Rebuild theme-aware README assets; counts come from the actual agent catalog."""

import argparse
from pathlib import Path

if __package__:
    from .visuals import PALETTES, start_svg, text
else:
    from visuals import PALETTES, start_svg, text


ROOT = Path(__file__).resolve().parents[1]
GROUPS = {
    "Cloud agents": {"aws-ssm", "aws-cloudwatch", "gcp-guest", "gcp-osconfig", "gcp-ops", "azure", "do-metrics", "do-droplet", "vultr"},
    "Virtualization": {"qemu", "vmware", "virtualbox", "hyperv"},
    "Reporting / management": {"landscape", "apport"},
    "Provisioning": {"cloud-init"},
}


def catalog_ids():
    source = (ROOT / "antimon.sh").read_text(encoding="utf-8")
    block = source.split("<<'CATALOG'\n", 1)[1].split("\nCATALOG", 1)[0]
    ids = {row.split("|", 1)[0] for row in block.splitlines()}
    grouped = set().union(*GROUPS.values())
    if ids != grouped or sum(map(len, GROUPS.values())) != len(ids):
        raise ValueError("Update the visual groups to match the agent catalog")
    return ids


def hero(theme):
    p = PALETTES[theme]
    svg = start_svg(1200, 440, "Anti-Monitoring — Less noise. More control.",
                    "Linux guest-agent control by HVHBIGNAME. Scan, review a plan, apply and restore service state.", theme)
    svg += f'''<defs><pattern id="grid" width="28" height="28" patternUnits="userSpaceOnUse"><path d="M28 0H0V28" fill="none" stroke="{p['line']}" stroke-width=".65"/></pattern></defs>
<style>
  .mobile {{ display: none; }}
  .pulse {{ animation: pulse 4s ease-in-out infinite; }}
  @keyframes pulse {{ 0%,100% {{ opacity: .45; }} 50% {{ opacity: 1; }} }}
  @media (max-width: 600px) {{ .desktop {{ display: none; }} .mobile {{ display: inline; }} }}
  @media (prefers-reduced-motion: reduce) {{ .pulse {{ animation: none; }} }}
</style>
<g class="desktop">
<path d="M32 78H1168M32 367H1168" stroke="{p['line']}"/>
<path d="M44 29v24m10-24v24m-10-12h10m14-12 9 24 9-24" fill="none" stroke="{p['accent']}" stroke-width="3"/>
{text(105, 49, 'HVHBIGNAME / LINUX TOOLS', fill=p['fg'], size=20, weight=700)}
{text(1155, 47, 'CONTROL / 02', fill=p['muted'], size=13, mono=True, anchor='end')}
{text(44, 125, 'ANTI-MONITORING', fill=p['muted'], size=17, mono=True)}
{text(38, 221, 'LESS NOISE.', fill=p['fg'], size=90, weight=900)}
{text(38, 312, 'MORE CONTROL.', fill=p['accent'], size=82, weight=900)}
<rect x="798" y="100" width="357" height="244" fill="url(#grid)" opacity=".65"/>
<g transform="translate(970 220)">
  <circle r="129" fill="none" stroke="{p['line']}"/>
  <circle r="106" fill="none" stroke="{p['line']}" stroke-dasharray="2 8"/>
  <path d="M-155 0H155M0-140V140" stroke="{p['line']}"/>
  <path d="M0-95 92-42V43L0 97-92 43V-42Z" fill="{p['panel']}" stroke="{p['accent']}" stroke-width="1.5"/>
  <path d="m-92-42 92 52 92-52M0 10v87M-46-69v86l46 27 46-27v-86" fill="none" stroke="{p['accent']}" opacity=".35"/>
  <rect x="-39" y="-48" width="78" height="74" rx="8" fill="{p['soft']}" stroke="{p['accent']}"/>
  <path d="m-18-13 12 11 26-28" fill="none" stroke="{p['accent']}" stroke-width="5"/>
  <circle cx="-130" r="5" fill="{p['accent']}" class="pulse"/>
  <circle cx="130" r="5" fill="{p['accent']}"/>
  {text(0, -146, 'OBSERVE', fill=p['muted'], size=12, mono=True, anchor='middle')}
  {text(0, 149, 'DECIDE', fill=p['muted'], size=12, mono=True, anchor='middle')}
</g>
<circle cx="48" cy="403" r="4" fill="{p['accent']}" class="pulse"/>
{text(63, 408, 'POSIX SH / LOCAL REPORTS / EXPLICIT ACTIONS', fill=p['fg'], size=13, mono=True)}
{text(1155, 408, 'SCAN → PLAN → APPLY', fill=p['muted'], size=13, mono=True, anchor='end')}
</g>
<g class="mobile">
<path d="M42 108H1158" stroke="{p['line']}"/>
{text(45, 73, 'HVHBIGNAME / ANTI-MONITORING', fill=p['muted'], size=39, weight=700)}
{text(38, 250, 'YOUR VM.', fill=p['fg'], size=154, weight=900)}
{text(38, 389, 'YOUR CHOICE.', fill=p['accent'], size=141, weight=900)}
</g>
</svg>
'''
    return svg


def workflow(theme):
    p = PALETTES[theme]
    svg = start_svg(1200, 240, "Scan → plan → apply → verify",
                    "Read-only scan, explicit selection, recorded changes and verified state. Service snapshots support restoration.", theme)
    svg += text(34, 39, "THE CONTROL LOOP", fill=p["muted"], size=15, mono=True)
    cards = (("01", "SCAN", "Find packages + services"), ("02", "PLAN", "Choose exactly what changes"),
             ("03", "APPLY", "Record state, then act"), ("04", "VERIFY", "Check the actual result"))
    for index, (number, title, detail) in enumerate(cards):
        x = 32 + index * 294
        svg += f'<rect x="{x}" y="63" width="266" height="117" rx="10" fill="{p["panel"]}" stroke="{p["line"]}"/>\n'
        svg += text(x + 18, 94, number, fill=p["accent"], size=18, mono=True)
        svg += text(x + 18, 128, title, fill=p["fg"], size=27, weight=700)
        svg += text(x + 18, 156, detail, fill=p["muted"], size=16)
        if index < 3:
            svg += f'<path d="M{x + 273} 120h12m-5-5 5 5-5 5" fill="none" stroke="{p["accent"]}"/>'
    svg += text(34, 216, "RESTORE / Saved service state. Package reinstallation is a separate operation.", fill=p["muted"], size=16, mono=True)
    return svg + "\n</svg>\n"


def coverage(theme, ids):
    p = PALETTES[theme]
    svg = start_svg(1200, 345, "Agent catalog by function",
                    "Catalog coverage, computed from the source: nine cloud groups, four virtualization groups, two reporting groups and one provisioning group. These are catalog counts, not scan results.", theme)
    svg += text(35, 43, "SURFACE MAP / CATALOG", fill=p["muted"], size=16, mono=True)
    svg += text(47, 172, f"{len(ids):02}", fill=p["accent"], size=111, weight=900)
    svg += text(48, 211, "AGENT GROUPS", fill=p["fg"], size=23, weight=700)
    svg += text(48, 249, "5 native package families", fill=p["muted"], size=18)
    svg += text(48, 278, "+ Snap / 4 init families", fill=p["muted"], size=18)
    colors = (p["accent"], p["fg"], p["muted"], p["warn"])
    for index, ((label, group), color) in enumerate(zip(GROUPS.items(), colors)):
        y = 98 + index * 52
        svg += text(376, y, label, fill=p["fg"], size=19)
        svg += f'<rect x="666" y="{y - 15}" width="430" height="14" rx="3" fill="{p["panel"]}"/>'
        svg += f'<rect x="666" y="{y - 15}" width="{430 * len(group) / 9:.2f}" height="14" rx="3" fill="{color}"/>'
        svg += text(1151, y, len(group), fill=color, size=22, mono=True, anchor="end")
    svg += f'<path d="M32 301H1168" stroke="{p["line"]}"/>'
    svg += text(35, 328, "SOURCE-DERIVED COUNTS / YOUR MACHINE IS MEASURED BY antimon --scan --json", fill=p["muted"], size=14, mono=True)
    return svg + "\n</svg>\n"


def workflow_mobile(theme):
    p = PALETTES[theme]
    svg = start_svg(600, 416, "Scan → plan → apply → verify",
                    "A readable two-by-two control loop for small screens.", theme)
    svg += text(26, 40, "THE CONTROL LOOP", fill=p["muted"], size=20, mono=True)
    cards = (("01", "SCAN", "Find guest components"), ("02", "PLAN", "Review exact targets"),
             ("03", "APPLY", "Record, then change"), ("04", "VERIFY", "Confirm the result"))
    for index, (number, title, detail) in enumerate(cards):
        x, y = 26 + (index % 2) * 284, 74 + (index // 2) * 154
        svg += f'<rect x="{x}" y="{y}" width="264" height="122" rx="10" fill="{p["panel"]}" stroke="{p["line"]}"/>'
        svg += text(x + 18, y + 29, number, fill=p["accent"], size=19, mono=True)
        svg += text(x + 18, y + 68, title, fill=p["fg"], size=32, weight=700)
        svg += text(x + 18, y + 98, detail, fill=p["muted"], size=19)
    svg += text(26, 387, "RESTORE / Keep the recovery snapshot.", fill=p["muted"], size=18, mono=True)
    return svg + "\n</svg>\n"


def coverage_mobile(theme, ids):
    p = PALETTES[theme]
    svg = start_svg(600, 510, "Agent catalog by function",
                    "16 groups: 9 cloud, 4 virtualization, 2 reporting/management, 1 provisioning. Source-derived catalog counts.", theme)
    svg += text(28, 42, "SURFACE MAP / CATALOG", fill=p["muted"], size=20, mono=True)
    svg += text(28, 144, len(ids), fill=p["accent"], size=104, weight=900)
    svg += text(190, 94, "AGENT GROUPS", fill=p["fg"], size=26, weight=700)
    svg += text(190, 125, "5 package families + Snap", fill=p["muted"], size=19)
    svg += text(190, 153, "4 init families", fill=p["muted"], size=19)
    colors = (p["accent"], p["fg"], p["muted"], p["warn"])
    for index, ((label, group), color) in enumerate(zip(GROUPS.items(), colors)):
        y = 211 + index * 64
        svg += text(28, y, label, fill=p["fg"], size=23)
        svg += text(570, y, len(group), fill=color, size=25, mono=True, anchor="end")
        svg += f'<rect x="28" y="{y + 13}" width="544" height="12" rx="3" fill="{p["panel"]}"/>'
        svg += f'<rect x="28" y="{y + 13}" width="{544 * len(group) / 9:.2f}" height="12" rx="3" fill="{color}"/>'
    svg += text(28, 478, "CATALOG COUNTS / NOT A SERVER SCAN", fill=p["muted"], size=18, mono=True)
    return svg + "\n</svg>\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    ids = catalog_ids()
    assets = ROOT / "assets"
    if not args.check:
        assets.mkdir(exist_ok=True)
    for theme in PALETTES:
        for name, content in (("hero", hero(theme)), ("workflow", workflow(theme)), ("coverage", coverage(theme, ids)),
                              ("workflow-mobile", workflow_mobile(theme)), ("coverage-mobile", coverage_mobile(theme, ids))):
            path = assets / f"{name}-{theme}.svg"
            if args.check:
                if not path.exists() or path.read_text(encoding="utf-8") != content:
                    raise SystemExit(f"Stale asset: {path.name}; run python3 tools/generate_assets.py")
            else:
                path.write_text(content, encoding="utf-8", newline="\n")
    print("README assets: OK" if args.check else "Generated theme-aware desktop and mobile README assets")


if __name__ == "__main__":
    main()
