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

INSTANT_LOAD_OLD = (
    "  local instantLoad = min(max(torque / ((maxCurrentTorque + 1e-30) * device.outputTorqueState * device.forcedInductionCoef), 0), 1)"
)
INSTANT_LOAD_NEW = (
    "  local instantLoad = min(max(torque / ((maxCurrentTorque + 1e-30) * device.forcedInductionCoef), 0), 1)"
)

ULTRA_TORQUE_HELPER = """
  local function loadUltraMultCurve(key)
    if not jbeamData[key] then return {} end
    local tableData = tableFromHeaderTable(jbeamData[key])
    local points = {}
    for _, v in pairs(tableData) do
      maxAvailableRPM = max(maxAvailableRPM, v.rpm)
      table.insert(points, {v.rpm, v.torque})
    end
    return createCurve(points)
  end

  local rawUltraIntakeMultCurve = loadUltraMultCurve("torqueModUltraIntakeMult")
  local rawUltraSpacerMultCurve = loadUltraMultCurve("torqueModUltraSpacerMult")
  local rawUltraStrokerMultCurve = loadUltraMultCurve("torqueModUltraStrokerMult")
  local rawUltraPistonsMultCurve = loadUltraMultCurve("torqueModUltraPistonsMult")
  local rawUltraRingsMultCurve = loadUltraMultCurve("torqueModUltraRingsMult")
  local rawUltraCamshaftMultCurve = loadUltraMultCurve("torqueModUltraCamshaftMult")
  local rawUltraValvetrainMultCurve = loadUltraMultCurve("torqueModUltraValvetrainMult")
  local rawUltraHeadsMultCurve = loadUltraMultCurve("torqueModUltraHeadsMult")
  local rawUltraIgnitionCurve = {}
  local lastUltraIgnitionValue = 0
  if jbeamData.torqueModUltraIgnition then
    local ignitionTable = tableFromHeaderTable(jbeamData.torqueModUltraIgnition)
    local ignitionPoints = {}
    for _, v in pairs(ignitionTable) do
      maxAvailableRPM = max(maxAvailableRPM, v.rpm)
      table.insert(ignitionPoints, {v.rpm, v.torque})
    end
    rawUltraIgnitionCurve = createCurve(ignitionPoints)
    lastUltraIgnitionValue = rawUltraIgnitionCurve[#rawUltraIgnitionCurve] or 0
  end
"""

STOCK_COMBINED_OLD = """  local rawCombinedCurve = {}
  for i = 0, maxAvailableRPM, 1 do
    local base = rawBaseCurve[i] or 0
    local baseMult = rawTorqueMultCurve[i] or 1
    local intake = rawIntakeCurve[i] or lastRawIntakeValue
    local exhaust = rawExhaustCurve[i] or lastRawExhaustValue
    rawCombinedCurve[i] = base * baseMult + intake + exhaust
  end"""

STOCK_COMBINED_NEW = (
    ULTRA_TORQUE_HELPER
    + """  local rawCombinedCurve = {}
  for i = 0, maxAvailableRPM, 1 do
    local base = rawBaseCurve[i] or 0
    local baseMult = rawTorqueMultCurve[i] or 1
    local intake = rawIntakeCurve[i] or lastRawIntakeValue
    local exhaust = rawExhaustCurve[i] or lastRawExhaustValue
    local ultraMult = (rawUltraIntakeMultCurve[i] or 1)
      * (rawUltraSpacerMultCurve[i] or 1)
      * (rawUltraStrokerMultCurve[i] or 1)
      * (rawUltraPistonsMultCurve[i] or 1)
      * (rawUltraRingsMultCurve[i] or 1)
      * (rawUltraCamshaftMultCurve[i] or 1)
      * (rawUltraValvetrainMultCurve[i] or 1)
      * (rawUltraHeadsMultCurve[i] or 1)
    local ultraIgnition = rawUltraIgnitionCurve[i] or lastUltraIgnitionValue
    rawCombinedCurve[i] = base * baseMult * ultraMult + intake + exhaust + ultraIgnition
  end"""
)

CLASSIC_COMBINED_OLD = (
    "    rawCombinedCurve[i] = base * baseMult * StrokerMult * CylHeadMult * InjectorMult * CamshaftMult * IcMult * FuelMult + intake + exhaust + Filter + Header + Distributor + VelocityStack + Spacer + IntkManifold + DrySump"
)
CLASSIC_COMBINED_NEW = (
    "    local ultraMult = (rawUltraIntakeMultCurve[i] or 1)\n"
    "      * (rawUltraSpacerMultCurve[i] or 1)\n"
    "      * (rawUltraStrokerMultCurve[i] or 1)\n"
    "      * (rawUltraPistonsMultCurve[i] or 1)\n"
    "      * (rawUltraRingsMultCurve[i] or 1)\n"
    "      * (rawUltraCamshaftMultCurve[i] or 1)\n"
    "      * (rawUltraValvetrainMultCurve[i] or 1)\n"
    "      * (rawUltraHeadsMultCurve[i] or 1)\n"
    "    local ultraIgnition = rawUltraIgnitionCurve[i] or lastUltraIgnitionValue\n"
    "    rawCombinedCurve[i] = base * baseMult * StrokerMult * CylHeadMult * InjectorMult * CamshaftMult * IcMult * FuelMult * ultraMult + intake + exhaust + Filter + Header + Distributor + VelocityStack + Spacer + IntkManifold + DrySump + ultraIgnition"
)

CLASSIC_COMBINED_ANCHOR = "  local rawCombinedCurve = {}\n  for i = 0, maxAvailableRPM, 1 do"


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
    if INSTANT_LOAD_OLD not in text:
        raise SystemExit("[ERRO] Âncora de instantEngineLoad não encontrada — engine base mudou?")
    text = text.replace(INSTANT_LOAD_OLD, INSTANT_LOAD_NEW, 1)
    return text


def patch_stock_ultra_torque(text: str) -> str:
    if STOCK_COMBINED_OLD not in text:
        raise SystemExit("[ERRO] Âncora de curva de torque stock não encontrada — engine base mudou?")
    return text.replace(STOCK_COMBINED_OLD, STOCK_COMBINED_NEW, 1)


def patch_classic_ultra_torque(text: str) -> str:
    if CLASSIC_COMBINED_ANCHOR not in text:
        raise SystemExit("[ERRO] Âncora de curva de torque classic não encontrada — engine base mudou?")
    if CLASSIC_COMBINED_OLD not in text:
        raise SystemExit("[ERRO] Fórmula de torque classic não encontrada — engine base mudou?")
    text = text.replace(CLASSIC_COMBINED_ANCHOR, ULTRA_TORQUE_HELPER + CLASSIC_COMBINED_ANCHOR, 1)
    return text.replace(CLASSIC_COMBINED_OLD, CLASSIC_COMBINED_NEW, 1)


def write_fork(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    print(f"[OK] {path.relative_to(KIT_DIR)} ({path.stat().st_size // 1024} KB)")


def main() -> None:
    classic = patch_classic_ultra_torque(patch_engine_source(read_classic_source(), "ceep"))
    stock = patch_stock_ultra_torque(patch_engine_source(read_stock_source(), "stock"))
    write_fork(OUT_DIR / "ultra_classic_combustionEngine.lua", classic)
    write_fork(OUT_DIR / "ultra_stock_combustionEngine.lua", stock)
    print("[OK] Forks URE gerados com torque + combustível + stall + torqueModUltra integrados")


if __name__ == "__main__":
    main()