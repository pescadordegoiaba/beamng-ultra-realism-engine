#!/usr/bin/env python3
"""
Gera pecas JBeam do UltraRealismEngine para os veiculos suportados.

O resultado sao partes selecionaveis no slot "Additional Modification".
"""
from __future__ import annotations

import json
from pathlib import Path

KIT_DIR = Path(__file__).resolve().parent.parent
MOD_DIR = KIT_DIR / "UltraRealismEngine_Prototype"

COMMON = {
    "enableEngineEffect": True,
    "enableFrictionFallback": False,
    "debugLog": False,
    "allowStall": False,
    "allowLockup": False,
    "failureAggression": 0.48,
    "autoDetectEngine": False,
    "autoFuelingMode": False,
    "preferCarburetor": False,
    "autoTuneVECurve": False,
    "autoMinDisplacementL": 0.6,
    "autoMaxDisplacementL": 18.0,
    "autoTorquePerLiterNm": 0,
    "useBeamNGEnvironment": False,
    "airTempC": 25,
    "pressurePa": 101325,
    "humidity": 0.45,
    "fuelDensityKgM3": 740,
    "fuelOctaneRON": 95,
    "referenceOctaneRON": 95,
    "stoichAFR": 14.7,
    "powerAFR": 12.8,
    "carbThrottleBoreMM": 38,
    "carbVenturiMM": 27,
    "mainJetMM": 1.18,
    "jetDischargeCoef": 0.74,
    "carbMinSignalPa": 250,
    "carbFullSignalPa": 4600,
    "carbIdealAirMS": 82,
    "carbChokeAirMS": 145,
    "carbSonicStartMS": 230,
    "carbSonicEndMS": 305,
    "autoDetectCarbSetup": True,
    "carbCount": 1,
    "carbBarrels": 1,
    "carbProgressive": False,
    "secondaryThrottleStart": 0.52,
    "carbDischargeCoef": 0.82,
    "throttleBodyDiameterMM": 55,
    "throttleBodyCount": 1,
    "throttleBodyDischargeCoef": 0.86,
    "runnerDischargeCoef": 0.88,
    "valveDischargeCoef": 0.72,
    "runnerFrictionFactor": 0.028,
    "intakeLocalLossCoef": 0.85,
    "powerValveThrottle": 0.72,
    "powerValveFuelMult": 1.18,
    "closedThrottleVECoef": 0.18,
    "idleCircuitThrottle": 0.34,
    "chokeFuelMult": 0.82,
    "fuelPumpKgS": 0.018,
    "chokeBelowC": 8,
    "fullChokeC": -15,
    "chokeDisableRPM": 2600,
    "injectorCCMin": 240,
    "injectorCount": 4,
    "baseTimingDeg": 12,
    "rpmTimingGainDeg": 24,
    "loadTimingRetardDeg": 10,
    "hotAirTimingRetardPerC": 0.05,
    "timingToleranceDeg": 10,
    "startupProtectionSeconds": 6.0,
    "startMinTorqueFactor": 0.94,
    "startFailureSuppression": 0.75,
    "stallDelaySeconds": 2.5,
    "valveTrainExpansionMMPerC": 0.0012,
    "minHotValveLashMM": 0.025,
    "maxValveLashMM": 0.55,
    "referenceCompressionRatio": 9.5,
    "pistonOptimalTempC": 105,
    "oilOptimalTempC": 90,
    "pistonSeizureTempC": 285,
    "coldPistonLoss": 0.075,
    "coldOilFrictionLoss": 0.10,
    "hotPistonLoss": 0.48,
    "frictionPenaltyNm": 38,
    "dynamicFrictionPenalty": 0.010,
    "suspensionAffectsGrip": True,
    "enableSuspensionBeamEffects": True,
    "damperFadeStartC": 95,
    "damperFadeEndC": 175,
    "damperMinCoef": 0.58,
    "springMinCoef": 0.92,
    "suspensionApplyInterval": 0.20,
    "cgHeightM": 0.55,
    "trackWidthM": 1.55,
    "wheelbaseM": 2.60,
    "steeringToLateralG": 0.82,
    "throttleToLongG": 0.42,
    "brakeToLongG": 0.95,
}

VEHICLES = {
    "covet": {
        "slotType": "covet_mod",
        "display": "Ibishu Covet 1.5 carb",
        "config": {
            "fuelingMode": "carb",
            "displacementL": 1.5,
            "idleRPM": 850,
            "redlineRPM": 6500,
            "veBase": 0.56,
            "vePeakGain": 0.35,
            "vePeakRPM": 4200,
            "veSpreadRPM": 1750,
            "carbThrottleBoreMM": 34,
            "carbVenturiMM": 25,
            "mainJetMM": 1.08,
            "fuelPumpKgS": 0.014,
            "idleFuelKgS": 0.00010,
            "accelPumpKgS": 0.0012,
            "injectorCCMin": 185,
            "injectorCount": 4,
            "baseTimingDeg": 10,
            "rpmTimingGainDeg": 25,
            "loadTimingRetardDeg": 9,
            "fuelOctaneRON": 95,
            "frictionPenaltyNm": 28,
            "cgHeightM": 0.52,
            "trackWidthM": 1.43,
            "wheelbaseM": 2.40,
        },
    },
    "pickup": {
        "slotType": "pickup_mod",
        "display": "Gavril D-Series 5.5 V8 carb",
        "config": {
            "fuelingMode": "carb",
            "displacementL": 5.5,
            "idleRPM": 700,
            "redlineRPM": 5200,
            "veBase": 0.58,
            "vePeakGain": 0.30,
            "vePeakRPM": 3600,
            "veSpreadRPM": 1700,
            "carbThrottleBoreMM": 54,
            "carbVenturiMM": 39,
            "mainJetMM": 1.55,
            "fuelPumpKgS": 0.050,
            "idleFuelKgS": 0.00038,
            "accelPumpKgS": 0.0045,
            "powerAFR": 12.6,
            "baseTimingDeg": 12,
            "rpmTimingGainDeg": 20,
            "loadTimingRetardDeg": 12,
            "fuelOctaneRON": 93,
            "frictionPenaltyNm": 55,
            "cgHeightM": 0.72,
            "trackWidthM": 1.70,
            "wheelbaseM": 3.10,
            "steeringToLateralG": 0.68,
            "throttleToLongG": 0.34,
            "brakeToLongG": 0.82,
        },
    },
    "vivace": {
        "slotType": "vivace_mod",
        "display": "Cherrier Vivace 1.6 EFI",
        "config": {
            "fuelingMode": "injection",
            "displacementL": 1.6,
            "idleRPM": 750,
            "redlineRPM": 6600,
            "veBase": 0.62,
            "vePeakGain": 0.36,
            "vePeakRPM": 5200,
            "veSpreadRPM": 2000,
            "injectorCCMin": 330,
            "injectorCount": 4,
            "powerAFR": 12.4,
            "baseTimingDeg": 10,
            "rpmTimingGainDeg": 28,
            "loadTimingRetardDeg": 12,
            "hotAirTimingRetardPerC": 0.07,
            "fuelOctaneRON": 98,
            "frictionPenaltyNm": 32,
            "cgHeightM": 0.54,
            "trackWidthM": 1.57,
            "wheelbaseM": 2.67,
        },
    },
    "etk800": {
        "slotType": "etk800_mod",
        "display": "ETK 800 3.0 I6 EFI",
        "config": {
            "fuelingMode": "injection",
            "displacementL": 3.0,
            "idleRPM": 700,
            "redlineRPM": 6500,
            "veBase": 0.64,
            "vePeakGain": 0.34,
            "vePeakRPM": 5000,
            "veSpreadRPM": 2100,
            "injectorCCMin": 380,
            "injectorCount": 6,
            "powerAFR": 12.5,
            "baseTimingDeg": 12,
            "rpmTimingGainDeg": 26,
            "loadTimingRetardDeg": 11,
            "hotAirTimingRetardPerC": 0.06,
            "fuelOctaneRON": 98,
            "frictionPenaltyNm": 42,
            "cgHeightM": 0.56,
            "trackWidthM": 1.62,
            "wheelbaseM": 2.86,
        },
    },
    "bastion": {
        "slotType": "bastion_mod",
        "display": "Bruckell Bastion 5.7 V8 EFI",
        "config": {
            "fuelingMode": "injection",
            "displacementL": 5.7,
            "idleRPM": 650,
            "redlineRPM": 6200,
            "veBase": 0.65,
            "vePeakGain": 0.32,
            "vePeakRPM": 4800,
            "veSpreadRPM": 2200,
            "injectorCCMin": 420,
            "injectorCount": 8,
            "powerAFR": 12.5,
            "baseTimingDeg": 12,
            "rpmTimingGainDeg": 24,
            "loadTimingRetardDeg": 13,
            "hotAirTimingRetardPerC": 0.07,
            "fuelOctaneRON": 95,
            "frictionPenaltyNm": 58,
            "cgHeightM": 0.58,
            "trackWidthM": 1.65,
            "wheelbaseM": 2.92,
            "throttleToLongG": 0.48,
            "brakeToLongG": 1.02,
        },
    },
    "sunburst2": {
        "slotType": "sunburst2_mod",
        "display": "Hirochi Sunburst 2.0 EFI",
        "config": {
            "fuelingMode": "injection",
            "displacementL": 2.0,
            "idleRPM": 800,
            "redlineRPM": 7000,
            "veBase": 0.61,
            "vePeakGain": 0.37,
            "vePeakRPM": 5400,
            "veSpreadRPM": 2100,
            "injectorCCMin": 360,
            "injectorCount": 4,
            "powerAFR": 12.3,
            "baseTimingDeg": 12,
            "rpmTimingGainDeg": 28,
            "loadTimingRetardDeg": 12,
            "hotAirTimingRetardPerC": 0.07,
            "fuelOctaneRON": 98,
            "frictionPenaltyNm": 36,
            "cgHeightM": 0.55,
            "trackWidthM": 1.53,
            "wheelbaseM": 2.65,
        },
    },
}


