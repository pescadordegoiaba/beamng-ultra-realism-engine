# UltraRealismEngine Prototype - BeamNG.drive

Mod experimental para adicionar uma camada de simulacao mecanica mais realista em veiculos do BeamNG.drive.

## O que foi implementado

- Ponto de ignicao automatico, comparado com MBT estimado e corrigido pela qualidade/material do distribuidor.
- Temperatura, pressao, umidade, chuva e pressao dinamica de ar por velocidade, incluindo leitura do ambiente real do mapa quando disponivel.
- Densidade do ar umido e efeito em torque/AFR.
- Carburador com diametro de borboleta, Venturi, gicle principal, circuito de marcha lenta, bomba de aceleracao, valvula de potencia e afogador inferidos pela peca ativa.
- Equivalencia automatica para Weber 32/36 DGV, 40 DCOE e 45 DCOE quando as pecas CEEP/Ford indicam esse tipo de carburacao.
- Densidade/material inferidos para admissao e pistoes, afetando temperatura, rugosidade, inercia termica e resposta sob chuva/velocidade.
- Deteccao de carburacao multipla pelas pecas ativas: Six 1-barrel, Quad 2-barrel, Twin 4-barrel e Six-Pack progressivo.
- Injecao com vazao calculada, duty cycle e enriquecimento por temperatura/carga.
- Modo diesel separado, com mistura pobre e combustivel mais denso.
- Integracao automatica com autodeteccao de idle/redline, cilindros, torque e cilindrada estimada do `mainEngine`.
- Pecas internas comuns para CEEP/Ford: short block, geometria bore/stroke, pistoes, aneis, mancais de biela, virabrequim/bielas, comando, valvetrain, cabecotes, junta/prisioneiros, ignicao e sistema de oleo.
- Quarenta carburadores adicionais comuns para CEEP/Ford, incluindo Weber, Holley, Edelbrock, Carter, Quick Fuel e Demon.
- Oito modelos OBJ fornecidos pelo autor substituem completamente o antigo scan improvisado. As 40 configuracoes escolhem automaticamente a familia, orientacao e escala equivalentes.
- Borboleta, pistonete/slide do Venturi e alavanca do cabo do acelerador sao `props` BeamNG separados e animados pelo acelerador efetivo.
- Montagem visual automatica pela flange traseira real de cada OBJ, referencias `airb`, grupos de deformacao e hierarquia nativa de cada motor CEEP/Ford.
- Conjuntos duplos, triplos, quadruplos e de seis carburadores instanciam a quantidade fisica correspondente. Downdraft usa distribuicao linear, 2x2 ou 2x3; sidedraft usa linha sincronizada.
- Subslot nativo **Filter** em cada carburador adicional, com **Matched Air Filter** e **Tunnel Venturi**. O filtro e o tunel usam malhas dimensionadas e posicionadas para a entrada do modelo selecionado.
- Tuning comum adicional de coletor de admissao, espacador/plenum, alimentacao de combustivel e damper/flywheel.
- Protecao de partida/marcha lenta para nao apagar o motor enquanto o BeamNG ainda esta estabilizando o idle controller.
- Vazao de ar, vazao de combustivel, L/h e combustivel acumulado como telemetria.
- Mistura rica/pobre, misfire, knock, vapor lock, gelo no carburador, fouling e dano progressivo.
- Choque por mudanca brusca de clima.
- Fadiga termica de amortecedores, carga lateral/longitudinal estimada e efeito opcional em beams de suspensao identificados com seguranca.

## Veiculos suportados no pacote

As pecas aparecem no slot **Additional Modification**:

- `covet` - Ibishu Covet 1.5 carburado
- `pickup` - Gavril D-Series 5.5 V8 carburado
- `vivace` - Cherrier Vivace 1.6 EFI
- `etk800` - ETK 800 3.0 I6 EFI
- `bastion` - Bruckell Bastion 5.7 V8 EFI
- `sunburst2` - Hirochi Sunburst 2.0 EFI

Nao existem perfis manuais de carburador/EFI/diesel. A integracao principal e:

- `Ultra Realism Automatic Integration`

