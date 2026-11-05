#!/usr/bin/env python3
"""Compile checked-in String Catalogs for SwiftPM/Command Line Tools builds."""
import json
from pathlib import Path

resources = Path(__file__).resolve().parent.parent / "Sources/Ada/Resources"
for catalog_path in sorted(resources.glob("*.xcstrings")):
    catalog = json.loads(catalog_path.read_text())
    for language in ("tr", "en"):
        lines = ["// Generated from " + catalog_path.name + "; edit the catalog instead."]
        for key, entry in sorted(catalog["strings"].items()):
            value = entry["localizations"][language]["stringUnit"]["value"]
            # JSON quoting is compatible with the literal strings format here.
            lines.append(json.dumps(key, ensure_ascii=False) + " = " + json.dumps(value, ensure_ascii=False) + ";")
        target = resources / (language + ".lproj") / (catalog_path.stem + ".strings")
        target.parent.mkdir(exist_ok=True)
        target.write_text("\n".join(lines) + "\n")