COMPAT_SLOT_TYPES = {
    # Stock vehicles touched by CEEP and Ford_Engine_Pack_JITTERUSA.
    "barstow": "barstow_mod",
    "bluebuck": "bluebuck_mod",
    "bolide": "bolide_mod",
    "burnside": "burnside_mod",
    "covet": "covet_mod",
    "dumptruck": "dumptruck_mod",
    "etk800": "etk800_mod",
    "etkc": "etkc_mod",
    "etki": "etki_mod",
    "fullsize": "fullsize_mod",
    "lansdale": "lansdale_mod",
    "legran": "legran_mod",
    "md_series": "md_series_mod",
    "midtruck": "midtruck_mod",
    "midsize": "midsize_mod",
    "miramar": "miramar_mod",
    "moonhawk": "moonhawk_mod",
    "nine": "nine_mod",
    "pessima": "pessima_mod",
    "pickup": "pickup_mod",
    "racetruck": "racetruck_mod",
    "roamer": "roamer_mod",
    "scintilla": "scintilla_mod",
    "sunburst2": "sunburst2_mod",
    "us_semi": "us_semi_mod",
    "van": "van_mod",
    "vivace": "vivace_mod",
    "wendover": "wendover_mod",
    "wl40": "wl40_mod",

    # Ford pack vehicles are commonly installed by separate vehicle mods.
    # The engine pack only ships powertrain parts, so these assumed mod slots are
    # harmless when the matching vehicle is not installed.
    "65stang": "65stang_mod",
    "barrettbronco": "barrettbronco_mod",
    "bronco_LM": "bronco_LM_mod",
    "crownvic": "crownvic_mod",
    "hoonicorn": "hoonicorn_mod",
    "rs200": "rs200_mod",
    "s550": "s550_mod",
}

AUTO_CONFIG = {
    "fuelingMode": "auto",
    "autoDetectEngine": True,
    "autoFuelingMode": True,
    "preferCarburetor": False,
    "autoTuneVECurve": True,
    "autoDetectCarbSetup": True,
    "debugLog": False,
    "diagnosticLog": False,
    "climatePreset": "game_environment",
    "useBeamNGEnvironment": True,
}

AUTO_CONFIG_CEEP = {
    **AUTO_CONFIG,
    "integrationMode": "ceep",
    "preferCarburetor": True,
}
AUTO_CONFIG_FORD = {
    **AUTO_CONFIG,
    "integrationMode": "ford",
    "preferCarburetor": False,
}

def build_auto_config(extra: dict | None = None) -> dict:
    out = {}
    out.update(AUTO_CONFIG)
    if extra:
        out.update(extra)
    return out


ULTRA_ENGINE_SLOTS = [
    ["ultra_realism_carburetor", "", "Carburetor Assembly"],
    ["ultra_realism_intake_geometry", "ultra_realism_intake_stock", "Intake Manifold Geometry", {"coreSlot": True}],
    ["ultra_realism_carb_spacer", "ultra_realism_spacer_none", "Carburetor Spacer / Plenum", {"coreSlot": True}],
    ["ultra_realism_fuel_delivery", "ultra_realism_fuel_delivery_stock", "Fuel Delivery", {"coreSlot": True}],
    ["ultra_realism_rotating_response", "ultra_realism_rotating_stock", "Damper / Flywheel Response", {"coreSlot": True}],
    ["ultra_realism_short_block", "ultra_realism_short_block_stock", "Short Block", {"coreSlot": True}],
    ["ultra_realism_stroker_kit", "ultra_realism_stroker_stock", "Stroker / Bore Geometry", {"coreSlot": True}],
    ["ultra_realism_pistons", "ultra_realism_pistons_cast", "Pistons", {"coreSlot": True}],
    ["ultra_realism_piston_rings", "ultra_realism_rings_stock", "Piston Rings", {"coreSlot": True}],
    ["ultra_realism_rod_bearings", "ultra_realism_bearings_stock", "Rod Bearings", {"coreSlot": True}],
    ["ultra_realism_crank_rods", "ultra_realism_crank_rods_stock", "Crankshaft / Connecting Rods", {"coreSlot": True}],
    ["ultra_realism_camshaft", "ultra_realism_cam_stock", "Camshaft", {"coreSlot": True}],
    ["ultra_realism_valvetrain", "ultra_realism_valvetrain_stock", "Valvetrain", {"coreSlot": True}],
    ["ultra_realism_cylinder_heads", "ultra_realism_heads_stock", "Cylinder Heads", {"coreSlot": True}],
    ["ultra_realism_head_gasket", "ultra_realism_head_gasket_stock", "Head Gasket / Fasteners", {"coreSlot": True}],
    ["ultra_realism_ignition", "ultra_realism_ignition_stock", "Distributor / Ignition", {"coreSlot": True}],
    ["ultra_realism_oil_system", "ultra_realism_oil_stock", "Oil System", {"coreSlot": True}],
]

CEEP_SYNC_DEFAULTS = {
    "ultra_realism_carburetor": "ultra_realism_ceep_sync_carburetor",
    "ultra_realism_intake_geometry": "ultra_realism_ceep_sync_intake_geometry",
    "ultra_realism_carb_spacer": "ultra_realism_ceep_sync_carb_spacer",
    "ultra_realism_fuel_delivery": "ultra_realism_ceep_sync_fuel_delivery",
    "ultra_realism_rotating_response": "ultra_realism_ceep_sync_rotating_response",
    "ultra_realism_short_block": "ultra_realism_ceep_sync_short_block",
    "ultra_realism_stroker_kit": "ultra_realism_ceep_sync_stroker_kit",
    "ultra_realism_pistons": "ultra_realism_ceep_sync_pistons",
    "ultra_realism_piston_rings": "ultra_realism_ceep_sync_piston_rings",
    "ultra_realism_rod_bearings": "ultra_realism_ceep_sync_rod_bearings",
    "ultra_realism_crank_rods": "ultra_realism_ceep_sync_crank_rods",
    "ultra_realism_camshaft": "ultra_realism_ceep_sync_camshaft",
    "ultra_realism_valvetrain": "ultra_realism_ceep_sync_valvetrain",
    "ultra_realism_cylinder_heads": "ultra_realism_ceep_sync_cylinder_heads",
    "ultra_realism_head_gasket": "ultra_realism_ceep_sync_head_gasket",
    "ultra_realism_ignition": "ultra_realism_ceep_sync_ignition",
    "ultra_realism_oil_system": "ultra_realism_ceep_sync_oil_system",
}

FORD_SYNC_DEFAULTS = {
    slot_type: part_name.replace("_ceep_", "_ford_")
    for slot_type, part_name in CEEP_SYNC_DEFAULTS.items()
}


def native_sync_slots(defaults: dict[str, str], pack_name: str) -> list[list]:
    return [
        [
            slot_type,
            defaults[slot_type],
            f"{description} ({pack_name} Native / Override)",
            *row[3:],
        ]
        for row in ULTRA_ENGINE_SLOTS
        for slot_type, _, description in [row[:3]]
    ]


CEEP_ENGINE_SLOTS = native_sync_slots(CEEP_SYNC_DEFAULTS, "CEEP")
FORD_ENGINE_SLOTS = native_sync_slots(FORD_SYNC_DEFAULTS, "Ford")


def torque_curve(points: list[tuple[int, float]]) -> list[list[float | int | str]]:
    return [["rpm", "torque"], *[[rpm, torque] for rpm, torque in points]]


def part(slot_type: str, name: str, value: int = 0, main_engine: dict | None = None) -> dict:
    out: dict = {
        "information": {
            "authors": "OpenAI ChatGPT / local modkit",
            "name": name,
            "value": value,
        },
        "slotType": slot_type,
    }
    if main_engine:
        out["mainEngine"] = main_engine
    return out