Nos ZIPs CEEP e Ford patchados, cada definicao de `mainEngine` recebe somente o controller. Nao existe peca intermediaria `Ultra Realism Tuning` e nenhuma das categorias mecanicas e despejada como slot filho direto do frame **Engine**.

No CEEP, as pecas adicionais reutilizam as abas e `slotType` nativos:

- os comandos aparecem diretamente nas abas **Camshaft** do Top End;
- os 40 carburadores aparecem diretamente nas abas **Carburetor/Carburetors** dos coletores;
- short blocks, stroker kits, valvetrain, cabecotes, distribuidores, intake manifolds, spacers, oil pans e flywheels aparecem nas respectivas categorias nativas;
- as pecas clonadas preservam os subslots nativos da peca que substituem.

Somente categorias inexistentes sao adicionadas. Pistoes, aneis, mancais de biela e virabrequim/bielas ficam dentro de **Short Block** no Bottom End; junta/prisioneiros ficam dentro de **Cylinder Head**; e alimentacao de combustivel fica dentro da peca de carburador.

No Ford Pack, que normalmente modela o carburador como uma peca completa de **Intake** e os ajustes como **Engine Variant**, o novo slot **Carburetor** e filho somente das admissoes carburadas. Camshaft e demais categorias internas inexistentes ficam dentro da peca nativa **Engine Variant**. Oil system e flywheel reutilizam as abas nativas **Oil Pan** e **Flywheel**.

Cada uma das 12 admissoes carburadas encontradas no Ford Pack recebe um slot visual interno proprio. Isso evita reutilizar coordenadas de outro veiculo: cada peca usa o `airb` e os grupos do intake Ford que a hospeda.

Os antigos auto-mods por veiculo foram removidos para impedir controller duplicado. A versao atual ativa o controller pelos motores CEEP/Ford patchados.

O controller reconhece combinacoes nativas como `1x4-Barrel`, Twin, Tripple, Quad, Six-Pack, DCOE, Sport, Performance e Race. Motores EFI continuam EFI quando nenhuma peca carburada esta ativa. Quando um dos 40 carburadores e selecionado na aba nativa, o Lua le diretamente os dados estruturados da peca: quantidade de carburadores, corpos primarios/secundarios, abertura progressiva/mecanica/vacuo, diametros de borboleta e venturi, gicle, CFM nominal, queda de pressao de teste, booster e bomba de aceleracao.

As dimensoes Weber 32/36, 40 DCOE e 45 DCOE usam configuracoes tecnicas publicadas. Nos conjuntos Weber multiplos, o CFM total e uma estimativa de engenharia baseada na soma dos carburadores; nao e um valor oficial Weber.

Nao ha sliders nem parametros editaveis no slot tecnico. A configuracao JBeam gerada apenas liga o controller automatico; os parametros fisicos sao definidos no Lua por peca ativa, tamanho inferido, material, clima, densidade do ar, chuva, umidade e velocidade.

O Venturi nao usa mais uma razao fixa. O controller infere a garganta equivalente pelo modelo/tamanho do carburador: por exemplo, Weber 32/36 DGV usa gargantas equivalentes 26/27 mm, Weber 40 DCOE usa 30 mm, Weber 45 DCOE usa 36 mm, e carburadores sem identificacao usam proporcao calculada pelo deslocamento por corpo.

As malhas visuais sao geradas da mesma estrutura `ultraRealismCarburetor`, portanto mudancas em `primaryBoreMM`, `secondaryBoreMM`, `primaryVenturiMM`, `secondaryVenturiMM`, quantidade de corpos ou quantidade de carburadores alteram tanto a geometria exportada quanto o calculo de vazao. Clima, temperatura, pressao, densidade, velocidade, umidade e chuva continuam calculados dinamicamente pelo Lua e nao sao substituidos por valores da malha.

O **Matched Air Filter** calcula perda de carga pela area de fluxo, area de midia, coeficiente de descarga e velocidade do ar. Umidade e chuva saturam progressivamente a midia; velocidade ajuda a expulsar e secar a agua. O **Tunnel Venturi** continua calculando velocidade, numero de Reynolds, fator de atrito, rugosidade, comprimento, contracao de area e coeficiente de descarga.

