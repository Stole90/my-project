## CircuitWorld.gd
## Top-level Game-layer orchestrator.  Owns one or more CircuitModels
## and pumps them every physics frame via solve_if_dirty().
##
## Designed to be added once to the scene tree (or set as autoload).
## Keeps the Game layer cleanly separated from the simulation layer:
##
##   Game (Node3D / scene)
##         │   uses
##         ▼
##   ElementBridge (Node3D)
##         │   binds
##         ▼
##   CircuitElement (RefCounted, pure logic)
##         │   inside
##         ▼
##   CircuitModel + CircuitSolver
#class_name CircuitWorld   # intentionally commented: conflicts with the autoload singleton of the same name
extends Node

@export var auto_solve: bool = true        # call solve_if_dirty() every frame
@export var transient_mode: bool = false   # use TransientSolver each step
@export var transient_dt: float = SimConstants.DEFAULT_DELTA_T

# Cable thermal model — heating, resistance drift, insulation damage.
@export var thermal_enabled: bool = true
# Multiplier applied to real frame Δt before stepping the thermal model.
# Use >1.0 to make heating feel responsive in gameplay (real cables heat
# over many minutes; the default τ values are already game-scaled but
# this knob lets the designer dial it further).
@export_range(0.1, 100.0, 0.1) var thermal_time_scale: float = 1.0
# Ambient temperature [°C] broadcast to all cables every frame.
@export var ambient_c: float = SimConstants.DEFAULT_AMBIENT_C

var models: Array = []  # Array[CircuitModel]

func add_model(model: CircuitModel) -> void:
		if not models.has(model):
				models.append(model)

func remove_model(model: CircuitModel) -> void:
		models.erase(model)

var sim_accumulator := 0.0
const SIM_INTERVAL := 0.1 # 10 Hz

func _physics_process(delta: float) -> void:
	if not auto_solve:
		return

	sim_accumulator += delta

	if sim_accumulator < SIM_INTERVAL:
		return

	var sim_dt = sim_accumulator
	sim_accumulator = 0.0

	for m in models:
		if transient_mode:
			m.step_transient(sim_dt)
		else:
			m.dt = sim_dt
			m.solve_if_dirty()
			m.dt = 0.0

		if thermal_enabled:
			m.step_thermal(sim_dt * thermal_time_scale, ambient_c)
