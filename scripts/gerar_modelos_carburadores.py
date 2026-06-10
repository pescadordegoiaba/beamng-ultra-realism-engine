#!/usr/bin/env python3
"""Gera as 40 malhas de carburador do Ultra Realism em um unico Collada.

Execute pelo Blender:
  blender --background --python scripts/gerar_modelos_carburadores.py

As dimensoes funcionais vem de ``carburetor_parts()``. O scan Artec e usado
somente no Holley 1904 vintage; as outras familias usam geometria leve criada
com os mesmos diametros de corpo e venturi consumidos pelo controller Lua.
"""
from __future__ import annotations

import math
import sys
from datetime import UTC, datetime
from pathlib import Path
from xml.etree import ElementTree as ET

import bpy
from mathutils import Vector

KIT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(KIT_DIR / "scripts"))

from gerar_jbeam_variantes import carburetor_parts  # noqa: E402

SOURCE_OBJ = KIT_DIR / "assets_sources" / "artec_carburetor" / "Carburetor.obj"
OUTPUT_DAE = (
    KIT_DIR
    / "UltraRealismEngine_Prototype"
    / "vehicles"
    / "common"
    / "ultra_realism"
    / "carburetor_models.dae"
)
PREVIEW_PATH = Path("/tmp/ure_carburetor_catalog.png")

MATERIALS = {
    "UltraRealismCarbCast": (0.28, 0.30, 0.31, 1.0),
    "UltraRealismCarbZinc": (0.43, 0.40, 0.28, 1.0),
    "UltraRealismCarbMachined": (0.56, 0.58, 0.59, 1.0),
    "UltraRealismCarbBlack": (0.035, 0.04, 0.045, 1.0),
    "UltraRealismCarbBrass": (0.55, 0.31, 0.07, 1.0),
    "UltraRealismCarbRed": (0.35, 0.025, 0.018, 1.0),
}


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials):
        for block in list(datablocks):
            datablocks.remove(block)


def make_materials() -> dict[str, bpy.types.Material]:
    result = {}
    for name, color in MATERIALS.items():
        material = bpy.data.materials.new(name)
        material.diffuse_color = color
        material.metallic = 0.72 if name not in {"UltraRealismCarbBlack", "UltraRealismCarbRed"} else 0.25
        material.roughness = 0.32 if "Machined" in name else 0.44
        result[name] = material
    return result


def assign_material(obj: bpy.types.Object, material: bpy.types.Material) -> None:
    obj.data.materials.append(material)


def apply_transform(obj: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)


def add_box(
    components: list[bpy.types.Object],
    materials: dict[str, bpy.types.Material],
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    material: str = "UltraRealismCarbCast",
    bevel: float = 0.006,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    apply_transform(obj)
    if bevel > 0:
        modifier = obj.modifiers.new("machined_edges", "BEVEL")
        modifier.width = min(bevel, min(dimensions) * 0.18)
        modifier.segments = 2
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)
    assign_material(obj, materials[material])
    components.append(obj)
    return obj


