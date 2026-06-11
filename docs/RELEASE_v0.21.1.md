# Release v0.21.1 — Ultra Realism Engine

**Data:** 2026-06-10  
**BeamNG.drive:** `0.36.0+` (testado em `0.38.3.0`)

## Publicar esta release (mantenedor)

Se os ZIPs já estão compilados localmente:

```bash
./scripts/publicar_release.sh
```

Isso cria/atualiza a release `v0.21.1` no GitHub com os 3 assets. Requer `gh auth login`.

## Downloads

| Arquivo | Descrição | Tamanho aprox. |
|---------|-----------|----------------|
| `UltraRealismEngine_Prototype.zip` | Mod principal URE | ~3 MB |
| `classic_engine_expansion_pack.zip` | CEEP patchado com integração nativa URE | ~475 MB |
| `Ford_Engine_Pack_JITTERUSA.zip` | Ford Engine Pack patchado com integração nativa URE | ~299 MB |

> **Aviso legal:** os ZIPs CEEP e Ford desta release são **obras derivadas patchadas**. Você deve possuir legalmente os mods originais no [BeamNG resources](https://www.beamng.com/resources/) antes de usar os arquivos patchados. Não deixe original + patchado ativos ao mesmo tempo.

## Instalação rápida

### Linux / Heroic (script completo)

```bash
git clone https://github.com/pescadordegoiaba/beamng-ultra-realism-engine.git
cd beamng-ultra-realism-engine
chmod +x scripts/instalar_tudo.sh
./scripts/instalar_tudo.sh --download --all-targets
```

### Windows (PowerShell)

```powershell
git clone https://github.com/pescadordegoiaba/beamng-ultra-realism-engine.git
cd beamng-ultra-realism-engine
gh release download v0.21.1 --repo pescadordegoiaba/beamng-ultra-realism-engine --dir downloads/v0.21.1
# Copie os 3 ZIPs para:
#   %LOCALAPPDATA%\BeamNG.drive\current\mods\repo\
```

### Python (alternativa)

```bash
python3 scripts/instalar_mod_beamng.py --all-targets --with-packs
```

## O que mudou em v0.21.1

- **Turbo i4 flathead CEEP** habilitado (slot + manifold TC mínimo)
- **Forced induction** melhor detectado (turbo/supercharger → throttle body, não carburador clonado)
- **Performance:** cache de scan de peças, `partsSyncInterval` mínimo 0,5 s
- **Short block:** slots URE só no owner canônico `_stock` (menos lag ao abrir Bottom End)
- **Defaults:** `debugLog`/`diagnosticLog` desligados; CEEP com `preferCarburetor: true`

## Histórico recente

| Versão | Destaque |
|--------|----------|
| **0.21.1** | Fix CEEP turbo/carburador, performance short block, i4 turbo |
| **0.21.0** | Roadmap A–F: ownership, partCurves, bus, induction EFI/diesel, hooks |
| **0.15.3** | Diferenciação 1× vs 6× carburador, blend por déficit de ar |

## Verificação pós-instalação

1. Mod Manager: 3 ZIPs ativos, CEEP/Ford **originais desativados**
2. Spawn Moonhawk / pickup i4 flathead CEEP
3. Console Lua: `print(electrics.values.ure_partsScanCount)` — deve permanecer baixo
4. Log de spawn: `controller initialized v0.21.1`