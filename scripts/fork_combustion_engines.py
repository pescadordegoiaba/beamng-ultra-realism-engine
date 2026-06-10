#!/usr/bin/env python3
"""Gera forks URE de classic_combustionEngine e combustionEngine com combustível integrado."""
from __future__ import annotations

import re
import zipfile
from pathlib import Path

KIT_DIR = Path(__file__).resolve().parent.parent
OUT_DIR = KIT_DIR / "UltraRealismEngine_Prototype" / "lua" / "vehicle" / "powertrain"
CEEP_ZIP = KIT_DIR / "patched_mods" / "classic_engine_expansion_pack.zip"
STOCK_SRC = Path("/home/gullin/Games/BeamNG.drive/lua/vehicle/powertrain/combustionEngine.lua")

URE_HEADER = """-- Ultra Realism Engine fork. Combustion + fuel model integrated via ultra_combustionEngineIntegration.
-- Derived from BeamNG.drive / CEEP combustion engine (bCDDL). Do not replace with vanilla at runtime.
"""

INTEGRATION_REQUIRE = 'local ureIntegration = rerequire("powertrain/ultra_combustionEngineIntegration")\n'

TORQUE_OLD = (
    "  torque = ((torque * device.forcedInductionCoef * throttleMap) + device.nitrousOxideTorque) "
    "* device.outputTorqueState * (ignitionCut and 0 or 1) * device.slowIgnitionErrorCoef * device.fastIgnitionErrorCoef"
)
TORQUE_NEW = (
    "  local ureTorqueCoef = ureIntegration.resolveTorqueCoef(device)\n"
    "  torque = ((torque * device.forcedInductionCoef * throttleMap) + device.nitrousOxideTorque) "
    "* ureTorqueCoef * (ignitionCut and 0 or 1) * device.slowIgnitionErrorCoef * device.fastIgnitionErrorCoef"
)

FUEL_OLD = (
    "  device.spentEnergy = device.spentEnergy + burnEnergy * invBurnEfficiency\n"
    "  device.spentEnergyNitrousOxide = device.spentEnergyNitrousOxide + burnEnergyNitrousOxide * invBurnEfficiency"
)
FUEL_NEW = (
    "  local ureSpent, ureSpentN2O = ureIntegration.computeSpentEnergy(device, burnEnergy, burnEnergyNitrousOxide, invBurnEfficiency, dt)\n"
    "  device.spentEnergy = device.spentEnergy + ureSpent\n"
    "  device.spentEnergyNitrousOxide = device.spentEnergyNitrousOxide + ureSpentN2O"
)

STALL_ANCHOR = "    device.stallTimer = 1\n  end"
STALL_INJECT = (
    "    device.stallTimer = 1\n  end\n\n  ureIntegration.postStallGuard(device)"
)

INIT_ANCHOR = "  selectUpdates(device)\n\n  return device"
INIT_INJECT = (
    "  selectUpdates(device)\n\n"
    "  ureIntegration.onDeviceInit(device, jbeamData)\n\n"
    "  return device"
)


def read_classic_source() -> str:
    if not CEEP_ZIP.exists():
        raise SystemExit(f"[ERRO] CEEP patched zip ausente: {CEEP_ZIP}")
    with zipfile.ZipFile(CEEP_ZIP) as zf:
        name = "lua/vehicle/powertrain/classic_combustionEngine.lua"
        if name not in zf.namelist():
            raise SystemExit(f"[ERRO] {name} não encontrado no pack CEEP")
        return zf.read(name).decode("utf-8", errors="replace")


def read_stock_source() -> str:
    if not STOCK_SRC.exists():
        raise SystemExit(f"[ERRO] combustionEngine.lua não encontrado: {STOCK_SRC}")
    return STOCK_SRC.read_text(encoding="utf-8", errors="replace")


def normalize_text(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n")


def patch_engine_source(text: str, default_profile: str) -> str:
    text = normalize_text(text)
    if TORQUE_OLD not in text:
        raise SystemExit("[ERRO] Âncora de torque não encontrada — engine base mudou?")
    if FUEL_OLD not in text:
        raise SystemExit("[ERRO] Âncora de combustível não encontrada — engine base mudou?")
    if STALL_ANCHOR not in text:
        raise SystemExit("[ERRO] Âncora de stall não encontrada — engine base mudou?")
    if INIT_ANCHOR not in text:
        raise SystemExit("[ERRO] Âncora de init não encontrada — engine base mudou?")

    text = URE_HEADER + text
    text = text.replace("local M = {}\n", "local M = {}\n\n" + INTEGRATION_REQUIRE, 1)
    text = text.replace(TORQUE_OLD, TORQUE_NEW, 1)
    text = text.replace(FUEL_OLD, FUEL_NEW, 1)
    text = text.replace(STALL_ANCHOR, STALL_INJECT, 1)
    text = text.replace(INIT_ANCHOR, INIT_INJECT, 1)
    return text


def write_fork(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    print(f"[OK] {path.relative_to(KIT_DIR)} ({path.stat().st_size // 1024} KB)")


def main() -> None:
    classic = patch_engine_source(read_classic_source(), "ceep")
    stock = patch_engine_source(read_stock_source(), "stock")
    write_fork(OUT_DIR / "ultra_classic_combustionEngine.lua", classic)
    write_fork(OUT_DIR / "ultra_stock_combustionEngine.lua", stock)
    print("[OK] Forks URE gerados com torque + combustível + stall integrados")


if __name__ == "__main__":
    main()