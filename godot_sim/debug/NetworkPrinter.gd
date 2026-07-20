## NetworkPrinter.gd
## Pretty-print helpers for debugging.  Pure functions, no side-effects.

class_name NetworkPrinter
extends RefCounted

static func print_model(model: CircuitModel) -> void:
	var sep: String = "─".repeat(60)
	print(sep)
	print("  NETWORK: %s   (solved=%s)" % [model.network_name, str(model.last_solved_ok)])
	print(sep)

	print("[NODES]")
	for n in model.nodes:
		print("  %s" % str(n))

	print("[ELEMENTS]")
	for e in model.elements:
		var I: float = 0.0 if e.current == null else e.current.magnitude()
		print("  %-30s  I=%.4fA  enabled=%s" % [str(e), I, str(e.enabled)])

	var totals: Dictionary = model.get_totals()
	if not totals.is_empty():
		print("[TOTALS]")
		print("  Load P    = %.3f W"        % totals["load_P_w"])
		print("  Load Q    = %.3f VAr"      % totals["load_Q_var"])
		print("  Cable Σ   = %.4f W (loss)" % totals["cable_loss_w"])
		print("  Source P  = %.3f W"        % totals["source_P_w"])
		var balance: float = abs(totals["source_P_w"] - totals["load_P_w"] - totals["cable_loss_w"])
		print("  Balance   = %.6f W"        % balance)
	print(sep)
