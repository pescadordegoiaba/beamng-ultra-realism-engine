#!/usr/bin/env python3
"""Gera o catalogo BeamNG a partir dos carburadores fornecidos pelo usuario."""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

KIT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(KIT_DIR / "scripts"))

import gerar_modelos_carburadores as legacy  # noqa: E402
from gerar_jbeam_variantes import (  # noqa: E402
    USER_CARBURETOR_MODELS,
    carburetor_parts,
    carburetor_visual_spec,
)

SOURCE_DIR = KIT_DIR / "assets_sources" / "user_carburetors"
OUTPUT_DIR = KIT_DIR / "UltraRealismEngine_Prototype" / "vehicles" / "common" / "ultra_realism"
OUTPUT_DAE = OUTPUT_DIR / "carburetor_models.dae"
OUTPUT_MANIFEST = OUTPUT_DIR / "carburetor_visual_manifest.json"
PREVIEW_PATH = Path("/tmp/ure_user_carburetor_catalog.png")

MATERIAL_MAP = {
    "cast_aluminum": "UltraRealismCarbCast",
    "aluminum_light": "UltraRealismCarbMachined",
    "steel": "UltraRealismCarbMachined",
    "steel_dark": "UltraRealismCarbBlack",
    "spring_steel": "UltraRealismCarbMachined",
    "brass": "UltraRealismCarbBrass",
    "rubber_dark": "UltraRealismCarbBlack",
    "dark_cavity": "UltraRealismCarbBlack",
}

MOVING_GROUP_MARKERS = (
    "throttle_pulley",
    "throttle_flat_arm",
    "throttle_arm_up",
    "throttle_stop_arm",
    "pulley_disk",
    "pulley_groove",
    "pulley_center_bolt",
    "pulley_bolt",
    "return_stop_arm",
    "return_spring",
    "master_return_spring",
    "spring_center_pin",
    "master_spring_pin",
    "vertical_link_rod",
    "link_rod_",
    "main_cable_actuator_arm",
    "control_cable_tail",
    "sync_bridge_arm",
    "triple_throttle_sync_shaft",
    "top_sync_rod",
    "lower_equalizer_rod",
)


def excluded_group(group: str) -> bool:
    lowered = group.lower()
    return any(marker in lowered for marker in MOVING_GROUP_MARKERS)


def load_filtered_obj(
    path: Path,
    materials: dict[str, bpy.types.Material],
) -> bpy.types.Object:
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[list[int], str]] = []
    group = ""
    material = "cast_aluminum"
    with path.open("r", encoding="utf-8", errors="ignore") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if line.startswith("v "):
                fields = line.split()
                vertices.append(tuple(map(float, fields[1:4])))
            elif line.startswith(("g ", "o ")):
                group = line.split(None, 1)[1].strip()
            elif line.startswith("usemtl "):
                material = line.split(None, 1)[1].strip()
            elif line.startswith("f ") and not excluded_group(group):
                indices = []
                for token in line.split()[1:]:
                    index = int(token.split("/")[0])
                    indices.append(index - 1 if index > 0 else len(vertices) + index)
                if len(indices) >= 3:
                    for face_index in range(1, len(indices) - 1):
                        faces.append(([indices[0], indices[face_index], indices[face_index + 1]], material))

    mesh = bpy.data.meshes.new(path.stem)
    mesh.from_pydata(vertices, [], [face for face, _material in faces])
    mesh.update(calc_edges=True)
    obj = bpy.data.objects.new(path.stem, mesh)
    bpy.context.collection.objects.link(obj)

    used_materials: list[str] = []
    for _face, source_material in faces:
        target = MATERIAL_MAP.get(source_material, "UltraRealismCarbCast")
        if target not in used_materials:
            used_materials.append(target)
    for name in used_materials:
        mesh.materials.append(materials[name])
    material_indices = {name: index for index, name in enumerate(used_materials)}
    for polygon, (_face, source_material) in zip(mesh.polygons, faces):
        target = MATERIAL_MAP.get(source_material, "UltraRealismCarbCast")
        polygon.material_index = material_indices[target]
        polygon.use_smooth = True
    return obj


def oriented_body(
    source: bpy.types.Object,
    model_name: str,
    orientation: str,
    flange_x: float,
) -> bpy.types.Object:
    obj = source.copy()
    obj.data = source.data.copy()
    bpy.context.collection.objects.link(obj)
    for vertex in obj.data.vertices:
        x, y, z = vertex.co
        if orientation == "downdraft":
            vertex.co = (z - 0.020, y, flange_x - x)
        else:
            vertex.co = (x - flange_x, y, z - 0.020)
    obj.name = f"ure_user_{model_name}_{orientation}"
    obj.data.name = obj.name
    return obj