def add_cylinder(
    components: list[bpy.types.Object],
    materials: dict[str, bpy.types.Material],
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    material: str = "UltraRealismCarbMachined",
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    vertices: int = 20,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    assign_material(obj, materials[material])
    components.append(obj)
    return obj


def add_venturi(
    components: list[bpy.types.Object],
    materials: dict[str, bpy.types.Material],
    name: str,
    location: tuple[float, float, float],
    bore_mm: float,
    venturi_mm: float,
    axis: str = "z",
) -> None:
    bore = bore_mm / 1000.0
    venturi = min(venturi_mm, bore_mm * 0.96) / 1000.0
    rotation = (math.radians(90), 0.0, 0.0) if axis == "y" else (0.0, 0.0, 0.0)
    bpy.ops.mesh.primitive_cone_add(
        vertices=24,
        radius1=bore * 0.50,
        radius2=venturi * 0.50,
        depth=0.036,
        end_fill_type="NOTHING",
        location=location,
        rotation=rotation,
    )
    cone = bpy.context.object
    cone.name = f"{name}_venturi_{venturi_mm:g}mm"
    assign_material(cone, materials["UltraRealismCarbMachined"])
    components.append(cone)

    major_radius = bore * 0.50
    minor_radius = max(0.0022, bore * 0.055)
    torus_rotation = rotation
    bpy.ops.mesh.primitive_torus_add(
        major_radius=max(major_radius - minor_radius, minor_radius),
        minor_radius=minor_radius,
        major_segments=24,
        minor_segments=8,
        location=(
            location[0],
            location[1] - (0.018 if axis == "y" else 0.0),
            location[2] + (0.018 if axis == "z" else 0.0),
        ),
        rotation=torus_rotation,
    )
    lip = bpy.context.object
    lip.name = f"{name}_throttle_bore_{bore_mm:g}mm"
    assign_material(lip, materials["UltraRealismCarbMachined"])
    components.append(lip)

    dark_location = (
        location[0],
        location[1] + (0.012 if axis == "y" else 0.0),
        location[2] - (0.012 if axis == "z" else 0.0),
    )
    add_cylinder(
        components,
        materials,
        f"{name}_throat",
        dark_location,
        max(venturi * 0.46, 0.004),
        0.002,
        "UltraRealismCarbBlack",
        rotation,
        20,
    )


def add_linkage(
    components: list[bpy.types.Object],
    materials: dict[str, bpy.types.Material],
    base: tuple[float, float, float],
    span: float,
) -> None:
    x, y, z = base
    add_cylinder(
        components,
        materials,
        "throttle_shaft",
        (x, y, z),
        0.003,
        span,
        "UltraRealismCarbBrass",
        (math.radians(90), 0.0, 0.0),
        12,
    )
    add_box(
        components,
        materials,
        "throttle_arm",
        (x + 0.018, y + span * 0.48, z + 0.006),
        (0.038, 0.004, 0.009),
        "UltraRealismCarbBrass",
        0.001,
    )


def layout_positions(count: int, spacing: float, grid: bool = False) -> list[tuple[float, float]]:
    if count <= 1:
        return [(0.0, 0.0)]
    if grid and count == 4:
        half = spacing * 0.52
        return [(-half, -half), (half, -half), (-half, half), (half, half)]
    start = -0.5 * spacing * (count - 1)
    return [(0.0, start + index * spacing) for index in range(count)]


def build_downdraft_unit(
    components: list[bpy.types.Object],
    materials: dict[str, bpy.types.Material],
    origin: tuple[float, float],
    primary_bores: list[float],
    venturis: list[float],
    family: str,
) -> None:
    x0, y0 = origin
    barrels = len(primary_bores)
    largest_bore = max(primary_bores)
    spacing = largest_bore / 1000.0 + 0.018
    if barrels == 1:
        throat_positions = [(x0, y0)]
        body_x, body_y = 0.105, 0.100
    elif barrels == 2:
        throat_positions = [(x0 - spacing * 0.50, y0), (x0 + spacing * 0.50, y0)]
        body_x, body_y = spacing + 0.080, 0.115
    else:
        throat_positions = [
            (x0 - spacing * 0.50, y0 - spacing * 0.50),
            (x0 + spacing * 0.50, y0 - spacing * 0.50),
            (x0 - spacing * 0.50, y0 + spacing * 0.50),
            (x0 + spacing * 0.50, y0 + spacing * 0.50),
        ]
        body_x = body_y = spacing + 0.095

    body_material = "UltraRealismCarbZinc" if family in {"dgv", "idf", "carter"} else "UltraRealismCarbCast"
    add_box(
        components,
        materials,
        f"{family}_main_body",
        (x0, y0, 0.080),
        (body_x, body_y, 0.105),
        body_material,
        0.008,
    )
    bowl_offset = body_y * 0.55
    bowl_count = 2 if family in {"holley", "dominator", "quickfuel", "demon"} and barrels >= 4 else 1
    for bowl_index in range(bowl_count):
        sign = -1 if bowl_index == 0 else 1
        add_box(
            components,
            materials,
            f"{family}_float_bowl_{bowl_index}",
            (x0, y0 + sign * bowl_offset, 0.078),
            (body_x * 0.84, 0.045, 0.075),
            "UltraRealismCarbZinc" if family == "carter" else "UltraRealismCarbCast",
            0.007,
        )
    for index, ((x, y), bore, venturi) in enumerate(zip(throat_positions, primary_bores, venturis)):
        add_venturi(
            components,
            materials,
            f"{family}_{index}",
            (x, y, 0.145),
            bore,
            venturi,
        )
        add_cylinder(
            components,
            materials,
            f"{family}_base_{index}",
            (x, y, 0.018),
            bore / 2000.0 + 0.008,
            0.036,
            "UltraRealismCarbCast",
            vertices=20,
        )
    add_linkage(components, materials, (x0 + body_x * 0.48, y0, 0.105), body_y * 1.15)


def build_dcoe_unit(
    components: list[bpy.types.Object],
    materials: dict[str, bpy.types.Material],
    origin: tuple[float, float],
    bore: float,
    venturi: float,
) -> None:
    x0, y0 = origin
    barrel_spacing = bore / 1000.0 + 0.020
    add_box(
        components,
        materials,
        "dcoe_body",
        (x0, y0, 0.068),
        (0.115, barrel_spacing + 0.070, 0.115),
        "UltraRealismCarbZinc",
        0.009,
    )
    for index, y in enumerate((y0 - barrel_spacing * 0.50, y0 + barrel_spacing * 0.50)):
        add_venturi(
            components,
            materials,
            f"dcoe_{index}",
            (x0 - 0.070, y, 0.078),
            bore,
            venturi,
            "y",
        )
        add_cylinder(
            components,
            materials,
            f"dcoe_air_horn_{index}",
            (x0 - 0.105, y, 0.078),
            bore / 2000.0 + 0.006,
            0.050,
            "UltraRealismCarbMachined",
            (0.0, math.radians(90), 0.0),
            24,
        )
    add_box(
        components,
        materials,
        "dcoe_float_bowl",
        (x0 + 0.050, y0, 0.065),
        (0.055, barrel_spacing + 0.050, 0.080),
        "UltraRealismCarbZinc",
        0.007,
    )
    add_linkage(components, materials, (x0 + 0.054, y0, 0.105), barrel_spacing + 0.080)


def import_artec_scan(materials: dict[str, bpy.types.Material]) -> bpy.types.Object:
    if not SOURCE_OBJ.exists():
        raise RuntimeError(f"Modelo Artec ausente: {SOURCE_OBJ}")
    before = set(bpy.data.objects)
    bpy.ops.wm.obj_import(filepath=str(SOURCE_OBJ))
    imported = [obj for obj in bpy.data.objects if obj not in before and obj.type == "MESH"]
    if not imported:
        raise RuntimeError("O OBJ Artec nao gerou nenhuma malha")
    scan = imported[0]
    scan.name = "artec_carburetor_scan_decimated"
    scan.scale = (0.00078, 0.00078, 0.00078)
    apply_transform(scan)
    bpy.context.view_layer.objects.active = scan
    scan.select_set(True)
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    scan.location = (0.0, 0.0, scan.dimensions.z * 0.50)
    modifier = scan.modifiers.new("game_decimation", "DECIMATE")
    modifier.ratio = 0.012
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    for slot in list(scan.material_slots):
        scan.data.materials.pop(index=0)
    assign_material(scan, materials["UltraRealismCarbZinc"])
    scan.select_set(False)
    return scan


def family_for(key: str) -> str:
    if "dcoe" in key:
        return "dcoe"
    if "dgv" in key or "dgas" in key:
        return "dgv"
    if "idf" in key or "ida" in key:
        return "idf"
    if "4500" in key:
        return "dominator"
    if "edelbrock" in key or "carter" in key:
        return "carter"
    if "quick_fuel" in key:
        return "quickfuel"
    if "demon" in key:
        return "demon"
    return "holley"


def join_components(
    components: list[bpy.types.Object],
    name: str,
    center_vertical: bool = True,
) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in components:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = components[0]
    if len(components) > 1:
        bpy.ops.object.join()
        result = bpy.context.object
    else:
        result = components[0]
    result.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    modifier = result.modifiers.new("collada_triangulation", "TRIANGULATE")
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    if center_vertical:
        min_z = min(corner[2] for corner in result.bound_box)
        max_z = max(corner[2] for corner in result.bound_box)
        center_z = (min_z + max_z) * 0.5
        for vertex in result.data.vertices:
            vertex.co.z -= center_z
    result.select_set(False)
    return result


def add_float_source(
    mesh_element: ET.Element,
    source_id: str,
    values: list[float],
    params: tuple[str, ...],
) -> None:
    source = ET.SubElement(mesh_element, "source", id=source_id)
    array_id = f"{source_id}-array"
    array = ET.SubElement(
        source,
        "float_array",
        id=array_id,
        count=str(len(values)),
    )
    array.text = " ".join(f"{value:.7g}" for value in values)
    technique = ET.SubElement(source, "technique_common")
    accessor = ET.SubElement(
        technique,
        "accessor",
        source=f"#{array_id}",
        count=str(len(values) // len(params)),
        stride=str(len(params)),
    )
    for param in params:
        ET.SubElement(accessor, "param", name=param, type="float")


def export_static_collada(
    output: Path,
    models: list[bpy.types.Object],
    materials: dict[str, bpy.types.Material],
) -> None:
    """Exporta as malhas estaticas sem depender do add-on Collada do Blender."""
    namespace = "http://www.collada.org/2005/11/COLLADASchema"
    ET.register_namespace("", namespace)
    root = ET.Element(
        f"{{{namespace}}}COLLADA",
        version="1.4.1",
    )
    asset = ET.SubElement(root, "asset")
    contributor = ET.SubElement(asset, "contributor")
    ET.SubElement(contributor, "authoring_tool").text = "Ultra Realism Blender dimensional carburetor generator"
    timestamp = datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    ET.SubElement(asset, "created").text = timestamp
    ET.SubElement(asset, "modified").text = timestamp
    ET.SubElement(asset, "unit", meter="1", name="meter")
    ET.SubElement(asset, "up_axis").text = "Z_UP"

    effects = ET.SubElement(root, "library_effects")
    library_materials = ET.SubElement(root, "library_materials")
    for name, material in materials.items():
        effect_id = f"{name}-effect"
        effect = ET.SubElement(effects, "effect", id=effect_id)
        profile = ET.SubElement(effect, "profile_COMMON")
        technique = ET.SubElement(profile, "technique", sid="common")
        phong = ET.SubElement(technique, "phong")
        diffuse = ET.SubElement(phong, "diffuse")
        ET.SubElement(diffuse, "color").text = " ".join(
            f"{value:.6g}" for value in material.diffuse_color
        )
        specular = ET.SubElement(phong, "specular")
        ET.SubElement(specular, "color").text = "0.42 0.42 0.42 1"
        shininess = ET.SubElement(phong, "shininess")
        ET.SubElement(shininess, "float").text = "28"
        dae_material = ET.SubElement(library_materials, "material", id=name, name=name)
        ET.SubElement(dae_material, "instance_effect", url=f"#{effect_id}")

    geometries = ET.SubElement(root, "library_geometries")
    visual_scenes = ET.SubElement(root, "library_visual_scenes")
    visual_scene = ET.SubElement(
        visual_scenes,
        "visual_scene",
        id="UltraRealismCarburetors",
        name="UltraRealismCarburetors",
    )

    for model in models:
        mesh = model.data
        geometry_id = f"{model.name}-geometry"
        geometry = ET.SubElement(
            geometries,
            "geometry",
            id=geometry_id,
            name=model.name,
        )
        mesh_element = ET.SubElement(geometry, "mesh")
        positions = [coordinate for vertex in mesh.vertices for coordinate in vertex.co]
        normals = [coordinate for polygon in mesh.polygons for coordinate in polygon.normal]
        add_float_source(
            mesh_element,
            f"{geometry_id}-positions",
            positions,
            ("X", "Y", "Z"),
        )
        add_float_source(
            mesh_element,
            f"{geometry_id}-normals",
            normals,
            ("X", "Y", "Z"),
        )
        vertices_id = f"{geometry_id}-vertices"
        vertices = ET.SubElement(mesh_element, "vertices", id=vertices_id)
        ET.SubElement(
            vertices,
            "input",
            semantic="POSITION",
            source=f"#{geometry_id}-positions",
        )

        polygons_by_material: dict[int, list[tuple[int, bpy.types.MeshPolygon]]] = {}
        for polygon_index, polygon in enumerate(mesh.polygons):
            polygons_by_material.setdefault(polygon.material_index, []).append(
                (polygon_index, polygon)
            )
        used_material_names = []
        for material_index, polygons in sorted(polygons_by_material.items()):
            material = (
                mesh.materials[material_index]
                if material_index < len(mesh.materials)
                else materials["UltraRealismCarbCast"]
            )
            material_name = material.name
            used_material_names.append(material_name)
            triangles = ET.SubElement(
                mesh_element,
                "triangles",
                material=material_name,
                count=str(len(polygons)),
            )
            ET.SubElement(
                triangles,
                "input",
                semantic="VERTEX",
                source=f"#{vertices_id}",
                offset="0",
            )
            ET.SubElement(
                triangles,
                "input",
                semantic="NORMAL",
                source=f"#{geometry_id}-normals",
                offset="1",
            )
            indices: list[str] = []
            for polygon_index, polygon in polygons:
                for vertex_index in polygon.vertices:
                    indices.extend((str(vertex_index), str(polygon_index)))
            ET.SubElement(triangles, "p").text = " ".join(indices)

        node = ET.SubElement(
            visual_scene,
            "node",
            id=model.name,
            name=model.name,
            type="NODE",
        )
        instance = ET.SubElement(node, "instance_geometry", url=f"#{geometry_id}")
        bind_material = ET.SubElement(instance, "bind_material")
        technique_common = ET.SubElement(bind_material, "technique_common")
        for material_name in sorted(set(used_material_names)):
            ET.SubElement(
                technique_common,
                "instance_material",
                symbol=material_name,
                target=f"#{material_name}",
            )

    scene = ET.SubElement(root, "scene")
    ET.SubElement(
        scene,
        "instance_visual_scene",
        url="#UltraRealismCarburetors",
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(root).write(
        output,
        encoding="utf-8",
        xml_declaration=True,
    )


def render_preview(
    models: list[bpy.types.Object],
    materials: dict[str, bpy.types.Material],
) -> None:
    representative_names = {
        "ure_carb_weber_3236_dgv",
        "ure_carb_twin_weber_38_dgas",
        "ure_carb_weber_40_dcoe_28",
        "ure_carb_six_weber_40_dcoe_32",
        "ure_carb_quad_weber_48_ida_40",
        "ure_carb_holley_1904_1bbl",
        "ure_carb_holley_2300_500",
        "ure_carb_holley_4150_750_dp",
        "ure_carb_holley_4500_1050",
        "ure_carb_edelbrock_avs2_650",
        "ure_carb_quick_fuel_850_race",
        "ure_carb_speed_demon_750_annular",
    }
    visible_carbs = [model for model in models if model.name in representative_names]
    model_by_name = {model.name: model for model in models}
    visible = list(visible_carbs)
    for carb in visible_carbs:
        tunnel_name = carb.name.replace("ure_carb_", "ure_tunnel_", 1)
        if tunnel_name in model_by_name:
            visible.append(model_by_name[tunnel_name])
    for model in models:
        model.hide_render = model not in visible
    for index, model in enumerate(visible_carbs):
        row, column = divmod(index, 4)
        model.location = ((column - 1.5) * 0.72, (1 - row) * 0.72, 0.22)
        tunnel = model_by_name.get(model.name.replace("ure_carb_", "ure_tunnel_", 1))
        if tunnel:
            tunnel.location = model.location

    bpy.ops.mesh.primitive_plane_add(size=5.0, location=(0.0, 0.0, 0.0))
    plane = bpy.context.object
    plane_material = bpy.data.materials.new("PreviewFloor")
    plane_material.diffuse_color = (0.035, 0.042, 0.05, 1.0)
    plane_material.roughness = 0.72
    assign_material(plane, plane_material)

    bpy.ops.object.light_add(type="AREA", location=(1.5, -2.0, 5.0))
    key = bpy.context.object
    key.data.energy = 1300
    key.data.shape = "DISK"
    key.data.size = 4.0
    bpy.ops.object.light_add(type="AREA", location=(-3.0, 1.5, 2.5))
    fill = bpy.context.object
    fill.data.energy = 700
    fill.data.size = 3.0

    bpy.ops.object.camera_add(location=(4.2, -5.8, 5.0))
    camera = bpy.context.object
    direction = Vector((0.0, 0.0, 0.35)) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 3.8
    bpy.context.scene.camera = camera

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 1100
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(PREVIEW_PATH)
    scene.render.film_transparent = False
    scene.world.color = (0.018, 0.022, 0.028)
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.render.render(write_still=True)
    print(f"[PREVIEW] {PREVIEW_PATH}")


def build_model(
    key: str,
    definition: dict,
    materials: dict[str, bpy.types.Material],
    artec_scan: bpy.types.Object,
) -> bpy.types.Object:
    data = definition["ultraRealismCarburetor"]
    count = int(data["count"])
    primary = int(data["primaryBarrels"])
    secondary = int(data["secondaryBarrels"])
    family = family_for(key)
    components: list[bpy.types.Object] = []

    if key.endswith("holley_1904_1bbl"):
        scan = artec_scan.copy()
        scan.data = artec_scan.data.copy()
        bpy.context.collection.objects.link(scan)
        components.append(scan)
        add_venturi(
            components,
            materials,
            "holley_1904",
            (0.0, 0.0, scan.dimensions.z + 0.006),
            data["primaryBoreMM"],
            data["primaryVenturiMM"],
        )
    elif family == "dcoe":
        spacing = 0.142
        for x, y in layout_positions(count, spacing):
            build_dcoe_unit(
                components,
                materials,
                (x, y),
                data["primaryBoreMM"],
                data["primaryVenturiMM"],
            )
    else:
        bores = [float(data["primaryBoreMM"])] * primary
        venturis = [float(data["primaryVenturiMM"])] * primary
        bores.extend([float(data["secondaryBoreMM"])] * secondary)
        venturis.extend([float(data["secondaryVenturiMM"])] * secondary)
        spacing = 0.205 if len(bores) >= 4 else 0.165
        use_grid = family == "idf" and count == 4
        for x, y in layout_positions(count, spacing, use_grid):
            build_downdraft_unit(components, materials, (x, y), bores, venturis, family)

    mesh_name = key.removeprefix("ultra_realism_carb_")
    model = join_components(components, f"ure_carb_{mesh_name}")
    model["ure_model_id"] = int(data["modelId"])
    model["ure_carb_count"] = count
    model["ure_primary_bore_mm"] = float(data["primaryBoreMM"])
    model["ure_primary_venturi_mm"] = float(data["primaryVenturiMM"])
    return model


def equivalent_diameter_mm(data: dict, use_venturi: bool) -> float:
    primary_key = "primaryVenturiMM" if use_venturi else "primaryBoreMM"
    secondary_key = "secondaryVenturiMM" if use_venturi else "secondaryBoreMM"
    diameter_squared = (
        int(data["primaryBarrels"]) * float(data[primary_key]) ** 2
        + int(data["secondaryBarrels"]) * float(data[secondary_key]) ** 2
    ) * int(data["count"])
    return math.sqrt(max(diameter_squared, 1.0))


def build_tunnel_model(
    key: str,
    definition: dict,
    carb_model: bpy.types.Object,
    materials: dict[str, bpy.types.Material],
) -> bpy.types.Object:
    data = definition["ultraRealismCarburetor"]
    components: list[bpy.types.Object] = []
    carb_min_z = min(vertex.co.z for vertex in carb_model.data.vertices)
    throat_mm = equivalent_diameter_mm(data, True)
    bore_mm = equivalent_diameter_mm(data, False)
    count = int(data["count"])
    length = min(0.18, 0.095 + 0.010 * math.sqrt(count) + bore_mm * 0.00020)
    top_radius = max(bore_mm / 2000.0 * 0.72, 0.028)
    throat_radius = max(throat_mm / 2000.0 * 0.52, 0.020)
    base_radius = max(top_radius * 1.28, throat_radius * 1.55)
    center_z = carb_min_z - length * 0.50

    bpy.ops.mesh.primitive_cone_add(
        vertices=32,
        radius1=base_radius,
        radius2=top_radius,
        depth=length,
        end_fill_type="NGON",
        location=(0.0, 0.0, center_z),
    )
    outer = bpy.context.object
    outer.name = "tunnel_outer"
    assign_material(outer, materials["UltraRealismCarbCast"])
    components.append(outer)

    bpy.ops.mesh.primitive_cone_add(
        vertices=32,
        radius1=throat_radius * 1.20,
        radius2=throat_radius,
        depth=length + 0.004,
        end_fill_type="NOTHING",
        location=(0.0, 0.0, center_z),
    )
    inner = bpy.context.object
    inner.name = f"tunnel_venturi_{throat_mm:.1f}mm"
    assign_material(inner, materials["UltraRealismCarbMachined"])
    components.append(inner)

    for name, z, radius in (
        ("tunnel_top_flange", carb_min_z, top_radius),
        ("tunnel_manifold_flange", carb_min_z - length, base_radius),
    ):
        bpy.ops.mesh.primitive_torus_add(
            major_radius=max(radius - 0.004, 0.006),
            minor_radius=0.004,
            major_segments=32,
            minor_segments=8,
            location=(0.0, 0.0, z),
        )
        flange = bpy.context.object
        flange.name = name
        assign_material(flange, materials["UltraRealismCarbMachined"])
        components.append(flange)

    add_cylinder(
        components,
        materials,
        "tunnel_dark_throat",
        (0.0, 0.0, carb_min_z - length * 0.48),
        throat_radius * 0.92,
        0.003,
        "UltraRealismCarbBlack",
        vertices=28,
    )
    mesh_name = key.removeprefix("ultra_realism_carb_")
    tunnel = join_components(
        components,
        f"ure_tunnel_{mesh_name}",
        center_vertical=False,
    )
    tunnel["ure_tunnel_length_m"] = length
    tunnel["ure_tunnel_throat_mm"] = throat_mm
    tunnel["ure_tunnel_inlet_mm"] = bore_mm * 1.10
    return tunnel


def main() -> None:
    reset_scene()
    materials = make_materials()
    artec_scan = import_artec_scan(materials)
    artec_scan.hide_render = True
    artec_scan.hide_set(True)

    models = []
    for key, definition in carburetor_parts().items():
        model = build_model(key, definition, materials, artec_scan)
        tunnel = build_tunnel_model(key, definition, model, materials)
        models.extend((model, tunnel))
        print(
            f"[MALHA] {model.name}: "
            f"{len(model.data.vertices)} vertices, {len(model.data.polygons)} faces"
        )

    bpy.data.objects.remove(artec_scan, do_unlink=True)
    export_static_collada(OUTPUT_DAE, models, materials)
    print(f"[OK] {OUTPUT_DAE}")
    if "--render-preview" in sys.argv:
        render_preview(models, materials)


if __name__ == "__main__":
    main()
