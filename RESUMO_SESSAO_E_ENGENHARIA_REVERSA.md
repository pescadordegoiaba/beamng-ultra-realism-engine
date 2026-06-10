# Resumo da sessão + Engenharia reversa — Ultra Realism Engine

**Projeto:** [beamng-ultra-realism-engine](https://github.com/pescadordegoiaba/beamng-ultra-realism-engine)  
**Versão final desta sessão:** **0.15.3**  
**Veículo de teste principal:** Bruckell Moonhawk (config *Bandit Speed*) + motor CEEP no mapa West Coast USA  
**Data:** junho de 2026

---

## Índice

1. [Resumo executivo](#1-resumo-executivo)
2. [Cronologia dos problemas e correções](#2-cronologia-dos-problemas-e-correções)
3. [Arquitetura do mod (v0.15.3)](#3-arquitetura-do-mod-v0153)
4. [Engenharia reversa do BeamNG.drive](#4-engenharia-reversa-do-beamngdrive)
5. [Física do carburador e torque](#5-física-do-carburador-e-torque)
6. [Integração CEEP / Ford](#6-integração-ceep--ford)
7. [Pipeline de build e instalação](#7-pipeline-de-build-e-instalação)
8. [Como diagnosticar no jogo](#8-como-diagnosticar-no-jogo)
9. [Limitações conhecidas](#9-limitações-conhecidas)
10. [Referência de arquivos](#10-referência-de-arquivos)

---

## 1. Resumo executivo

Esta sessão partiu de um **crash ao spawnar o Moonhawk** com motor CEEP. O veículo carregava, depois era desabilitado com exceção Lua. Após corrigir o crash, o jogo **travava** (stutter severo). Depois de otimizar performance, o carro rodava fluido, mas a **diferença entre 1 carburador e 6 carburadores era quase inexistente** (~1 mph de velocidade final).

Três releases corrigiram isso em sequência:

| Versão | Problema | Correção principal |
|--------|----------|-------------------|
| **0.15.1** | Crash: `attempt to call global 'getIntegrationMode' (a nil value)` | Forward declarations Lua para funções usadas antes da definição |
| **0.15.2** | Travamento / lag extremo | Cache do bridge, telemetria em 10 Hz, scan de peças a 0,5 s |
| **0.15.3** | 1× vs 6× carburador sem diferença perceptível | Calibração CFM vs demanda do motor, blend por déficit de ar, bônus multi-carb |

**Estado atual esperado:** Moonhawk CEEP spawna sem crash, roda sem travar, e setups 1× vs 6× Weber devem diferir **~12–15% de torque** no alto RPM (equivalente a ~5–10 mph em velocidade final, não 1 mph).

---

## 2. Cronologia dos problemas e correções

### 2.1 Crash no spawn (v0.15.0 → v0.15.1)

**Sintoma no log:**

```
lua/vehicle/controller/ultraRealismEngine.lua:256:
attempt to call global 'getIntegrationMode' (a nil value)
*** DISABLING VEHICLE DUE TO EXCEPTION ***
Error 0 spawning vehicle "moonhawk"
```

**O que funcionava antes do crash:**

- Fork CEEP ativo: `URE fork active profile=ceep backend=powertrain/ultra_classic_combustionEngine`
- Controller inicializava: `controller initialized v0.15.0 (integration=ceep)`
- Detecção automática: `4.38 L, 8 cyl, carb, idle 1350 rpm, redline 6050 rpm`

**Causa raiz (engenharia reversa Lua):**

Em Lua, uma função `local` só existe **depois** da linha onde é declarada. O bloco `publishEngineBridge` (linha ~256) chamava `getIntegrationMode()` e `usesNativePartSync()`, mas essas funções eram declaradas **mais abaixo** no mesmo arquivo. O compilador Lua resolveu as chamadas como **globais** (inexistentes) → `nil`.

O controller chegava a inicializar porque `resolveIntegrationMode()` retorna cedo quando `integrationMode=ceep` sem chamar `getActivePartsText()`. O crash só ocorria no primeiro `updateGFX`, quando `publishEngineBridge` rodava.

**Correção:**

```lua
local resolveIntegrationMode
local getIntegrationMode
local usesNativePartSync
local getActivePartsText
```

E as definições passaram de `local function foo()` para `function foo()` (atribuição à variável local já declarada).

**Commit:** `c2d2a38` — `fix(controller): forward-declare integration helpers to stop Moonhawk crash`

---

### 2.2 Travamento severo (v0.15.1 → v0.15.2)

**Sintoma:** veículo carrega, mas FPS despenca / micro-freezes constantes.

**Causas identificadas (por impacto):**

#### A) `rerequire` a cada substep de física (crítico)

O arquivo `ultra_combustionEngineIntegration.lua` fazia:

```lua
local function getBridge()
  return rerequire("powertrain/ultraRealismEngineBridge")
end
```

Isso era chamado em **cada** `resolveTorqueCoef` e `computeSpentEnergy` dentro de `updateTorque` do motor — milhares de vezes por segundo (física ~2000 Hz). `rerequire` recarrega o módulo Lua repetidamente.

**Correção:** cache após primeiro load:

```lua
local cachedBridge
local function getBridge()
  if cachedBridge then return cachedBridge end
  cachedBridge = rerequire("powertrain/ultraRealismEngineBridge")
  return cachedBridge
end
```

#### B) ~160 `setElectricsValue` por frame

O controller publicava telemetria `ure_*` completa a 60 FPS. Cada escrita em `electrics.values` tem custo no lado GE/UI.

**Correção:**

- **Rápido (todo frame):** ~25 valores críticos (torque, AFR, throttle, falhas)
- **Lento (10 Hz):** restante da telemetria (`telemetryInterval = 0.1`)
- Publicação lenta forçada no 1º frame e quando peças mudam

#### C) Scan de peças todo frame

`syncActivePartsState()` chamava `computeActivePartsSignature()` → `getInstalledParts()` → `partmgmt.getConfig()` em todo `updateGFX`.

**Correção:** `partsSyncInterval = 0.5` s (ou imediato se assinatura mudar).

#### D) Defaults agressivos

- `debugLog` e `diagnosticLog` default `true` → logs periódicos no console
- `enableSuspensionBeamEffects` default `true` → `pcall` em beams de suspensão

**Correção:** defaults `false` para logs e suspensão beam.

**Commit:** `132af66` — `perf(ure): v0.15.2 — cache bridge, throttle telemetry, reduce per-frame cost`

---

### 2.3 Diferença 1× vs 6× carburador imperceptível (v0.15.2 → v0.15.3)

**Sintoma relatado:** quatro tipos de carburador testados na mesma reta WOT; o *six pack* ganhou só **~1 mph** sobre os outros.

**Evidência no log (condição de baixa carga — não WOT pleno):**

```
diag ... torque=0.769 physics=0.998 blend=0.01 applied=0.998
flow=1.000 demand=0.01 cfm=0.00 ... stall=0
carb=ultra_realism_native_ceep_..._six_weber_40_dcoe_32 count=6 barrels=2
```

Interpretação:

| Campo | Valor | Significado |
|-------|-------|-------------|
| `torque=0.769` | Fator físico calculado (restrição + mistura) | Penalidade real existe |
| `blend=0.01` | Quanto da penalidade é aplicada | **Quase zero** |
| `applied=0.998` | Torque efetivo no motor | **Ignora** a penalidade |
| `demand=0.01` | Carga no venturi | Idle / baixa marcha |
| `count=6` | Detecção correta do six pack | OK |

**Três causas combinadas:**

1. **`loadProportionalEngineEffect` usava `venturiDemandRatio`** — em setups grandes (6×), a demanda relativa ao venturi é baixa (`demand=0.08`), então `blend → 0` e o torque volta para ~100% mesmo com `torque` baixo no papel.

2. **Moonhawk 4.38 L + carburador único ~420 CFM** — no limite da demanda do motor no redline. O 6× (2520 CFM) passa fácil; o 1× também passava quase inteiro → diferença de velocidade final mínima.

3. **Nomes CEEP nativos** (`..._40_dcoe_32`) não casavam com os padrões de geometria (`40dcoe`, `40 dcoe`) → venturi inferido errado em alguns casos.

**Correções v0.15.3:**

| Mudança | Parâmetro / lógica | Efeito |
|---------|-------------------|--------|
| Blend por déficit de ar | `flowDeficit = 1 - inductionFlowRatio` no `demandSignal` | Penalidade aplicada quando o ar é cortado |
| Blend por RPM | `rpmLoad * throttle * 0.72` no `demandSignal` | WOT no alto giro ativa o efeito |
| Calibração CFM | `carbFlowCalibrationCoef = 0.82` | CFM efetivo menor → 1× mais “apertado” |
| Restrição parcial | `carbPartialRestrictionStart = 0.55` | Penalidade antes do choke total |
| Sizing ratio | `engineDemandM3s / effectiveRatedM3s` | Compara demanda do motor vs capacidade do carb |
| Bônus multi-carb | `multiCarbFlowBonus = 1.06` quando `sizingRatio < 0.42` e `count >= 2` | 6× respira melhor no topo |
| Parse de nomes | `_40_dcoe`, `_32`, `six_weber`, etc. | Geometria correta para peças CEEP geradas |

**Resultado em teste offline (4.38 L, WOT):**

| RPM | 1× coef | 6× coef | Gap |
|-----|---------|---------|-----|
| 4500 | 0.80 | 0.92 | +12% |
| 6000 | 0.70 | 0.85 | +15% |

**Commit:** `8847ebd` — `fix(carb): v0.15.3 — stronger 1x vs 6x differentiation on street engines`

---

## 3. Arquitetura do mod (v0.15.3)

### 3.1 Visão geral

```
┌─────────────────────────────────────────────────────────────────┐
│  JBeam (peças CEEP/Ford patchadas + ultra_realism_tuning.jbeam) │
│  ultraRealismCarburetor { count, venturi, ratedCFM, ... }       │
└────────────────────────────┬────────────────────────────────────┘
                             │ peças ativas / partmgmt
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  ultraRealismEngine.lua (controller auxiliar, order 6500)       │
│  • detecta carb / comando / clima / peças                      │
│  • calcula AFR, restrição venturi, torqueFactor               │
│  • publica bridge + telemetria ure_*                           │
│  • escreve engine.outputTorqueState                             │
└────────────┬───────────────────────────────┬──────────────────┘
             │ publishEngineBridge            │ outputTorqueState
             ▼                                ▼
┌────────────────────────────┐   ┌────────────────────────────────┐
│ ultraRealismEngineBridge   │   │ ultra_combustionEngine         │
│ estado compartilhado       │◄──│ roteador CEEP/Ford/stock       │
│ torque, fuel, stall        │   │                                │
└────────────┬───────────────┘   └───────────┬────────────────────┘
             │                               │
             │         ┌─────────────────────┴─────────────────────┐
             │         ▼                     ▼                       │
             │  ultra_classic_combustionEngine (CEEP fork)          │
             │  ultra_stock_combustionEngine (Ford/stock fork)      │
             │         │                                             │
             │         ▼                                             │
             │  ultra_combustionEngineIntegration.lua                │
             │  • resolveTorqueCoef(device)                          │
             │  • computeSpentEnergy(device) ← AFR do controller     │
             │  • postStallGuard(device)                             │
             └─────────────────────────────────────────────────────┘
```

### 3.2 Módulos principais

| Arquivo | Papel |
|---------|-------|
| `lua/vehicle/controller/ultraRealismEngine.lua` | Cérebro: física carb, clima, torque, telemetria |
| `lua/vehicle/powertrain/ultra_combustionEngine.lua` | Roteador: CEEP → classic fork, Ford → stock fork |
| `lua/vehicle/powertrain/ultra_classic_combustionEngine.lua` | Fork ~101 KB do `classic_combustionEngine` CEEP |
| `lua/vehicle/powertrain/ultra_stock_combustionEngine.lua` | Fork ~95 KB do `combustionEngine` vanilla |
| `lua/vehicle/powertrain/ultra_combustionEngineIntegration.lua` | Ponte controller ↔ motor (torque, combustível, stall) |
| `lua/vehicle/powertrain/ultraRealismEngineBridge.lua` | Estado compartilhado em memória (evita reler electrics) |
| `vehicles/common/ultra_realism/ultra_realism_tuning.jbeam` | 40 carburadores + peças comuns |
| `scripts/fork_combustion_engines.py` | Gera forks com patches em torque/fuel/stall |
| `scripts/integrar_packs_motores.py` | Injeta controller + `ultra_combustionEngine` nos ZIPs CEEP/Ford |

### 3.3 Fluxo de dados por frame

**GFX (60 Hz) — controller:**

1. `syncActivePartsState` (a cada 0,5 s ou se peças mudarem)
2. `detectCarbSetupFromParts` / `analyzeEngineParts` (se necessário)
3. Ler RPM, throttle, clima
4. `calcEngineAirMassFlow` → demanda de ar do motor
5. `applyCarbAirRestriction` → ar entregue após venturi/CFM
6. `calcFuelCarb` → AFR, lambda, combustível
7. Calcular `performanceFactor` (mistura, ignição, pistão, **inductionTorqueEff**)
8. `resolveAppliedTorqueFactor` → blend proporcional à carga
9. `applyEngineEffectCoef` → `engine.outputTorqueState = target`
10. `publishEngineBridge` → bridge em memória
11. Telemetria `ure_*` (rápida + lenta)

**Physics (~2000 Hz) — motor fork:**

1. `updateTorque` lê throttle dos electrics
2. `ureIntegration.resolveTorqueCoef(device)` lê bridge (cacheado)
3. `torque = torqueCurve * ... * ureTorqueCoef`
4. `ureIntegration.computeSpentEnergy` usa `fuelKgS` / lambda do controller
5. `postStallGuard` suprime stall falso quando saudável

**Ordem crítica (ver seção 4):** o controller aplica `outputTorqueState` **depois** de `powertrain.update` no mesmo substep — um frame de física de defasagem, aceitável em 2000 Hz.

---

## 4. Engenharia reversa do BeamNG.drive

### 4.1 Loop principal do veículo

Arquivo vanilla: `lua/vehicle/main.lua`

#### Física (`onPhysicsStep`)

```
wheels.updateWheelVelocities
powertrain.update              ← torque calculado AQUI (updateTorque)
controller.updateWheelsIntermediate
wheels.updateWheelTorques
controller.update              ← URE reaplica outputTorqueState AQUI
thrusters / hydros / beamstate / extensions
```

**Consequência:** o fator de torque do URE entra **um sub-passo depois** do cálculo que o consome. Em ~2000 Hz isso é sub-milissegundo. O `updateWheelsIntermediate` também reaplica o coeficiente entre passos.

#### Gráficos (`onGraphicsStep`)

```
controller.updateGFX           ← URE calcula mistura/torque (order 6500)
...
powertrain.updateGFX           ← motor RESETA intakeAirDensityCoef
powertrain.updateGFXLastStage
```

**Consequência:** `intakeAirDensityCoef` é sobrescrito todo frame com `obj:getRelativeAirDensity()` no GFX do motor. **Não usar** `intakeAirDensityCoef` para escalar torque do mod — usar **`outputTorqueState`**, que persiste.

### 4.2 Motor de combustão nativo

Arquivo: `lua/vehicle/powertrain/combustionEngine.lua`  
CEEP: `classic_combustionEngine.lua` (mesma lógica, curvas diferentes)

#### Cálculo de torque (`updateTorque`)

```lua
torque = torqueCurve[rpm] * intakeAirDensityCoef
torque = (torque * throttleMap * forcedInduction + nitrous)
       * outputTorqueState
       * ignitionCut * ignitionErrorCoefs
```

| Variável | Quem controla | URE usa? |
|----------|---------------|----------|
| `torqueCurve[rpm]` | JBeam do motor | Indiretamente (não altera) |
| `intakeAirDensityCoef` | Altitude; **resetado no GFX** | Não (telemetria só) |
| `outputTorqueState` | Dano, lockup, **URE** | **Sim — via bridge/fork** |
| `throttleMap` | Idle governor + pedal | Nativo |

#### Consumo de combustível (vanilla)

```lua
device.spentEnergy += burnEnergy * invBurnEfficiency
```

O fork URE substitui por:

```lua
local ureSpent, ureSpentN2O = ureIntegration.computeSpentEnergy(...)
device.spentEnergy += ureSpent
```

Quando `ureUltraEngine=true` e bridge ativo, `spentEnergy` segue `fuelKgS` e lambda do controller.

#### Idle governor

Em `updateTorque`, o motor calcula `idleThrottle` para manter RPM perto de `idleAV`. Se `outputTorqueState` cai sem demanda real de ar, o governador **não compensa totalmente** → RPM pode cair → UI de stall.

#### Stall (GFX do motor, ~linha 488–502 no classic fork)

```lua
if outputAV1 < starterMaxAV * 0.8 and ignitionCoef > 0 then
  stallTimer = max(stallTimer - dt, 0)
  if stallTimer <= 0 then isStalled = true end
else
  isStalled = false
  stallTimer = 1
end
ureIntegration.postStallGuard(device)  -- patch URE
```

#### Stall na UI (`vehicleController`, order 500)

```lua
if not isEngineRunning then
  guihooks.message(..., "vehicle.engine.isStalling")
end
```

`isEngineRunning` (ex. `automaticGearbox.lua`):

```lua
outputAV1 > starterMaxAV * 0.8 and starterEngagedCoef <= 0
```

**Não usa** `engine.isStalled` para a mensagem — usa **RPM físico instantâneo**.

O URE roda em order **6500** (depois do vehicleController). Não impede a mensagem no mesmo frame; `publishNativeRunningState` e `postStallGuard` tentam corrigir `electrics.engineRunning` e `isStalled`.

### 4.3 Por que o mod “não parecia funcionar” antes das correções

| Expectativa do jogador | Comportamento nativo + bug URE | Sintoma |
|------------------------|--------------------------------|---------|
| Carb pequeno = menos torque sempre | Blend `→ 1.0` no idle/baixa carga | `torque=0.77` mas `applied=0.99` |
| 6× muito mais rápido que 1× | 1× já passa ar suficiente em 4.38 L | ~1 mph de diferença |
| `stall=0` no diag = sem mensagem UI | UI usa `outputAV1 < 0.8 × starterMaxAV` | Spam `vehicle.engine.isStalling` |
| Telemetria = física | 160 electrics/frame + rerequire | Travamento |
| `intakeAirDensityCoef` para física | Resetado no GFX | Efeito some |

### 4.4 API de torque recomendada pela BeamNG

Comentário no código vanilla e no URE:

> BeamNG developers recommend `outputTorqueState` for real torque scaling.

O URE escreve:

```lua
engine.outputTorqueState = target
if type(engine.setOutputTorqueState) == "function" then
  engine:setOutputTorqueState(target)
end
```

O fork substitui `device.outputTorqueState` no produto final do torque por `ureIntegration.resolveTorqueCoef(device)`.

---

## 5. Física do carburador e torque

### 5.1 Detecção de carburador (ordem de prioridade)

1. **`ultraRealismCarburetor` estruturado** na peça ativa (40 configs em `ultra_realism_tuning.jbeam`)
2. **Inferência por nome** (`inferCarbDefinitionFromPartName`) — peças `ultra_realism_native_ceep_*`
3. **Sync nativo CEEP** (`applyNativeCarbDefinition`) — texto da peça OEM (1×4, Six-Pack, etc.)
4. **Heurística por texto** (`detectCarbSetupFromParts`) — fallback por keywords no `getActivePartsText()`

`partsDetectionSource` na telemetria:

| Valor | Origem |
|-------|--------|
| 2 | Tabela JBeam estruturada genérica |
| 3 | Inferência por nome `ultra_realism_carb_*` |
| 4 | Carb nativo CEEP/Ford (texto OEM) |
| 5 | Heurística de texto |

### 5.2 Capacidade do venturi

```lua
maxFlowM3s = venturiArea * dischargeCoef * sonicVelocity * throttleGate
venturiDemandRatio = airM3s / maxFlowM3s
```

Se `venturiDemandRatio > 1` → choke geométrico (∝ `1/ratio²`).

### 5.3 Modelo CFM nominal

```lua
effectiveRatedM3s = ratedCFM * 0.00047194745 * carbFlowCalibrationCoef  -- default 0.82
cfmLoad = airM3s / effectiveRatedM3s
sizingRatio = engineDemandM3s / effectiveRatedM3s
```

Penalidade progressiva (`carbPartialRestrictionStart = 0.55`):

- `load > 1.0` → `1 / load²`
- `0.55 < load < 1.0` → interpolação quadrática
- `sizingRatio < 0.42` e `count >= 2` → bônus `multiCarbFlowBonus` (default 1.06)

### 5.4 Da restrição de ar ao torque

```lua
inductionFlowRatio = airKgS_entregue / airKgS_solicitado
inductionTorqueEff = lerp(1, inductionFlowRatio, inductionLoad)
-- reforço extra se inductionLoad > 0.55 (carb)

performanceFactor = mixEff * timingEff * pistonEff * ... * inductionTorqueEff
appliedTorqueFactor = resolveAppliedTorqueFactor(performanceFactor, ..., inductionFlowRatio)
```

**`resolveAppliedTorqueFactor` (v0.15.3):**

```lua
flowDeficit = 1 - inductionFlowRatio
rpmLoad = rpm / redlineRPM
demandSignal = max(inductionLoad, flowDeficit, venturiDemandRatio,
                   throttle * 0.42, rpmLoad * throttle * 0.72)
blend = clamp(demandSignal * loadProportionalEngineEffectGain, 0, 1)  -- gain default 1.35
applied = lerp(1.0, performanceFactor, blend) * failureFactor
```

No **idle** (`demandSignal ≈ 0`): `applied → 1.0` — correto, carb não deve matar marcha lenta.  
No **WOT alto RPM** com 1×: `flowDeficit` alto → `blend → 1` → penalidade total.

### 5.5 Exemplo numérico — Moonhawk 4.38 L

Demanda de ar no redline (aprox.):

```
intakeM3s = displacementL/1000 * (rpm/60) * 0.5 * VE
         ≈ 0.00438 * (6050/60) * 0.5 * 0.85 ≈ 0.19 m³/s ≈ 400 CFM
```

| Setup | ratedCFM | CFM efetivo (×0.82) | sizingRatio @6000 RPM |
|-------|----------|---------------------|------------------------|
| 1× Weber 40 DCOE | 340–420 | ~280–344 | **~1.1–1.4** (apertado) |
| 6× Weber 40 DCOE | 2520 | ~2066 | **~0.09** (folgado) |

Por isso o 1× sofre restrição real e o 6× ganha bônus de fluxo.

---

## 6. Integração CEEP / Ford

### 6.1 O que o script de patch faz

`scripts/integrar_packs_motores.py`:

1. Troca `["combustionEngine", "mainEngine"]` → `["ultra_combustionEngine", "mainEngine"]`
2. Injeta controller `["ultraRealismEngine", { integrationMode: "ceep"|"ford", ... }]`
3. Clona peças do `ultra_realism_tuning.jbeam` nos slots nativos (Carburetor, Camshaft, etc.)
4. Gera peças `ultra_realism_native_ceep_*` / `ultra_realism_native_ford_*` para configs OEM

### 6.2 Roteamento do motor

`ultra_combustionEngine.lua`:

```lua
-- CEEP → ultra_classic_combustionEngine
-- Ford / stock → ultra_stock_combustionEngine
device.ureUltraEngine = true
device.ureEngineProfile = "ceep" | "ford" | "stock"
```

### 6.3 Patches no fork (via `fork_combustion_engines.py`)

| Âncora vanilla | Substituição URE |
|----------------|------------------|
| `* device.outputTorqueState *` no produto de torque | `* ureIntegration.resolveTorqueCoef(device) *` |
| `spentEnergy += burnEnergy * invBurnEfficiency` | `computeSpentEnergy(...)` com AFR integrado |
| Após bloco de stall timer | `ureIntegration.postStallGuard(device)` |
| Antes de `return device` no init | `ureIntegration.onDeviceInit(device, jbeamData)` |

### 6.4 Conflitos observados no log (não fatais)

```
Duplicate part found: tire_R_175_65_14_uni_2 ...
parts names are duplicate: c_oilpan_color_291 ...
```

Causa: CEEP + outros mods (tires, oilpan) definem mesmas part names em `/vehicles/common/`. BeamNG usa a última carregada. Não impede spawn, mas pode causar peças erradas.

```
slot "moonhawk_mod" ... "ultra_realism_moonhawk_auto_mod" was not found
```

Slot de mod do Moonhawk referencia peça que não existe no pack — cosmético/config.

```
Failed to load diffuse map moonhawk_lights_g.color
```

Texturas vanilla do Moonhawk ausentes — não relacionado ao URE.

---

## 7. Pipeline de build e instalação

### 7.1 Comandos usados nesta sessão

```bash
cd /home/gullin/Downloads/beamng_super_realism_modkit

# Gera forks + ZIP principal
python3 scripts/gerar_zip_mod.py

# Valida Lua, testes offline, ZIPs patchados
python3 scripts/validar_projeto.py 1

# Instala nos 3 alvos (Linux nativo + Heroic steamuser + gullin)
python3 scripts/instalar_mod_beamng.py --all-targets --with-packs
```

### 7.2 Alvos de instalação detectados

- `/home/gullin/.local/share/BeamNG/BeamNG.drive/current/mods/repo`
- `.../Heroic/.../steamuser/.../mods/repo`
- `.../Heroic/.../gullin/.../mods/repo`

### 7.3 Testes offline (sem jogo)

```bash
lua scripts/test_carburetor_physics.lua   # 1× vs 6×, blend idle/WOT
lua scripts/test_ceep_sync.lua            # detecção CEEP/Ford
lua scripts/test_ultra_combustion_engine.lua  # bridge, fork, cache
```

### 7.4 Versões e commits desta sessão

| Versão | Commit | Descrição |
|--------|--------|-----------|
| 0.15.1 | `c2d2a38` | Fix crash `getIntegrationMode` |
| 0.15.2 | `132af66` | Performance: cache bridge, telemetria 10 Hz |
| 0.15.3 | `8847ebd` | Carb 1× vs 6× diferenciado |

---

## 8. Como diagnosticar no jogo

### 8.1 Ativar logs (temporário)

No JBeam do controller (ou snippet):

```json
"debugLog": true,
"diagnosticLog": true
```

Após validar, volte para `false` (default v0.15.2+) para evitar custo de console.

### 8.2 Linha `diag` esperada

```
diag parts=98 carb=... count=6 barrels=2 native=0 detected=1 src=3
torque=0.70 physics=0.70 blend=0.95 applied=0.70
flow=0.48 demand=0.85 cfm=1.12 afr=12.8 lambda=0.87 misfire=0.00 stall=0
```

**Importante:** compare em **WOT no alto RPM** (última marcha, reta longa). Logs em idle mostram `blend≈0.01` por design.

| Campo | WOT saudável 1× | WOT saudável 6× |
|-------|-----------------|-----------------|
| `flow` | 0.45–0.65 | 0.90–1.00 |
| `blend` | 0.85–1.00 | 0.70–0.95 |
| `torque` / `applied` | 0.65–0.75 | 0.85–0.95 |
| `cfm` / sizing | > 0.9 | < 0.3 |

### 8.3 Telemetria útil (`electrics` / apps)

- `ure_carbCount`, `ure_carbRatedCFM`, `ure_activeVenturiAreaM2`
- `ure_inductionFlowRatio`, `ure_venturiDemandRatio`, `ure_carbSizingRatio`
- `ure_torqueFactor`, `ure_appliedTorqueFactor`, `ure_engineEffectLoadBlend`
- `ure_afr`, `ure_lambda`, `ure_fuel_gps`, `ure_air_gps`

### 8.4 Afinar sensibilidade (JBeam)

```json
"carbFlowCalibrationCoef": 0.82,
"carbPartialRestrictionStart": 0.55,
"multiCarbFlowBonus": 1.06,
"loadProportionalEngineEffectGain": 1.35,
"telemetryInterval": 0.1,
"partsSyncInterval": 0.5
```

Valores menores de `carbFlowCalibrationCoef` → 1× mais restritivo.  
Valores maiores de `multiCarbFlowBonus` → 6× mais forte no topo.

---

## 9. Limitações conhecidas

1. **Mensagem UI `vehicle.engine.isStalling`** pode aparecer mesmo com mistura saudável se RPM físico cair abaixo de `starterMaxAV × 0.8` — o URE mitiga via `postStallGuard` e `suppressFalseStallUI`, mas não remove o `guihooks.message` do `vehicleController`.

2. **Defasagem de 1 substep** entre cálculo de torque nativo e `outputTorqueState` do controller — aceitável em alta frequência, mas relevante em transientes extremos.

3. **Packs CEEP/Ford originais** devem ser substituídos pelos **patchados** — sem isso, `ultra_combustionEngine` não é usado.

4. **Duplicatas JBeam** entre mods (tires, oilpan CEEP) podem alterar peças silenciosamente.

5. **Diferença de velocidade final** depende de marcha, redline real na reta, arrasto e peso — torque +15% não garante +15% de velocidade (tipicamente ~5–10 mph em muscle car).

6. **README principal** ainda descreve o projeto como “protótipo infuncional” em partes — a v0.15.x é substancialmente mais integrada, mas não substitui 100% do modelo termodinâmico OEM.

---

## 10. Referência de arquivos

### No repositório (modkit)

| Caminho | Descrição |
|---------|-----------|
| `UltraRealismEngine_Prototype/lua/vehicle/controller/ultraRealismEngine.lua` | Controller principal |
| `UltraRealismEngine_Prototype/lua/vehicle/powertrain/ultra_combustionEngine.lua` | Roteador de motor |
| `UltraRealismEngine_Prototype/lua/vehicle/powertrain/ultra_combustionEngineIntegration.lua` | Integração torque/fuel/stall |
| `UltraRealismEngine_Prototype/lua/vehicle/powertrain/ultraRealismEngineBridge.lua` | Bridge em memória |
| `UltraRealismEngine_Prototype/vehicles/common/ultra_realism/ultra_realism_tuning.jbeam` | 40 carburadores |
| `scripts/fork_combustion_engines.py` | Gerador de forks |
| `scripts/integrar_packs_motores.py` | Patch CEEP/Ford |
| `scripts/instalar_mod_beamng.py` | Instalador multi-alvo |
| `scripts/test_carburetor_physics.lua` | Testes 1× vs 6× |
| `jbeam_snippets/controller_ultra_realism_snippet.jbeam` | Snippet manual |
| `REVERSE_ENGINEERING.md` | Notas ER anteriores (v0.14.9) — este doc supersede parcialmente |

### No jogo (BeamNG.drive vanilla — referência)

| Caminho | Tema |
|---------|------|
| `lua/vehicle/main.lua` | Ordem physics/GFX |
| `lua/vehicle/controller.lua` | `defaultOrder` dos controllers |
| `lua/vehicle/powertrain/combustionEngine.lua` | Torque, stall, combustível |
| `lua/vehicle/controller/vehicleController/vehicleController.lua` | Mensagens `isStalling` |
| `lua/vehicle/controller/vehicleController/shiftLogic/*.lua` | `isEngineRunning` |

---

## Apêndice A — Glossário

| Termo | Significado |
|-------|-------------|
| **AFR** | Air-Fuel Ratio (massa ar / massa combustível) |
| **Lambda** | AFR / AFR estequiométrico (1.0 = estequiométrico) |
| **CFM** | Cubic Feet per Minute — vazão volumétrica nominal do carburador |
| **Venturi** | Garganta do carburador onde a pressão cai e succiona combustível |
| **VE** | Volumetric Efficiency — eficiência volumétrica do motor |
| **outputTorqueState** | Multiplicador de torque persistente no device do motor |
| **Bridge** | Estado compartilhado controller ↔ motor sem passar por 160 electrics |
| **Fork** | Cópia patchada do `combustionEngine.lua` com hooks URE |
| **GFX step** | Tick gráfico ~60 Hz (telemetria, UI) |
| **Physics step** | Substep de simulação ~2000 Hz (torque, forças) |

---

## Apêndice B — Checklist pós-atualização

- [ ] **Reload Mods** no BeamNG (ou reiniciar)
- [ ] Confirmar log: `controller initialized v0.15.3`
- [ ] Confirmar: `URE fork active profile=ceep`
- [ ] Testar 1× vs 6× na mesma reta, WOT, última marcha
- [ ] Capturar `diag` em **alto RPM**, não em idle
- [ ] Se ainda igual: verificar `debugLog=on` no JBeam (custo) e `ure_carbSizingRatio` na telemetria

---

*Documento gerado após a sessão de debug Moonhawk CEEP (crash → performance → diferenciação de carburadores). Para detalhes de instalação em português, ver também [README_PT-BR.md](README_PT-BR.md) e [CREDITS.md](CREDITS.md).*