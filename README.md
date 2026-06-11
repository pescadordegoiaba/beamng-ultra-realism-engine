# Ultra Realism Engine — BeamNG.drive Modkit

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.21.1-blue.svg)](UltraRealismEngine_Prototype/mod_info/info.json)
[![BeamNG](https://img.shields.io/badge/BeamNG.drive-0.36%2B-green.svg)](COMPATIBILITY.json)
[![Release](https://img.shields.io/github/v/release/pescadordegoiaba/beamng-ultra-realism-engine?label=release)](https://github.com/pescadordegoiaba/beamng-ultra-realism-engine/releases)

Mechanical simulation layer for combustion engines in [BeamNG.drive](https://www.beamng.com/game/): carburetor physics (Venturi, CFM, mixture), injection, climate, ignition, progressive failures, and native integration with **[CEEP] Classic Engine Expansion Pack** (JΛVI) and **Ford Engine Pack JITTERUSA**.

> **Status: advanced prototype (v0.21.1)** — full CEEP/Ford engine fork, carb physics via `outputTorqueState`, integrated fuel (AFR/`spentEnergy`), modular runtime (`ownership`, `partCurves`, EFI/diesel induction). Not a finished commercial product.

**Documentation**

| Document | Content |
|----------|---------|
| [README_PT-BR.md](README_PT-BR.md) | Full guide in Portuguese |
| [docs/RELEASE_v0.21.1.md](docs/RELEASE_v0.21.1.md) | Release notes + legal notice for patched packs |
| [COMPATIBILITY.json](COMPATIBILITY.json) | BeamNG version matrix |
| [RESUMO_SESSAO_E_ENGENHARIA_REVERSA.md](RESUMO_SESSAO_E_ENGENHARIA_REVERSA.md) | Debug session + reverse engineering notes |
| [patched_mods/README.md](patched_mods/README.md) | How to patch CEEP/Ford locally |

---

## Releases (pre-built ZIPs)

Latest: **[v0.21.1](https://github.com/pescadordegoiaba/beamng-ultra-realism-engine/releases/tag/v0.21.1)**

| Asset | Description |
|-------|-------------|
| `UltraRealismEngine_Prototype.zip` | Main URE mod (~3 MB) |
| `classic_engine_expansion_pack.zip` | **Patched** CEEP with native URE slots (~475 MB) |
| `Ford_Engine_Pack_JITTERUSA.zip` | **Patched** Ford pack with native URE slots (~299 MB) |

**BeamNG.drive compatibility:** `0.36.0+` — tested on **`0.38.3.0`**. See [COMPATIBILITY.json](COMPATIBILITY.json).

> Patched CEEP/Ford ZIPs are derivative works. You must legally own the originals from [BeamNG resources](https://www.beamng.com/resources/). **Disable** the original CEEP/Ford zips in Mod Manager — use only the patched versions from this release.

### One-command install (Linux / Heroic)

```bash
git clone https://github.com/pescadordegoiaba/beamng-ultra-realism-engine.git
cd beamng-ultra-realism-engine
chmod +x scripts/instalar_tudo.sh
./scripts/instalar_tudo.sh --download --all-targets
```

The script downloads all three ZIPs from GitHub Releases and copies them to every detected `mods/repo` folder.

**Other install options:**

```bash
# Local ZIPs already built
./scripts/instalar_tudo.sh --all-targets

# Python installer
python3 scripts/instalar_mod_beamng.py --all-targets --with-packs

# Custom mods folder
./scripts/instalar_tudo.sh --mods-dir "$HOME/.local/share/BeamNG/BeamNG.drive/current/mods/repo"
```

**After install:** Mod Manager → disable original CEEP/Ford → enable the 3 URE zips → **Reload Mods**.

---

## What's new in v0.21.x

| Version | Highlight |
|---------|-----------|
| **0.21.1** | CEEP i4 turbo enabled, FI throttle-body routing, parts-scan cache, short-block slot dedup |
| **0.21.0** | Roadmap A–F: `ownership`, `partCurves`, `bus`, EFI/diesel induction, combustion hooks |
| **0.15.3** | Real 1× vs 6× carb differentiation (CFM calibration, air-deficit blend) |

Full notes: [docs/RELEASE_v0.21.1.md](docs/RELEASE_v0.21.1.md)

---

## Repository layout

| Path | Content |
|------|---------|
| `UltraRealismEngine_Prototype/` | Installable mod: Lua controller, engine forks, JBeam (40 carbs), Collada assets |
| `scripts/` | Build, validation, offline tests, CEEP/Ford integration, installers |
| `assets_sources/` | Author-supplied carburetor OBJs (8 visual families) |
| `patched_mods/` | README only in git — patched ZIPs ship via **GitHub Releases** |
| `downloads/` | Optional cache for `instalar_tudo.sh --download` |

---

## Architecture (v0.21.1)

```
JBeam parts (patched CEEP/Ford + ultra_realism_tuning.jbeam)
        ↓
ultraRealismEngine.lua (controller, order 6500)
  • venturi/CFM restriction, AFR, climate, torque
  • ultra_realism/ownership, partCurves, bus, induction_*
  • publishEngineBridge → ultraRealismEngineBridge
        ↓
ultra_combustionEngine.lua (router)
  → ultra_classic_combustionEngine (CEEP)
  → ultra_stock_combustionEngine (Ford/stock)
        ↓
ultra_combustionEngineIntegration.lua + Hooks
  • resolveTorqueCoef, computeSpentEnergy, postStallGuard
  • resolveForcedInductionCoef
```

---

## Build from source

Requirements: Python 3, Lua, Blender (optional, for `carburetor_models.dae`).

```bash
git clone https://github.com/pescadordegoiaba/beamng-ultra-realism-engine.git
cd beamng-ultra-realism-engine

python3 scripts/gerar_zip_mod.py
python3 scripts/validar_projeto.py 1

# Patch CEEP/Ford (requires legally owned originals)
python3 scripts/integrar_packs_motores.py \
  --ceep /path/to/classic_engine_expansion_pack.zip \
  --ford /path/to/Ford_Engine_Pack_JITTERUSA.zip

./scripts/instalar_tudo.sh --all-targets
```

Without **patched** CEEP/Ford packs, the controller does not appear in those engines' native part trees and the engine fork is not used.

---

## What works today

- Stable CEEP/Ford spawn with full engine fork
- Playable performance (parts-scan cache, 0.5 s sync interval, debug logs off by default)
- **40 carburetors** with distinct geometry, CFM, and count (1× / 2× / 3× / 4× / 6×)
- ~12–15% torque difference between 1× and 6× on ~4.4 L engines
- Real torque via `outputTorqueState` + `resolveTorqueCoef`
- Integrated fuel: `spentEnergy` follows controller AFR/lambda when `ureUltraEngine=true`
- CEEP i4 flathead turbo path (v0.21.1)
- `ure_*` telemetry, animated carb visuals (8 author OBJs)
- Auto-detect: displacement, idle/redline, carb/EFI mode, CEEP/Ford parts

## Known limitations

| Area | Status |
|------|--------|
| `vehicle.engine.isStalling` UI | May appear with healthy mixture; mitigated via `postStallGuard` |
| Required packs | Patched CEEP/Ford + main URE zip |
| JBeam duplicates | Conflicts with other mods (tires, CEEP oilpan) — log warnings |
| In-game UI | No tuning app; parameters in JBeam/Lua |
| Patched pack redistribution | Release assets require owning originals legally |

Details: [RESUMO_SESSAO_E_ENGENHARIA_REVERSA.md](RESUMO_SESSAO_E_ENGENHARIA_REVERSA.md) §9.

---

## Offline tests

```bash
python3 scripts/validar_projeto.py 1
lua scripts/test_parts_scan_cache.lua
python3 scripts/test_i4_turbo_integration.py
```

---

## Version

Canonical: `UltraRealismEngine_Prototype/mod_info/info.json` → **0.21.1**

---

## Contributing

Issues and PRs welcome.

- Keep `scripts/validar_projeto.py` passing.
- Do not commit third-party mod sources (CEEP/Ford originals).
- Update [CREDITS.md](CREDITS.md) when adding external assets.

---

## License

Original code: [MIT](LICENSE). Third parties: [CREDITS.md](CREDITS.md).