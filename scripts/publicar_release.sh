#!/usr/bin/env bash
# Publica a release GitHub com os 3 ZIPs já compilados.
# Pré-requisitos: gh auth login, ZIPs gerados localmente.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO="pescadordegoiaba/beamng-ultra-realism-engine"
TAG="v0.21.1"

MAIN_ZIP="${KIT_DIR}/UltraRealismEngine_Prototype.zip"
CEEP_ZIP="${KIT_DIR}/patched_mods/classic_engine_expansion_pack.zip"
FORD_ZIP="${KIT_DIR}/patched_mods/Ford_Engine_Pack_JITTERUSA.zip"
NOTES="${KIT_DIR}/docs/RELEASE_v0.21.1.md"

for f in "$MAIN_ZIP" "$CEEP_ZIP" "$FORD_ZIP" "$NOTES"; do
  [[ -f "$f" ]] || { echo "[ERRO] Arquivo ausente: $f" >&2; exit 1; }
done

command -v gh >/dev/null || { echo "[ERRO] Instale GitHub CLI (gh)" >&2; exit 1; }

echo "[+] Verificando release ${TAG}..."
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "[+] Release existe — atualizando assets..."
  gh release upload "$TAG" --repo "$REPO" --clobber \
    "$MAIN_ZIP" "$CEEP_ZIP" "$FORD_ZIP"
else
  echo "[+] Criando release ${TAG}..."
  gh release create "$TAG" \
    --repo "$REPO" \
    --title "Ultra Realism Engine ${TAG}" \
    --notes-file "$NOTES" \
    "$MAIN_ZIP" "$CEEP_ZIP" "$FORD_ZIP"
fi

echo "[OK] Release publicada: https://github.com/${REPO}/releases/tag/${TAG}"