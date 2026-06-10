BeamNG.Drive carburetor visual asset pack
========================================

Conteúdo:
- vehicles/common/carburetor_visual_pack/meshes/*.dae
- materials.json
- jbeam_snippets/*_animated_props.jbeam
- source_obj_fixed/*.obj

Alterações aplicadas:
1. Conversão dos OBJ para DAE/Collada com Z_UP e unidade em metros.
2. Carburetor_realistic.obj foi detectado como o OBJ mais pesado e convertido com escala 0.001.
   O tamanho máximo sai de aproximadamente 208 unidades para aproximadamente 0.208 m,
   ficando coerente com os outros carburadores do pack.
3. Os carburadores triple foram regenerados com espaçamento lateral maior entre corpos.
   Isso elimina a interseção das bocas/bellmouths do venturi.
4. Cada DAE recebeu borboletas de venturi como objetos separados:
   - single/realistic: 1 butterfly
   - triple: 3 butterflies sincronizadas
5. Cada DAE também possui keyframes simples de preview em Collada: fechado -> aberto -> fechado.
6. Os arquivos JBeam em jbeam_snippets incluem exemplos de props usando entrada throttle
   para abrir/fechar as borboletas no jogo.

Instalação sugerida:
- Copie a pasta vehicles para Documents/BeamNG.drive/mods/unpacked/carburetor_visual_pack/
- Ou compacte esta pasta como ZIP de mod.

Integração:
- Estes são assets visuais universais. Para aparecerem em um veículo específico, o JBeam do veículo
  precisa referenciar o mesh DAE e copiar/adaptar o snippet correspondente.
- O slotType dos snippets é carburetor_visual; ajuste para o slot do seu veículo/mod.
- Se a função throttle não animar no seu veículo, troque o campo func do prop pela fonte de entrada
  usada no JBeam desse veículo.