O antigo scan Artec nao e mais usado nem empacotado. O catalogo atual usa somente os oito modelos locais em `assets_sources/user_carburetors`; a tabela `carburetor_visual_manifest.json` registra o modelo, orientacao, escala, pivôs e malhas animadas usados por cada uma das 40 configuracoes.

## Instalar

A pasta `/home/gullin/Games/BeamNG.drive/` e a instalacao do jogo. Nao instale mods dentro de `content/vehicles`.

Use a pasta de usuario encontrada nesta maquina:

```bash
cd /home/gullin/Downloads/beamng_super_realism_modkit
blender --background --python scripts/gerar_modelos_carburadores_usuario.py
python3 scripts/gerar_zip_mod.py
python3 scripts/instalar_mod_beamng.py --beamng-user-dir "/home/gullin/Games/Heroic/Prefixes/default/drive_c/users/gullin/AppData/Local/BeamNG/BeamNG.drive/current" --repo
```

`gerar_zip_mod.py` executa o Blender automaticamente quando ele esta instalado; a linha explicita acima serve para diagnosticar somente a geracao dos modelos.

Ou informe diretamente a pasta de mods/repo:

```bash
python3 scripts/instalar_mod_beamng.py --mods-dir "/home/gullin/Games/Heroic/Prefixes/default/drive_c/users/gullin/AppData/Local/BeamNG/BeamNG.drive/current/mods/repo"
```

Ou tente deteccao automatica:

```bash
python3 scripts/instalar_mod_beamng.py --auto
```

O ZIP final fica em:

```text
/home/gullin/Downloads/beamng_super_realism_modkit/UltraRealismEngine_Prototype.zip
```

## Ativar no jogo

1. Abra o BeamNG.drive.
2. Va em **Repository > Mods Manager** e confirme que `UltraRealismEngine_Prototype.zip` esta ativo.
3. Spawne um veiculo suportado.
4. Va em **Vehicle Config > Parts**.
5. Se estiver usando os packs CEEP/Ford patchados, escolha o motor normalmente. O frame **Engine** contem apenas o hook; abra **Top End**, **Bottom End**, **Camshaft**, **Carburetor**, **Short Block**, **Engine Variant** ou a categoria nativa equivalente para selecionar as pecas.
6. Nao selecione uma antiga peca `Ultra Realism Automatic Integration` em configuracoes salvas. Ela foi removida e o motor patchado ja carrega o controller.

## Telemetria

No console de Vehicle Lua do carro atual:

```lua
dump(electrics.values)
```

Procure variaveis com prefixo `ure_`, por exemplo:

