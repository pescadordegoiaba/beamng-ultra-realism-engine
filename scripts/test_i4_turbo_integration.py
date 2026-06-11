#!/usr/bin/env python3
"""Validates CEEP flathead i4 turbo integration in the patched pack."""
from __future__ import annotations

import json
import re
import zipfile
from pathlib import Path

KIT_DIR = Path(__file__).resolve().parent.parent
ZIP_CEEP = KIT_DIR / "patched_mods" / "classic_engine_expansion_pack.zip"
I4_PARTS = (
    "vehicles/common/CEEP/ceep_engine_jbeam/c_common_engine_parts/"
    "I4_engines/c_common_lhead_i4_parts.jbeam"
)
I4_TC_MANIFOLDS = (
    "vehicles/common/CEEP/ceep_engine_jbeam/c_common_TC/"
    "I4_TC_manifolds/c_common_TC_manifolds_lhead_i4.jbeam"
)


def main() -> None:
    if not ZIP_CEEP.exists():
        raise SystemExit(f"[FAIL] missing CEEP zip: {ZIP_CEEP}")

    with zipfile.ZipFile(ZIP_CEEP) as zf:
        parts_text = zf.read(I4_PARTS).decode("utf-8", errors="replace")
        if "/*" in parts_text and "c_tc_lhead_stock_intake_i4" in parts_text:
            block = parts_text[parts_text.find("/*") : parts_text.find("*/") + 2]
            if "c_tc_lhead_stock_intake_i4" in block:
                raise SystemExit("[FAIL] i4 turbo intake slot is still commented out")
        if '"c_tc_lhead_stock_intake_i4"' not in parts_text:
            raise SystemExit("[FAIL] i4 turbo intake slot missing from parts file")
        if '"slotType" : "c_lhead_stock_intake_i4"' not in parts_text.replace(" ", ""):
            if '"slotType":"c_lhead_stock_intake_i4"' not in parts_text.replace(" ", ""):
                raise SystemExit("[FAIL] i4 turbo intake uses wrong slotType")
        if I4_TC_MANIFOLDS not in zf.namelist():
            raise SystemExit("[FAIL] i4 turbo manifold file missing from CEEP zip")
        manifold_text = zf.read(I4_TC_MANIFOLDS).decode("utf-8", errors="replace")
        if '"c_tc_lhead_stock_manifold_i4"' not in manifold_text:
            raise SystemExit("[FAIL] i4 turbo manifold part missing")
        if "turbocharger" not in manifold_text:
            raise SystemExit("[FAIL] i4 turbo manifold missing turbocharger block")
        marker = json.loads(zf.read("ultra_realism_integration.json").decode("utf-8"))
        i4_stats = marker.get("i4Turbo", {})
        if not i4_stats.get("i4TurboIntakeEnabled"):
            raise SystemExit("[FAIL] integration marker missing i4TurboIntakeEnabled")

    if re.search(r"c_sb_stockohv_intake_v8", parts_text):
        raise SystemExit("[FAIL] i4 turbo still references V8 intake slotType")

    print("[OK] CEEP i4 turbo integration validated (v0.21.1)")


if __name__ == "__main__":
    main()