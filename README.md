# Ultra Realism Engine — BeamNG.drive Modkit

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.15.3-blue.svg)](UltraRealismEngine_Prototype/mod_info/info.json)

Camada de simulação mecânica para motores a combustão no [BeamNG.drive](https://www.beamng.com/game/): carburador (Venturi, CFM, mistura), injeção, clima, ignição, falhas progressivas e integração nativa com os packs **[CEEP] Classic Engine Expansion Pack** (JΛVI) e **Ford Engine Pack JITTERUSA**.

> **Estado: protótipo avançado (v0.15.3)** — motor CEEP/Ford com fork completo, física de carburador aplicada via `outputTorqueState`, combustível integrado (AFR/`spentEnergy`). Ainda não é produto final: UI de stall nativa, tuning fino e dependência dos packs patchados permanecem.

**Documentação**

| Documento | Conteúdo |
|-----------|----------|
| [README_PT-BR.md](README_PT-BR.md) | Guia completo em português (peças, instalação, telemetria) |
| [RESUMO_SESSAO_E_ENGENHARIA_REVERSA.md](RESUMO_SESSAO_E_ENGENHARIA_REVERSA.md) | Resumo da sessão de debug + engenharia reversa BeamNG/URE |
| [REVERSE_ENGINEERING.md](REVERSE_ENGINEERING.md) | Notas técnicas do loop physics/GFX (complementar) |
| [CREDITS.md](CREDITS.md) | Licenças e terceiros |
| [patched_mods/README.md](patched_mods/README.md) | Como patchar CEEP/Ford localmente |

---

## Novidades v0.15.x

| Versão | Destaque |
|--------|----------|
| **0.15.3** | Diferenciação real 1× vs 6× carburador (calibração CFM vs cilindrada, blend por déficit de ar) |
| **0.15.2** | Performance: cache do bridge, telemetria 10 Hz, scan de peças a 0,5 s |
| **0.15.1** | Fix crash `getIntegrationMode` no spawn (forward declarations Lua) |
| **0.15.0** | Forks completos `ultra_classic/stock_combustionEngine` com torque + combustível + stall |

---

## O que há neste repositório

| Caminho | Conteúdo |
|---------|----------|
| `UltraRealismEngine_Prototype/` | Mod instalável: controller Lua, forks de motor, JBeam (40 carburadores), assets Collada |
| `scripts/` | Build, validação, testes offline, integração CEEP/Ford, instalador |
| `assets_sources/` | OBJs de carburador do autor (8 famílias visuais) |
| `jbeam_snippets/` | Snippet manual para patch em outros veículos |
| `patched_mods/` | **Somente README** — ZIPs patchados não são redistribuídos |

**Não versionado:** `UltraRealismEngine_Prototype.zip`, `patched_mods/*.zip` (gerados localmente).

---

## Arquitetura (v0.15.3)

```
Peças JBeam (CEEP/Ford patchados + ultra_realism_tuning.jbeam)
        ↓
ultraRealismEngine.lua (controller, order 6500)
  • restrição venturi/CFM, AFR, clima, torque
  • publishEngineBridge → ultraRealismEngineBridge
  • engine.outputTorqueState
        ↓
ultra_combustionEngine.lua (roteador)
  → ultra_classic_combustionEngine (CEEP)
  → ultra_stock_combustionEngine (Ford/stock)
        ↓
ultra_combustionEngineIntegration.lua
  • resolveTorqueCoef, computeSpentEnergy, postStallGuard
```

---

## Build rápido

Requisitos: Python 3, Lua, Blender (opcional, para `carburetor_models.dae`).

```bash
git clone https://github.com/pescadordegoiaba/beamng-ultra-realism-engine.git
cd beamng-ultra-realism-engine

python3 scripts/gerar_zip_mod.py
python3 scripts/validar_projeto.py 1

# Patch CEEP/Ford (obrigatório para integração nativa)
python3 scripts/integrar_packs_motores.py \
  --ceep /caminho/classic_engine_expansion_pack.zip \
  --ford /caminho/Ford_Engine_Pack_JITTERUSA.zip

python3 scripts/instalar_mod_beamng.py --all-targets --with-packs
```

### Integração CEEP / Ford

Sem os packs **patchados**, o controller não aparece na árvore de peças nativa desses motores e o fork de motor não é usado.

1. Obtenha os mods originais no fórum BeamNG (CEEP — JΛVI; Ford — JITTERUSA).
2. Siga [patched_mods/README.md](patched_mods/README.md).
3. No jogo: **desative** ZIPs originais; use **somente** patchados + `UltraRealismEngine_Prototype.zip`.
4. **Reload Mods** após atualizar.

---

## O que funciona hoje

- Spawn estável com motor CEEP/Ford (crash Lua corrigido em v0.15.1).
- Performance jogável em v0.15.2+ (sem `rerequire` por substep, telemetria throttled).
- **40 carburadores** com geometria, CFM e contagem (1× / 2× / 3× / 4× / 6×) distintos.
- Diferença de torque **~12–15%** entre 1× e 6× em motor ~4.4 L (teste offline e Moonhawk in-game após v0.15.3).
- Torque real via `outputTorqueState` + fork `resolveTorqueCoef`.
- Combustível integrado: `spentEnergy` segue AFR/lambda do controller quando `ureUltraEngine=true`.
- Telemetria `ure_*`, logs `diag` (opcional), assets visuais animados (8 OBJs do autor).
- Detecção automática: cilindrada, idle/redline, modo carb/EFI, peças CEEP/Ford.

## Limitações conhecidas

| Área | Situação |
|------|----------|
| Mensagem UI `vehicle.engine.isStalling` | Pode aparecer com mistura saudável; URE mitiga via `postStallGuard`, não remove `guihooks` |
| Packs obrigatórios | CEEP/Ford patchados + ZIP principal |
| Duplicatas JBeam | Conflitos com outros mods (tires, oilpan CEEP) — avisos no log |
| Idle / transientes | Tuning de mistura ainda em evolução |
| UI in-game | Sem app de tuning; parâmetros no JBeam/Lua |
| Produto final | Protótipo para desenvolvedores e entusiastas, não substituto OEM completo |

Detalhes: [RESUMO_SESSAO_E_ENGENHARIA_REVERSA.md](RESUMO_SESSAO_E_ENGENHARIA_REVERSA.md) §9.

---

## Testes offline

```bash
lua scripts/test_carburetor_physics.lua      # 1× vs 6× venturi/torque/blend
lua scripts/test_ceep_sync.lua               # sync peças CEEP/Ford
lua scripts/test_ultra_combustion_engine.lua # bridge, fork, cache
```

---

## Telemetria in-game

```lua
dump(electrics.values)  -- chaves ure_*
```

Log `diag` (ativar `diagnosticLog: true` no JBeam — **desligado por default** em v0.15.2+):

```text
UltraRealismEngine|diag parts=... carb=... torque=... blend=... flow=... demand=... cfm=...
```

**Dica:** compare logs em **WOT alto RPM**, não em idle (`blend≈0` no idle é intencional).

Parâmetros de tuning no controller:

```json
"carbFlowCalibrationCoef": 0.82,
"multiCarbFlowBonus": 1.06,
"telemetryInterval": 0.1,
"debugLog": false,
"diagnosticLog": false
```

---

## Versão

Canônica: `UltraRealismEngine_Prototype/mod_info/info.json` → **0.15.3**

---

## Contribuir

Issues e PRs são bem-vindos.

- Mantenha `scripts/validar_projeto.py` passando.
- Não commite ZIPs de mods de terceiros (CEEP/Ford).
- Atualize [CREDITS.md](CREDITS.md) se adicionar assets externos.

---

## Licença

Código original: [MIT](LICENSE). Terceiros: [CREDITS.md](CREDITS.md).