def carb_part(
    name: str,
    model_id: int,
    count: int,
    primary_barrels: int,
    secondary_barrels: int,
    primary_bore_mm: float,
    secondary_bore_mm: float,
    primary_venturi_mm: float,
    secondary_venturi_mm: float,
    main_jet_mm: float,
    rated_cfm: float,
    secondary_type: str,
    secondary_start: float,
    discharge_coef: float = 0.82,
    booster_signal_coef: float = 1.0,
    accel_pump_coef: float = 1.0,
) -> dict:
    out = part("ultra_realism_carburetor", name, 800 + int(rated_cfm * 2))
    out["ultraRealismCarburetor"] = {
        "modelId": model_id,
        "count": count,
        "primaryBarrels": primary_barrels,
        "secondaryBarrels": secondary_barrels,
        "primaryBoreMM": primary_bore_mm,
        "secondaryBoreMM": secondary_bore_mm,
        "primaryVenturiMM": primary_venturi_mm,
        "secondaryVenturiMM": secondary_venturi_mm,
        "mainJetMM": main_jet_mm,
        "ratedCFM": rated_cfm,
        "ratingPressureDropPa": 10159 if primary_barrels + secondary_barrels <= 2 else 5079,
        "secondaryType": secondary_type,
        "secondaryStart": secondary_start,
        "dischargeCoef": discharge_coef,
        "boosterSignalCoef": booster_signal_coef,
        "accelPumpCoef": accel_pump_coef,
    }
    return out


def carburetor_parts() -> dict[str, dict]:
    specs = [
        # Weber downdraft and sidedraft assemblies. Factory DGV/DCOE dimensions
        # follow Weber data; multi-carb CFM is the total assembly capacity.
        ("weber_3236_dgv", "Weber 32/36 DGV Progressive", 323601, 1, 1, 1, 32, 36, 26, 27, 1.375, 300, "progressive", 0.44, 0.82, 1.08, 1.00),
        ("weber_3236_dgev", "Weber 32/36 DGEV Progressive", 323602, 1, 1, 1, 32, 36, 26, 27, 1.390, 310, "progressive", 0.42, 0.82, 1.08, 1.03),
        ("twin_weber_3236", "Twin Weber 32/36 DGV Progressive", 323603, 2, 1, 1, 32, 36, 26, 27, 1.400, 600, "progressive", 0.42, 0.83, 1.08, 1.05),
        ("weber_38_dgas", "Weber 38 DGAS Synchronous", 380101, 1, 2, 0, 38, 38, 30, 30, 1.450, 390, "synchronous", 0.00, 0.83, 1.04, 1.05),
        ("twin_weber_38_dgas", "Twin Weber 38 DGAS Synchronous", 380102, 2, 2, 0, 38, 38, 30, 30, 1.500, 780, "synchronous", 0.00, 0.84, 1.04, 1.08),
        ("weber_40_dcoe_28", "Weber 40 DCOE - 28 mm Venturi", 400128, 1, 2, 0, 40, 40, 28, 28, 1.100, 340, "synchronous", 0.00, 0.84, 1.12, 1.05),
        ("twin_weber_40_dcoe_30", "Twin Weber 40 DCOE - 30 mm Venturi", 400230, 2, 2, 0, 40, 40, 30, 30, 1.150, 760, "synchronous", 0.00, 0.85, 1.10, 1.08),
        ("triple_weber_40_dcoe_30", "Triple Weber 40 DCOE - 30 mm Venturi", 400330, 3, 2, 0, 40, 40, 30, 30, 1.150, 1140, "synchronous", 0.00, 0.85, 1.10, 1.10),
        ("quad_weber_40_dcoe_32", "Quad Weber 40 DCOE - 32 mm Venturi", 400432, 4, 2, 0, 40, 40, 32, 32, 1.250, 1680, "synchronous", 0.00, 0.86, 1.04, 1.12),
        ("six_weber_40_dcoe_32", "Six Weber 40 DCOE - 32 mm Venturi", 400632, 6, 2, 0, 40, 40, 32, 32, 1.250, 2520, "synchronous", 0.00, 0.86, 1.04, 1.15),
        ("weber_45_dcoe_34", "Weber 45 DCOE - 34 mm Venturi", 450134, 1, 2, 0, 45, 45, 34, 34, 1.350, 470, "synchronous", 0.00, 0.85, 1.05, 1.08),
        ("twin_weber_45_dcoe_36", "Twin Weber 45 DCOE - 36 mm Venturi", 450236, 2, 2, 0, 45, 45, 36, 36, 1.450, 1040, "synchronous", 0.00, 0.86, 1.00, 1.12),
        ("triple_weber_45_dcoe_36", "Triple Weber 45 DCOE - 36 mm Venturi", 450336, 3, 2, 0, 45, 45, 36, 36, 1.450, 1560, "synchronous", 0.00, 0.86, 1.00, 1.14),
        ("quad_weber_45_dcoe_38", "Quad Weber 45 DCOE - 38 mm Venturi", 450438, 4, 2, 0, 45, 45, 38, 38, 1.550, 2240, "synchronous", 0.00, 0.87, 0.96, 1.16),
        ("weber_48_idf_40", "Weber 48 IDF - 40 mm Venturi", 480140, 1, 2, 0, 48, 48, 40, 40, 1.650, 600, "synchronous", 0.00, 0.87, 0.94, 1.12),
        ("quad_weber_48_ida_40", "Quad Weber 48 IDA - 40 mm Venturi", 480440, 4, 2, 0, 48, 48, 40, 40, 1.700, 2400, "synchronous", 0.00, 0.88, 0.94, 1.18),

        # Holley-style 1, 2 and 4 barrel carburetors.
        ("holley_1904_1bbl", "Holley 1904 1-Barrel 190 CFM", 190401, 1, 1, 0, 36, 36, 28, 28, 1.400, 190, "synchronous", 0.00, 0.80, 1.14, 0.92),
        ("holley_2300_350", "Holley 2300 2-Barrel 350 CFM", 230035, 1, 2, 0, 38, 38, 30, 30, 1.600, 350, "synchronous", 0.00, 0.82, 1.08, 1.00),
        ("holley_2300_500", "Holley 2300 2-Barrel 500 CFM", 230050, 1, 2, 0, 42.9, 42.9, 36.8, 36.8, 1.750, 500, "synchronous", 0.00, 0.84, 1.00, 1.08),
        ("holley_4160_390_vs", "Holley 4160 4-Barrel 390 CFM Vacuum Secondary", 416039, 1, 2, 2, 39.7, 39.7, 27.5, 27.5, 1.600, 390, "vacuum", 0.52, 0.82, 1.12, 0.95),
        ("holley_4160_600_vs", "Holley 4160 4-Barrel 600 CFM Vacuum Secondary", 416060, 1, 2, 2, 39.7, 39.7, 31.8, 31.8, 1.680, 600, "vacuum", 0.48, 0.83, 1.08, 1.00),
        ("holley_4150_600_dp", "Holley 4150 4-Barrel 600 CFM Double Pumper", 415060, 1, 2, 2, 39.7, 39.7, 31.8, 31.8, 1.700, 600, "mechanical", 0.42, 0.84, 1.04, 1.18),
        ("holley_4150_650_dp", "Holley 4150 4-Barrel 650 CFM Double Pumper", 415065, 1, 2, 2, 41.3, 41.3, 33.0, 33.0, 1.750, 650, "mechanical", 0.40, 0.84, 1.02, 1.20),
        ("holley_4150_700_dp", "Holley 4150 4-Barrel 700 CFM Double Pumper", 415070, 1, 2, 2, 42.9, 42.9, 34.3, 34.3, 1.780, 700, "mechanical", 0.39, 0.85, 1.00, 1.22),
        ("holley_4150_750_vs", "Holley 4150 4-Barrel 750 CFM Vacuum Secondary", 415075, 1, 2, 2, 42.9, 42.9, 35.0, 35.0, 1.780, 750, "vacuum", 0.46, 0.85, 1.00, 1.05),
        ("holley_4150_750_dp", "Holley 4150 4-Barrel 750 CFM Double Pumper", 415175, 1, 2, 2, 42.9, 42.9, 35.0, 35.0, 1.780, 750, "mechanical", 0.38, 0.85, 0.98, 1.24),
        ("holley_4150_800_dp", "Holley 4150 4-Barrel 800 CFM Double Pumper", 415080, 1, 2, 2, 43.7, 43.7, 36.0, 36.0, 1.850, 800, "mechanical", 0.37, 0.86, 0.96, 1.26),
        ("holley_4150_850_dp", "Holley 4150 4-Barrel 850 CFM Double Pumper", 415085, 1, 2, 2, 44.5, 44.5, 37.0, 37.0, 1.900, 850, "mechanical", 0.36, 0.86, 0.94, 1.28),
        ("holley_4500_950", "Holley 4500 Dominator 950 CFM", 450095, 1, 2, 2, 50.8, 50.8, 42.0, 42.0, 2.000, 950, "mechanical", 0.34, 0.87, 0.90, 1.30),
        ("holley_4500_1050", "Holley 4500 Dominator 1050 CFM", 450105, 1, 2, 2, 52.4, 52.4, 44.5, 44.5, 2.100, 1050, "mechanical", 0.33, 0.88, 0.88, 1.34),

        # Edelbrock/Carter and modern performance carburetors.
        ("edelbrock_avs2_500", "Edelbrock AVS2 4-Barrel 500 CFM", 190500, 1, 2, 2, 35.6, 41.3, 28.0, 33.0, 2.450, 500, "airValve", 0.50, 0.84, 1.15, 0.98),
        ("edelbrock_avs2_650", "Edelbrock AVS2 Annular 4-Barrel 650 CFM", 190650, 1, 2, 2, 36.6, 44.5, 30.2, 35.6, 2.560, 650, "airValve", 0.46, 0.85, 1.22, 1.02),
        ("edelbrock_avs2_800", "Edelbrock AVS2 Annular 4-Barrel 800 CFM", 190800, 1, 2, 2, 39.7, 45.7, 32.5, 38.0, 2.690, 800, "airValve", 0.42, 0.86, 1.18, 1.05),
        ("edelbrock_performer_600", "Edelbrock Performer 4-Barrel 600 CFM", 140600, 1, 2, 2, 36.6, 44.5, 29.7, 35.0, 2.450, 600, "airValve", 0.48, 0.84, 1.08, 0.98),
        ("carter_afb_750", "Carter AFB Competition 4-Barrel 750 CFM", 975075, 1, 2, 2, 39.7, 44.5, 32.0, 36.5, 2.600, 750, "airValve", 0.44, 0.85, 1.05, 1.02),
        ("quick_fuel_580_vs", "Quick Fuel 4-Barrel 580 CFM Vacuum Secondary", 580001, 1, 2, 2, 39.7, 39.7, 31.0, 31.0, 1.700, 580, "vacuum", 0.48, 0.85, 1.08, 1.02),
        ("quick_fuel_650_ms", "Quick Fuel 4-Barrel 650 CFM Mechanical", 650001, 1, 2, 2, 41.3, 41.3, 33.0, 33.0, 1.780, 650, "mechanical", 0.40, 0.86, 1.02, 1.20),
        ("quick_fuel_750_annular", "Quick Fuel Annular 4-Barrel 750 CFM", 750001, 1, 2, 2, 42.9, 42.9, 35.0, 35.0, 1.880, 750, "mechanical", 0.38, 0.87, 1.24, 1.22),
        ("quick_fuel_850_race", "Quick Fuel Race 4-Barrel 850 CFM", 850001, 1, 2, 2, 44.5, 44.5, 37.0, 37.0, 1.950, 850, "mechanical", 0.35, 0.88, 1.00, 1.28),
        ("speed_demon_750_annular", "Speed Demon Annular 4-Barrel 750 CFM", 750002, 1, 2, 2, 42.9, 42.9, 35.0, 35.0, 1.880, 750, "mechanical", 0.38, 0.87, 1.22, 1.24),
    ]
    assert len(specs) == 40
    out = {}
    for spec in specs:
        key, *args = spec
        out[f"ultra_realism_carb_{key}"] = carb_part(*args)
    return out


