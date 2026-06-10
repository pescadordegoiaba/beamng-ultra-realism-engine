#!/usr/bin/env python3
"""
Instala ZIPs do Ultra Realism na pasta mods/repo do BeamNG.drive.

Uso:
  python3 instalar_mod_beamng.py --all-targets
  python3 instalar_mod_beamng.py --beamng-user-dir "$HOME/Games/Heroic/Prefixes/default/drive_c/users/steamuser/AppData/Local/BeamNG/BeamNG.drive/current" --repo
"""
from __future__ import annotations

import argparse
import shutil
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
KIT_DIR = SCRIPT_DIR.parent
DEFAULT_ZIP = KIT_DIR / "UltraRealismEngine_Prototype.zip"
DEFAULT_PACKS = [
    KIT_DIR / "patched_mods" / "classic_engine_expansion_pack.zip",
    KIT_DIR / "patched_mods" / "Ford_Engine_Pack_JITTERUSA.zip",
]


def heroic_user_roots(home: Path) -> list[Path]:
    heroic_users = home / "Games/Heroic/Prefixes/default/drive_c/users"
    if not heroic_users.exists():
        return []
    return [heroic_users / name / "AppData/Local/BeamNG/BeamNG.drive" for name in heroic_users.iterdir() if name.is_dir()]


def beamng_roots() -> list[Path]:
    home = Path.home()
    roots = [
        home / ".local/share/BeamNG/BeamNG.drive",
        home / ".local/share/BeamNG.drive",
        home / "Documents/BeamNG.drive",
        home / "AppData/Local/BeamNG.drive",
        home / f"Games/Heroic/Prefixes/default/drive_c/users/{home.name}/AppData/Local/BeamNG/BeamNG.drive",
    ]
    roots.extend(heroic_user_roots(home))
    return [root for root in roots if root.exists()]


def user_dirs() -> list[Path]:
    found: list[Path] = []
    for root in beamng_roots():
        for child in root.iterdir():
            if child.is_dir() and (child.name.startswith("0.") or child.name.lower() in {"current", "latest"}):
                found.append(child)
        found.append(root)
    unique = sorted(set(found), key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)
    return unique


def repo_dirs() -> list[Path]:
    repos: list[Path] = []
    for user_dir in user_dirs():
        repo = user_dir / "mods" / "repo"
        if repo.exists() or (user_dir / "mods").exists() or user_dir.name in {"current", "latest"} or user_dir.name.startswith("0."):
            repos.append(repo)
    return sorted(set(repos), key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)


def install_zip(zip_path: Path, mods_dir: Path) -> Path:
    mods_dir.mkdir(parents=True, exist_ok=True)
    target = mods_dir / zip_path.name
    shutil.copy2(zip_path, target)
    return target


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--auto", action="store_true", help="instala no alvo mais recente detectado")
    ap.add_argument("--all-targets", action="store_true", help="instala em todos os mods/repo detectados (Linux + Heroic/Wine)")
    ap.add_argument("--beamng-user-dir", type=Path, help="pasta current/0.xx do usuário do BeamNG")
    ap.add_argument("--mods-dir", type=Path, help="pasta mods/repo exata")
    ap.add_argument("--repo", action="store_true", help="usa mods/repo em vez de mods")
    ap.add_argument("--zip", type=Path, action="append", default=[], help="ZIP a copiar (pode repetir)")
    ap.add_argument("--with-packs", action="store_true", help="também copia os packs CEEP/Ford patched")
    args = ap.parse_args()

    zips = [path.expanduser().resolve() for path in (args.zip or [DEFAULT_ZIP])]
    include_packs = args.with_packs or (
        not args.zip and all(path.exists() for path in DEFAULT_PACKS)
    )
    if include_packs:
        zips.extend(path for path in DEFAULT_PACKS if path.exists())
    zips = list(dict.fromkeys(zips))

    missing = [path for path in zips if not path.exists()]
    if missing:
        joined = "\n".join(str(path) for path in missing)
        raise SystemExit(f"[ERRO] ZIP(s) não encontrado(s):\n{joined}\nExecute scripts/gerar_zip_mod.py primeiro.")

    if args.mods_dir:
        targets = [args.mods_dir.expanduser().resolve()]
    elif args.all_targets:
        targets = repo_dirs()
        if not targets:
            raise SystemExit("[ERRO] Nenhum mods/repo detectado.")
        print("[+] Alvos detectados:")
        for target in targets:
            print(f"    - {target}")
    elif args.beamng_user_dir:
        user_dir = args.beamng_user_dir.expanduser().resolve()
        targets = [user_dir / "mods" / ("repo" if args.repo else "")]
    elif args.auto:
        found = user_dirs()
        if not found:
            raise SystemExit("[ERRO] Não achei a pasta do BeamNG. Use --all-targets ou --beamng-user-dir.")
        print("[+] Possíveis pastas encontradas:")
        for index, path in enumerate(found[:8], 1):
            print(f"    {index}. {path}")
        chosen = found[0]
        print(f"[+] Usando: {chosen}")
        targets = [chosen / "mods" / ("repo" if args.repo else "")]
    else:
        raise SystemExit("[ERRO] Use --all-targets, --auto, --beamng-user-dir ou --mods-dir")

    for mods_dir in targets:
        for zip_path in zips:
            target = install_zip(zip_path, mods_dir)
            print(f"[OK] {zip_path.name} -> {target}")

    print("[OK] Reinicie o BeamNG ou use Reload Mods no Mod Manager.")


if __name__ == "__main__":
    main()