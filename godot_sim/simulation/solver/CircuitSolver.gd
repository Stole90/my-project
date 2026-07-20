## CircuitSolver.gd
## Abstract base class for every numerical solver.
##
## CircuitModel calls solve(model) and gets back a Dictionary of solved
## state.  This indirection means we can swap in:
##   - YBusSolver        (steady-state AC, Phase 0)
##   - TransientSolver   (backward-Euler, time-stepped)
##   - ThreePhaseSolver  (per-phase decoupled or full coupled)
## without touching CircuitModel or any element.

class_name CircuitSolver
extends RefCounted

## Run one solve cycle.
## Return value is a Dictionary with at least:
##   "ok"          : bool
##   "solve_ms"    : float
##   "errors"      : Array[String]  (empty when ok)
## Subclasses may add extra keys.
func solve(_model) -> Dictionary:
    push_error("CircuitSolver.solve() must be overridden")
    return {"ok": false, "solve_ms": 0.0, "errors": ["not implemented"]}

# ── Shared linear-algebra helpers (used by every solver) ───────────

static func make_complex_matrix(rows: int, cols: int) -> Array:
    var mat: Array = []
    mat.resize(rows)
    for i in range(rows):
        var row: Array = []
        row.resize(cols)
        for j in range(cols):
            row[j] = Complex.zero()
        mat[i] = row
    return mat

static func make_complex_vector(size: int) -> Array:
    var vec: Array = []
    vec.resize(size)
    for i in range(size):
        vec[i] = Complex.zero()
    return vec

## Solve A·x = b via Gaussian elimination with partial pivoting.
## Returns [] when matrix is singular.
## Solve A·x = b koristeći native float arrays (bez Complex GC objekata).
## A je Array[Array[Complex]], b je Array[Complex] — isti interfejs kao pre.
## Interno konvertuje u flat PackedFloat64Array za brzinu.
static func gaussian_elimination(A: Array, b: Array) -> Array:
    var N: int = b.size()
    if N == 0:
        return []

    # ── Konvertuj u flat real matrica proširena desnom stranom ──────
    # Svaki kompleksni broj = 2 floata: [re, im]
    # Redovi: N redova, N+1 kolona (poslednja = b), svaka kolona = 2 floata
    # Ukupno: N * (N+1) * 2 floata
    var cols: int = N + 1
    var M: PackedFloat64Array = PackedFloat64Array()
    M.resize(N * cols * 2)

    for i in range(N):
        for j in range(N):
            var c: Complex = A[i][j]
            var base: int = (i * cols + j) * 2
            M[base]     = c.re
            M[base + 1] = c.im
        # Desna strana
        var base_b: int = (i * cols + N) * 2
        M[base_b]     = b[i].re
        M[base_b + 1] = b[i].im

    # ── Gaussian elimination sa partial pivoting ─────────────────────
    var perm: PackedInt32Array = PackedInt32Array()
    perm.resize(N)
    for i in range(N):
        perm[i] = i

    for col in range(N):
        # Nađi pivot
        var pivot_row: int   = col
        var pivot_mag2: float = 0.0
        for row in range(col, N):
            var base: int = (perm[row] * cols + col) * 2
            var re: float = M[base]
            var im: float = M[base + 1]
            var mag2: float = re * re + im * im
            if mag2 > pivot_mag2:
                pivot_mag2 = mag2
                pivot_row  = row

        if pivot_mag2 < SimConstants.PIVOT_EPSILON * SimConstants.PIVOT_EPSILON:
            push_error("gaussian_elimination: zero pivot at column %d" % col)
            return []

        # Zameni redove (samo indekse, ne podatke)
        if pivot_row != col:
            var tmp: int   = perm[col]
            perm[col]      = perm[pivot_row]
            perm[pivot_row] = tmp

        # Eliminacija
        var p: int     = perm[col]
        var pb: int    = (p * cols + col) * 2
        var p_re: float = M[pb]
        var p_im: float = M[pb + 1]
        var p_mag2: float = p_re * p_re + p_im * p_im

        for row in range(col + 1, N):
            var r: int   = perm[row]
            var rb: int  = (r * cols + col) * 2
            var r_re: float = M[rb]
            var r_im: float = M[rb + 1]
            if r_re == 0.0 and r_im == 0.0:
                continue

            # factor = M[r][col] / M[p][col]  (kompleksno deljenje)
            var f_re: float = (r_re * p_re + r_im * p_im) / p_mag2
            var f_im: float = (r_im * p_re - r_re * p_im) / p_mag2

            # Eliminišemo od col do N (uključujući b)
            for k in range(col, cols):
                var kb_p: int = (p * cols + k) * 2
                var kb_r: int = (r * cols + k) * 2
                var pk_re: float = M[kb_p]
                var pk_im: float = M[kb_p + 1]
                # M[r][k] -= factor * M[p][k]
                M[kb_r]     -= f_re * pk_re - f_im * pk_im
                M[kb_r + 1] -= f_re * pk_im + f_im * pk_re

    # ── Back substitution ────────────────────────────────────────────
    var x_re: PackedFloat64Array = PackedFloat64Array()
    var x_im: PackedFloat64Array = PackedFloat64Array()
    x_re.resize(N)
    x_im.resize(N)

    for i in range(N - 1, -1, -1):
        var r: int     = perm[i]
        var base_b: int = (r * cols + N) * 2
        var val_re: float = M[base_b]
        var val_im: float = M[base_b + 1]

        for j in range(i + 1, N):
            var base_ij: int = (r * cols + j) * 2
            var aij_re: float = M[base_ij]
            var aij_im: float = M[base_ij + 1]
            # val -= A[r][j] * x[j]
            val_re -= aij_re * x_re[j] - aij_im * x_im[j]
            val_im -= aij_re * x_im[j] + aij_im * x_re[j]

        # x[i] = val / M[r][i]
        var base_ii: int = (r * cols + i) * 2
        var d_re: float = M[base_ii]
        var d_im: float = M[base_ii + 1]
        var d_mag2: float = d_re * d_re + d_im * d_im
        x_re[i] = (val_re * d_re + val_im * d_im) / d_mag2
        x_im[i] = (val_im * d_re - val_re * d_im) / d_mag2

    # ── Konvertuj nazad u Array[Complex] ─────────────────────────────
    var result: Array = []
    result.resize(N)
    for i in range(N):
        result[i] = Complex.new(x_re[i], x_im[i])
    return result
