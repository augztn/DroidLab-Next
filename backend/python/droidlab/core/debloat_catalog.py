"""Curated package guidance for DroidLab's Android Debloater.

The catalog is copied from the user's ADB App Manager project under its MIT
license. Entries are advisory and never authorize a package operation.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any

CATALOG_PATH = Path(__file__).resolve().parent.parent / "data" / "debloat_catalog.json"
VALID_RISKS = (
    "critical",
    "high",
    "review first",
    "advanced",
    "conditional",
    "low",
    "optional",
)


@dataclass(frozen=True, slots=True)
class PackageGuidance:
    package: str
    app: str
    function: str
    risk: str
    impact: str

    def to_dict(self) -> dict[str, str]:
        return {
            "package": self.package,
            "app": self.app,
            "function": self.function,
            "risk": self.risk,
            "impact": self.impact,
        }


@lru_cache(maxsize=1)
def load_catalog() -> tuple[dict[str, PackageGuidance], dict[str, tuple[str, str]]]:
    raw = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    if raw.get("schemaVersion") != 1:
        raise ValueError("Unsupported debloat catalog schema.")
    entries = raw.get("entries")
    recommendations = raw.get("recommendations")
    if not isinstance(entries, str) or not isinstance(recommendations, str):
        raise ValueError("Debloat catalog is incomplete.")

    # The source file defines Python literals. Parse only this fixed project
    # data file using literal_eval; never evaluate downloaded/user-provided code.
    import ast

    entry_map: dict[str, PackageGuidance] = {}
    parsed_entries = ast.literal_eval(entries.split("=", 1)[1].strip())
    if not isinstance(parsed_entries, list):
        raise ValueError("Debloat catalog entries must be a list.")
    for item in parsed_entries:
        if not isinstance(item, dict):
            continue
        values = {key: item.get(key, "") for key in ("package", "app", "function", "risk", "impact")}
        if not all(isinstance(value, str) and value.strip() for value in values.values()):
            continue
        package = values["package"]
        if package in entry_map:
            raise ValueError(f"Duplicate debloat catalog package: {package}")
        entry_map[package] = PackageGuidance(**values)

    rec_literal = ast.literal_eval(recommendations.split("=", 1)[1].strip())
    if not isinstance(rec_literal, dict):
        raise ValueError("Debloat recommendations must be a mapping.")
    rec_map: dict[str, tuple[str, str]] = {}
    for package, value in rec_literal.items():
        if (
            isinstance(package, str)
            and isinstance(value, tuple)
            and len(value) == 2
            and all(isinstance(part, str) for part in value)
        ):
            rec_map[package] = value
    return entry_map, rec_map


def lookup_guidance(package: str) -> dict[str, Any]:
    entries, recommendations = load_catalog()
    entry = entries.get(package)
    rec = recommendations.get(package)
    if entry is not None:
        value = entry.to_dict()
        value["listed"] = True
        value["recommendation"] = rec[0] if rec else "Not recommended — review first"
        value["recommendation_note"] = rec[1] if rec else entry.impact
        return value
    if rec is not None:
        # A standalone recommendation entry still needs to display its own
        # function/risk rather than borrowing a guessed description.
        return {
            "package": package,
            "app": "",
            "function": "",
            "risk": rec[0],
            "impact": rec[1],
            "listed": True,
            "recommendation": rec[0],
            "recommendation_note": rec[1],
        }
    return {
        "package": package,
        "app": "",
        "function": "",
        "risk": "Not listed — review manually",
        "impact": "No curated guidance exists for this exact package ID. Not listed does not mean safe or unsafe.",
        "listed": False,
        "recommendation": "Not listed",
        "recommendation_note": "",
    }


def classify_package(package: str) -> str:
    """Classify a recommendation independently from the broader OEM risk guide."""
    guidance = lookup_guidance(package)
    risk = guidance["risk"].casefold()
    if "critical" in risk:
        return "critical"
    if risk.startswith("high") or "do not remove" in risk or "keep" in risk:
        return "high"
    if "review first" in risk or "unclear" in risk:
        return "review"
    if "advanced" in risk:
        return "advanced"
    if "conditional" in risk or "feature loss" in risk:
        return "conditional"
    if "low" in risk or "optional" in risk:
        return "optional"
    return "unlisted"
