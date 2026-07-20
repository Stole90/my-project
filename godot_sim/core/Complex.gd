## Complex.gd
## Complex number arithmetic for AC phasor analysis.
## Preserved from original implementation (works correctly, well-tested).
## Used by every phasor, impedance, admittance and matrix entry.

class_name Complex
extends RefCounted

var re: float = 0.0
var im: float = 0.0

func _init(real: float = 0.0, imag: float = 0.0) -> void:
	re = real
	im = imag

static func from_polar(magnitude: float, angle_rad: float) -> Complex:
	return Complex.new(magnitude * cos(angle_rad), magnitude * sin(angle_rad))

static func zero() -> Complex:
	return Complex.new(0.0, 0.0)

static func one() -> Complex:
	return Complex.new(1.0, 0.0)

func magnitude() -> float:
	return sqrt(re * re + im * im)

func phase_rad() -> float:
	return atan2(im, re)

func phase_deg() -> float:
	return rad_to_deg(atan2(im, re))

func add(other: Complex) -> Complex:
	return Complex.new(re + other.re, im + other.im)

func sub(other: Complex) -> Complex:
	return Complex.new(re - other.re, im - other.im)

func mul(other: Complex) -> Complex:
	return Complex.new(
		re * other.re - im * other.im,
		re * other.im + im * other.re
	)

func scale(r: float) -> Complex:
	return Complex.new(re * r, im * r)

func div(other: Complex) -> Complex:
	var denom: float = other.re * other.re + other.im * other.im
	if denom < 1e-300:
		push_error("Complex.div: division by zero")
		return Complex.zero()
	return Complex.new(
		(re * other.re + im * other.im) / denom,
		(im * other.re - re * other.im) / denom
	)

func reciprocal() -> Complex:
	return Complex.one().div(self)

func conjugate() -> Complex:
	return Complex.new(re, -im)

func negate() -> Complex:
	return Complex.new(-re, -im)

func add_inplace(other: Complex) -> Complex:
	re += other.re
	im += other.im
	return self

func sub_inplace(other: Complex) -> Complex:
	re -= other.re
	im -= other.im
	return self

func copy() -> Complex:
	return Complex.new(re, im)

func _to_string() -> String:
	if im >= 0.0:
		return "%.6f+%.6fj" % [re, im]
	return "%.6f%.6fj" % [re, im]
