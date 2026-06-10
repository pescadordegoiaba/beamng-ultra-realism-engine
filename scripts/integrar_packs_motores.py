#!/usr/bin/env python3
"""Integra o Ultra Realism na hierarquia nativa de packs de motores.

O controller continua ligado diretamente ao mainEngine. Pecas que ja possuem
categoria no pack usam o slotType nativo dessa categoria. Apenas componentes
sem categoria nativa recebem subslots novos no proprietario mecanico correto.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import re
import zipfile
from collections import defaultdict
from pathlib import Path

from gerar_jbeam_variantes import (
    AUTO_CONFIG_CEEP,
    AUTO_CONFIG_FORD,
    ULTRA_ENGINE_SLOTS,
    additional_tuning_parts,
    carburetor_parts,
    carburetor_visual_spec,
    ultra_engine_parts,
)

KIT_DIR = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT_DIR = KIT_DIR / "patched_mods"
MOD_DIR = KIT_DIR / "UltraRealismEngine_Prototype"
INTEGRATION_MARKER = "ultra_realism_integration.json"
OLD_NATIVE_PARTS_PREFIX = "vehicles/common/ultra_realism_native/"
CARB_ASSET_PATHS = [
    "vehicles/common/ultra_realism/carburetor_models.dae",
    "vehicles/common/ultra_realism/carburetor_models.materials.json",
    "vehicles/common/ultra_realism/carburetor_visual_manifest.json",
    "vehicles/common/ultra_realism/THIRD_PARTY_ASSETS.md",
]
OBSOLETE_CARB_ASSET_PATHS = {
    "vehicles/common/ultra_realism/licenses/artec_carburetor_CC_BY_3_0.txt",
}
DOWNDRAFT_CARB_FLANGE_DROP_M = 0.135
SIDEDRAFT_CARB_CENTER_DROP_M = 0.055
POWERTRAIN_RE = re.compile(
    r'\["(?:(?:classic_)?combustionEngine|ultra_combustionEngine)"\s*,\s*"mainEngine"'
)
SLOT_ROW_RE = re.compile(
    r'\[\s*"([^"]+)"\s*,\s*"([^"]*)"\s*,\s*"([^"]+)"'
    r'(?:\s*,\s*(\{[^\r\n]*\}))?\s*\]\s*,?'
)

MISSING_SHORT_BLOCK_SLOTS = [
    ["ultra_realism_pistons", "ultra_realism_pistons_cast", "Pistons"],
    ["ultra_realism_piston_rings", "ultra_realism_rings_stock", "Piston Rings"],
    ["ultra_realism_rod_bearings", "ultra_realism_bearings_stock", "Rod Bearings"],
    ["ultra_realism_crank_rods", "ultra_realism_crank_rods_stock", "Crankshaft / Connecting Rods"],
]
MISSING_HEAD_SLOTS = [
    ["ultra_realism_head_gasket", "ultra_realism_head_gasket_stock", "Head Gasket / Fasteners"],
]
MISSING_CARB_SLOTS = [
    ["ultra_realism_fuel_delivery", "ultra_realism_fuel_delivery_stock", "Fuel Delivery"],
]
FORD_VARIANT_SLOTS = [
    ["ultra_realism_short_block", "ultra_realism_short_block_stock", "Short Block"],
    ["ultra_realism_pistons", "ultra_realism_pistons_cast", "Pistons"],
    ["ultra_realism_piston_rings", "ultra_realism_rings_stock", "Piston Rings"],
    ["ultra_realism_rod_bearings", "ultra_realism_bearings_stock", "Rod Bearings"],
    ["ultra_realism_crank_rods", "ultra_realism_crank_rods_stock", "Crankshaft / Connecting Rods"],
    ["ultra_realism_camshaft", "ultra_realism_cam_stock", "Camshaft"],
    ["ultra_realism_valvetrain", "ultra_realism_valvetrain_stock", "Valvetrain"],
    ["ultra_realism_cylinder_heads", "ultra_realism_heads_stock", "Cylinder Heads"],
    ["ultra_realism_head_gasket", "ultra_realism_head_gasket_stock", "Head Gasket / Fasteners"],
    ["ultra_realism_ignition", "ultra_realism_ignition_stock", "Distributor / Ignition"],
]

CEEP_CARB_LABELS = {
    "carburetor",
    "carburetors",
    "cross-ram carburetors",
    "turbo manifold",
    "turbo intake manifold",
    "twincharger manifold",
    "supercharger manifold",
    "supercharger intake",
}
CEEP_INTAKE_GEOMETRY_LABELS = {
    "intake manifold",
    "intake",
    "turbo manifold",
    "turbo intake manifold",
    "twincharger manifold",
    "supercharger manifold",
    "supercharger intake",
    "procharger manifold",
}
CEEP_NATIVE_CATEGORY_LABELS = {
    "ultra_realism_carburetor": CEEP_CARB_LABELS,
    "ultra_realism_intake_geometry": CEEP_INTAKE_GEOMETRY_LABELS,
    "ultra_realism_carb_spacer": {
        "intake spacer",
        "spacer",
        "spacer & carburetor",
        "spacer & carburetors",
    },
    "ultra_realism_rotating_response": {"flywheel"},
    "ultra_realism_short_block": {"short block"},
    "ultra_realism_stroker_kit": {"stroker kit"},
    "ultra_realism_camshaft": {"camshaft"},
    "ultra_realism_valvetrain": {"valvetrain"},
    "ultra_realism_cylinder_heads": {"cylinder head"},
    "ultra_realism_ignition": {"distributor"},
    "ultra_realism_oil_system": {"oil pan"},
}
FORD_INTAKE_GEOMETRY_LABELS = {
    "intake",
    "intake pipe",
    "intake & exhaust",
}
FORD_NATIVE_CATEGORY_LABELS = {
    "ultra_realism_rotating_response": {"flywheel"},
    "ultra_realism_oil_system": {"oil pan"},
    "ultra_realism_intake_geometry": FORD_INTAKE_GEOMETRY_LABELS,
}
FORD_CARB_INTAKE_KEYWORDS = (
    "carburetor",
    " carb",
    "carb-",
    "-carb",
    "holley",
    "edelbrock",
    "weber",
    "2bbl",
    "4bbl",
    "quad",
    "twin carb",
    "six pack",
    "sixpack",
    "turbo",
    "supercharger",
    "twincharger",
    "blower",
    "procharger",
    "itb",
    "throttle body",
    "individual throttle",
)
FORD_CARB_INTAKE_EXCLUDES = (
    "diesel",
    "electric",
    "efi only",
)


def matching_delimiter(text: str, start: int, open_char: str, close_char: str) -> int | None:
    depth = 0
    in_string = False
    escaped = False
    line_comment = False
    block_comment = False
    i = start
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if line_comment:
            if ch == "\n":
                line_comment = False
            i += 1
            continue
        if block_comment:
            if ch == "*" and nxt == "/":
                block_comment = False
                i += 2
            else:
                i += 1
            continue
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            i += 1
            continue
        if ch == "/" and nxt == "/":
            line_comment = True
            i += 2
            continue
        if ch == "/" and nxt == "*":
            block_comment = True
            i += 2
            continue
        if ch == '"':
            in_string = True
        elif ch == open_char:
            depth += 1
        elif ch == close_char:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return None


def part_blocks(text: str) -> list[tuple[int, int]]:
    """Retorna blocos de pecas em JBeam com ou sem objeto raiz externo."""
    significant = text.lstrip()
    part_depth = 2 if significant.startswith("{") else 1
    blocks: list[tuple[int, int]] = []
    depth = 0
    part_start: int | None = None
    in_string = False
    escaped = False
    line_comment = False
    block_comment = False
    i = 0
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if line_comment:
            if ch == "\n":
                line_comment = False
            i += 1
            continue
        if block_comment:
            if ch == "*" and nxt == "/":
                block_comment = False
                i += 2
            else:
                i += 1
            continue
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            i += 1
            continue
        if ch == "/" and nxt == "/":
            line_comment = True
            i += 2
            continue
        if ch == "/" and nxt == "*":
            block_comment = True
            i += 2
            continue
        if ch == '"':
            in_string = True
        elif ch == "{":
            depth += 1
            if depth == part_depth:
                part_start = i
        elif ch == "}":
            if depth == part_depth and part_start is not None:
                blocks.append((part_start, i + 1))
                part_start = None
            depth -= 1
        i += 1
    return blocks


def part_key(text: str, block_start: int) -> str:
    prefix = text[max(0, block_start - 500) : block_start]
    matches = list(re.finditer(r'"([^"]+)"\s*:\s*$', prefix, re.MULTILINE))
    return matches[-1].group(1) if matches else ""


def slot_type(block: str) -> str:
    match = re.search(r'"slotType"\s*:\s*"([^"]+)"', block)
    return match.group(1) if match else ""


def information_name(block: str) -> str:
    match = re.search(r'"name"\s*:\s*"([^"]+)"', block)
    return match.group(1) if match else ""


def extract_airb_positions(block: str) -> list[tuple[float, float, float]]:
    return [
        tuple(map(float, match))
        for match in re.findall(
            r'\[\s*"airb[^"]*"\s*,\s*(-?[0-9.]+)\s*,\s*(-?[0-9.]+)\s*,\s*(-?[0-9.]+)',
            block,
        )
    ]


def extract_airb_nodes(block: str) -> list[str]:
    return [
        node_id
        for node_id in re.findall(
            r'\[\s*"(airb[^"]*)"\s*,\s*-?[0-9.]+\s*,\s*-?[0-9.]+\s*,\s*-?[0-9.]+',
            block,
        )
    ]


def extract_prop_positions(block: str) -> list[tuple[float, float, float]]:
    return [
        tuple(map(float, match))
        for match in re.findall(
            r'"baseTranslationGlobal"\s*:\s*\{\s*"x"\s*:\s*(-?[0-9.]+)\s*,'
            r'\s*"y"\s*:\s*(-?[0-9.]+)\s*,\s*"z"\s*:\s*(-?[0-9.]+)',
            block,
        )
    ]


def extract_prop_refs(block: str) -> list[tuple[str, str, str]]:
    match = re.search(r'"props"\s*:\s*\[', block)
    if not match:
        return []
    array_start = block.find("[", match.start())
    array_end = matching_delimiter(block, array_start, "[", "]")
    if array_end is None:
        return []
    section = block[array_start : array_end + 1]
    refs = []
    for ref, x_node, y_node in re.findall(
        r'\[\s*"[^"]+"\s*,\s*"[^"]+"\s*,\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*"([^"]+)"',
        section,
    ):
        if ref not in {"idRef:", "idRef"}:
            refs.append((ref, x_node, y_node))
    return refs


def extract_flexbody_groups(block: str) -> list[str]:
    match = re.search(r'"flexbodies"\s*:\s*\[', block)
    if not match:
        return []
    array_start = block.find("[", match.start())
    array_end = matching_delimiter(block, array_start, "[", "]")
    if array_end is None:
        return []
    groups: list[str] = []
    section = block[array_start : array_end + 1]
    for row_groups in re.findall(
        r'\[\s*"[^"]+"\s*,\s*\[([^\]]*)\]',
        section,
    ):
        for group in re.findall(r'"([^"]+)"', row_groups):
            if group not in groups:
                groups.append(group)
    return groups


def extract_slot_rows(block: str) -> list[list]:
    slots_match = re.search(r'"slots"\s*:\s*\[', block)
    if not slots_match:
        return []
    array_start = block.find("[", slots_match.start())
    array_end = matching_delimiter(block, array_start, "[", "]")
    if array_end is None:
        return []
    rows: list[list] = []
    for match in SLOT_ROW_RE.finditer(block[array_start : array_end + 1]):
        row: list = [match.group(1), match.group(2), match.group(3)]
        if row[0] == "type" and row[1] == "default":
            continue
        if match.group(4):
            try:
                row.append(json.loads(match.group(4)))
            except json.JSONDecodeError:
                pass
        rows.append(row)
    return rows


def slot_rows_text(rows: list[list], indent: str = "        ") -> str:
    return "\n".join(
        indent + json.dumps(row, separators=(",", ":"), ensure_ascii=True) + ","
        for row in rows
    )


def add_slots_to_block(block: str, rows: list[list]) -> tuple[str, int]:
    existing = extract_slot_rows(block)
    existing_types = {row[0] for row in existing}
    additions = [row for row in rows if row[0] not in existing_types]
    if not additions:
        return block, 0

    slots_match = re.search(r'"slots"\s*:\s*\[', block)
    if slots_match:
        array_start = block.find("[", slots_match.start())
        first_row_start = block.find("[", array_start + 1)
        first_row_end = (
            matching_delimiter(block, first_row_start, "[", "]")
            if first_row_start >= 0
            else None
        )
        if first_row_end is None:
            return block, 0
        line_end = block.find("\n", first_row_end)
        if line_end < 0:
            line_end = first_row_end + 1
        insert = "\n" + slot_rows_text(additions)
        return block[:line_end] + insert + block[line_end:], len(additions)

    st_match = re.search(r'"slotType"\s*:\s*"[^"]+"\s*,?', block)
    if not st_match:
        return block, 0
    table = (
        '\n    "slots": [\n'
        '        ["type","default","description"],\n'
        f"{slot_rows_text(additions)}\n"
        "    ],"
    )
    return block[: st_match.end()] + table + block[st_match.end() :], len(additions)


def patch_matching_parts(text: str, predicate, rows: list[list]) -> tuple[str, int, int]:
    changed_parts = 0
    added_rows = 0
    for start, end in reversed(part_blocks(text)):
        block = text[start:end]
        if not predicate(part_key(text, start), block):
            continue
        patched, count = add_slots_to_block(block, rows)
        if count:
            text = text[:start] + patched + text[end:]
            changed_parts += 1
            added_rows += count
    return text, changed_parts, added_rows


def strip_previous_integration(text: str) -> str:
    direct_types = ["ultra_realism_tuning", *(row[0] for row in ULTRA_ENGINE_SLOTS)]
    slot_pattern = "|".join(re.escape(value) for value in direct_types)
    text = re.sub(
        rf'(?m)^[ \t]*\["(?:{slot_pattern})"\s*,[^\r\n]*\r?\n?',
        "",
        text,
    )
    text = re.sub(
        r'(?m)^[ \t]*\["ultraRealismEngine"\s*,[^\r\n]*\r?\n?',
        "",
        text,
    )
    text = re.sub(
        r"(?m)^[ \t]*// Ultra Realism direct engine hook[^\r\n]*\r?\n?",
        "",
        text,
    )
    text = re.sub(
        r'(?m)^[ \t]*\["ultra_realism_ford_carb_[^"]*"\s*,[^\r\n]*\r?\n?',
        "",
        text,
    )
    return text


def insert_controller(
    text: str,
    slot_type_pos: int,
    main_engine_pos: int,
    config: dict,
) -> tuple[str, bool]:
    row = (
        '        ["ultraRealismEngine",'
        + json.dumps(config, separators=(",", ":"), ensure_ascii=True)
        + "],"
    )
    controller_pos = text.rfind('"controller"', slot_type_pos, main_engine_pos)
    if controller_pos >= 0:
        controller_open = text.find("[", controller_pos, main_engine_pos)
        first_row_open = text.find("[", controller_open + 1, main_engine_pos)
        if controller_open < 0 or first_row_open < 0:
            return text, False
        first_row_close = matching_delimiter(text, first_row_open, "[", "]")
        if first_row_close is None or first_row_close > main_engine_pos:
            return text, False
        line_end = text.find("\n", first_row_close)
        if line_end < 0:
            line_end = first_row_close + 1
        return text[:line_end] + "\n" + row + text[line_end:], True

    main_line_start = text.rfind("\n", 0, main_engine_pos) + 1
    indent_match = re.match(r"[ \t]*", text[main_line_start:main_engine_pos])
    indent = indent_match.group(0) if indent_match else "    "
    table = (
        f"{indent}// Ultra Realism direct engine hook\n"
        f'{indent}"controller": [\n'
        f'{indent}    ["fileName"],\n'
        f"{indent}    {row.strip()}\n"
        f"{indent}],\n"
    )
    return text[:main_line_start] + table + text[main_line_start:], True


def patch_ultra_powertrain(text: str, pack_mode: str) -> tuple[str, int, int]:
    text, engine_rows = re.subn(
        r'\["(?:classic_)?combustionEngine"\s*,\s*"mainEngine"',
        '["ultra_combustionEngine", "mainEngine"',
        text,
    )
    profile_rows = 0
    if engine_rows and '"ureEngineProfile"' not in text:

        def inject_profile(match: re.Match[str]) -> str:
            nonlocal profile_rows
            profile_rows += 1
            indent = re.match(r"[ \t]*", match.group(0)).group(0)
            inner = indent + (" " * 4 if indent else "        ")
            return f'{match.group(1)}\n{inner}"ureEngineProfile": "{pack_mode}",'

        text = re.sub(r'("mainEngine"\s*:\s*\{)', inject_profile, text, count=1)
    return text, engine_rows, profile_rows


def patch_controllers(text: str, config: dict) -> tuple[str, int]:
    changes = 0
    for match in reversed(list(POWERTRAIN_RE.finditer(text))):
        st_pos = text.rfind('"slotType"', max(0, match.start() - 30000), match.start())
        main_pos = text.find('"mainEngine"', match.end(), min(len(text), match.end() + 30000))
        if st_pos < 0 or main_pos < 0:
            continue
        text, changed = insert_controller(text, st_pos, main_pos, config)
        changes += int(changed)
    return text, changes


def archive_inventory(entries: dict[str, bytes]) -> dict:
    labels: dict[str, set[str]] = defaultdict(set)
    layouts: dict[str, list[list[list]]] = defaultdict(list)
    names: dict[str, list[str]] = defaultdict(list)
    definitions: dict[str, list[dict]] = defaultdict(list)
    owners: dict[str, list[dict]] = defaultdict(list)
    for filename, data in entries.items():
        if not filename.lower().endswith(".jbeam"):
            continue
        text = data.decode("utf-8", errors="replace")
        for start, end in part_blocks(text):
            block = text[start:end]
            st = slot_type(block)
            if not st:
                continue
            rows = extract_slot_rows(block)
            if rows:
                layouts[st].append(rows)
                for row in rows:
                    labels[row[2].strip().lower()].add(row[0])
            names[st].append(information_name(block))
            record = {
                "filename": filename,
                "partKey": part_key(text, start),
                "slotType": st,
                "name": information_name(block),
                "rows": rows,
                "airb": extract_airb_positions(block),
                "airbNodes": extract_airb_nodes(block),
                "props": extract_prop_positions(block),
                "propRefs": extract_prop_refs(block),
                "groups": extract_flexbody_groups(block),
            }
            definitions[st].append(record)
            for row in rows:
                owners[row[0]].append(record)
    return {
        "labels": labels,
        "layouts": layouts,
        "names": names,
        "definitions": definitions,
        "owners": owners,
    }


def unique_positions(records: list[dict]) -> list[tuple[float, float, float]]:
    airb = [position for record in records for position in record["airb"]]
    positions = airb or [position for record in records for position in record["props"]]
    unique: list[tuple[float, float, float]] = []
    seen = set()
    for position in positions:
        rounded = tuple(round(value, 5) for value in position)
        if rounded not in seen:
            seen.add(rounded)
            unique.append(position)
    return unique


def average_position(
    positions: list[tuple[float, float, float]],
) -> tuple[float, float, float] | None:
    if not positions:
        return None
    count = len(positions)
    return tuple(
        round(sum(position[axis] for position in positions) / count, 5)
        for axis in range(3)
    )


def representative_groups(records: list[dict], mode: str) -> list[str]:
    candidates = [record["groups"] for record in records if record["groups"]]
    if candidates:
        return copy.deepcopy(max(candidates, key=lambda groups: (len(groups), groups)))
    return ["classic_engine"] if mode == "ceep" else []


def representative_prop_refs(records: list[dict]) -> tuple[str, str, str]:
    for record in records:
        if record["propRefs"]:
            return record["propRefs"][0]
    for record in records:
        if len(record["airbNodes"]) >= 3:
            return tuple(record["airbNodes"][:3])
    return ("e2r", "e2l", "e4r")


def resolve_mount(inventory: dict, target: str, mode: str) -> dict:
    """Resolve a origem visual pelo slot, por seus owners e por owners recursivos."""
    seen = {target}
    frontier = [target]
    fallback_groups: list[str] = []
    for _depth in range(6):
        definitions = [
            record
            for current in frontier
            for record in inventory["definitions"].get(current, [])
        ]
        positions = unique_positions(definitions)
        if positions:
            return {
                "pos": average_position(positions),
                "groups": representative_groups(definitions, mode),
                "propRefs": representative_prop_refs(definitions),
                "source": "slot",
            }
        groups = representative_groups(definitions, mode)
        if groups and not fallback_groups:
            fallback_groups = groups

        owner_records = [
            record
            for current in frontier
            for record in inventory["owners"].get(current, [])
        ]
        positions = unique_positions(owner_records)
        if positions:
            return {
                "pos": average_position(positions),
                "groups": representative_groups(owner_records, mode),
                "propRefs": representative_prop_refs(owner_records),
                "source": "owner",
            }
        groups = representative_groups(owner_records, mode)
        if groups and not fallback_groups:
            fallback_groups = groups
        next_frontier = []
        for record in owner_records:
            owner_type = record["slotType"]
            if owner_type and owner_type not in seen:
                seen.add(owner_type)
                next_frontier.append(owner_type)
        frontier = next_frontier
        if not frontier:
            break

    if "lhead" in target and "v8" in target:
        position = (0.0, -1.35, 0.90)
    elif "sb_v8" in target or "stockohv" in target:
        position = (0.0, -1.45, 0.88)
    else:
        position = (0.0, -1.35, 0.90)
    return {
        "pos": position,
        "groups": fallback_groups or (["classic_engine"] if mode == "ceep" else []),
        "propRefs": ("e2r", "e2l", "e4r"),
        "source": "family-fallback",
    }


def representative_layout(layouts: list[list[list]]) -> list[list]:
    if not layouts:
        return []
    return copy.deepcopy(max(layouts, key=lambda rows: (len(rows), json.dumps(rows, sort_keys=True))))


def source_parts() -> dict[str, dict]:
    parts = {}
    parts.update(carburetor_parts())
    parts.update(additional_tuning_parts())
    parts.update(ultra_engine_parts())
    return parts


def native_target_types(inventory: dict, labels: set[str]) -> list[str]:
    result: set[str] = set()
    for label in labels:
        result.update(inventory["labels"].get(label, set()))
    return sorted(result)


def ceep_valvetrain_types(inventory: dict) -> list[str]:
    result = set(native_target_types(inventory, {"valvetrain"}))
    head_types = set(native_target_types(inventory, {"cylinder head"}))
    for head_type in head_types:
        for layout in inventory["layouts"].get(head_type, []):
            for row in layout:
                if row[2].strip().lower() in {"internals", "valvetrain"}:
                    result.add(row[0])
    return sorted(result)


def visual_mesh_names(source_key: str, source_value: dict) -> dict[str, str]:
    short_key = source_key.removeprefix("ultra_realism_carb_")
    spec = carburetor_visual_spec(source_key, source_value)
    return {
        "body": f"ure_user_{spec['sourceModel']}_{spec['orientation']}",
        "butterfly": f"ure_motion_{short_key}_butterfly",
        "slide": f"ure_motion_{short_key}_slide",
        "linkage": f"ure_motion_{short_key}_linkage",
        "filter": f"ure_filter_{short_key}",
        "tunnel": f"ure_tunnel_{short_key}",
    }


def mounted_position(mount: dict, orientation: str) -> tuple[float, float, float]:
    position = mount["pos"]
    drop = (
        DOWNDRAFT_CARB_FLANGE_DROP_M
        if orientation == "downdraft"
        else SIDEDRAFT_CARB_CENTER_DROP_M
    )
    return (
        position[0],
        position[1],
        round(position[2] - drop, 5),
    )


def add_position(
    position: tuple[float, float, float],
    offset: tuple[float, float, float],
) -> tuple[float, float, float]:
    return (
        round(position[0] + offset[0], 6),
        round(position[1] + offset[1], 6),
        round(position[2] + offset[2], 6),
    )


def prop_row(
    function_name: str,
    mesh_name: str,
    refs: tuple[str, str, str],
    position: tuple[float, float, float],
    rotation: tuple[float, float, float],
    translation: tuple[float, float, float],
) -> list:
    return [
        function_name,
        mesh_name,
        refs[0],
        refs[1],
        refs[2],
        {"x": 0, "y": 0, "z": 0},
        {"x": rotation[0], "y": rotation[1], "z": rotation[2]},
        {"x": translation[0], "y": translation[1], "z": translation[2]},
        0,
        1,
        0,
        1,
        {
            "baseTranslationGlobal": {
                "x": position[0],
                "y": position[1],
                "z": position[2],
            },
            "baseRotationGlobal": {"x": 0, "y": 0, "z": 0},
        },
    ]


def add_carb_visual(
    clone: dict,
    source_key: str,
    source_value: dict,
    mount: dict,
) -> None:
    spec = carburetor_visual_spec(source_key, source_value)
    meshes = visual_mesh_names(source_key, source_value)
    position = mounted_position(mount, spec["orientation"])
    groups = mount["groups"]
    if not groups:
        return
    flexbodies = [["mesh", "[group]:", "nonFlexMaterials"]]
    for instance in spec["bodyInstances"]:
        instance_position = add_position(position, instance)
        flexbodies.append(
            [
                meshes["body"],
                groups,
                [],
                {
                    "pos": {
                        "x": instance_position[0],
                        "y": instance_position[1],
                        "z": instance_position[2],
                    },
                    "rot": {"x": 0, "y": 0, "z": 0},
                    "scale": {
                        "x": spec["scale"],
                        "y": spec["scale"],
                        "z": spec["scale"],
                    },
                },
            ]
        )
    clone["flexbodies"] = flexbodies

    refs = tuple(mount.get("propRefs", ("e2r", "e2l", "e4r")))
    props = [
        [
            "func",
            "mesh",
            "idRef:",
            "idX:",
            "idY:",
            "baseRotation",
            "rotation",
            "translation",
            "min",
            "max",
            "offset",
            "multiplier",
        ]
    ]
    for pivot in spec["butterflyPivots"]:
        props.append(
            prop_row(
                "ure_carbThrottleVisual",
                meshes["butterfly"],
                refs,
                add_position(position, pivot),
                (0, 78, 0),
                (0, 0, 0),
            )
        )
    for pivot in spec["slidePivots"]:
        props.append(
            prop_row(
                "ure_carbSlideVisual",
                meshes["slide"],
                refs,
                add_position(position, pivot),
                (0, 0, 0),
                tuple(spec["slideTranslation"]),
            )
        )
    for pivot in spec["linkagePivots"]:
        props.append(
            prop_row(
                "ure_carbLinkageVisual",
                meshes["linkage"],
                refs,
                add_position(position, pivot),
                (0, 65, 0),
                (0, 0, 0),
            )
        )
    clone["props"] = props
    clone["ultraRealismVisual"] = {
        "mesh": meshes["body"],
        "sourceModel": spec["sourceModel"],
        "orientation": spec["orientation"],
        "scale": spec["scale"],
        "bodyInstances": len(spec["bodyInstances"]),
        "animatedButterflies": len(spec["butterflyPivots"]),
        "animatedSlides": len(spec["slidePivots"]),
        "animatedLinkages": len(spec["linkagePivots"]),
        "mountSource": mount["source"],
        "mountDropM": (
            DOWNDRAFT_CARB_FLANGE_DROP_M
            if spec["orientation"] == "downdraft"
            else SIDEDRAFT_CARB_CENTER_DROP_M
        ),
        "mountPosition": {
            "x": position[0],
            "y": position[1],
            "z": position[2],
        },
    }


def tunnel_geometry(source_value: dict) -> dict:
    carb = source_value["ultraRealismCarburetor"]
    count = int(carb["count"])
    bore_squared = (
        int(carb["primaryBarrels"]) * float(carb["primaryBoreMM"]) ** 2
        + int(carb["secondaryBarrels"]) * float(carb["secondaryBoreMM"]) ** 2
    ) * count
    venturi_squared = (
        int(carb["primaryBarrels"]) * float(carb["primaryVenturiMM"]) ** 2
        + int(carb["secondaryBarrels"]) * float(carb["secondaryVenturiMM"]) ** 2
    ) * count
    bore_equivalent = bore_squared ** 0.5
    throat_equivalent = venturi_squared ** 0.5
    length = min(0.18, 0.095 + 0.010 * count ** 0.5 + bore_equivalent * 0.00020)
    return {
        "lengthM": round(length, 5),
        "inletEquivalentDiameterMM": round(bore_equivalent * 1.10, 3),
        "outletEquivalentDiameterMM": round(bore_equivalent, 3),
        "throatEquivalentDiameterMM": round(throat_equivalent, 3),
        "surfaceRoughnessM": 0.000015,
        "materialDensityKgM3": 2700,
        "dischargeCoefficient": 0.94,
        "localLossCoefficient": 0.18,
    }


def add_tunnel_slot(clone: dict, child_slot: str) -> None:
    slots = clone.setdefault(
        "slots",
        [["type", "default", "description"]],
    )
    if not slots or slots[0][0] != "type":
        slots.insert(0, ["type", "default", "description"])
    slots[:] = [
        row
        for index, row in enumerate(slots)
        if index == 0 or len(row) < 3 or "filter" not in str(row[2]).lower()
    ]
    if child_slot not in {row[0] for row in slots[1:] if row}:
        slots.append([child_slot, "", "Filter"])


def make_tunnel_part(
    mode: str,
    source_key: str,
    source_value: dict,
    child_slot: str,
    mount: dict,
    file_group: str,
) -> dict:
    spec = carburetor_visual_spec(source_key, source_value)
    meshes = visual_mesh_names(source_key, source_value)
    position = mounted_position(mount, spec["orientation"])
    return {
        "information": {
            "authors": "OpenAI ChatGPT / local modkit",
            "name": "Tunnel Venturi",
            "value": 650,
        },
        "slotType": child_slot,
        "ultraRealismCategory": "ultra_realism_tunnel_venturi",
        "ultraRealismTunnelVenturi": tunnel_geometry(source_value),
        "ultraRealismVisual": {
            "mesh": meshes["tunnel"],
            "orientation": spec["orientation"],
            "mountSource": mount["source"],
            "mountPosition": {
                "x": position[0],
                "y": position[1],
                "z": position[2],
            },
        },
        "flexbodies": [
            ["mesh", "[group]:", "nonFlexMaterials"],
            [
                meshes["tunnel"],
                mount["groups"],
                [],
                {
                    "pos": {
                        "x": position[0],
                        "y": position[1],
                        "z": position[2],
                    },
                    "rot": {"x": 0, "y": 0, "z": 0},
                    "scale": {"x": 1, "y": 1, "z": 1},
                },
            ],
        ],
        "_ureFileGroup": file_group,
    }


def filter_geometry(source_value: dict) -> dict:
    carb = source_value["ultraRealismCarburetor"]
    count = int(carb["count"])
    primary_area = (
        math.pi
        * (float(carb["primaryBoreMM"]) / 1000.0) ** 2
        * 0.25
        * int(carb["primaryBarrels"])
        * count
    )
    secondary_area = (
        math.pi
        * (float(carb["secondaryBoreMM"]) / 1000.0) ** 2
        * 0.25
        * int(carb["secondaryBarrels"])
        * count
    )
    flow_area = max((primary_area + secondary_area) * 1.35, 0.001)
    return {
        "flowAreaM2": round(flow_area, 7),
        "mediaAreaM2": round(flow_area * 11.5, 6),
        "dischargeCoefficient": 0.97,
        "dryLossCoefficient": 0.30,
        "wetSensitivity": 2.25,
        "waterSheddingSpeedMS": 18.0,
        "materialDensityKgM3": 1180,
    }


def make_filter_part(
    source_key: str,
    source_value: dict,
    child_slot: str,
    mount: dict,
    file_group: str,
) -> dict:
    spec = carburetor_visual_spec(source_key, source_value)
    meshes = visual_mesh_names(source_key, source_value)
    position = mounted_position(mount, spec["orientation"])
    return {
        "information": {
            "authors": "OpenAI ChatGPT / local modkit",
            "name": "Matched Air Filter",
            "value": 420,
        },
        "slotType": child_slot,
        "ultraRealismCategory": "ultra_realism_intake_filter",
        "ultraRealismIntakeFilter": filter_geometry(source_value),
        "ultraRealismVisual": {
            "mesh": meshes["filter"],
            "orientation": spec["orientation"],
            "mountSource": mount["source"],
            "mountPosition": {
                "x": position[0],
                "y": position[1],
                "z": position[2],
            },
        },
        "flexbodies": [
            ["mesh", "[group]:", "nonFlexMaterials"],
            [
                meshes["filter"],
                mount["groups"],
                [],
                {
                    "pos": {
                        "x": position[0],
                        "y": position[1],
                        "z": position[2],
                    },
                    "rot": {"x": 0, "y": 0, "z": 0},
                    "scale": {"x": 1, "y": 1, "z": 1},
                },
            ],
        ],
        "_ureFileGroup": file_group,
    }


def ford_intake_supports_ure_carb(name: str) -> bool:
    lowered = name.lower()
    if any(token in lowered for token in FORD_CARB_INTAKE_EXCLUDES):
        return False
    return any(keyword in lowered for keyword in FORD_CARB_INTAKE_KEYWORDS)


def ford_carb_owner_specs(inventory: dict) -> list[dict]:
    intake_types = set(native_target_types(inventory, FORD_INTAKE_GEOMETRY_LABELS))
    specs = []
    seen = set()
    for intake_type in sorted(intake_types):
        for record in inventory["definitions"].get(intake_type, []):
            name = record["name"]
            if not ford_intake_supports_ure_carb(name):
                continue
            identity = (record["filename"], record["partKey"])
            if identity in seen:
                continue
            seen.add(identity)
            owner_hash = hashlib.sha1(
                f"{record['filename']}:{record['partKey']}".encode("utf-8")
            ).hexdigest()[:10]
            positions = unique_positions([record])
            specs.append(
                {
                    **record,
                    "childSlot": f"ultra_realism_ford_carb_{owner_hash}",
                    "mount": {
                        "pos": average_position(positions) or (0.0, -1.35, 0.90),
                        "groups": representative_groups([record], "ford"),
                        "propRefs": representative_prop_refs([record]),
                        "source": "ford-intake-airb",
                    },
                }
            )
    return specs


def generate_native_parts(mode: str, inventory: dict) -> tuple[dict[str, dict], dict[str, int]]:
    all_parts = source_parts()
    category_labels = (
        CEEP_NATIVE_CATEGORY_LABELS if mode == "ceep" else FORD_NATIVE_CATEGORY_LABELS
    )
    generated: dict[str, dict] = {}
    category_counts: dict[str, int] = {}

    for source_slot, labels in category_labels.items():
        targets = (
            ceep_valvetrain_types(inventory)
            if mode == "ceep" and source_slot == "ultra_realism_valvetrain"
            else native_target_types(inventory, labels)
        )
        candidates = [
            (key, value)
            for key, value in all_parts.items()
            if value.get("slotType") == source_slot
        ]
        for target in targets:
            preserved_slots = representative_layout(inventory["layouts"].get(target, []))
            mount = (
                resolve_mount(inventory, target, mode)
                if source_slot == "ultra_realism_carburetor"
                else None
            )
            if source_slot == "ultra_realism_short_block":
                preserved_slots.extend(
                    row for row in MISSING_SHORT_BLOCK_SLOTS
                    if row[0] not in {item[0] for item in preserved_slots}
                )
            elif source_slot == "ultra_realism_cylinder_heads":
                preserved_slots.extend(
                    row for row in MISSING_HEAD_SLOTS
                    if row[0] not in {item[0] for item in preserved_slots}
                )
            elif source_slot == "ultra_realism_carburetor":
                preserved_slots.extend(
                    row for row in MISSING_CARB_SLOTS
                    if row[0] not in {item[0] for item in preserved_slots}
                )

            target_hash = hashlib.sha1(target.encode("utf-8")).hexdigest()[:10]
            for source_key, source_value in candidates:
                clone = copy.deepcopy(source_value)
                clone["slotType"] = target
                clone["ultraRealismCategory"] = source_slot
                info = clone.setdefault("information", {})
                info["name"] = f"Ultra Realism - {info.get('name', source_key)}"
                if preserved_slots:
                    clone["slots"] = [
                        ["type", "default", "description"],
                        *copy.deepcopy(preserved_slots),
                    ]
                if mount is not None:
                    add_carb_visual(clone, source_key, source_value, mount)
                    source_hash = hashlib.sha1(source_key.encode("utf-8")).hexdigest()[:8]
                    child_slot = (
                        f"ultra_realism_tunnel_{mode}_{target_hash}_{source_hash}"
                    )
                    add_tunnel_slot(clone, child_slot)
                clone_key = f"ultra_realism_native_{mode}_{target_hash}_{source_key.removeprefix('ultra_realism_')}"
                generated[clone_key] = clone
                if mount is not None:
                    tunnel_key = (
                        f"ultra_realism_tunnel_{mode}_{target_hash}_"
                        f"{source_key.removeprefix('ultra_realism_carb_')}"
                    )
                    generated[tunnel_key] = make_tunnel_part(
                        mode,
                        source_key,
                        source_value,
                        child_slot,
                        mount,
                        f"{target}:tunnel",
                    )
                    filter_key = (
                        f"ultra_realism_filter_{mode}_{target_hash}_"
                        f"{source_key.removeprefix('ultra_realism_carb_')}"
                    )
                    generated[filter_key] = make_filter_part(
                        source_key,
                        source_value,
                        child_slot,
                        mount,
                        f"{target}:tunnel",
                    )
        category_counts[source_slot] = len(targets)

    if mode == "ford":
        candidates = [
            (key, value)
            for key, value in all_parts.items()
            if value.get("slotType") == "ultra_realism_carburetor"
        ]
        owners = ford_carb_owner_specs(inventory)
        for owner in owners:
            owner_hash = owner["childSlot"].rsplit("_", 1)[-1]
            for source_key, source_value in candidates:
                clone = copy.deepcopy(source_value)
                clone["slotType"] = owner["childSlot"]
                clone["ultraRealismCategory"] = "ultra_realism_carburetor"
                info = clone.setdefault("information", {})
                info["name"] = f"Ultra Realism - {info.get('name', source_key)}"
                clone["slots"] = [
                    ["type", "default", "description"],
                    *copy.deepcopy(MISSING_CARB_SLOTS),
                ]
                add_carb_visual(clone, source_key, source_value, owner["mount"])
                source_hash = hashlib.sha1(source_key.encode("utf-8")).hexdigest()[:8]
                child_slot = (
                    f"ultra_realism_tunnel_ford_{owner_hash}_{source_hash}"
                )
                add_tunnel_slot(clone, child_slot)
                clone_key = (
                    f"ultra_realism_native_ford_{owner_hash}_"
                    f"{source_key.removeprefix('ultra_realism_')}"
                )
                generated[clone_key] = clone
                tunnel_key = (
                    f"ultra_realism_tunnel_ford_{owner_hash}_"
                    f"{source_key.removeprefix('ultra_realism_carb_')}"
                )
                generated[tunnel_key] = make_tunnel_part(
                    mode,
                    source_key,
                    source_value,
                    child_slot,
                    owner["mount"],
                    f"{owner['childSlot']}:tunnel",
                )
                filter_key = (
                    f"ultra_realism_filter_ford_{owner_hash}_"
                    f"{source_key.removeprefix('ultra_realism_carb_')}"
                )
                generated[filter_key] = make_filter_part(
                    source_key,
                    source_value,
                    child_slot,
                    owner["mount"],
                    f"{owner['childSlot']}:tunnel",
                )
        category_counts["ultra_realism_carburetor"] = len(owners)
    return generated, category_counts


def native_parts_files(mode: str, parts: dict[str, dict]) -> dict[str, bytes]:
    """Divide o catalogo para evitar o limite pratico do loader JBeam."""
    grouped: dict[str, dict[str, dict]] = defaultdict(dict)
    for key, value in parts.items():
        file_group = value.get("_ureFileGroup", value["slotType"])
        serialized = {
            field: field_value
            for field, field_value in value.items()
            if not field.startswith("_ure")
        }
        grouped[file_group][key] = serialized

    namespace = "CEEP" if mode == "ceep" else "ford_engine_pack"
    files: dict[str, bytes] = {}
    for target, target_parts in sorted(grouped.items()):
        target_hash = hashlib.sha1(target.encode("utf-8")).hexdigest()[:10]
        filename = (
            f"vehicles/common/{namespace}/ultra_realism_native/"
            f"ure_{mode}_{target_hash}.jbeam"
        )
        files[filename] = (
            json.dumps(target_parts, indent=2, ensure_ascii=True) + "\n"
        ).encode("utf-8")
    return files


def patch_ceep_hierarchy(text: str, inventory: dict) -> tuple[str, dict[str, int]]:
    short_types = set(native_target_types(inventory, {"short block"}))
    head_types = set(native_target_types(inventory, {"cylinder head"}))
    carb_types = set(native_target_types(inventory, CEEP_CARB_LABELS))
    stats: dict[str, int] = {}

    text, parts, rows = patch_matching_parts(
        text, lambda _key, block: slot_type(block) in short_types, MISSING_SHORT_BLOCK_SLOTS
    )
    stats["shortBlockOwners"] = parts
    stats["shortBlockRows"] = rows
    text, parts, rows = patch_matching_parts(
        text, lambda _key, block: slot_type(block) in head_types, MISSING_HEAD_SLOTS
    )
    stats["headOwners"] = parts
    stats["headRows"] = rows
    text, parts, rows = patch_matching_parts(
        text, lambda _key, block: slot_type(block) in carb_types, MISSING_CARB_SLOTS
    )
    stats["carbOwners"] = parts
    stats["carbRows"] = rows
    return text, stats


def remove_dedicated_carb_flexbodies(block: str) -> tuple[str, int]:
    match = re.search(r'"flexbodies"\s*:\s*\[', block)
    if not match:
        return block, 0
    array_start = block.find("[", match.start())
    array_end = matching_delimiter(block, array_start, "[", "]")
    if array_end is None:
        return block, 0
    section = block[array_start : array_end + 1]
    section, count = re.subn(
        r'(?mi)^[ \t]*\["[^"\r\n]*carb[^"\r\n]*"\s*,[^\r\n]*\r?\n?',
        "",
        section,
    )
    return block[:array_start] + section + block[array_end + 1 :], count


def patch_ford_hierarchy(
    text: str,
    inventory: dict,
    filename: str,
) -> tuple[str, dict[str, int]]:
    stats: dict[str, int] = {}
    text, parts, rows = patch_matching_parts(
        text,
        lambda _key, block: "engine_variant" in slot_type(block).lower(),
        FORD_VARIANT_SLOTS,
    )
    stats["variantOwners"] = parts
    stats["variantRows"] = rows
    owner_specs = {
        (spec["filename"], spec["partKey"]): spec
        for spec in ford_carb_owner_specs(inventory)
    }
    carb_parts = 0
    carb_rows = 0
    removed_meshes = 0
    for start, end in reversed(part_blocks(text)):
        key = part_key(text, start)
        spec = owner_specs.get((filename, key))
        if spec is None:
            continue
        block = text[start:end]
        block, removed = remove_dedicated_carb_flexbodies(block)
        block, added = add_slots_to_block(
            block,
            [
                [spec["childSlot"], "", "Carburetor"],
                [
                    "ultra_realism_carb_spacer",
                    "ultra_realism_spacer_none",
                    "Carburetor Spacer / Plenum",
                ],
                [
                    "ultra_realism_fuel_delivery",
                    "ultra_realism_fuel_delivery_stock",
                    "Fuel Delivery",
                ],
            ],
        )
        if added or removed:
            text = text[:start] + block + text[end:]
        if added:
            carb_parts += 1
            carb_rows += added
        removed_meshes += removed
    stats["carbIntakeOwners"] = carb_parts
    stats["carbIntakeRows"] = carb_rows
    stats["nativeCarbMeshesRemoved"] = removed_meshes
    return text, stats


def carb_asset_entries() -> dict[str, bytes]:
    assets = {}
    for relative in CARB_ASSET_PATHS:
        path = MOD_DIR / relative
        if not path.exists():
            raise SystemExit(
                f"[ERRO] Asset de carburador ausente: {path}. "
                "Execute blender --background --python "
                "scripts/gerar_modelos_carburadores_usuario.py"
            )
        assets[relative] = path.read_bytes()
    return assets


def patch_zip(source: Path, output: Path, mode: str, config: dict) -> dict:
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(source, "r") as zin:
        entries = {
            info.filename: zin.read(info.filename)
            for info in zin.infolist()
            if info.filename != INTEGRATION_MARKER
            and not info.filename.startswith(OLD_NATIVE_PARTS_PREFIX)
            and "/ultra_realism_native/" not in info.filename
            and info.filename not in OBSOLETE_CARB_ASSET_PATHS
        }
        infos = {info.filename: info for info in zin.infolist()}

    inventory = archive_inventory(entries)
    native_parts, native_categories = generate_native_parts(mode, inventory)
    generated_native_files = native_parts_files(mode, native_parts)
    modified_files = 0
    patched_engines = 0
    hierarchy_totals: dict[str, int] = defaultdict(int)

    for filename, data in list(entries.items()):
        if not filename.lower().endswith(".jbeam"):
            continue
        original = data.decode("utf-8", errors="replace")
        text = strip_previous_integration(original)
        text, _, _ = patch_ultra_powertrain(text, mode)
        text, controller_count = patch_controllers(text, config)
        if mode == "ceep":
            text, hierarchy = patch_ceep_hierarchy(text, inventory)
        else:
            text, hierarchy = patch_ford_hierarchy(text, inventory, filename)
        for key, value in hierarchy.items():
            hierarchy_totals[key] += value
        patched_engines += controller_count
        if text != original:
            entries[filename] = text.encode("utf-8")
            modified_files += 1

    entries.update(generated_native_files)
    entries.update(carb_asset_entries())
    marker = {
        "integration": "UltraRealismEngine",
        "integrationMode": "native-slot-hierarchy",
        "ultraCombustionEngineHook": True,
        "packMode": mode,
        "source": source.name,
        "patchedEngineDefinitions": patched_engines,
        "directEngineSlotCount": 0,
        "nativeGeneratedParts": len(native_parts),
        "nativeGeneratedFiles": len(generated_native_files),
        "nativeCategoryTargetCounts": native_categories,
        "carburetorSourceModels": 8,
        "carburetorAnimatedConfigurations": 40,
        "matchedAirFilterVisualModels": 40,
        "tunnelVenturiVisualModels": 40,
        "downdraftCarburetorFlangeDropM": DOWNDRAFT_CARB_FLANGE_DROP_M,
        "sidedraftCarburetorCenterDropM": SIDEDRAFT_CARB_CENTER_DROP_M,
        "carburetorAsset": CARB_ASSET_PATHS[0],
        "hierarchy": dict(hierarchy_totals),
    }
    entries[INTEGRATION_MARKER] = json.dumps(marker, indent=2).encode("utf-8")

    with zipfile.ZipFile(
        output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6
    ) as zout:
        for filename, data in entries.items():
            info = infos.get(filename)
            if info is not None:
                zout.writestr(info, data)
            else:
                zout.writestr(filename, data)

    return {
        "files": modified_files,
        "engines": patched_engines,
        "nativeParts": len(native_parts),
        **dict(hierarchy_totals),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ceep", type=Path, required=True)
    parser.add_argument("--ford", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    args = parser.parse_args()

    jobs = [
        (
            args.ceep.expanduser().resolve(),
            "classic_engine_expansion_pack.zip",
            "ceep",
            AUTO_CONFIG_CEEP,
        ),
        (
            args.ford.expanduser().resolve(),
            "Ford_Engine_Pack_JITTERUSA.zip",
            "ford",
            AUTO_CONFIG_FORD,
        ),
    ]
    for source, output_name, mode, config in jobs:
        if not source.exists():
            raise SystemExit(f"[ERRO] ZIP nao encontrado: {source}")
        output = args.output_dir.expanduser().resolve() / output_name
        result = patch_zip(source, output, mode, config)
        if result["engines"] < 1:
            raise SystemExit(
                f"[ERRO] {output.name}: nenhum motor recebeu hook ultraRealismEngine. "
                "Verifique se o ZIP de origem é o pack CEEP/Ford correto."
            )
        print(
            f"[OK] {output}: {result['engines']} motores, "
            f"{result['nativeParts']} pecas nativas URE, "
            f"{result['files']} arquivos JBeam alterados"
        )


if __name__ == "__main__":
    main()