- `ure_afr`, `ure_lambda`
- `ure_autoDetected`, `ure_displacementL`, `ure_cylinders`, `ure_fuelingModeId`
- `ure_driverThrottle`, `ure_effectiveThrottle`, `ure_startProtection`, `ure_rawTorqueFactor`
- `ure_carbCount`, `ure_carbBarrels`, `ure_activeCarbBarrels`, `ure_carbSetupDetected`
- `ure_carbPrimaryBoreMM`, `ure_carbSecondaryBoreMM`, `ure_carbPrimaryVenturiMM`, `ure_carbSecondaryVenturiMM`
- `ure_carbRatedCFM`, `ure_carbCFMLoad`, `ure_carbSecondaryOpening`, `ure_carbStructuredDefinition`
- `ure_activeCarbBoreAreaM2`, `ure_activeVenturiAreaM2`
- `ure_carbTotalDiameterMM`, `ure_venturiTotalDiameterMM`, `ure_carbWeberEquivalentId`
- `ure_manifoldPressureKPa`, `ure_manifoldVacuumKPa`, `ure_runnerAirMS`, `ure_inductionFlowRatio`, `ure_inductionTorqueEfficiency`
- `ure_compressionRatio`, `ure_distributorQuality`, `ure_ignitionScatterDeg`
- `ure_valveCount`, `ure_valveFlowCoef`, `ure_camStage`
- `ure_runnerDiameterMM`, `ure_runnerLengthM`, `ure_throttleBodyDiameterMM`, `ure_runnerRoughnessFactor`
- `ure_carbThrottleVisual`, `ure_carbSlideVisual`, `ure_carbLinkageVisual`
- `ure_tunnelVenturiActive`, `ure_tunnelVenturiLengthM`, `ure_tunnelVenturiInletDiameterMM`, `ure_tunnelVenturiOutletDiameterMM`
- `ure_tunnelVenturiThroatDiameterMM`, `ure_tunnelVenturiVelocityMS`, `ure_tunnelVenturiPressureDropPa`, `ure_tunnelVenturiReynolds`
- `ure_airFilterActive`, `ure_airFilterFlowAreaM2`, `ure_airFilterVelocityMS`, `ure_airFilterPressureDropPa`, `ure_airFilterWetness`
- `ure_intakeMaterialDensityKgM3`, `ure_pistonMaterialDensityKgM3`
- `ure_pistonTempC`, `ure_pistonEfficiency`, `ure_pistonSeizureRisk`
- `ure_ringSealCoef`, `ure_ringFrictionCoef`, `ure_ringDurabilityCoef`
- `ure_bearingFrictionCoef`, `ure_bearingOilDemand`, `ure_bearingDurabilityCoef`
- `ure_oilCoolingCoef`, `ure_oilGControlCoef`, `ure_oilPressureReserveCoef`, `ure_headGasketStrengthCoef`
- `ure_airDensity`, `ure_densityFactor`, `ure_air_gps`, `ure_rainIntensity`, `ure_ramAirPressurePa`
- `ure_fuel_gps`, `ure_fuel_lph`, `ure_fuelUsedL`
- `ure_fuelDeliveryCapacityLPH`, `ure_intakeHeatIsolationCoef`
- `ure_timingDeg`, `ure_mbtDeg`, `ure_timingError`, `ure_timingEfficiency`
- `ure_torqueFactor`, `ure_engineEffectTarget`, `ure_engineEffectApplied`, `ure_knockRisk`, `ure_misfire`
- `ure_carbIce`, `ure_vaporLock`, `ure_climateShock`, `ure_intakeTempC`
- `ure_venturiDP`, `ure_carbRestriction`, `ure_jetSignal`, `ure_sonicLimit`
- `ure_injectorDuty`
- `ure_damperTempC`, `ure_damperFade`, `ure_springFatigue`
- `ure_lateralG`, `ure_longG`, `ure_rollLoadTransfer`

## Patch manual em outro veiculo/mod

Para mods unpacked ou copias de JBeam:

```bash
cd /home/gullin/Downloads/beamng_super_realism_modkit
python3 scripts/aplicar_controller_em_jbeam.py --jbeam /caminho/do/veiculo/arquivo.jbeam --dry-run
python3 scripts/aplicar_controller_em_jbeam.py --jbeam /caminho/do/veiculo/arquivo.jbeam
```

O script cria backup `.bak`.

Snippet manual:

```text
jbeam_snippets/controller_ultra_realism_snippet.jbeam
```

## Limitacoes reais

Isto e um controller auxiliar, nao uma substituicao completa do motor fisico interno do BeamNG. A partir da versao 0.14.1, o fator fisico calculado e aplicado em `intakeAirDensityCoef` no passo de fisica seguinte ao `powertrain.update()`. A atribuicao e absoluta, nao cumulativa, e deixa `outputTorqueState` reservado para o sistema nativo de dano. Assim, area de Venturi, CFM, mistura, ignicao, compressao, temperatura e falhas alteram o torque real sem multiplicar indefinidamente a curva dos motores CEEP/Ford.

Os 40 nomes comerciais nao sao apresentados como scans exatos de fabrica. Os oito modelos visuais sao equivalentes fornecidos pelo autor e sao escalados pela geometria fisica de cada configuracao.

O efeito fisico de suspensao usa `obj:setBeamSpringDamp` apenas em beams que parecem amortecedores/molas por nome/propriedades. Se um veiculo nao expuser esses beams de forma identificavel, a suspensao continua com telemetria sem alteracao fisica direta.