USER_CARBURETOR_MODELS = {
    "roundslide_classic": {
        "source": "carb_01_roundslide_classic",
        "baseBoreMM": 40.0,
        "flangeX": 0.0835,
        "inletX": -0.086329,
    },
    "big_bell_racing": {
        "source": "carb_02_big_bell_racing",
        "baseBoreMM": 42.0,
        "flangeX": 0.0835,
        "inletX": -0.107079,
    },
    "turbo_vacuum_sidepod": {
        "source": "carb_03_turbo_vacuum_sidepod",
        "baseBoreMM": 40.0,
        "flangeX": 0.0835,
        "inletX": -0.082321,
    },
    "compact_offroad": {
        "source": "carb_04_compact_offroad",
        "baseBoreMM": 38.0,
        "flangeX": 0.0835,
        "inletX": -0.071389,
    },
    "vintage_sidedraft": {
        "source": "carb_05_vintage_sidedraft",
        "baseBoreMM": 40.0,
        "flangeX": 0.0835,
        "inletX": -0.098779,
    },
    "triple_street": {
        "source": "carb_triple_01_street_bigbody",
        "baseBoreMM": 48.0,
        "flangeX": 0.0976,
        "inletX": -0.123359,
        "nativeCentersY": [-0.142, 0.0, 0.142],
    },
    "triple_racing": {
        "source": "carb_triple_02_racing_velocitystack",
        "baseBoreMM": 48.0,
        "flangeX": 0.0976,
        "inletX": -0.140479,
        "nativeCentersY": [-0.142, 0.0, 0.142],
    },
    "triple_touring": {
        "source": "carb_triple_03_touring_diaphragm",
        "baseBoreMM": 48.0,
        "flangeX": 0.0976,
        "inletX": -0.119079,
        "nativeCentersY": [-0.142, 0.0, 0.142],
    },
}


def _carb_visual_family(source_key: str, carb: dict) -> tuple[str, str]:
    key = source_key.lower()
    count = int(carb["count"])
    if "dcoe" in key and count == 6:
        return "triple_touring", "sidedraft"
    if count == 3:
        if "40_dcoe" in key:
            return "triple_street", "sidedraft"
        if "45_dcoe" in key or "race" in key or "demon" in key:
            return "triple_racing", "sidedraft" if "dcoe" in key else "downdraft"
        if carb["secondaryType"] in {"vacuum", "airValve"}:
            return "triple_touring", "downdraft"
        return "triple_street", "downdraft"
    if "dcoe" in key:
        return "vintage_sidedraft", "sidedraft"
    if "dgv" in key:
        return "compact_offroad", "downdraft"
    if "dgas" in key:
        return "roundslide_classic", "downdraft"
    if "idf" in key or "ida" in key or "4500" in key:
        return "big_bell_racing", "downdraft"
    if "4160" in key or carb["secondaryType"] in {"vacuum", "airValve"}:
        return "turbo_vacuum_sidepod", "downdraft"
    if "1904" in key or "carter" in key:
        return "vintage_sidedraft", "downdraft"
    if "2300" in key:
        return "compact_offroad", "downdraft"
    if "quick_fuel" in key or "demon" in key or float(carb["ratedCFM"]) >= 750:
        return "big_bell_racing", "downdraft"
    return "roundslide_classic", "downdraft"


def _carb_instance_layout(count: int, orientation: str, spacing: float) -> list[tuple[float, float, float]]:
    if count <= 1:
        return [(0.0, 0.0, 0.0)]
    if orientation == "downdraft" and count == 4:
        half = spacing * 0.5
        return [(-half, -half, 0.0), (half, -half, 0.0), (-half, half, 0.0), (half, half, 0.0)]
    if orientation == "downdraft" and count == 6:
        return [
            (-spacing * 0.5, -spacing, 0.0),
            (spacing * 0.5, -spacing, 0.0),
            (-spacing * 0.5, 0.0, 0.0),
            (spacing * 0.5, 0.0, 0.0),
            (-spacing * 0.5, spacing, 0.0),
            (spacing * 0.5, spacing, 0.0),
        ]
    start = -spacing * (count - 1) * 0.5
    return [(0.0, start + spacing * index, 0.0) for index in range(count)]


def carburetor_visual_spec(source_key: str, source_value: dict) -> dict:
    carb = source_value["ultraRealismCarburetor"]
    model_family, orientation = _carb_visual_family(source_key, carb)
    model = USER_CARBURETOR_MODELS[model_family]
    scale = max(0.78, min(1.28, float(carb["primaryBoreMM"]) / model["baseBoreMM"]))
    count = int(carb["count"])
    native_centers = model.get("nativeCentersY")
    if native_centers:
        if count == 6:
            assembly_spacing = 0.44 * scale
            instances = [
                (0.0, -assembly_spacing * 0.5, 0.0),
                (0.0, assembly_spacing * 0.5, 0.0),
            ]
            centers = [
                (0.0, center_y * scale + instance[1], 0.0)
                for instance in instances
                for center_y in native_centers
            ]
        else:
            instances = [(0.0, 0.0, 0.0)]
            centers = [(0.0, center_y * scale, 0.0) for center_y in native_centers]
    else:
        spacing = 0.128 * scale
        instances = _carb_instance_layout(count, orientation, spacing)
        centers = list(instances)

    flange_x = float(model["flangeX"])
    butterfly_source_x = 0.0
    slide_source_x = -0.018
    linkage_source_x = 0.012
    if orientation == "downdraft":
        butterfly_base = (0.0, 0.0, (flange_x - butterfly_source_x) * scale)
        slide_base = (0.040 * scale, 0.0, (flange_x - slide_source_x) * scale)
        linkage_base = (0.0, 0.058 * scale, (flange_x - linkage_source_x) * scale)
        inlet_base = (0.0, 0.0, (flange_x - float(model["inletX"])) * scale)
        slide_translation = (0.040 * scale, 0.0, 0.0)
    else:
        butterfly_base = ((butterfly_source_x - flange_x) * scale, 0.0, 0.0)
        slide_base = ((slide_source_x - flange_x) * scale, 0.0, 0.040 * scale)
        linkage_base = ((linkage_source_x - flange_x) * scale, 0.058 * scale, 0.0)
        inlet_base = ((float(model["inletX"]) - flange_x) * scale, 0.0, 0.0)
        slide_translation = (0.0, 0.0, 0.040 * scale)

    def offset_points(base: tuple[float, float, float]) -> list[tuple[float, float, float]]:
        return [
            (base[0] + center[0], base[1] + center[1], base[2] + center[2])
            for center in centers
        ]

    return {
        "modelFamily": model_family,
        "sourceModel": model["source"],
        "orientation": orientation,
        "scale": round(scale, 6),
        "bodyInstances": instances,
        "carbCenters": centers,
        "butterflyPivots": offset_points(butterfly_base),
        "slidePivots": offset_points(slide_base),
        "linkagePivots": offset_points(linkage_base),
        "inletPivots": offset_points(inlet_base),
        "slideTranslation": slide_translation,
        "primaryBoreMM": float(carb["primaryBoreMM"]),
        "count": count,
        "usesNativeTripleBody": bool(native_centers),
    }