def add_butterfly(
    key: str,
    orientation: str,
    bore_mm: float,
    materials: dict[str, bpy.types.Material],
) -> bpy.types.Object:
    components: list[bpy.types.Object] = []
    radius = bore_mm / 2000.0 * 0.94
    rotation = (0.0, math.radians(90), 0.0) if orientation == "sidedraft" else (0.0, 0.0, 0.0)
    legacy.add_cylinder(
        components,
        materials,
        "butterfly_plate",
        (0.0, 0.0, 0.0),
        radius,
        0.0018,
        "UltraRealismCarbBrass",
        rotation,
        32,
    )
    legacy.add_cylinder(
        components,
        materials,
        "butterfly_shaft",
        (0.0, 0.0, 0.0),
        max(radius * 0.07, 0.0016),
        radius * 2.35,
        "UltraRealismCarbMachined",
        (math.radians(90), 0.0, 0.0),
        12,
    )
    return legacy.join_components(
        components,
        f"ure_motion_{key}_butterfly",
        center_vertical=False,
    )


def add_slide(
    key: str,
    bore_mm: float,
    materials: dict[str, bpy.types.Material],
) -> bpy.types.Object:
    components: list[bpy.types.Object] = []
    radius = bore_mm / 2000.0 * 0.93
    legacy.add_cylinder(
        components,
        materials,
        "round_venturi_slide",
        (0.0, 0.0, 0.0),
        radius,
        radius * 1.85,
        "UltraRealismCarbMachined",
        (math.radians(90), 0.0, 0.0),
        28,
    )
    legacy.add_box(
        components,
        materials,
        "slide_cutaway",
        (0.0, 0.0, -radius * 0.42),
        (radius * 1.55, radius * 1.95, radius * 0.52),
        "UltraRealismCarbBlack",
        0.002,
    )
    return legacy.join_components(
        components,
        f"ure_motion_{key}_slide",
        center_vertical=False,
    )


def add_linkage(
    key: str,
    bore_mm: float,
    materials: dict[str, bpy.types.Material],
) -> bpy.types.Object:
    components: list[bpy.types.Object] = []
    radius = max(bore_mm / 2000.0 * 0.60, 0.012)
    legacy.add_cylinder(
        components,
        materials,
        "cable_pulley",
        (0.0, 0.0, 0.0),
        radius,
        0.004,
        "UltraRealismCarbBrass",
        (math.radians(90), 0.0, 0.0),
        24,
    )
    legacy.add_box(
        components,
        materials,
        "cable_actuator_arm",
        (radius * 0.72, 0.0, radius * 0.24),
        (radius * 1.75, 0.005, 0.007),
        "UltraRealismCarbBrass",
        0.0015,
    )
    legacy.add_cylinder(
        components,
        materials,
        "cable_pin",
        (radius * 1.48, 0.0, radius * 0.24),
        0.0026,
        0.010,
        "UltraRealismCarbMachined",
        (math.radians(90), 0.0, 0.0),
        12,
    )
    return legacy.join_components(
        components,
        f"ure_motion_{key}_linkage",
        center_vertical=False,
    )


def add_filter_model(
    key: str,
    spec: dict,
    materials: dict[str, bpy.types.Material],
) -> bpy.types.Object:
    components: list[bpy.types.Object] = []
    radius = spec["primaryBoreMM"] / 2000.0 + 0.018
    for x, y, z in spec["inletPivots"]:
        if spec["orientation"] == "downdraft":
            location = (x, y, z + 0.022)
            rotation = (0.0, 0.0, 0.0)
        else:
            location = (x - 0.022, y, z)
            rotation = (0.0, math.radians(90), 0.0)
        legacy.add_cylinder(
            components,
            materials,
            "pleated_filter_media",
            location,
            radius,
            0.044,
            "UltraRealismCarbRed",
            rotation,
            32,
        )
        legacy.add_cylinder(
            components,
            materials,
            "filter_end_cap",
            location,
            radius + 0.004,
            0.004,
            "UltraRealismCarbMachined",
            rotation,
            32,
        )
    return legacy.join_components(
        components,
        f"ure_filter_{key}",
        center_vertical=False,
    )


def add_tunnel_model(
    key: str,
    spec: dict,
    definition: dict,
    materials: dict[str, bpy.types.Material],
) -> bpy.types.Object:
    components: list[bpy.types.Object] = []
    carb = definition["ultraRealismCarburetor"]
    count = max(int(carb["count"]), 1)
    length = min(0.18, 0.095 + 0.010 * math.sqrt(count) + spec["primaryBoreMM"] * 0.00020)
    bore_radius = spec["primaryBoreMM"] / 2000.0 * 0.72
    venturi_radius = float(carb["primaryVenturiMM"]) / 2000.0 * 0.56
    for x, y, z in spec["carbCenters"]:
        if spec["orientation"] == "downdraft":
            location = (x, y, z - length * 0.5)
            rotation = (0.0, 0.0, 0.0)
        else:
            location = (x + length * 0.5, y, z)
            rotation = (0.0, math.radians(90), 0.0)
        bpy.ops.mesh.primitive_cone_add(
            vertices=32,
            radius1=max(bore_radius * 1.28, venturi_radius * 1.55),
            radius2=max(bore_radius, 0.024),
            depth=length,
            location=location,
            rotation=rotation,
        )
        outer = bpy.context.object
        outer.name = "matched_tunnel_body"
        legacy.assign_material(outer, materials["UltraRealismCarbCast"])
        components.append(outer)
    return legacy.join_components(
        components,
        f"ure_tunnel_{key}",
        center_vertical=False,
    )


