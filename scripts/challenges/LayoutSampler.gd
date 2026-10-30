class_name LayoutSampler
extends RefCounted

## v16 RUN FORGE - procedural playfield geometry.
##
## Positions are no longer ad-hoc rejection loops: dart throwing over a
## spatial hash grid gives O(1) neighbour checks, safe edge margins keep
## tokens off the tray borders, and progressive radius relaxation means
## the sampler always terminates and always fills its quota - density
## pressure eases the spacing instead of deadlocking or silently stacking
## tokens on top of each other. The 0..1 coordinate space matches the
## existing canvas renderer contract (x, y as fractions of the play area).

## Darts thrown before the radius relaxes one notch.
const DARTS_PER_RELAX: int = 26
## Each relaxation multiplies the working radius by this.
const RELAX_STEP: float = 0.92
## The radius never shrinks below this fraction of the request.
const RELAX_FLOOR: float = 0.42
## Conservative play-field width (pixels) the separation maths assumes.
const REF_WIDTH: float = 300.0

## Full-field sample with min-distance separation (0..1 coords).
static func sample_field(rng: RandomNumberGenerator, count: int, min_dist: float,
		margin_x: float = 0.10, margin_y: float = 0.13) -> Array[Vector2]:
	var rect := Rect2(margin_x, margin_y, 1.0 - margin_x * 2.0, 1.0 - margin_y * 2.0)
	return _dart_field(rng, count, min_dist, rect, [], 0.0)

## Full-field sample that also keeps its distance from fixed obstacles
## (cluster dots, the Go/No-Go trigger, etc.).
static func sample_field_avoiding(rng: RandomNumberGenerator, count: int, min_dist: float,
		obstacles: Array, obstacle_dist: float,
		margin_x: float = 0.10, margin_y: float = 0.13) -> Array[Vector2]:
	var rect := Rect2(margin_x, margin_y, 1.0 - margin_x * 2.0, 1.0 - margin_y * 2.0)
	return _dart_field(rng, count, min_dist, rect, obstacles, obstacle_dist)

## Half-field sample for split comparisons (side "L" or "R").
static func sample_split(rng: RandomNumberGenerator, count: int, min_dist: float, side: String) -> Array[Vector2]:
	var rect := Rect2(0.06, 0.16, 0.38, 0.68) if side == "L" else Rect2(0.56, 0.16, 0.38, 0.68)
	return _dart_field(rng, count, min_dist, rect, [], 0.0)

## Points sprinkled inside a disc around a center (estimation clusters).
static func ring_cluster(rng: RandomNumberGenerator, center: Vector2, count: int,
		r_min: float, r_max: float, self_dist: float = 0.0) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for i in count:
		var placed := false
		for attempt in 14:
			var angle := rng.randf_range(0.0, TAU)
			var rad: float = sqrt(rng.randf()) * rng.randf_range(r_min, r_max)
			var p := Vector2(
				clampf(center.x + cos(angle) * rad, 0.07, 0.93),
				clampf(center.y + sin(angle) * rad, 0.10, 0.90))
			if self_dist <= 0.0:
				pts.append(p)
				placed = true
				break
			var ok := true
			for q in pts:
				if p.distance_to(q) < self_dist:
					ok = false
					break
			if ok:
				pts.append(p)
				placed = true
				break
		if not placed:
			continue
	return pts

## Separation (in normalized units) a token of `size_px` drawn pixels needs
## so two of them can never fuse, based on the conservative field width.
static func separation_for(size_px: float, draw_scale: float = 1.25) -> float:
	return maxf(0.085, size_px * draw_scale * 1.06 / REF_WIDTH)

static func _dart_field(rng: RandomNumberGenerator, count: int, min_dist: float,
		rect: Rect2, obstacles: Array, obstacle_dist: float) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	if count <= 0:
		return pts
	var radius := maxf(0.012, min_dist)
	var floor_r := radius * RELAX_FLOOR
	var cell := radius
	var grid := {}
	var since_relax := 0
	var guard := 0
	var guard_max := maxi(600, count * 90)
	while pts.size() < count and guard < guard_max:
		guard += 1
		var candidate := Vector2(
			rect.position.x + rng.randf() * rect.size.x,
			rect.position.y + rng.randf() * rect.size.y)
		if not _far_enough(candidate, radius, grid, cell):
			since_relax += 1
			if since_relax >= DARTS_PER_RELAX and radius > floor_r:
				radius = maxf(floor_r, radius * RELAX_STEP)
				cell = radius
				grid = _regrid(pts, cell)
				since_relax = 0
			continue
		if _blocked_by_obstacle(candidate, obstacles, obstacle_dist):
			since_relax += 1
			continue
		var key := _cell_key(candidate, cell)
		if not grid.has(key):
			grid[key] = []
		grid[key].append(candidate)
		pts.append(candidate)
		since_relax = 0
	# Guarantee the quota even under pathological density requests.
	while pts.size() < count:
		pts.append(Vector2(
			rect.position.x + rng.randf() * rect.size.x,
			rect.position.y + rng.randf() * rect.size.y))
	return pts

static func _blocked_by_obstacle(candidate: Vector2, obstacles: Array, obstacle_dist: float) -> bool:
	if obstacle_dist <= 0.0:
		return false
	for o in obstacles:
		if candidate.distance_to(Vector2(float(o.x), float(o.y))) < obstacle_dist:
			return true
	return false

static func _cell_key(p: Vector2, cell: float) -> Vector2i:
	return Vector2i(int(floor(p.x / cell)), int(floor(p.y / cell)))

static func _far_enough(candidate: Vector2, radius: float, grid: Dictionary, cell: float) -> bool:
	var key := _cell_key(candidate, cell)
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var k := key + Vector2i(ox, oy)
			if grid.has(k):
				for p in grid[k]:
					if candidate.distance_to(p) < radius:
						return false
	return true

static func _regrid(pts: Array[Vector2], cell: float) -> Dictionary:
	var grid := {}
	for p in pts:
		var k := _cell_key(p, cell)
		if not grid.has(k):
			grid[k] = []
		grid[k].append(p)
	return grid