def additional_tuning_parts() -> dict[str, dict]:
    parts = {
        "ultra_realism_intake_stock": part("ultra_realism_intake_geometry", "Existing / Stock Intake Manifold"),
        "ultra_realism_intake_dual_plane": part("ultra_realism_intake_geometry", "Dual-Plane Street Intake", 900, {
            "torqueModUltraIntakeMult": torque_curve([(0, 1.01), (2000, 1.06), (4000, 1.05), (6000, 1.00), (8000, 0.94), (10000, 0.88)]),
        }),
        "ultra_realism_intake_single_plane": part("ultra_realism_intake_geometry", "Single-Plane Performance Intake", 1400, {
            "torqueModUltraIntakeMult": torque_curve([(0, 0.96), (2000, 0.98), (4000, 1.05), (6000, 1.12), (8000, 1.12), (10000, 1.05)]),
            "$+maxRPM": 150,
        }),
        "ultra_realism_intake_cross_ram": part("ultra_realism_intake_geometry", "Cross-Ram Long Runner Intake", 2600, {
            "torqueModUltraIntakeMult": torque_curve([(0, 0.98), (2000, 1.08), (4000, 1.12), (6000, 1.06), (8000, 0.98), (10000, 0.90)]),
        }),
        "ultra_realism_intake_tunnel_ram": part("ultra_realism_intake_geometry", "Tunnel-Ram High RPM Intake", 3200, {
            "torqueModUltraIntakeMult": torque_curve([(0, 0.88), (2000, 0.92), (4000, 1.02), (6000, 1.18), (8000, 1.28), (10000, 1.22)]),
            "$+maxRPM": 350,
        }),
        "ultra_realism_intake_individual_runner": part("ultra_realism_intake_geometry", "Individual Runner Intake", 4200, {
            "torqueModUltraIntakeMult": torque_curve([(0, 0.95), (2000, 1.00), (4000, 1.10), (6000, 1.18), (8000, 1.20), (10000, 1.14)]),
            "$+maxRPM": 450,
        }),

        "ultra_realism_spacer_none": part("ultra_realism_carb_spacer", "No Additional Carburetor Spacer"),
        "ultra_realism_spacer_4hole_25": part("ultra_realism_carb_spacer", "25 mm Four-Hole Spacer", 180, {
            "torqueModUltraSpacerMult": torque_curve([(0, 1.00), (2000, 1.03), (4000, 1.02), (6000, 1.00), (8000, 0.99), (10000, 0.98)]),
        }),
        "ultra_realism_spacer_open_25": part("ultra_realism_carb_spacer", "25 mm Open Plenum Spacer", 220, {
            "torqueModUltraSpacerMult": torque_curve([(0, 0.99), (2000, 1.00), (4000, 1.02), (6000, 1.04), (8000, 1.04), (10000, 1.02)]),
        }),
        "ultra_realism_spacer_open_50": part("ultra_realism_carb_spacer", "50 mm Open Plenum Spacer", 320, {
            "torqueModUltraSpacerMult": torque_curve([(0, 0.97), (2000, 0.99), (4000, 1.02), (6000, 1.06), (8000, 1.07), (10000, 1.05)]),
        }),
        "ultra_realism_spacer_tapered": part("ultra_realism_carb_spacer", "Tapered Four-Hole Spacer", 480, {
            "torqueModUltraSpacerMult": torque_curve([(0, 1.00), (2000, 1.02), (4000, 1.04), (6000, 1.04), (8000, 1.03), (10000, 1.00)]),
        }),
        "ultra_realism_spacer_phenolic": part("ultra_realism_carb_spacer", "Phenolic Heat-Isolating Spacer", 350, {
            "torqueModUltraSpacerMult": torque_curve([(0, 1.00), (2000, 1.01), (4000, 1.02), (6000, 1.02), (8000, 1.01), (10000, 1.00)]),
        }),

        "ultra_realism_fuel_delivery_stock": part("ultra_realism_fuel_delivery", "Existing / Stock Fuel Delivery"),
        "ultra_realism_fuel_delivery_mechanical": part("ultra_realism_fuel_delivery", "High-Flow Mechanical Fuel Pump", 420),
        "ultra_realism_fuel_delivery_electric_street": part("ultra_realism_fuel_delivery", "Electric Street Fuel Pump", 620),
        "ultra_realism_fuel_delivery_electric_race": part("ultra_realism_fuel_delivery", "Electric Race Fuel Pump", 980),
        "ultra_realism_fuel_delivery_return": part("ultra_realism_fuel_delivery", "Return-Style Regulated Fuel System", 1450),
        "ultra_realism_fuel_delivery_boost": part("ultra_realism_fuel_delivery", "Boost-Referenced Fuel System", 1900),

        "ultra_realism_rotating_stock": part("ultra_realism_rotating_response", "Existing / Stock Damper and Flywheel"),
        "ultra_realism_rotating_heavy": part("ultra_realism_rotating_response", "Heavy Flywheel and Damper", 500, {
            "$*inertia": 1.28,
            "$*engineBrakeTorque": 1.08,
        }),
        "ultra_realism_rotating_light": part("ultra_realism_rotating_response", "Lightweight Flywheel", 850, {
            "$*inertia": 0.76,
            "$*dynamicFriction": 0.98,
        }),
        "ultra_realism_rotating_race": part("ultra_realism_rotating_response", "Billet Race Flywheel and Damper", 1800, {
            "$*inertia": 0.62,
            "$*dynamicFriction": 0.96,
            "$+maxRPM": 250,
            "$+maxPhysicalRPM": 250,
        }),
        "ultra_realism_rotating_fluid": part("ultra_realism_rotating_response", "Viscous Harmonic Damper", 1200, {
            "$*inertia": 1.04,
            "$+maxRPM": 150,
            "$+maxPhysicalRPM": 150,
            "$*maxTorqueRating": 1.08,
        }),

        "ultra_realism_tb_stock": part("ultra_realism_throttle_body", "Existing / Stock Throttle Body"),
        "ultra_realism_tb_58_single": part("ultra_realism_throttle_body", "58 mm Single Throttle Body", 420, {
            "ultraRealismThrottleBody": {"diameterMM": 58, "count": 1, "dischargeCoef": 0.88},
        }),
        "ultra_realism_tb_70_single": part("ultra_realism_throttle_body", "70 mm Single Throttle Body", 680, {
            "ultraRealismThrottleBody": {"diameterMM": 70, "count": 1, "dischargeCoef": 0.90},
        }),
        "ultra_realism_tb_80_twin": part("ultra_realism_throttle_body", "80 mm Twin Throttle Bodies", 1200, {
            "ultraRealismThrottleBody": {"diameterMM": 80, "count": 2, "dischargeCoef": 0.91},
        }),
        "ultra_realism_tb_race_90": part("ultra_realism_throttle_body", "90 mm Race Throttle Body", 1800, {
            "ultraRealismThrottleBody": {"diameterMM": 90, "count": 1, "dischargeCoef": 0.93},
        }),

        "ultra_realism_diesel_injection_stock": part(
            "ultra_realism_diesel_injection", "Existing / Stock Diesel Injection"
        ),
        "ultra_realism_diesel_injection_street": part(
            "ultra_realism_diesel_injection", "Street Diesel Injection Pump", 900, {
                "ultraRealismDieselInjection": {
                    "nozzleFlowMM3PerStroke": 42,
                    "targetPowerAFR": 18.5,
                },
            }
        ),
        "ultra_realism_diesel_injection_performance": part(
            "ultra_realism_diesel_injection", "Performance Diesel Injection Pump", 2200, {
                "ultraRealismDieselInjection": {
                    "nozzleFlowMM3PerStroke": 58,
                    "targetPowerAFR": 17.8,
                },
            }
        ),
    }
    fuel_lph = {
        "ultra_realism_fuel_delivery_mechanical": 130,
        "ultra_realism_fuel_delivery_electric_street": 190,
        "ultra_realism_fuel_delivery_electric_race": 340,
        "ultra_realism_fuel_delivery_return": 420,
        "ultra_realism_fuel_delivery_boost": 520,
    }
    for key, lph in fuel_lph.items():
        parts[key]["ultraRealismFuelDelivery"] = {"capacityLPH": lph}
    return parts


def tuning_part(name: str, config: dict, slots: list | None = None) -> dict:
    return {
        "information": {
            "authors": "OpenAI ChatGPT / local modkit",
            "name": name,
            "value": 0,
        },
        "slotType": "ultra_realism_tuning",
        "slots": [["type", "default", "description"], *(slots or ULTRA_ENGINE_SLOTS)],
        "controller": [["fileName"], ["ultraRealismEngine", build_auto_config(config)]],
    }