def render_preview(bodies: list[bpy.types.Object], materials: dict[str, bpy.types.Material]) -> None:
    for obj in bpy.context.scene.objects:
        obj.hide_render = obj not in bodies
    for index, obj in enumerate(bodies):
        row, column = divmod(index, 4)
        obj.location = ((column - 1.5) * 0.58, (0.5 - row) * 0.72, 0.10)

    bpy.ops.mesh.primitive_plane_add(size=4.5, location=(0.0, 0.0, 0.0))
    plane = bpy.context.object
    floor = bpy.data.materials.new("PreviewFloor")
    floor.diffuse_color = (0.035, 0.042, 0.05, 1.0)
    floor.roughness = 0.72
    legacy.assign_material(plane, floor)

    bpy.ops.object.light_add(type="AREA", location=(1.8, -2.5, 4.5))
    bpy.context.object.data.energy = 1250
    bpy.context.object.data.size = 4.0
    bpy.ops.object.light_add(type="AREA", location=(-2.8, 1.5, 2.2))
    bpy.context.object.data.energy = 650
    bpy.context.object.data.size = 3.0
    bpy.ops.object.camera_add(location=(3.6, -5.2, 3.7))
    camera = bpy.context.object
    direction = Vector((0.0, 0.0, 0.35)) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 3.15
    bpy.context.scene.camera = camera

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 1000
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(PREVIEW_PATH)
    scene.world.color = (0.018, 0.022, 0.028)
    bpy.ops.render.render(write_still=True)
    print(f"[PREVIEW] {PREVIEW_PATH}")


def main() -> None:
    legacy.reset_scene()
    materials = legacy.make_materials()
    definitions = carburetor_parts()
    visual_specs = {
        key: carburetor_visual_spec(key, definition)
        for key, definition in definitions.items()
    }

    raw_sources = {}
    for model in USER_CARBURETOR_MODELS.values():
        source_name = model["source"]
        if source_name not in raw_sources:
            source_path = SOURCE_DIR / f"{source_name}.obj"
            if not source_path.exists():
                raise RuntimeError(f"Modelo do usuario ausente: {source_path}")
            raw_sources[source_name] = load_filtered_obj(source_path, materials)

    body_variants: dict[tuple[str, str], bpy.types.Object] = {}
    for spec in visual_specs.values():
        identity = (spec["sourceModel"], spec["orientation"])
        if identity in body_variants:
            continue
        model_meta = next(
            value
            for value in USER_CARBURETOR_MODELS.values()
            if value["source"] == spec["sourceModel"]
        )
        body_variants[identity] = oriented_body(
            raw_sources[spec["sourceModel"]],
            spec["sourceModel"],
            spec["orientation"],
            float(model_meta["flangeX"]),
        )

    models = list(body_variants.values())
    manifest = {"sourceModels": [], "carburetors": {}}
    for (source_model, orientation), body in sorted(body_variants.items()):
        manifest["sourceModels"].append(
            {
                "source": source_model,
                "orientation": orientation,
                "mesh": body.name,
                "vertices": len(body.data.vertices),
                "triangles": len(body.data.polygons),
            }
        )

    for source_key, definition in definitions.items():
        short_key = source_key.removeprefix("ultra_realism_carb_")
        spec = visual_specs[source_key]
        butterfly = add_butterfly(short_key, spec["orientation"], spec["primaryBoreMM"], materials)
        slide = add_slide(short_key, spec["primaryBoreMM"], materials)
        linkage = add_linkage(short_key, spec["primaryBoreMM"], materials)
        filter_model = add_filter_model(short_key, spec, materials)
        tunnel_model = add_tunnel_model(short_key, spec, definition, materials)
        models.extend((butterfly, slide, linkage, filter_model, tunnel_model))
        manifest["carburetors"][source_key] = {
            **spec,
            "bodyMesh": f"ure_user_{spec['sourceModel']}_{spec['orientation']}",
            "butterflyMesh": butterfly.name,
            "slideMesh": slide.name,
            "linkageMesh": linkage.name,
            "filterMesh": filter_model.name,
            "tunnelMesh": tunnel_model.name,
        }

    for raw_source in raw_sources.values():
        bpy.data.objects.remove(raw_source, do_unlink=True)
    legacy.export_static_collada(OUTPUT_DAE, models, materials)
    OUTPUT_MANIFEST.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )
    print(f"[OK] {OUTPUT_DAE}")
    print(f"[OK] {OUTPUT_MANIFEST}")
    if "--render-preview" in sys.argv:
        render_preview(list(body_variants.values()), materials)


if __name__ == "__main__":
    main()
