#!/usr/bin/env python3
"""
Gera o ZIP instalável do mod a partir da pasta UltraRealismEngine_Prototype.

Uso:
  cd ~/Downloads/beamng_super_realism_modkit
  python3 scripts/gerar_zip_mod.py
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

KIT_DIR = Path(__file__).resolve().parent.parent
SRC = KIT_DIR / "UltraRealismEngine_Prototype"
OUT = KIT_DIR / "UltraRealismEngine_Prototype.zip"
GENERATOR = KIT_DIR / "scripts" / "gerar_jbeam_variantes.py"
MODEL_GENERATOR = KIT_DIR / "scripts" / "gerar_modelos_carburadores_usuario.py"
MODEL_ASSET = SRC / "vehicles" / "common" / "ultra_realism" / "carburetor_models.dae"

if not SRC.exists():
    raise SystemExit(f"[ERRO] Pasta fonte não encontrada: {SRC}")

blender = shutil.which("blender")
if MODEL_GENERATOR.exists() and blender:
    subprocess.run(
        [blender, "--background", "--python", str(MODEL_GENERATOR)],
        check=True,
    )
elif not MODEL_ASSET.exists():
    raise SystemExit(
        "[ERRO] Blender nao encontrado e o asset Collada ainda nao existe. "
        "Instale o Blender ou gere carburetor_models.dae em outra maquina."
    )

FORK_SCRIPT = KIT_DIR / "scripts" / "fork_combustion_engines.py"
if FORK_SCRIPT.exists():
    subprocess.run([sys.executable, str(FORK_SCRIPT)], check=True)

if GENERATOR.exists():
    subprocess.run([sys.executable, str(GENERATOR)], check=True)

if OUT.exists():
    OUT.unlink()

with ZipFile(OUT, "w", ZIP_DEFLATED) as zf:
    for path in SRC.rglob("*"):
        if path.is_file():
            arc = path.relative_to(SRC)
            zf.write(path, arc.as_posix())
            print(f"[+] {arc.as_posix()}")
print(f"[OK] ZIP gerado: {OUT}")
