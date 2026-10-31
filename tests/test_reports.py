"""Validate local report rendering against malformed data and XML injection."""

import json
import subprocess
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path
from xml.etree import ElementTree

from tools.render_report import render, validate

ROOT = Path(__file__).resolve().parents[1]


def sample():
    return {
        "schema_version": 1, "complete": True,
        "system": {"distribution": "Fixture Linux", "package_manager": "apt", "init_system": "systemd"},
        "agents": [{"id": "qemu", "name": "QEMU Guest Agent", "findings": [
            {"kind": "package", "name": "qemu-guest-agent", "startup": "installed", "active": "-"},
            {"kind": "service", "name": "qemu-guest-agent", "startup": "masked", "active": "inactive"},
        ]}],
        "counts": {"packages": 1, "snaps": 0, "services": 1, "manual": 0},
    }


class ReportTests(unittest.TestCase):
    def test_actual_findings_produce_valid_accessible_svg(self):
        root = ElementTree.fromstring(render(sample()))
        ns = {"svg": "http://www.w3.org/2000/svg"}
        self.assertEqual(root.attrib["role"], "img")
        self.assertIsNotNone(root.find("svg:title", ns))
        self.assertIsNotNone(root.find("svg:desc", ns))
        content = " ".join(root.itertext())
        self.assertIn("qemu", content)
        self.assertIn("Fixture Linux / apt / systemd", content)
        self.assertIn("not a privacy score", content)

    def test_partial_inventory_is_marked_in_both_themes(self):
        report = sample()
        report["complete"] = False
        for theme in ("dark", "light"):
            with self.subTest(theme=theme):
                self.assertIn("PARTIAL INVENTORY", render(report, theme))

    def test_markup_is_text_and_never_executable_svg(self):
        report = sample()
        report["agents"][0]["id"] = "<script>bad()</script>"
        report["system"]["distribution"] = '<image href="https://example.invalid/track">'
        svg = render(report)
        root = ElementTree.fromstring(svg)
        self.assertIn("&lt;script&gt;", svg)
        self.assertFalse(any(node.tag.endswith("}script") or node.tag.endswith("}image") for node in root.iter()))

    def test_summary_must_match_findings(self):
        report = sample()
        report["counts"]["packages"] = 50
        with self.assertRaisesRegex(ValueError, "counts"):
            validate(report)

    def test_unknown_schema_and_boolean_schema_are_rejected(self):
        for schema in (0, 2, True, "1"):
            report = sample()
            report["schema_version"] = schema
            with self.subTest(schema=schema), self.assertRaises(ValueError):
                validate(report)

    def test_invalid_finding_kind_is_a_validation_error(self):
        for kind in ("unknown", [], None):
            report = sample()
            report["agents"][0]["findings"][0]["kind"] = kind
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                validate(report)

    def test_duplicate_agents_are_rejected(self):
        report = sample()
        report["agents"].append(deepcopy(report["agents"][0]))
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            validate(report)

    def test_empty_inventory_still_renders(self):
        report = sample()
        report["agents"] = []
        report["counts"] = dict.fromkeys(report["counts"], 0)
        ElementTree.fromstring(render(report))

    def test_xml_control_characters_are_rejected(self):
        report = sample()
        report["system"]["distribution"] = "bad\x01text"
        with self.assertRaisesRegex(ValueError, "XML"):
            render(report)

    def test_invalid_input_does_not_replace_existing_output(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            source = path / "invalid.json"
            destination = path / "report.svg"
            source.write_text(json.dumps({"schema_version": 100}), encoding="utf-8")
            destination.write_text("existing report", encoding="utf-8")
            result = subprocess.run([sys.executable, str(ROOT / "tools" / "render_report.py"), str(source),
                                     "--output", str(destination)], capture_output=True, text=True, timeout=20, check=False)
            self.assertEqual(result.returncode, 1)
            self.assertIn("Cannot render report", result.stderr)
            self.assertEqual(destination.read_text(encoding="utf-8"), "existing report")


if __name__ == "__main__":
    unittest.main()
