Este mod usa o controller Lua:

  lua/vehicle/controller/ultraRealismEngine.lua

As pecas geradas ja aparecem no slot "Additional Modification" dos veiculos suportados.

Para ativar em outro veiculo/mod unpacked, adicione dentro da secao "controller" do JBeam:

  ["ultraRealismEngine", { "fuelingMode": "auto", "autoDetectEngine": true, "autoFuelingMode": true }]

Use o snippet completo em:

  jbeam_snippets/controller_ultra_realism_snippet.jbeam

Nao existem ajustes em runtime nesta versao. O controller infere os parametros pelas pecas ativas e pelo ambiente.
