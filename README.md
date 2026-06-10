# Ultra Realism Engine — BeamNG.drive Modkit

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Camada **experimental** de simulação mecânica para motores a combustão no [BeamNG.drive](https://www.beamng.com/game/): carburador (Venturi, CFM, mistura), injeção, clima, ignição, falhas progressivas e integração nativa com os packs **[CEEP] Classic Engine Expansion Pack** (JΛVI) e **Ford Engine Pack JITTERUSA**.

> **Estado: protótipo — ainda não é um mod “funcional” no sentido de produto acabado.**  
> Veja a seção [Por que ainda não funciona de verdade](#por-que-ainda-não-funciona-de-verdade).

Documentação detalhada em português: [README_PT-BR.md](README_PT-BR.md)  
Créditos e licenças de terceiros: [CREDITS.md](CREDITS.md)

---

## O que há neste repositório (source completa)

| Caminho | Conteúdo |
|---------|----------|
| `UltraRealismEngine_Prototype/` | Mod instalável: controller Lua, JBeam (40 carburadores + peças), assets Collada |
| `scripts/` | Build, validação, testes offline, integração CEEP/Ford, instalador |
| `assets_sources/` | OBJs de carburador do autor + scan Artec legado (CC BY, não usado no build) |
| `jbeam_snippets/` | Snippet manual para patch em outros veículos |
| `patched_mods/` | **Somente README** — ZIPs patchados de CEEP/Ford não são redistribuídos |

**Não versionado:** `UltraRealismEngine_Prototype.zip`, `patched_mods/*.zip` (gerados localmente).

---

## Build rápido

Requisitos: Python 3, Lua, Blender (para regenerar `carburetor_models.dae`).

```bash
git clone https://github.com/pescadordegoiaba/beamng-ultra-realism-engine.git
cd beamng-ultra-realism-engine

# 1) Gerar ZIP do mod principal
python3 scripts/gerar_zip_mod.py

# 2) Validar (Lua, física offline, integridade)
python3 scripts/validar_projeto.py 1

# 3) Patch CEEP/Ford (obrigatório para integração nativa)
python3 scripts/integrar_packs_motores.py \
  --ceep /caminho/classic_engine_expansion_pack.zip \
  --ford /caminho/Ford_Engine_Pack_JITTERUSA.zip

# 4) Instalar os 3 ZIPs (main + packs patchados; detecta Linux + Heroic/Wine)
python3 scripts/instalar_mod_beamng.py --all-targets --with-packs
```

### Integração CEEP / Ford (obrigatória para uso “completo”)

Sem os packs patchados, o controller **não** aparece na árvore de peças nativa desses motores.

1. Obtenha os mods originais no fórum BeamNG (CEEP — JΛVI; Ford — JITTERUSA) — **apenas como entrada** do script de patch.
2. Siga [patched_mods/README.md](patched_mods/README.md).
3. No jogo, **desative** os ZIPs originais e use **somente** os patchados + `UltraRealismEngine_Prototype.zip`.

---

## Por que ainda não funciona de verdade

Este projeto é honestamente um **protótipo de pesquisa**, não um substituto do motor nativo do BeamNG. O que funciona hoje e o que ainda falha:

### O que já existe (parcialmente)

- Controller auxiliar `ultraRealismEngine.lua` com telemetria `ure_*` e logs `diag` no console.
- Detecção de peças ativas (CEEP/Ford), 40 carburadores com geometria e CFM distintos.
- Diferença mensurável de torque entre 1× / 3× / 4× / 6× em testes offline.
- Aplicação de efeito físico via `outputTorqueState` / `intakeAirDensityCoef`.
- Assets visuais animados (borboleta, slide, linkage) a partir de 8 modelos OBJ do autor.

### Por que ainda é “infuncional” na prática

1. **Motor nativo com hook condicional (`ultra_combustionEngine`)**  
   Nos packs CEEP/Ford patchados, cada `mainEngine` usa `ultra_combustionEngine`, que detecta o perfil (`ceep` / `ford`) e delega ao backend correto (`classic_combustionEngine` ou `combustionEngine`). Fora desses packs, o veículo continua com o motor stock. Ainda não é substituição total do powertrain — o hook aplica torque/stall **dentro** do ciclo nativo via bridge Lua.

2. **Conflito com detecção de stall nativa**  
   O `vehicleController` marca `vehicle.engine.isStalling` quando `outputAV1 < starterMaxAV × 0.8`, independente do flag `stall=0` do nosso `diag`. Reduzir torque para simular restrição de venturi pode fazer o jogo acreditar que o motor morreu, mesmo com mistura saudável.

3. **Calibração de mistura ainda instável**  
   Carburadores grandes (ex.: Holley 4500) podem enriquecer demais no idle/transiente; carburadores nativos CEEP podem parecer “mornos” no torque. É tuning contínuo, não física fechada.

4. **Dependência forte de CEEP/Ford patchados**  
   O ZIP principal sozinho **não** entrega a experiência anunciada. Sem `integrar_packs_motores.py` + mods originais, faltam slots, duplicatas JBeam e referências quebradas (ex.: `ultra_realism_moonhawk_auto_mod was not found` em configs antigas).

5. **Detecção de peças frágil entre veículos**  
   `activeParts`, `partsTree`, `v.data.parts` e sync nativo nem sempre concordam. Um veículo pode cair no perfil genérico 1× mesmo com six-pack selecionado.

6. **Modelos visuais = equivalentes, não réplicas**  
   Os 8 OBJs são famílias fictícias escaladas por bore/venturi JBeam. Nomes comerciais (Weber/Holley/…) são rótulos de tuning, não scans de fábrica.

7. **Suspensão / fadiga / dano = telemetria primeiro**  
   Efeito em beams de suspensão só ocorre se o JBeam do carro expuser amortecedores identificáveis; muitos veículos só ganham gauges, não física nova.

8. **Sem UI de tuning in-game**  
   Parâmetros vivem no Lua/JBeam gerado; não há app, sliders nem documentação in-game para o jogador final.

### Resumo

| Expectativa do jogador | Realidade hoje |
|------------------------|----------------|
| “Motor novo no BeamNG” | Overlay de torque + telemetria |
| “Cada carburador sente diferente” | Sim em WOT/testes; no idle ainda inconsistente |
| “Instalo e funciona em qualquer carro” | Precisa CEEP/Ford patchados + config correta |
| “Pronto para publicar no Repo” | **Não** — protótipo para desenvolvedores |

---

## Testes offline

```bash
lua scripts/test_carburetor_physics.lua   # 1× vs 6× venturi/torque
lua scripts/test_ceep_sync.lua            # sync de peças CEEP/Ford
```

---

## Telemetria in-game

No console Lua do veículo:

```lua
dump(electrics.values)  -- procure chaves ure_*
```

Log automático a cada ~5 s (se `diagnosticLog` ativo):

```text
UltraRealismEngine|diag parts=... carb=... torque=... afr=... demand=... cfm=...
```

---

## Estrutura de versão

Versão canônica: `UltraRealismEngine_Prototype/mod_info/info.json` (atualmente **0.14.12**).

---

## Contribuir

Issues e PRs são bem-vindos. Ao contribuir:

- Mantenha `scripts/validar_projeto.py` passando.
- Não commite ZIPs de mods de terceiros (CEEP/Ford).
- Atualize [CREDITS.md](CREDITS.md) se adicionar assets externos.

---

## Licença

Código original: [MIT](LICENSE).  
Terceiros: [CREDITS.md](CREDITS.md).