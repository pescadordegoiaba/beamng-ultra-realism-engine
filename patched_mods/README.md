# Packs CEEP / Ford (não incluídos no repositório)

Esta pasta guarda **ZIPs patchados** gerados por `scripts/integrar_packs_motores.py`. Eles **não** são versionados no GitHub porque são obras derivadas de mods de terceiros que você precisa possuir legalmente antes de patchar.

## Pré-requisitos

1. Instale no BeamNG (Mods Manager) os mods originais:
   - **[CEEP] Classic Engine Expansion Pack** — autor **JΛVI** ([BeamNG resources](https://www.beamng.com/resources/))
   - **Ford Engine Pack JITTERUSA** — autor **JITTERUSA**
2. Copie os ZIPs originais para esta pasta **ou** aponte o script para o caminho deles.

## Gerar os patches

```bash
cd beamng_super_realism_modkit
python3 scripts/integrar_packs_motores.py \
  --ceep-zip /caminho/para/classic_engine_expansion_pack.zip \
  --ford-zip /caminho/para/Ford_Engine_Pack_JITTERUSA.zip
```

Saída esperada:

- `patched_mods/classic_engine_expansion_pack.zip`
- `patched_mods/Ford_Engine_Pack_JITTERUSA.zip`

Instale com:

```bash
python3 scripts/instalar_mod_beamng.py --all-targets --with-packs
```

Sem esses packs patchados, o **Ultra Realism Engine** não aparece nos slots nativos de motor CEEP/Ford — o mod principal sozinho não integra a árvore de peças desses packs.