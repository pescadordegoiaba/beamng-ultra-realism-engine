#!/usr/bin/env python3
"""
Patch experimental para inserir o controller ultraRealismEngine em um .jbeam existente.

Uso seguro:
  cd ~/Downloads/beamng_super_realism_modkit
  python3 scripts/aplicar_controller_em_jbeam.py --jbeam /caminho/veiculo/arquivo.jbeam --dry-run
  python3 scripts/aplicar_controller_em_jbeam.py --jbeam /caminho/veiculo/arquivo.jbeam

Ele faz backup .bak antes de alterar. Recomendado apenas em mods unpacked/cópias,
não nos arquivos originais do jogo.
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path

CONTROLLER_LINE = '''            ["ultraRealismEngine", {
                "fuelingMode": "auto",
                "autoDetectEngine": true,
                "autoFuelingMode": true,
                "preferCarburetor": false,
                "autoTuneVECurve": true,
                "autoDetectCarbSetup": true,
                "debugLog": true,
                "diagnosticLog": true,
                "climatePreset": "game_environment",
                "useBeamNGEnvironment": true
            }],
'''


def insert_into_controller_block(text: str) -> tuple[str, bool]:
    if '"ultraRealismEngine"' in text:
        return text, False

    m = re.search(r'("controller"\s*:\s*\[\s*\n\s*\["fileName"\]\s*,?\s*\n)', text)
    if m:
        pos = m.end()
        return text[:pos] + CONTROLLER_LINE + text[pos:], True

    # Fallback: tenta inserir uma seção controller após information, se existir.
    m = re.search(r'("slotType"\s*:\s*"[^"]+"\s*,?\s*\n)', text)
    if m:
        pos = m.end()
        block = '''        "controller": [
            ["fileName"],
''' + CONTROLLER_LINE + '''        ],
'''
        return text[:pos] + block + text[pos:], True

    return text, False


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--jbeam", type=Path, required=True)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    path = args.jbeam.expanduser().resolve()
    if not path.exists():
        raise SystemExit(f"[ERRO] Arquivo não encontrado: {path}")

    text = path.read_text(encoding="utf-8", errors="replace")
    new_text, changed = insert_into_controller_block(text)
    if not changed:
        if '"ultraRealismEngine"' in text:
            print("[OK] O controller já existe nesse arquivo.")
        else:
            print("[ERRO] Não encontrei onde inserir. Use o snippet manual em jbeam_snippets/controller_ultra_realism_snippet.jbeam")
        return

    if args.dry_run:
        print("[DRY-RUN] Alteração possível. Nada foi escrito.")
        print("----- trecho inserido -----")
        print(CONTROLLER_LINE)
        return

    backup = path.with_suffix(path.suffix + ".bak")
    backup.write_text(text, encoding="utf-8")
    path.write_text(new_text, encoding="utf-8")
    print(f"[OK] Backup: {backup}")
    print(f"[OK] Controller inserido em: {path}")


if __name__ == "__main__":
    main()
