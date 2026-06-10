#!/usr/bin/env python3
"""Reaplica ultra_combustionEngine nos ZIPs patched já existentes."""
from __future__ import annotations

import re
import zipfile
from pathlib import Path

from integrar_packs_motores import patch_ultra_powertrain

KIT_DIR = Path(__file__).resolve().parent.parent
PACKS = [
    (KIT_DIR / "patched_mods" / "classic_engine_expansion_pack.zip", "ceep"),
    (KIT_DIR / "patched_mods" / "Ford_Engine_Pack_JITTERUSA.zip", "ford"),
]


def repatch_zip(path: Path, pack_mode: str) -> dict:
    if not path.exists():
        raise SystemExit(f"[ERRO] ZIP ausente: {path}")

    temp = path.with_suffix(".zip.tmp")
    engines = 0
    files = 0
    with zipfile.ZipFile(path, "r") as zin, zipfile.ZipFile(
        temp, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6
    ) as zout:
        for info in zin.infolist():
            data = zin.read(info.filename)
            if info.filename.lower().endswith(".jbeam"):
                text = data.decode("utf-8", errors="replace")
                patched, rows, _ = patch_ultra_powertrain(text, pack_mode)
                if patched != text:
                    data = patched.encode("utf-8")
                    files += 1
                    engines += rows
            new_info = zipfile.ZipInfo(filename=info.filename, date_time=info.date_time)
            new_info.compress_type = zipfile.ZIP_DEFLATED
            new_info.external_attr = info.external_attr
            zout.writestr(new_info, data)

    bad = zipfile.ZipFile(temp).testzip()
    if bad:
        temp.unlink(missing_ok=True)
        raise SystemExit(f"[ERRO] ZIP corrompido: {path.name}")
    temp.replace(path)
    return {"files": files, "engines": engines}


def main() -> None:
    for path, mode in PACKS:
        result = repatch_zip(path, mode)
        print(
            f"[OK] {path.name}: {result['engines']} motores -> ultra_combustionEngine, "
            f"{result['files']} arquivos JBeam"
        )


if __name__ == "__main__":
    main()