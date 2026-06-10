# Engenharia reversa — BeamNG.drive vs Ultra Realism Engine

Documento técnico baseado na instalação em `/home/gullin/Games/BeamNG.drive/` e no mod **v0.14.9**.

## 1. Loop principal do veículo

Arquivo: `lua/vehicle/main.lua`

### Física (`onPhysicsStep`)

```
wheels.updateWheelVelocities
powertrain.update          ← torque do motor calculado AQUI
controller.updateWheelsIntermediate
wheels.updateWheelTorques
controller.update          ← UltraRealismEngine aplica outputTorqueState AQUI
thrusters / hydros / beamstate / extensions
```

**Consequência:** o fator de torque do URE sempre entra **um sub-passo de física depois** do cálculo que o usa. Com ~2000 Hz isso é sub-milissegundo, mas o problema real não é lag — é **aplicar penalidade de torque no idle**.

### Gráficos (`onGraphicsStep`)

```
controller.updateGFX       ← URE calcula mistura/torque (ordem 6500)
...
powertrain.updateGFX       ← motor nativo RESETA intakeAirDensityCoef
powertrain.updateGFXLastStage
```

**Consequência:** `intakeAirDensityCoef` é sobrescrito todo frame com `obj:getRelativeAirDensity()` em `combustionEngine.lua:616`. O URE deve usar **`outputTorqueState`**, que não é resetado no GFX.

## 2. Motor de combustão nativo

Arquivo: `lua/vehicle/powertrain/combustionEngine.lua` (CEEP usa `classic_combustionEngine.lua`, mesma lógica).

### Torque

```lua
torque = torqueCurve[rpm] * intakeAirDensityCoef
torque = (torque * throttleMap * forcedInduction) * outputTorqueState * ignitionCoefs
```

- `outputTorqueState` — multiplicador persistente (API `scaleOutputTorque`, dano, lockup)
- `intakeAirDensityCoef` — altitude + **resetado no GFX**

### Idle governor (`updateFixedStep`, chamado de dentro de `updateTorque`)

Ajusta `idleThrottle` para manter RPM perto de `idleAV`. Se `outputTorqueState < 1` sem demanda real de ar, o governador **não compensa totalmente** → RPM cai.

### Stall

GFX (`combustionEngine.lua:488-496`):

```lua
if outputAV1 < starterMaxAV * 0.8 and ignitionCoef > 0 then
  stallTimer -= dt
  if stallTimer <= 0 then isStalled = true
end
```

`vehicleController` (`vehicleController.lua:310-318`, ordem **500**):

```lua
if not isEngineRunning then
  guihooks.message(..., "vehicle.engine.isStalling")
end
```

`isEngineRunning` (ex. `automaticGearbox.lua:317`):

```lua
outputAV1 > starterMaxAV * 0.8 and starterEngagedCoef <= 0
```

**Não usa** `engine.isStalled` para a mensagem — usa **RPM físico instantâneo**.

URE roda em ordem **6500** (depois do vehicleController), portanto não impede a mensagem no mesmo frame; só pode corrigir `electrics.engineRunning` para gauges.

## 3. Por que o mod “não funcionava como esperado”

| Expectativa | Realidade nativa | Sintoma |
|-------------|------------------|---------|
| Carburador pequeno = menos torque sempre | Restrição só importa com demanda de ar | `torque=0.67` no idle com `demand=0.02` |
| `stall=0` no diag = motor ok | UI usa `outputAV1 < starterMaxAV×0.8` | Spam `vehicle.engine.isStalling` |
| `intakeAirDensityCoef` para física | Resetado no GFX | Efeito some se usado como fallback |
| Simular AFR real | Combustível nativo não lê `ure_afr` | Telemetria ok, consumo OEM |
| Mod standalone | Precisa CEEP/Ford patchados | Slots/peças ausentes |

## 4. Correções v0.14.9

### A) Efeito proporcional à carga (`loadProportionalEngineEffect`)

```lua
applied = lerp(1.0, rawTorqueFactor, blend)
blend = clamp(max(inductionLoad, venturiDemand, throttle*0.3) * gain, 0, 1)
```

No idle (`demand≈0`), `applied → 1.0` — física de carburador só penaliza em carga real.

### B) Guard de stall + `engineRunning` override

- `clearFalseStallState` — `isStalled=false`, `stallTimer=1`
- `publishNativeRunningState` — `electrics.engineRunning=1` quando saudável
- `updateWheelsIntermediate` — reaplica `outputTorqueState` entre passos

### C) Diag expandido

```
torque=... physics=... blend=... applied=...
```

- `torque` — fator físico bruto calculado
- `physics` — após blend proporcional à carga
- `blend` — quanto da penalidade está ativa (0=no idle, 1=WOT)
- `applied` — valor em `outputTorqueState`

## 5. O que ainda não dá para resolver só com Lua auxiliar

1. Substituir consumo de combustível / AFR no motor nativo
2. Impedir `guihooks.message` de stall sem manter RPM acima do limiar
3. Integrar sem CEEP/Ford patchados
4. Simular palhetas, mapas OEM, injeção por cilindro

## 6. Referências úteis no jogo

| Arquivo | Tema |
|---------|------|
| `lua/vehicle/main.lua` | Ordem physics/GFX |
| `lua/vehicle/controller.lua` | Ordem dos controllers (`defaultOrder`) |
| `lua/vehicle/powertrain/combustionEngine.lua` | Torque, stall, intakeAirDensityCoef |
| `lua/vehicle/controller/vehicleController/vehicleController.lua` | Mensagens isStalling |
| `lua/vehicle/controller/vehicleController/shiftLogic/*.lua` | `isEngineRunning` |