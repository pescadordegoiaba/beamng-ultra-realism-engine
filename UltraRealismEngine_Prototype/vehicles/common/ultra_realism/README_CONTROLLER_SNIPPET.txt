Este mod usa o controller Lua:

  lua/vehicle/controller/ultraRealismEngine.lua

Para CEEP/Ford: use os packs patchados (scripts/integrar_packs_motores.py).
O mod principal sozinho nao injeta hooks nos motores nativos desses packs.

Para ativar em outro veiculo/mod unpacked, adicione dentro da secao "controller" do JBeam:

  ["ultraRealismEngine", {
    "integrationMode": "auto",
    "fuelingMode": "auto",
    "autoDetectEngine": true,
    "autoFuelingMode": true
  }]

CEEP/Ford patchados usam integrationMode "ceep" ou "ford" automaticamente.
Modo "auto" detecta o pack pelas pecas instaladas.

Snippet completo:

  jbeam_snippets/controller_ultra_realism_snippet.jbeam

Nao existem ajustes em runtime nesta versao. O controller infere parametros pelas pecas ativas e pelo ambiente.