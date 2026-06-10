#!/usr/bin/env python3
"""Validates fork patch anchors against current engine sources."""
from __future__ import annotations

import os
import zipfile
from pathlib import Path

from fork_combustion_engines import (
    CEEP_ZIP,
    CLASSIC_COMBINED_ANCHOR,
    CLASSIC_COMBINED_OLD,
    FUEL_OLD,
    INIT_ANCHOR,
    INSTANT_LOAD_OLD,
    STOCK_COMBINED_OLD,
    STALL_ANCHOR,
    TORQUE_OLD,
    normalize_text,
    read_classic_source,
    read_stock_source,
)

KIT_DIR = Path(__file__).resolve().parent.parent


def check_anchors(label: str, text: str, anchors: list[str]) -> None:
    missing = [anchor for anchor in anchors if anchor not in text]
    if missing:
        raise SystemExit(f"[FAIL] {label} missing anchors: {len(missing)}")


def main() -> None:
    if not CEEP_ZIP.exists():
        raise SystemExit(f"[FAIL] CEEP zip missing: {CEEP_ZIP}")

    classic = normalize_text(read_classic_source())
    stock = normalize_text(read_stock_source())

    check_anchors(
        "classic",
        classic,
        [
            TORQUE_OLD,
            FUEL_OLD,
            STALL_ANCHOR,
            INIT_ANCHOR,
            INSTANT_LOAD_OLD,
            CLASSIC_COMBINED_ANCHOR,
            CLASSIC_COMBINED_OLD,
        ],
    )
    check_anchors(
        "stock",
        stock,
        [TORQUE_OLD, FUEL_OLD, STALL_ANCHOR, INIT_ANCHOR, INSTANT_LOAD_OLD, STOCK_COMBINED_OLD],
    )

    fork_dir = KIT_DIR / "UltraRealismEngine_Prototype" / "lua" / "vehicle" / "powertrain"
    for name in ("ultra_classic_combustionEngine.lua", "ultra_stock_combustionEngine.lua"):
        text = (fork_dir / name).read_text(encoding="utf-8")
        for marker in (
            "ureIntegration.resolveTorqueCoef",
            "ureIntegration.resolveForcedInductionCoef",
            "ureIntegration.computeSpentEnergy",
            "torqueModUltraIntakeMult",
        ):
            if marker not in text:
                raise SystemExit(f"[FAIL] {name} missing {marker}")

    beamng_root = Path(os.environ.get("BEAMNG_ROOT", "/home/gullin/Games/BeamNG.drive")).expanduser()
    if not (beamng_root / "lua" / "vehicle" / "powertrain" / "combustionEngine.lua").exists():
        print(f"[WARN] BEAMNG_ROOT stock source not found at {beamng_root}")

    print("[OK] fork anchors validated (v0.21.0)")


if __name__ == "__main__":
    main()