def native_sync_parts(defaults: dict[str, str], integration: str) -> dict[str, dict]:
    parts = {}
    pack_name = integration.upper() if integration == "ceep" else integration.title()
    for slot_type, part_name in defaults.items():
        category = slot_type.removeprefix("ultra_realism_").replace("_", " ").title()
        synced = part(slot_type, f"Automatic - Use {pack_name} {category}")
        synced["ultraRealismNativeSync"] = {
            "integration": integration,
            "category": slot_type,
        }
        parts[part_name] = synced
    return parts


def ultra_engine_parts() -> dict[str, dict]:
    return {
        # Short blocks mirror the practical CEEP choices while staying generic
        # enough to work on Ford, CEEP and stock engines.
        "ultra_realism_short_block_stock": part("ultra_realism_short_block", "Cast Stock Short Block"),
        "ultra_realism_short_block_worn": part("ultra_realism_short_block", "Worn Short Block", 80, {
            "idleRPMRoughness": 280,
            "$*friction": 1.22,
            "$*dynamicFriction": 1.18,
            "$*inertia": 1.05,
            "cylinderWallTemperatureDamageThreshold": 125,
            "headGasketDamageThreshold": 900000,
            "pistonRingDamageThreshold": 850000,
            "connectingRodDamageThreshold": 1150000,
            "$*maxTorqueRating": 0.72,
        }),
        "ultra_realism_short_block_cast_light": part("ultra_realism_short_block", "Cast Light Weight Short Block", 1500, {
            "$+maxRPM": 250,
            "$+maxPhysicalRPM": 250,
            "$*friction": 1.05,
            "$*dynamicFriction": 1.04,
            "$*inertia": 0.90,
            "$*maxTorqueRating": 1.15,
            "$*maxOverTorqueDamage": 2.0,
        }),
        "ultra_realism_short_block_cast_heavy": part("ultra_realism_short_block", "Cast Heavy Duty Short Block", 1800, {
            "$*friction": 1.10,
            "$*dynamicFriction": 1.16,
            "$*inertia": 1.18,
            "$*cylinderWallTemperatureDamageThreshold": 1.10,
            "headGasketDamageThreshold": 1750000,
            "pistonRingDamageThreshold": 1750000,
            "connectingRodDamageThreshold": 2250000,
            "$*maxTorqueRating": 1.45,
        }),
        "ultra_realism_short_block_forged": part("ultra_realism_short_block", "Forged Short Block", 4500, {
            "$+maxRPM": 500,
            "$+maxPhysicalRPM": 500,
            "$*friction": 1.08,
            "$*dynamicFriction": 1.08,
            "$*inertia": 0.96,
            "$*cylinderWallTemperatureDamageThreshold": 1.18,
            "headGasketDamageThreshold": 1900000,
            "pistonRingDamageThreshold": 1900000,
            "connectingRodDamageThreshold": 2450000,
            "$*maxTorqueRating": 1.90,
        }),
        "ultra_realism_short_block_forged_light": part("ultra_realism_short_block", "Forged Light Weight Short Block", 5200, {
            "$+maxRPM": 850,
            "$+maxPhysicalRPM": 850,
            "$*friction": 1.06,
            "$*dynamicFriction": 1.04,
            "$*inertia": 0.72,
            "$*cylinderWallTemperatureDamageThreshold": 1.12,
            "headGasketDamageThreshold": 1800000,
            "pistonRingDamageThreshold": 1800000,
            "connectingRodDamageThreshold": 2350000,
            "$*maxTorqueRating": 1.70,
        }),
        "ultra_realism_short_block_forged_heavy": part("ultra_realism_short_block", "Forged Heavy Duty Short Block", 6500, {
            "$+maxRPM": 450,
            "$+maxPhysicalRPM": 450,
            "$*friction": 1.14,
            "$*dynamicFriction": 1.18,
            "$*inertia": 1.28,
            "$*cylinderWallTemperatureDamageThreshold": 1.32,
            "headGasketDamageThreshold": 2100000,
            "pistonRingDamageThreshold": 2100000,
            "connectingRodDamageThreshold": 2750000,
            "$*maxTorqueRating": 2.40,
        }),
        "ultra_realism_short_block_billet": part("ultra_realism_short_block", "Billet Aluminum Short Block", 9000, {
            "$+maxRPM": 1000,
            "$+maxPhysicalRPM": 1000,
            "$*friction": 1.10,
            "$*dynamicFriction": 1.10,
            "$*inertia": 0.82,
            "engineBlockMaterial": "aluminium",
            "$*cylinderWallTemperatureDamageThreshold": 1.55,
            "engineBlockTemperatureDamageThreshold": 800,
            "headGasketDamageThreshold": 2800000,
            "pistonRingDamageThreshold": 2800000,
            "connectingRodDamageThreshold": 3500000,
            "$*maxTorqueRating": 3.00,
        }),
        "ultra_realism_short_block_billet_heavy": part("ultra_realism_short_block", "Billet Heavy Duty Short Block", 11500, {
            "$+maxRPM": 800,
            "$+maxPhysicalRPM": 800,
            "$*friction": 1.18,
            "$*dynamicFriction": 1.22,
            "$*inertia": 1.02,
            "engineBlockMaterial": "aluminium",
            "$*cylinderWallTemperatureDamageThreshold": 1.85,
            "engineBlockTemperatureDamageThreshold": 850,
            "headGasketDamageThreshold": 3600000,
            "pistonRingDamageThreshold": 3600000,
            "connectingRodDamageThreshold": 4300000,
            "$*maxTorqueRating": 3.70,
        }),

        # Stroker geometry follows the CEEP undersquare/square/oversquare logic.
        "ultra_realism_stroker_stock": part("ultra_realism_stroker_kit", "Stock Bore / Stroke"),
        "ultra_realism_stroker_undersquare": part("ultra_realism_stroker_kit", "Under-Square Stroker Kit", 4800, {
            "torqueModUltraStrokerMult": torque_curve([(0, 1.0), (2000, 1.30), (4000, 1.18), (6000, 0.98), (8000, 0.70), (10000, 0.45)]),
            "$*inertia": 1.55,
            "$*friction": 1.08,
            "$*engineBrakeTorque": 1.18,
            "$+starterTorque": 180,
        }),
        "ultra_realism_stroker_square": part("ultra_realism_stroker_kit", "Square Stroker Kit", 5500, {
            "torqueModUltraStrokerMult": torque_curve([(0, 1.0), (2000, 1.12), (4000, 1.20), (6000, 1.12), (8000, 0.98), (10000, 0.85)]),
            "$*inertia": 1.16,
            "$*engineBrakeTorque": 1.08,
            "$+starterTorque": 160,
        }),
        "ultra_realism_stroker_oversquare": part("ultra_realism_stroker_kit", "Over-Square High RPM Kit", 6400, {
            "torqueModUltraStrokerMult": torque_curve([(0, 0.92), (2000, 0.98), (4000, 1.08), (6000, 1.18), (8000, 1.24), (10000, 1.16)]),
            "$+maxRPM": 350,
            "$+maxPhysicalRPM": 350,
            "$*friction": 0.94,
            "$*dynamicFriction": 0.94,
            "$*engineBrakeTorque": 0.92,
        }),

        # Pistons and ring packages are separate because real engines often mix
        # forged pistons with different ring tensions/gaps.
        "ultra_realism_pistons_cast": part("ultra_realism_pistons", "Cast Pistons"),
        "ultra_realism_pistons_hypereutectic": part("ultra_realism_pistons", "Hypereutectic Pistons", 900, {
            "$*friction": 0.98,
            "$*dynamicFriction": 0.98,
            "pistonRingDamageThreshold": 1800000,
        }),
        "ultra_realism_pistons_forged_lowcomp": part("ultra_realism_pistons", "Forged Low Compression Pistons", 2400, {
            "torqueModUltraPistonsMult": torque_curve([(0, 0.98), (2000, 0.98), (4000, 0.99), (6000, 1.00), (8000, 1.00), (10000, 1.00)]),
            "$+maxRPM": 250,
            "$*friction": 1.03,
            "$*maxTorqueRating": 1.20,
            "pistonRingDamageThreshold": 2000000,
        }),
        "ultra_realism_pistons_forged_highcomp": part("ultra_realism_pistons", "Forged High Compression Pistons", 2600, {
            "torqueModUltraPistonsMult": torque_curve([(0, 1.02), (2000, 1.06), (4000, 1.08), (6000, 1.05), (8000, 1.02), (10000, 0.98)]),
            "$+maxRPM": 200,
            "$*friction": 1.04,
            "$*maxTorqueRating": 1.25,
            "pistonRingDamageThreshold": 1950000,
        }),
        "ultra_realism_pistons_billet_coated": part("ultra_realism_pistons", "Coated Billet Pistons", 4200, {
            "torqueModUltraPistonsMult": torque_curve([(0, 1.00), (2000, 1.02), (4000, 1.05), (6000, 1.06), (8000, 1.05), (10000, 1.02)]),
            "$+maxRPM": 500,
            "$+maxPhysicalRPM": 500,
            "$*friction": 0.99,
            "$*dynamicFriction": 0.98,
            "$*maxTorqueRating": 1.45,
            "pistonRingDamageThreshold": 2300000,
        }),

        "ultra_realism_rings_stock": part("ultra_realism_piston_rings", "Stock Cast Piston Rings"),
        "ultra_realism_rings_moly": part("ultra_realism_piston_rings", "Moly Piston Rings", 450, {
            "$*friction": 0.98,
            "$*dynamicFriction": 0.99,
            "pistonRingDamageThreshold": 1850000,
        }),
        "ultra_realism_rings_file_fit": part("ultra_realism_piston_rings", "File-Fit Moly Piston Rings", 900, {
            "torqueModUltraRingsMult": torque_curve([(0, 1.00), (2000, 1.01), (4000, 1.02), (6000, 1.02), (8000, 1.01), (10000, 1.00)]),
            "$*friction": 0.99,
            "pistonRingDamageThreshold": 2100000,
        }),
        "ultra_realism_rings_low_tension": part("ultra_realism_piston_rings", "Low-Tension Drag Piston Rings", 1100, {
            "torqueModUltraRingsMult": torque_curve([(0, 0.99), (2000, 1.00), (4000, 1.02), (6000, 1.03), (8000, 1.03), (10000, 1.02)]),
            "$*friction": 0.94,
            "$*dynamicFriction": 0.96,
            "pistonRingDamageThreshold": 1750000,
        }),
        "ultra_realism_rings_worn": part("ultra_realism_piston_rings", "Worn Piston Rings", 50, {
            "torqueModUltraRingsMult": torque_curve([(0, 0.82), (2000, 0.84), (4000, 0.86), (6000, 0.84), (8000, 0.80), (10000, 0.72)]),
            "$*friction": 1.08,
            "$*dynamicFriction": 1.10,
            "pistonRingDamageThreshold": 700000,
        }),
        "ultra_realism_rings_broken": part("ultra_realism_piston_rings", "Broken Piston Rings", 0, {
            "pistonRingsDamagedOverride": True,
            "torqueModUltraRingsMult": torque_curve([(0, 0.48), (2000, 0.50), (4000, 0.48), (6000, 0.42), (8000, 0.35), (10000, 0.25)]),
            "$*friction": 1.30,
            "$*dynamicFriction": 1.28,
            "pistonRingDamageThreshold": 100000,
        }),

        "ultra_realism_bearings_stock": part("ultra_realism_rod_bearings", "Stock Rod Bearings"),
        "ultra_realism_bearings_trimetal": part("ultra_realism_rod_bearings", "Tri-Metal Rod Bearings", 600, {
            "$*friction": 0.99,
            "$*dynamicFriction": 0.98,
            "connectingRodDamageThreshold": 2350000,
        }),
        "ultra_realism_bearings_coated": part("ultra_realism_rod_bearings", "Coated Race Rod Bearings", 1100, {
            "$*friction": 0.96,
            "$*dynamicFriction": 0.96,
            "connectingRodDamageThreshold": 2700000,
            "$*maxTorqueRating": 1.12,
        }),
        "ultra_realism_bearings_high_clearance": part("ultra_realism_rod_bearings", "High-Clearance Drag Rod Bearings", 900, {
            "$*friction": 0.95,
            "$*dynamicFriction": 0.94,
            "connectingRodDamageThreshold": 2550000,
            "$*maxTorqueRating": 1.08,
        }),
        "ultra_realism_bearings_worn": part("ultra_realism_rod_bearings", "Worn Rod Bearings", 20, {
            "connectingRodBearingsDamagedOverride": True,
            "$*friction": 1.32,
            "$*dynamicFriction": 1.26,
            "connectingRodDamageThreshold": 850000,
            "$*maxTorqueRating": 0.65,
        }),

        "ultra_realism_crank_rods_stock": part("ultra_realism_crank_rods", "Stock Crankshaft and Connecting Rods"),
        "ultra_realism_crank_rods_forged": part("ultra_realism_crank_rods", "Forged Crankshaft and Rods", 3200, {
            "$+maxRPM": 350,
            "$+maxPhysicalRPM": 350,
            "$*inertia": 1.04,
            "$*maxTorqueRating": 1.55,
            "connectingRodDamageThreshold": 2850000,
        }),
        "ultra_realism_crank_rods_billet": part("ultra_realism_crank_rods", "Billet Crankshaft and H-Beam Rods", 6500, {
            "$+maxRPM": 650,
            "$+maxPhysicalRPM": 650,
            "$*inertia": 0.96,
            "$*maxTorqueRating": 2.10,
            "connectingRodDamageThreshold": 3500000,
        }),
        "ultra_realism_crank_rods_light": part("ultra_realism_crank_rods", "Lightweight Rotating Assembly", 4800, {
            "$+maxRPM": 700,
            "$+maxPhysicalRPM": 700,
            "$*inertia": 0.68,
            "$*friction": 0.97,
            "$*dynamicFriction": 0.96,
            "$*maxTorqueRating": 1.25,
            "connectingRodDamageThreshold": 2450000,
        }),
        "ultra_realism_crank_rods_heavy": part("ultra_realism_crank_rods", "Heavy Duty Rotating Assembly", 5200, {
            "$+maxRPM": 250,
            "$+maxPhysicalRPM": 250,
            "$*inertia": 1.35,
            "$*friction": 1.04,
            "$*dynamicFriction": 1.06,
            "$*maxTorqueRating": 2.30,
            "connectingRodDamageThreshold": 3800000,
        }),

        "ultra_realism_cam_stock": part("ultra_realism_camshaft", "Stock Camshaft"),
        "ultra_realism_cam_towing": part("ultra_realism_camshaft", "Towing / Low RPM Camshaft", 800, {
            "torqueModUltraCamshaftMult": torque_curve([(0, 1.02), (1500, 1.12), (3000, 1.08), (4500, 1.00), (6000, 0.92), (8000, 0.82), (10000, 0.70)]),
            "$*dynamicFriction": 1.02,
        }),
        "ultra_realism_cam_stage1": part("ultra_realism_camshaft", "Sport Camshaft Stage 1", 1200, {
            "torqueModUltraCamshaftMult": torque_curve([(0, 0.99), (2000, 1.04), (4000, 1.09), (6000, 1.08), (8000, 1.02), (10000, 0.95)]),
            "$+maxRPM": 150,
            "$+maxPhysicalRPM": 150,
            "$*maxTorqueRating": 1.05,
        }),
        "ultra_realism_cam_stage2": part("ultra_realism_camshaft", "Performance Camshaft Stage 2", 2200, {
            "torqueModUltraCamshaftMult": torque_curve([(0, 0.96), (2000, 1.00), (4000, 1.12), (6000, 1.18), (8000, 1.12), (10000, 1.00)]),
            "$+maxRPM": 350,
            "$+maxPhysicalRPM": 350,
            "idleRPMVariance": 55,
            "idleRPMVarianceFrequency": 7,
            "$*maxTorqueRating": 1.10,
        }),
        "ultra_realism_cam_stage3": part("ultra_realism_camshaft", "Race Camshaft Stage 3", 3800, {
            "torqueModUltraCamshaftMult": torque_curve([(0, 0.88), (2000, 0.94), (4000, 1.08), (6000, 1.26), (8000, 1.34), (10000, 1.22)]),
            "$+maxRPM": 650,
            "$+maxPhysicalRPM": 650,
            "idleRPMVariance": 115,
            "idleRPMVarianceFrequency": 9,
            "$*friction": 1.02,
            "$*maxTorqueRating": 1.18,
        }),
        "ultra_realism_cam_drag": part("ultra_realism_camshaft", "Drag Race Camshaft Stage 3", 4500, {
            "torqueModUltraCamshaftMult": torque_curve([(0, 0.80), (2000, 0.88), (4000, 1.02), (6000, 1.28), (8000, 1.44), (10000, 1.38)]),
            "$+maxRPM": 900,
            "$+maxPhysicalRPM": 900,
            "idleRPMVariance": 180,
            "idleRPMVarianceFrequency": 11,
            "$*friction": 1.05,
            "$*maxTorqueRating": 1.25,
        }),

        "ultra_realism_valvetrain_stock": part("ultra_realism_valvetrain", "Stock Valvetrain"),
        "ultra_realism_valvetrain_hydraulic": part("ultra_realism_valvetrain", "Hydraulic Lifters", 350, {
            "$*dynamicFriction": 0.99,
            "$+maxRPM": -100,
        }),
        "ultra_realism_valvetrain_springs": part("ultra_realism_valvetrain", "Performance Valve Springs", 950, {
            "$+maxRPM": 300,
            "$+maxPhysicalRPM": 300,
            "$*dynamicFriction": 1.02,
            "$*maxTorqueRating": 1.06,
        }),
        "ultra_realism_valvetrain_roller": part("ultra_realism_valvetrain", "Roller Rockers and Lifters", 1800, {
            "torqueModUltraValvetrainMult": torque_curve([(0, 1.00), (2000, 1.01), (4000, 1.03), (6000, 1.05), (8000, 1.04), (10000, 1.02)]),
            "$*friction": 0.98,
            "$*dynamicFriction": 0.96,
            "$+maxRPM": 250,
        }),
        "ultra_realism_valvetrain_solid": part("ultra_realism_valvetrain", "Solid Lifter Race Valvetrain", 2600, {
            "torqueModUltraValvetrainMult": torque_curve([(0, 0.98), (2000, 1.00), (4000, 1.04), (6000, 1.08), (8000, 1.08), (10000, 1.05)]),
            "$+maxRPM": 550,
            "$+maxPhysicalRPM": 550,
            "$*dynamicFriction": 1.04,
            "$*maxTorqueRating": 1.15,
        }),
        "ultra_realism_valvetrain_titanium": part("ultra_realism_valvetrain", "Titanium Valves and Retainers", 4200, {
            "torqueModUltraValvetrainMult": torque_curve([(0, 0.99), (2000, 1.00), (4000, 1.05), (6000, 1.10), (8000, 1.12), (10000, 1.08)]),
            "$+maxRPM": 800,
            "$+maxPhysicalRPM": 800,
            "$*dynamicFriction": 0.98,
            "$*maxTorqueRating": 1.22,
        }),

        "ultra_realism_heads_stock": part("ultra_realism_cylinder_heads", "Stock Iron Cylinder Heads"),
        "ultra_realism_heads_high_compression": part("ultra_realism_cylinder_heads", "High Compression Iron Heads", 1100, {
            "torqueModUltraHeadsMult": torque_curve([(0, 1.02), (2000, 1.06), (4000, 1.06), (6000, 1.03), (8000, 0.98), (10000, 0.92)]),
            "headGasketDamageThreshold": 1600000,
        }),
        "ultra_realism_heads_ported": part("ultra_realism_cylinder_heads", "Ported Iron Cylinder Heads", 2200, {
            "torqueModUltraHeadsMult": torque_curve([(0, 0.99), (2000, 1.02), (4000, 1.08), (6000, 1.12), (8000, 1.08), (10000, 1.00)]),
            "$+maxRPM": 200,
            "$*maxTorqueRating": 1.10,
        }),
        "ultra_realism_heads_aluminum": part("ultra_realism_cylinder_heads", "Aluminum Performance Heads", 3800, {
            "torqueModUltraHeadsMult": torque_curve([(0, 1.00), (2000, 1.04), (4000, 1.11), (6000, 1.15), (8000, 1.12), (10000, 1.04)]),
            "$+maxRPM": 300,
            "$*maxTorqueRating": 1.18,
            "headGasketDamageThreshold": 1900000,
            "$*engineBlockAirCoolingEfficiency": 1.10,
        }),
        "ultra_realism_heads_race": part("ultra_realism_cylinder_heads", "Race Aluminum Cylinder Heads", 6200, {
            "torqueModUltraHeadsMult": torque_curve([(0, 0.96), (2000, 1.00), (4000, 1.12), (6000, 1.24), (8000, 1.28), (10000, 1.20)]),
            "$+maxRPM": 700,
            "$+maxPhysicalRPM": 700,
            "$*maxTorqueRating": 1.30,
            "headGasketDamageThreshold": 2100000,
            "$*engineBlockAirCoolingEfficiency": 1.18,
        }),
        "ultra_realism_heads_four_valve": part("ultra_realism_cylinder_heads", "4-Valve Race Cylinder Heads", 7800, {
            "torqueModUltraHeadsMult": torque_curve([(0, 0.92), (2000, 0.98), (4000, 1.10), (6000, 1.30), (8000, 1.40), (10000, 1.32)]),
            "$+maxRPM": 950,
            "$+maxPhysicalRPM": 950,
            "$*maxTorqueRating": 1.35,
            "headGasketDamageThreshold": 2200000,
            "$*engineBlockAirCoolingEfficiency": 1.25,
        }),

        "ultra_realism_head_gasket_stock": part("ultra_realism_head_gasket", "Stock Composite Head Gasket"),
        "ultra_realism_head_gasket_mls": part("ultra_realism_head_gasket", "MLS Head Gasket + Head Studs", 700, {
            "headGasketDamageThreshold": 2200000,
            "$*maxTorqueRating": 1.08,
        }),
        "ultra_realism_head_gasket_copper": part("ultra_realism_head_gasket", "Copper Head Gasket", 950, {
            "headGasketDamageThreshold": 2600000,
            "$*maxTorqueRating": 1.14,
        }),
        "ultra_realism_head_gasket_fire_ring": part("ultra_realism_head_gasket", "Copper Fire-Ring Head Gasket", 1500, {
            "headGasketDamageThreshold": 3300000,
            "$*maxTorqueRating": 1.22,
            "$*maxOverTorqueDamage": 1.25,
        }),
        "ultra_realism_head_gasket_worn": part("ultra_realism_head_gasket", "Weak Head Gasket", 25, {
            "headGasketDamageThreshold": 650000,
            "$*maxTorqueRating": 0.78,
        }),

        "ultra_realism_ignition_stock": part("ultra_realism_ignition", "Stock Distributor"),
        "ultra_realism_ignition_points": part("ultra_realism_ignition", "Worn Points Ignition", 20, {
            "torqueModUltraIgnition": torque_curve([(0, -3), (2000, -4), (4000, -7), (6000, -14), (8000, -22), (10000, -34)]),
            "idleRPMVariance": 80,
            "idleRPMVarianceFrequency": 6,
        }),
        "ultra_realism_ignition_performance": part("ultra_realism_ignition", "Performance Distributor", 650, {
            "torqueModUltraIgnition": torque_curve([(0, 0), (2000, 2), (4000, 5), (6000, 8), (8000, 4), (10000, 0)]),
            "$+maxRPM": 100,
        }),
        "ultra_realism_ignition_electronic": part("ultra_realism_ignition", "Electronic Ignition", 1100, {
            "torqueModUltraIgnition": torque_curve([(0, 1), (2000, 3), (4000, 6), (6000, 9), (8000, 6), (10000, 2)]),
            "$+maxRPM": 200,
            "idleRPMVariance": 0,
        }),
        "ultra_realism_ignition_cdi": part("ultra_realism_ignition", "Programmable CDI Ignition", 1800, {
            "torqueModUltraIgnition": torque_curve([(0, 1), (2000, 4), (4000, 8), (6000, 12), (8000, 10), (10000, 6)]),
            "$+maxRPM": 350,
            "idleRPMVariance": 0,
        }),

        "ultra_realism_oil_stock": part("ultra_realism_oil_system", "Stock Wet Sump Oil System"),
        "ultra_realism_oil_baffled": part("ultra_realism_oil_system", "Baffled Wet Sump Oil Pan", 450, {
            "$*oilpanMaximumSafeG": 1.75,
            "$+oilVolume": 0.5,
        }),
        "ultra_realism_oil_high_volume": part("ultra_realism_oil_system", "High Volume Oil Pump", 650, {
            "$*oilpanMaximumSafeG": 2.0,
            "$+oilVolume": 1.0,
            "$*friction": 1.02,
            "connectingRodDamageThreshold": 2500000,
        }),
        "ultra_realism_oil_cooler": part("ultra_realism_oil_system", "Performance Oil Cooler", 900, {
            "$*oilRadiatorArea": 1.35,
            "$*oilRadiatorEffectiveness": 1.35,
            "oilThermostatTemperature": 95,
            "$+oilVolume": 1.2,
        }),
        "ultra_realism_oil_dry_sump": part("ultra_realism_oil_system", "Dry Sump Oil System", 3600, {
            "$*oilpanMaximumSafeG": 4.0,
            "$*oilRadiatorArea": 1.65,
            "$*oilRadiatorEffectiveness": 1.75,
            "oilThermostatTemperature": 90,
            "$+oilVolume": 3.0,
            "$*friction": 0.98,
            "$*dynamicFriction": 0.98,
            "connectingRodDamageThreshold": 3300000,
        }),
        "ultra_realism_oil_worn_pump": part("ultra_realism_oil_system", "Worn Oil Pump", 25, {
            "oilpanMaximumSafeG": 0.75,
            "$*friction": 1.08,
            "$*dynamicFriction": 1.12,
            "connectingRodDamageThreshold": 700000,
        }),
    }


def write_common_tuning_parts() -> None:
    common_dir = MOD_DIR / "vehicles" / "common" / "ultra_realism"
    common_dir.mkdir(parents=True, exist_ok=True)
    # CEEP/Ford now hook the controller directly and expose these parts through
    # native slotTypes. Do not publish the obsolete tuning/sync profile parts.
    parts = {}
    parts.update(carburetor_parts())
    parts.update(additional_tuning_parts())
    parts.update(ultra_engine_parts())
    out_path = common_dir / "ultra_realism_tuning.jbeam"
    out_path.write_text(json.dumps(parts, indent=4, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"[OK] {out_path.relative_to(KIT_DIR)}")


def remove_legacy_vehicle_auto_parts() -> None:
    vehicles_dir = MOD_DIR / "vehicles"
    for path in vehicles_dir.glob("*/ultra_realism_*.jbeam"):
        path.unlink()
        print(f"[REMOVIDO] {path.relative_to(KIT_DIR)}")


def main() -> None:
    write_common_tuning_parts()
    remove_legacy_vehicle_auto_parts()


if __name__ == "__main__":
    main()
