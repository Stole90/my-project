# Cable Rating System Data-Layer Summary (SRPS IEC 60364-5-52)

This document lists all components written for the data-driven Cable Rating System implemented in Godot 4.7 GDScript. All files are written with `class_name` and full static-typing to support clean integration into the simulation engine.

---

## 1. Directory Tree & Created Files

The entire structure has been built under `/app/cable_rating_system/godot_sim/cable_rating/`:

### Models (`/models/`)
* **`CableElectricalModel.gd`**: A pure `Resource` containing electrical properties (material, insulation type, cross-section, length, reactance/resistance). It knows nothing about how or where the cable is installed.
* **`CableInstallationModel.gd`**: A pure `Resource` representing the installation environment (method, temperatures, grouping arrangement, soil type, harmonics, ventilation, thermal insulation).
* **`CableRatingResult.gd`**: A pure data-container `Resource` holding base ampacity, individual derating coefficients (K1 to K5), final continuous rating, and diagnostic/error logs.

### Data Engines (`/data/`)
* **`InstallationMethod.gd`**: A static `Resource` defining characteristics of a single standard installation method (such as air/buried status, reference ambient/soil temperature, reference resistivity).
* **`InstallationMethodDB.gd`**: Central static reference registry that builds and lazy-caches the standard 10 IEC 60364-5-52 installation methods (A1, A2, B1, B2, C, D1, D2, E, F, G).
* **`IecAmpacityTable.gd`**: A standard `Resource` containing the nested lookup tables (`table[method][material][insulation][cross_section_str] = Iz`). Supports linear interpolation for non-tabulated sizes and features a seed-table generator.
* **`SoilTypeDB.gd`**: Maps qualitative soil categories ("normal", "sand", "clay", "wet", "dry", "rock") into physical soil thermal resistivity parameters [K·m/W].
* **`HarmonicLevelDB.gd`**: Provides derating coefficients based on qualitative harmonic levels ("none", "low", "medium", "high") or via continuous linear interpolation from raw current THD [%].

### Correction Factors (`/factors/`)
* **`TemperatureFactor.gd`**: Calculates K1 correction using the physical form: $K_1 = \sqrt{\frac{T_{max} - T_{actual}}{T_{max} - T_{ref}}}$.
* **`GroupingFactor.gd`**: Calculates K2 correction based on arrangement ("touching", "spacing", "tray", "conduit", "bundle") and circuit count (1 to 9+), using a clamped multi-curve dictionary lookup.
* **`SoilFactor.gd`**: Calculates K3 soil correction for buried methods using thermal resistivity ratio scaling: $K_3 = \sqrt{\frac{R_{ref}}{\max(R_{actual}, 0.01)}}$.
* **`HarmonicFactor.gd`**: Calculates K4 neutral/skin-effect derating via THD [%] interpolation or qualitative levels.
* **`InstallationFactor.gd`**: Calculates K5 composite factor accounting for ventilation coefficient, thermal wall insulation placement (0.90x penalty), and protective duct material.

### Core Orchestrator
* **`CableRatingCalculator.gd`**: The core simulation calculator. Merges the electrical model, installation model, and ampacity tables. Looks up base current, runs all five factor engines, and returns a compiled rating result. It maintains **zero** references to Node, Scene, UI, or View classes.

---

## 2. Standard-Derived vs. Approximate/Placeholder Values

To maintain immediate gameplay balance, the seed tables utilize existing in-game baselines for Method C, while other coefficients approximate physical behavior. The architecture is fully isolated, meaning any of the approximate tables can be replaced with official localized tables inside the data files without changing any execution code.

### Standard-Derived Core Ratings (Exact)
* **Method C - Copper/PVC Baseline**: 1.5mm²=16A, 2.5mm²=20A, 4mm²=25A, 6mm²=32A, 10mm²=50A, 16mm²=63A, 25mm²=80A, 35mm²=100A, 50mm²=125A, 70mm²=160A, 95mm²=200A, 120mm²=230A (matches existing project baselines).
* **Method C - Aluminium/PVC Baseline**: 1.5mm²=13A, 2.5mm²=16A, 4mm²=20A, 6mm²=25A, 10mm²=40A, 16mm²=50A, 25mm²=63A, 35mm²=80A, 50mm²=100A, 70mm²=125A, 95mm²=160A, 120mm²=185A (matches existing project baselines).
* **Insulation Continuous Temperature Ratings ($T_{max}$)**: PVC is rated continuously at **70°C**; XLPE and EPR are rated continuously at **90°C** (SRPS standard core temperatures).
* **Standard Reference Temperatures ($T_{ref}$)**: Ambient air reference is **30°C**; Soil reference is **20°C**.

### Approximate / Derived Multipliers (Should be updated for production validation)
* **Method Table Deratings**: Since other methods are not hardcoded in the existing game, the seed table derives them from the Method C baseline using IEC-aligned typical performance ratios:
  * *A1 (Conduit in insulated wall)*: 0.72x Method C
  * *A2 (Multicore in insulated wall conduit)*: 0.68x Method C
  * *B1 (Conduit on wall)*: 0.85x Method C
  * *B2 (Multicore in surface conduit)*: 0.80x Method C
  * *D1 (Buried in ground duct)*: 0.80x Method C
  * *D2 (Buried directly)*: 1.10x Method C
  * *E (Multicore in free air)*: 1.05x Method C
  * *F (Single-core touching in free air)*: 1.10x Method C
  * *G (Single-core spaced in free air)*: 1.25x Method C
  * *XLPE Insulation Improvement*: 1.18x multiplier over PVC equivalent rows.
* **Soil Resistivity Values ($K_{soil}$)**:
  * Normal soil: **1.0 K·m/W** (standard reference)
  * Sand: **2.5 K·m/W**
  * Clay: **1.2 K·m/W**
  * Wet soil: **0.7 K·m/W**
  * Dry soil: **2.0 K·m/W**
  * Rock: **1.5 K·m/W**
* **Harmonic Bands ($K_{harmonic}$)**:
  * *None/Low/Medium/High*: Maps to standard factors **1.0**, **0.95**, **0.86**, and **0.75** respectively.
  * *THD Percent Bands*: Interpolated between 0% (1.0), 15% (0.95), 30% (0.86), 45% (0.75).
* **Duct Material Multipliers ($K_{duct}$)**:
  * PVC Duct: **0.95**
  * Steel Duct: **0.92**
* **Thermal Wall Insulation Penalty**: **0.90** (applied under K5 factor if `has_thermal_insulation` is active).
