#!/usr/bin/env python3
"""Validacao em multiplas passagens do Ultra Realism Engine modkit."""
from __future__ import annotations

import json
import subprocess
import sys
import zipfile
from pathlib import Path

KIT_DIR = Path(__file__).resolve().parent.parent
MOD_DIR = KIT_DIR / "UltraRealismEngine_Prototype"
LUA = MOD_DIR / "lua" / "vehicle" / "controller" / "ultraRealismEngine.lua"
ULTRA_ENGINE = MOD_DIR / "lua" / "vehicle" / "powertrain" / "ultra_combustionEngine.lua"
ULTRA_BRIDGE = MOD_DIR / "lua" / "vehicle" / "powertrain" / "ultraRealismEngineBridge.lua"
ULTRA_CLASSIC = MOD_DIR / "lua" / "vehicle" / "powertrain" / "ultra_classic_combustionEngine.lua"
ULTRA_STOCK = MOD_DIR / "lua" / "vehicle" / "powertrain" / "ultra_stock_combustionEngine.lua"
ULTRA_INTEGRATION = MOD_DIR / "lua" / "vehicle" / "powertrain" / "ultra_combustionEngineIntegration.lua"
MATERIALS = MOD_DIR / "vehicles" / "common" / "ultra_realism" / "carburetor_models.materials.json"
INFO = MOD_DIR / "mod_info" / "info.json"
ZIP_MAIN = KIT_DIR / "UltraRealismEngine_Prototype.zip"
ZIP_CEEP = KIT_DIR / "patched_mods" / "classic_engine_expansion_pack.zip"
ZIP_FORD = KIT_DIR / "patched_mods" / "Ford_Engine_Pack_JITTERUSA.zip"
PACK_REQUIRED_ASSETS = [
    "vehicles/common/ultra_realism/carburetor_models.dae",
    "vehicles/common/ultra_realism/carburetor_models.materials.json",
    "vehicles/common/ultra_realism/carburetor_visual_manifest.json",
    "ultra_realism_integration.json",
]


def run(cmd: list[str], label: str) -> None:
    result = subprocess.run(cmd, cwd=KIT_DIR, capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"[FAIL] {label}\n{result.stdout}\n{result.stderr}")
    print(f"[OK] {label}")


def check_lua_syntax() -> None:
    for path in (LUA, ULTRA_ENGINE, ULTRA_BRIDGE, ULTRA_INTEGRATION, ULTRA_CLASSIC, ULTRA_STOCK):
        if not path.exists():
            raise SystemExit(f"[FAIL] missing {path}")
        run(["luac", "-p", str(path.relative_to(KIT_DIR))], f"Lua syntax {path.name}")


def check_tests() -> None:
    run(["lua", "scripts/test_carburetor_physics.lua"], "carb physics test")
    run(["lua", "scripts/test_breathing_air_system.lua"], "breathing air system test")
    run(["lua", "scripts/test_ceep_sync.lua"], "CEEP/Ford sync test")
    run(["lua", "scripts/test_ultra_combustion_engine.lua"], "ultra combustion engine test")


def check_materials() -> None:
    data = json.loads(MATERIALS.read_text(encoding="utf-8"))
    for name, material in data.items():
        if material.get("dynamicCubemap"):
            raise SystemExit(f"[FAIL] dynamicCubemap still enabled on {name}")
    print("[OK] materials without dynamicCubemap")


def check_lua_markers() -> None:
    text = LUA.read_text(encoding="utf-8")
    required = [
        "collectActivePartEntries",
        "getInstalledParts",
        "partmgmt.getConfig",
        "v.config.partsTree",
        "getPartData",
        "outputTorqueState",
        "debugLog",
        "diagnosticLog",
        "calcMaxVenturiCapacity",
        "ure_maxVenturiFlowM3s",
        "ure_venturiDemandRatio",
        "engineDamageTorqueCoef",
        "ure_failureTorqueFactor",
        "ure_performanceTorqueFactor",
        "resolveIntegrationMode",
        "restoreNativeEngineTorqueState",
        "publishEngineBridge",
        "ureUltraEngine",
        "integratedFuel",
        "publishEngineBridge",
    ]
    for marker in required:
        if marker not in text:
            raise SystemExit(f"[FAIL] missing Lua marker: {marker}")
    if "for partName, partData in pairs(v.data.activePartsData)" in text:
        raise SystemExit("[FAIL] legacy activePartsData scan still present")
    integration_text = ULTRA_INTEGRATION.read_text(encoding="utf-8")
    for marker in ("resolveTorqueCoef", "computeSpentEnergy", "integratedFuel"):
        if marker not in integration_text:
            raise SystemExit(f"[FAIL] missing integration marker: {marker}")
    classic_text = ULTRA_CLASSIC.read_text(encoding="utf-8")
    if "ureIntegration.resolveTorqueCoef" not in classic_text:
        raise SystemExit("[FAIL] classic fork missing torque integration")
    if "ureIntegration.computeSpentEnergy" not in classic_text:
        raise SystemExit("[FAIL] classic fork missing fuel integration")
    print("[OK] Lua active-part and venturi markers")


def check_version() -> None:
    info = json.loads(INFO.read_text(encoding="utf-8"))
    version = info.get("version", "")
    if version != "0.16.0":
        raise SystemExit(f"[FAIL] unexpected version {version}")
    print(f"[OK] version {version}")


