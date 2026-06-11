#!/usr/bin/env bash
# Instala Ultra Realism Engine v0.21.1 + packs CEEP/Ford já patchados.
# Uso:
#   ./scripts/instalar_tudo.sh                 # usa ZIPs locais ou baixa da release
#   ./scripts/instalar_tudo.sh --download      # força download do GitHub
#   ./scripts/instalar_tudo.sh --all-targets   # instala em todos os mods/repo detectados
#   ./scripts/instalar_tudo.sh --mods-dir "$HOME/Documents/BeamNG.drive/mods/repo"
set -euo pipefail

REPO="pescadordegoiaba/beamng-ultra-realism-engine"
TAG="v0.21.1"
URE_VERSION="0.21.1"
BEAMNG_MIN="0.36.0"
BEAMNG_TESTED="0.38.3.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DOWNLOAD_DIR="${KIT_DIR}/downloads/${TAG}"
CACHE_DIR="${KIT_DIR}/patched_mods"

MODS=(
  "UltraRealismEngine_Prototype.zip"
  "classic_engine_expansion_pack.zip"
  "Ford_Engine_Pack_JITTERUSA.zip"
)

DOWNLOAD=0
ALL_TARGETS=0
AUTO=0
MODS_DIR=""
BEAMNG_USER_DIR=""

usage() {
  cat <<EOF
Ultra Realism Engine — instalador completo (${TAG})

Compatível com BeamNG.drive ${BEAMNG_MIN}+ (testado em ${BEAMNG_TESTED}).

Opções:
  --download         Baixa os 3 ZIPs da release GitHub ${TAG}
  --all-targets      Copia para todos os mods/repo detectados (Linux + Heroic/Wine)
  --auto             Usa o alvo BeamNG mais recente
  --mods-dir PATH    Pasta mods/repo de destino
  --beamng-user-dir  Pasta current/0.xx do BeamNG (ex.: .../BeamNG.drive/current)
  -h, --help         Mostra esta ajuda

Exemplos:
  ./scripts/instalar_tudo.sh --download --all-targets
  ./scripts/instalar_tudo.sh --mods-dir "\$HOME/.local/share/BeamNG/BeamNG.drive/current/mods/repo"

Após instalar:
  1. Desative CEEP/Ford ORIGINAIS no Mod Manager (use só os patchados).
  2. Ative os 3 ZIPs instalados.
  3. Reload Mods ou reinicie o jogo.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --download) DOWNLOAD=1 ;;
    --all-targets) ALL_TARGETS=1 ;;
    --auto) AUTO=1 ;;
    --mods-dir) MODS_DIR="${2:-}"; shift ;;
    --beamng-user-dir) BEAMNG_USER_DIR="${2:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[ERRO] Opção desconhecida: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[ERRO] Comando obrigatório ausente: $1" >&2
    exit 1
  }
}

resolve_local_zip() {
  local name="$1"
  for base in "$CACHE_DIR" "$DOWNLOAD_DIR" "$KIT_DIR"; do
    if [[ -f "${base}/${name}" ]]; then
      printf '%s\n' "${base}/${name}"
      return 0
    fi
  done
  return 1
}

download_release_asset() {
  local name="$1"
  mkdir -p "$DOWNLOAD_DIR"
  local dest="${DOWNLOAD_DIR}/${name}"
  if [[ -f "$dest" ]]; then
    echo "[OK] Já baixado: $dest"
    return 0
  fi
  need_cmd gh
  echo "[+] Baixando ${name} da release ${TAG}..."
  gh release download "$TAG" \
    --repo "$REPO" \
    --pattern "$name" \
    --dir "$DOWNLOAD_DIR" \
    --clobber
  [[ -f "$dest" ]] || {
    echo "[ERRO] Download falhou: $dest" >&2
    exit 1
  }
}

collect_zip_paths() {
  ZIP_PATHS=()
  local name path
  for name in "${MODS[@]}"; do
    if [[ "$DOWNLOAD" -eq 1 ]]; then
      download_release_asset "$name"
      path="${DOWNLOAD_DIR}/${name}"
    elif path="$(resolve_local_zip "$name" || true)" && [[ -n "${path:-}" ]]; then
      :
    else
      echo "[ERRO] ZIP não encontrado: $name" >&2
      echo "       Execute com --download ou gere localmente:" >&2
      echo "       python3 scripts/gerar_zip_mod.py" >&2
      echo "       python3 scripts/integrar_packs_motores.py --ceep ... --ford ..." >&2
      exit 1
    fi
    ZIP_PATHS+=("$path")
    echo "[OK] Usando: $path"
  done
}

install_with_python() {
  local args=(python3 "$SCRIPT_DIR/instalar_mod_beamng.py")
  local zip
  for zip in "${ZIP_PATHS[@]}"; do
    args+=(--zip "$zip")
  done
  if [[ -n "$MODS_DIR" ]]; then
    args+=(--mods-dir "$MODS_DIR")
  elif [[ "$ALL_TARGETS" -eq 1 ]]; then
    args+=(--all-targets)
  elif [[ -n "$BEAMNG_USER_DIR" ]]; then
    args+=(--beamng-user-dir "$BEAMNG_USER_DIR" --repo)
  elif [[ "$AUTO" -eq 1 ]]; then
    args+=(--auto --repo)
  else
    args+=(--all-targets)
  fi
  "${args[@]}"
}

echo "=== Ultra Realism Engine ${URE_VERSION} (${TAG}) ==="
echo "BeamNG.drive compatível: ${BEAMNG_MIN}+ (testado em ${BEAMNG_TESTED})"
echo

collect_zip_paths
install_with_python

cat <<EOF

[OK] Instalação concluída.

Checklist no jogo:
  • Desative classic_engine_expansion_pack ORIGINAL (fórum CEEP/JΛVI)
  • Desative Ford_Engine_Pack ORIGINAL (fórum JITTERUSA)
  • Mantenha ativos apenas:
      - UltraRealismEngine_Prototype.zip
      - classic_engine_expansion_pack.zip (patchado URE)
      - Ford_Engine_Pack_JITTERUSA.zip (patchado URE)
  • Repository → Reload Mods

Documentação: https://github.com/${REPO}/releases/tag/${TAG}
EOF