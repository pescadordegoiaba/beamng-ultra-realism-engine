# Créditos e atribuições

## Ultra Realism Engine (este repositório)

| Papel | Quem |
|-------|------|
| Mantenedor / autor do modkit | [pescadordegoiaba](https://github.com/pescadordegoiaba) |
| Desenvolvimento do controller, pipeline de build e integração | Modkit local + assistência de IA (Grok) na iteração do código |
| Versão atual do controller | `0.14.11` — ver `UltraRealismEngine_Prototype/mod_info/info.json` |

Código Lua/Python/JBeam **original deste repositório**: licenciado sob [MIT](LICENSE), salvo onde indicado abaixo.

---

## BeamNG.drive

- **Plataforma**: [BeamNG.drive](https://www.beamng.com/game/) — BeamNG GmbH  
- APIs usadas: `powertrain`, `electrics`, controllers auxiliares, JBeam, props, Collada.  
- Este mod **não** é oficial, endossado ou mantido pela BeamNG GmbH.

---

## Mods de motor de terceiros (integração, não redistribuídos)

O fluxo `scripts/integrar_packs_motores.py` **modifica** cópias que **você** deve obter separadamente:

| Mod | Autor (BeamNG) | O que este projeto faz |
|-----|----------------|------------------------|
| **[CEEP] Classic Engine Expansion Pack** | **JΛVI** | Injeta o controller `ultraRealismEngine`, slots de peças internas, 40 carburadores e assets visuais nos `slotType` nativos (Top End, Bottom End, Carburetor, etc.). |
| **Ford Engine Pack JITTERUSA** | **JITTERUSA** | Mesma integração adaptada à hierarquia Ford (Intake / Engine Variant / Oil Pan / Flywheel). |

**Crédito**: toda a mecânica base, modelos, sons e curvas de torque desses packs pertencem aos autores originais. O Ultra Realism apenas adiciona uma camada de simulação auxiliar e peças JBeam extras.

Os ZIPs patchados **não** estão no Git — veja [patched_mods/README.md](patched_mods/README.md).

---

## Modelos visuais de carburador

### Pack principal (em uso)

Oito modelos OBJ fornecidos localmente pelo mantenedor, em `assets_sources/user_carburetors/`:

- `carb_01_roundslide_classic.obj`
- `carb_02_big_bell_racing.obj`
- `carb_03_turbo_vacuum_sidepod.obj`
- `carb_04_compact_offroad.obj`
- `carb_05_vintage_sidedraft.obj`
- `carb_triple_01_street_bigbody.obj`
- `carb_triple_02_racing_velocitystack.obj`
- `carb_triple_03_touring_diaphragm.obj`

**Adaptações feitas por este projeto** (ver `assets_sources/user_carburetors/README_PTBR.txt`):

- Conversão OBJ → Collada (`carburetor_models.dae`) com Blender, eixo Z_UP, metros.
- Remoção de grupos estáticos de borboleta; substituição por props BeamNG animados.
- Espaçamento lateral nos conjuntos triple para evitar interseção de corpos.
- Mapeamento das 40 configurações comerciais (Weber, Holley, Edelbrock, etc.) para famílias visuais equivalentes — **não** são réplicas CAD de peças reais.

### Scan Artec (legado, não empacotado)

`assets_sources/artec_carburetor/` — modelo **Carburetor** por **Artec Group** ([artec3d.com](https://www.artec3d.com)), licença **CC BY 3.0** (`LICENSE.txt`).

> **Nota:** a versão atual do mod **não** exporta nem referencia mais este scan. O arquivo permanece no repositório apenas como referência histórica e atribuição de licença.

---

## Marcas e nomenclatura comercial

Nomes como **Weber**, **Holley**, **Edelbrock**, **Carter**, **Quick Fuel**, **Demon**, **Ford**, **Gavril**, **Bruckell**, etc. são marcas dos respectivos titulares. As entradas JBeam `ultra_realism_carb_*` descrevem **equivalentes de engenharia** (CFM, venturi, giclê, corpos) para simulação no jogo, não produtos licenciados.

---

## Documentação BeamNG consultada

- [Vehicle electrics](https://documentation.beamng.com/modding/vehicle/sections/electrics/)
- [Controller / vehicle systems](https://documentation.beamng.com/modding/vehicle/vehicle_system/)

---

## Como citar este projeto

```text
Ultra Realism Engine Modkit for BeamNG.drive
https://github.com/pescadordegoiaba/beamng-ultra-realism-engine
Maintainer: pescadordegoiaba
```

Ao publicar vídeos ou forks, mencione **CEEP (JΛVI)**, **Ford Pack (JITTERUSA)** e os autores dos assets visuais quando usar esses conteúdos.