def check_zip(path: Path, required: list[str]) -> None:
    if not path.exists():
        raise SystemExit(f"[FAIL] missing zip {path}")
    with zipfile.ZipFile(path) as zf:
        names = set(zf.namelist())
        bad_entry = zf.testzip()
        if bad_entry:
            raise SystemExit(f"[FAIL] corrupt entry {bad_entry} in {path.name}")
        for item in required:
            if item not in names:
                raise SystemExit(f"[FAIL] {path.name} missing {item}")
    print(f"[OK] zip {path.name}")


def check_pack_integration(path: Path, expected_mode: str) -> None:
    controller_hits = 0
    ultra_engine_hits = 0
    profile_hits = 0
    with zipfile.ZipFile(path) as zf:
        for name in zf.namelist():
            if not name.lower().endswith(".jbeam"):
                continue
            text = zf.read(name).decode("utf-8", errors="replace")
            if '"ultraRealismEngine"' not in text:
                continue
            controller_hits += 1
            compact = text.replace(" ", "")
            if f'"integrationMode":"{expected_mode}"' not in compact:
                raise SystemExit(
                    f"[FAIL] {path.name} controller in {name} missing integrationMode {expected_mode}"
                )
            if '["ultra_combustionEngine","mainEngine"' in compact:
                ultra_engine_hits += 1
            if f'"ureEngineProfile":"{expected_mode}"' in compact:
                profile_hits += 1
    if controller_hits == 0:
        raise SystemExit(f"[FAIL] {path.name} has no ultraRealismEngine controller hooks")
    if ultra_engine_hits == 0:
        raise SystemExit(f"[FAIL] {path.name} has no ultra_combustionEngine powertrain hooks")
    if profile_hits < ultra_engine_hits:
        raise SystemExit(f"[FAIL] {path.name} missing ureEngineProfile={expected_mode} on some engines")
    print(
        f"[OK] {path.name} integrationMode={expected_mode} controllers={controller_hits} "
        f"ultraEngine={ultra_engine_hits}"
    )


def pack_materials_need_patch(path: Path) -> bool:
    target = "vehicles/common/ultra_realism/carburetor_models.materials.json"
    with zipfile.ZipFile(path) as zf:
        if target not in zf.namelist():
            return True
        data = json.loads(zf.read(target).decode("utf-8"))
    for material in data.values():
        if material.get("dynamicCubemap"):
            return True
    return False


def patch_materials_in_zip(path: Path) -> None:
    if not pack_materials_need_patch(path):
        print(f"[OK] materials already current in {path.name}")
        return
    target = "vehicles/common/ultra_realism/carburetor_models.materials.json"
    payload = MATERIALS.read_bytes()
    temp = path.with_suffix(".zip.tmp")
    with zipfile.ZipFile(path, "r") as zin, zipfile.ZipFile(
        temp, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6
    ) as zout:
        for info in zin.infolist():
            data = payload if info.filename == target else zin.read(info.filename)
            new_info = zipfile.ZipInfo(filename=info.filename, date_time=info.date_time)
            new_info.compress_type = zipfile.ZIP_DEFLATED
            new_info.external_attr = info.external_attr
            zout.writestr(new_info, data)
    bad_entry = zipfile.ZipFile(temp).testzip()
    if bad_entry:
        temp.unlink(missing_ok=True)
        raise SystemExit(f"[FAIL] patched zip corrupt: {path.name}")
    temp.replace(path)
    print(f"[OK] patched materials in {path.name}")


def main() -> None:
    passes = int(sys.argv[1]) if len(sys.argv) > 1 else 5
    for index in range(1, passes + 1):
        print(f"\n=== Validation pass {index}/{passes} ===")
        check_lua_syntax()
        check_lua_markers()
        check_materials()
        check_version()
        check_tests()
        if ZIP_MAIN.exists():
            check_zip(
                ZIP_MAIN,
                [
                    "lua/vehicle/controller/ultraRealismEngine.lua",
                    "lua/vehicle/powertrain/ultra_combustionEngine.lua",
                    "lua/vehicle/powertrain/ultraRealismEngineBridge.lua",
                    "lua/vehicle/powertrain/ultra_combustionEngineIntegration.lua",
                    "lua/vehicle/powertrain/ultra_classic_combustionEngine.lua",
                    "lua/vehicle/powertrain/ultra_stock_combustionEngine.lua",
                    "vehicles/common/ultra_realism/carburetor_models.materials.json",
                    "mod_info/info.json",
                ],
            )
        if index == 1:
            for pack in (ZIP_CEEP, ZIP_FORD):
                if pack.exists():
                    patch_materials_in_zip(pack)
        for pack, mode in ((ZIP_CEEP, "ceep"), (ZIP_FORD, "ford")):
            if pack.exists():
                check_zip(pack, PACK_REQUIRED_ASSETS)
                if index == 1:
                    check_pack_integration(pack, mode)
        if index == 1 and (not ZIP_CEEP.exists() or not ZIP_FORD.exists()):
            raise SystemExit(
                "[FAIL] patched CEEP/Ford ZIPs required for release validation "
                "(run scripts/integrar_packs_motores.py)"
            )
    print(f"\n[OK] Completed {passes} validation passes")


if __name__ == "__main__":
    main()