@tool
extends Node3D
## Generates village maps out of the tiles in res://Tiles and saves them as playable levels.
##
## How to use (in the editor):
##   1. Open Tools/map_generator.tscn.
##   2. Set size etc. in the inspector and press "New Map" (random seed) or "Generate" (current seed):
##      the map appears as a preview.
##   3. Press "Save Level": writes res://Levels/Generated/generated_level_<seed>.tscn with the map,
##      a baked navmesh, the player, door + end zone, item markers and enemies with patrol routes.
##
## In the game: the "Level Generator" page (Menues/level_generator.tscn) sets the values listed in
## SETTING_NAMES and plays the map right away (game_container.gd calls apply_settings() + generate()).
##
## Layout: a maze on a grid (randomized depth-first search) with some extra connections (loops)
## and optionally one 2x2 plaza. Every cell then gets a tile whose open sides match its connections.

const TILE_SIZE := 12.0
const TILE_DIR := "res://Tiles"

# Tile files are picked up automatically by their name prefix (new variants just need the right name)
const SHAPE_PREFIX := {
	"dead_end": "dead_end_tile_",
	"straight": "i_tile_",
	"corner": "l_tile_",
	"t": "t_tile_",
	"cross": "x_tile_",
	"plaza": "plaza_tile_",
}
# Open sides of each shape as the tiles are built (before rotating). N = -Z, S = +Z, E = +X, W = -X
const DEFAULT_OPEN := {
	"dead_end": ["S"],
	"straight": ["N", "S"],
	"corner": ["N", "E"],
	"t": ["E", "S", "W"],
	"cross": ["N", "E", "S", "W"],
}
# Rotating a tile by +90° around Y moves each side one step along this list (S -> E -> N -> W -> S)
const ROTATION_ORDER := ["N", "W", "S", "E"]
const DIRS := {"N": Vector2i(0, -1), "S": Vector2i(0, 1), "E": Vector2i(1, 0), "W": Vector2i(-1, 0)}
const OPPOSITE := {"N": "S", "S": "N", "E": "W", "W": "E"}
# Loops never remove dead ends below this number (start, goal and item spots live there)
const MIN_DEAD_ENDS := 3

# Settings the in-game Level Generator page can change (plain values only, no scenes)
const SETTING_NAMES: Array[String] = [
	"map_seed", "width", "height", "loop_chance", "with_plaza", "coin_markers",
	"enemy_density", "base_share", "paranoid_share", "watchman_share", "dog_share",
	"base_reach", "paranoid_reach", "dog_reach", "watchman_reach",
	"min_steps_from_start", "enemy_spawn_height",
]

# Door position in a dead-end tile (entry at +Z), door scene spans x 0..2.1 from its origin
const DOOR_LOCAL := Vector3(-1.05, 0.0, 5.5)

const PLAYER_SCENE := "res://Assets/Player/player.tscn"
const DOOR_SCENE := "res://Assets/BuiltAssets/door.tscn"
const END_ZONE_SCENE := "res://Assets/BuiltAssets/end_zone.tscn"
const ITEM_SPAWNER_SCRIPT := "res://item_spawner.gd"

@export var map_seed := 1
@export_range(3, 12) var width := 5
@export_range(3, 12) var height := 5
## Chance per wall between two cells to be opened up as well, so there is more than one way around
@export_range(0.0, 0.6, 0.05) var loop_chance := 0.15
## One 2x2 plaza somewhere inside the map (needs at least 4x4 cells)
@export var with_plaza := true
## How many coin markers are placed (the ItemSpawner picks coin_count of them at runtime)
@export var coin_markers := 6
@export_dir var output_folder := "res://Levels/Generated"

@export_tool_button("New Map", "RandomNumberGenerator") var new_map_button = new_map
@export_tool_button("Generate", "Reload") var generate_button = generate
@export_tool_button("Save Level", "Save") var save_button = save_level
@export_tool_button("Clear Preview", "Remove") var clear_button = clear_preview

@export_group("Enemies")
## Enemies per map cell (0 = none). A 5x5 map at 0.25 gets 6 enemies
@export_range(0.0, 1.0, 0.05) var enemy_density := 0.25
@export var base_enemy: PackedScene
@export var paranoid_enemy: PackedScene
@export var watchman: PackedScene
@export var guard_dog: PackedScene
## Shares of the enemy types (normalized automatically)
@export_range(0.0, 1.0, 0.05) var base_share := 0.40
@export_range(0.0, 1.0, 0.05) var paranoid_share := 0.25
@export_range(0.0, 1.0, 0.05) var watchman_share := 0.20
@export_range(0.0, 1.0, 0.05) var dog_share := 0.15
## How far an enemy patrols, in cells (1 cell = 12 m of street). 0 = stands still
@export_range(0, 8) var base_reach := 2
@export_range(0, 8) var paranoid_reach := 2
@export_range(0, 8) var dog_reach := 4
@export_range(0, 8) var watchman_reach := 0
## No enemy closer than this many cells to the player start (and none in the goal cell)
@export_range(0, 8) var min_steps_from_start := 1
## Spawn height above the navmesh
@export var enemy_spawn_height := 0.0
## Watchmen stand still, so they are only placed where the player can walk around them.
## Room the player keeps from the watchtower on the way around (on top of both collision radii)
@export var watchman_pass_margin := 0.3
## Optional: a NavigationMesh with settings you tuned (agent radius, layers, ...). It is copied for every bake.
@export var navmesh_template: NavigationMesh

var _rng := RandomNumberGenerator.new()
var _open := {}                    # Vector2i cell -> Array of open sides ("N", "E", ...)
var _plaza: Array[Vector2i] = []   # the 4 plaza cells, top-left first
var _tiles := {}                   # Vector2i cell -> tile instance
var _level: Node3D                 # preview / level being built
var _start := Vector2i(-1, -1)     # cell where the player starts
var _goal := Vector2i(-1, -1)      # cell with the end zone (and the door)
var _enemies_root: Node3D
var _patrols_root: Node3D
var _walkable := {}                  # Vector2i cell -> navmesh height at the cell centre (only cells the player can reach)

# Navmesh polygons, read back from the baked NavigationMesh
var _nav_polys: Array[PackedVector2Array] = []
var _nav_rects: Array[Rect2] = []
var _nav_comp: Array[int] = []       # connected piece each polygon belongs to
var _nav_height: Array[float] = []
var _start_comp := -1                # connected piece of the navmesh the player starts on


# ---------------------------------------------------------------- buttons

# Picks a new random seed and generates (the seed shows in the inspector, so a good map can be made again)
func new_map() -> void:
	map_seed = randi_range(1, 999999)
	notify_property_list_changed()
	generate()


# Same seed = same map
func generate() -> void:
	clear_preview()
	_rng.seed = map_seed
	var files := _collect_tile_files()
	if files.is_empty():
		return
	# Start and goal need two dead ends: very small maps can come out without, then roll again
	for _attempt in 20:
		_build_layout()
		if _open.keys().filter(_is_dead_end).size() >= 2:
			break
	_build_level(files)
	print(_layout_ascii())


func save_level() -> void:
	if _level == null or _level.name != _level_name():
		generate()
	if _level == null:
		return
	DirAccess.make_dir_recursive_absolute(output_folder)
	var scene := PackedScene.new()
	var err := scene.pack(_level)
	if err != OK:
		push_error("Map generator: could not pack the level (%s)" % error_string(err))
		return
	var path := "%s/generated_level_%d.tscn" % [output_folder, map_seed]
	err = ResourceSaver.save(scene, path)
	if err != OK:
		push_error("Map generator: could not save %s (%s)" % [path, error_string(err)])
		return
	# (EditorInterface via Engine: the name does not exist in exported games and would break the script)
	if Engine.is_editor_hint() and Engine.has_singleton("EditorInterface"):
		Engine.get_singleton("EditorInterface").get_resource_filesystem().scan()
	print("Map generator: saved ", path)


func get_settings() -> Dictionary:
	var settings := {}
	for setting in SETTING_NAMES:
		settings[setting] = get(setting)
	return settings


func apply_settings(settings: Dictionary) -> void:
	for setting in settings:
		if SETTING_NAMES.has(setting):
			set(setting, settings[setting])


func clear_preview() -> void:
	if _level and is_instance_valid(_level):
		_level.free()
	_level = null
	_tiles.clear()


func _level_name() -> String:
	return "GeneratedLevel%d" % map_seed


# ---------------------------------------------------------------- layout

func _build_layout() -> void:
	_open.clear()
	_plaza.clear()
	for y in height:
		for x in width:
			_open[Vector2i(x, y)] = []

	# The plaza is never at the border: it has no walls of its own, its neighbours close it off
	if with_plaza and width >= 4 and height >= 4:
		var p := Vector2i(_rng.randi_range(1, width - 3), _rng.randi_range(1, height - 3))
		_plaza = [p, p + Vector2i(1, 0), p + Vector2i(0, 1), p + Vector2i(1, 1)]
		_connect(p, "E")
		_connect(p, "S")
		_connect(p + Vector2i(1, 0), "S")
		_connect(p + Vector2i(0, 1), "E")

	# Randomized depth-first search ("recursive backtracker"): every cell becomes reachable
	var visited := {}
	var stack: Array[Vector2i] = []
	_visit(Vector2i(_rng.randi_range(0, width - 1), _rng.randi_range(0, height - 1)), visited, stack)
	while not stack.is_empty():
		var cur: Vector2i = stack.back()
		var options: Array[String] = []
		for side in DIRS:
			var n: Vector2i = cur + DIRS[side]
			if _inside(n) and not visited.has(n):
				options.append(side)
		if options.is_empty():
			stack.pop_back()
			continue
		var chosen: String = options[_rng.randi() % options.size()]
		_connect(cur, chosen)
		_visit(cur + DIRS[chosen], visited, stack)

	# Loops: open some extra connections so a guard does not block the only way,
	# but keep enough dead ends for the start, the goal and item spots
	var dead_ends := 0
	for cell in _open:
		if _is_dead_end(cell):
			dead_ends += 1
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			for side in ["E", "S"]:
				var n: Vector2i = cell + DIRS[side]
				if _inside(n) and not _open[cell].has(side) and _rng.randf() < loop_chance:
					var lost := int(_is_dead_end(cell)) + int(_is_dead_end(n))
					if dead_ends - lost < MIN_DEAD_ENDS:
						continue
					_connect(cell, side)
					dead_ends -= lost


func _visit(cell: Vector2i, visited: Dictionary, stack: Array[Vector2i]) -> void:
	var group: Array[Vector2i] = [cell]
	if _plaza.has(cell):
		group = _plaza
	for c in group:
		if not visited.has(c):
			visited[c] = true
			stack.append(c)


func _connect(cell: Vector2i, side: String) -> void:
	var n: Vector2i = cell + DIRS[side]
	if not _open[cell].has(side):
		_open[cell].append(side)
	if not _open[n].has(OPPOSITE[side]):
		_open[n].append(OPPOSITE[side])


func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


# Which shape and how many 90° steps turn its default open sides into the wanted ones
func _shape_for(sides: Array) -> Array:
	for shape in DEFAULT_OPEN:
		var base: Array = DEFAULT_OPEN[shape]
		if base.size() != sides.size():
			continue
		for k in 4:
			var matches := true
			for s in base:
				if not sides.has(_rotate_side(s, k)):
					matches = false
					break
			if matches:
				return [shape, k]
	return []


func _rotate_side(side: String, steps: int) -> String:
	return ROTATION_ORDER[(ROTATION_ORDER.find(side) + steps) % 4]


# Number of steps from one cell to every other cell
func _distances(from: Vector2i) -> Dictionary:
	var dist := {from: 0}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for side in _open[c]:
			var n: Vector2i = c + DIRS[side]
			if not dist.has(n):
				dist[n] = dist[c] + 1
				queue.append(n)
	return dist


# ---------------------------------------------------------------- level

func _collect_tile_files() -> Dictionary:
	var files := {}
	for shape in SHAPE_PREFIX:
		files[shape] = []
	for f in DirAccess.get_files_at(TILE_DIR):
		var file := f.trim_suffix(".remap")   # exported games list scenes as .tscn.remap
		if not file.ends_with(".tscn"):
			continue
		for shape in SHAPE_PREFIX:
			if file.begins_with(SHAPE_PREFIX[shape]):
				files[shape].append(TILE_DIR + "/" + file)
	for shape in files:
		files[shape].sort()  # same order on every machine, so a seed always gives the same map
		if files[shape].is_empty() and (shape != "plaza" or with_plaza):
			push_error("Map generator: no tiles found for '%s' (%s*.tscn in %s)" % [shape, SHAPE_PREFIX[shape], TILE_DIR])
			return {}
	return files


func _build_level(files: Dictionary) -> void:
	_level = Node3D.new()
	_level.name = _level_name()
	add_child(_level)  # inside the tree: needed for baking and global positions (not saved with this scene)

	var env_node := WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env_node.environment = env
	env_node.camera_attributes = CameraAttributesPractical.new()
	_add(env_node, _level)

	var nav := NavigationRegion3D.new()
	nav.name = "NavigationRegion3D"
	nav.navigation_mesh = _make_navmesh()
	_add(nav, _level)
	var map := Node3D.new()
	map.name = "Map"
	_add(map, nav)

	# Tiles
	_tiles.clear()
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			if _plaza.has(cell):
				if cell != _plaza[0]:
					continue
				var plaza := _add_tile(_pick(files["plaza"]), map, "Plaza_%d_%d" % [x, y])
				plaza.position = Vector3((x + 0.5) * TILE_SIZE, 0, (y + 0.5) * TILE_SIZE)
				plaza.rotation.y = deg_to_rad(90 * _rng.randi_range(0, 3))
				for c in _plaza:
					_tiles[c] = plaza
				continue
			var shape_rot := _shape_for(_open[cell])
			var shape: String = shape_rot[0]
			var tile := _add_tile(_pick(files[shape]), map, "%s_%d_%d" % [shape, x, y])
			tile.position = Vector3(x * TILE_SIZE, 0, y * TILE_SIZE)
			tile.rotation.y = deg_to_rad(90 * shape_rot[1])
			_tiles[cell] = tile

	nav.bake_navigation_mesh(false)
	_place_gameplay()
	_place_enemies(nav.navigation_mesh)


func _add_tile(path: String, parent: Node, node_name: String) -> Node3D:
	var tile: Node3D = load(path).instantiate()
	tile.name = node_name
	_add(tile, parent)
	return tile


func _add(node: Node, parent: Node) -> void:
	parent.add_child(node)
	node.owner = _level


func _pick(list: Array):
	return list[_rng.randi() % list.size()]


func _shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp


func _is_dead_end(cell: Vector2i) -> bool:
	return not _plaza.has(cell) and _open[cell].size() == 1


# A free spot in a cell: the tile's ItemSpawn marker (dead ends), else the middle of the street
func _spot(cell: Vector2i) -> Vector3:
	var marker: Node3D = _tiles[cell].get_node_or_null("ItemSpawn") as Node3D
	if marker:
		return _level.to_local(marker.global_position)
	return Vector3(cell.x * TILE_SIZE, 0.5, cell.y * TILE_SIZE)


func _place_gameplay() -> void:
	# Start and goal: the two dead ends that are farthest apart
	var dead_ends: Array[Vector2i] = []
	for cell in _open:
		if _is_dead_end(cell):
			dead_ends.append(cell)
	var start: Vector2i = dead_ends[0] if not dead_ends.is_empty() else Vector2i(0, 0)
	var goal := start
	var best := -1
	for a in dead_ends:
		var d := _distances(a)
		for b in dead_ends:
			if d[b] > best:
				best = d[b]
				start = a
				goal = b
	if goal == start:
		# (almost) no dead ends: goal is simply the farthest street cell
		var d := _distances(start)
		for cell in d:
			if not _plaza.has(cell) and d[cell] > d[goal]:
				goal = cell
	if _rng.randf() < 0.5 and _is_dead_end(start) and _is_dead_end(goal):
		var tmp := start
		start = goal
		goal = tmp
	_start = start
	_goal = goal

	# Player
	var player: Node3D = load(PLAYER_SCENE).instantiate()
	player.name = "Player"
	_add(player, _level)
	player.position = _spot(start) + Vector3(0, 0.5, 0)

	# Goal: end zone inside the goal dead end, door at its entry (the key opens it)
	var end_zone: Node3D = load(END_ZONE_SCENE).instantiate()
	end_zone.name = "EndZone"
	_add(end_zone, _level)
	var goal_spot := _spot(goal)
	end_zone.position = Vector3(goal_spot.x, 0, goal_spot.z)
	if _is_dead_end(goal):
		var door: Node3D = load(DOOR_SCENE).instantiate()
		door.name = "Door"
		_add(door, _level)
		door.transform = _tiles[goal].transform * Transform3D(Basis.IDENTITY, DOOR_LOCAL)
	else:
		push_warning("Map generator: the goal is not a dead end, no door placed")

	# Item markers: key and bomb far away from the start, dead ends first; coins anywhere else
	var from_start := _distances(start)
	var cells: Array[Vector2i] = []
	for cell in _open:
		if cell != start and cell != goal and not _plaza.has(cell):
			cells.append(cell)
	_shuffle(cells)  # random order among cells with the same distance
	cells.sort_custom(func(a, b):
		var da: int = from_start[a] + (100 if _is_dead_end(a) else 0)
		var db: int = from_start[b] + (100 if _is_dead_end(b) else 0)
		return da > db)
	var key_cells: Array[Vector2i] = []
	var bomb_cells: Array[Vector2i] = []
	for i in mini(6, cells.size()):
		if i % 2 == 0:
			key_cells.append(cells[i])
		else:
			bomb_cells.append(cells[i])
	var coin_cells := cells.slice(6)
	_shuffle(coin_cells)
	coin_cells = coin_cells.slice(0, coin_markers)

	var markers := Node3D.new()
	markers.name = "ItemMarkers"
	_add(markers, _level)
	var spawner := Node3D.new()
	spawner.name = "ItemSpawner"
	spawner.set_script(load(ITEM_SPAWNER_SCRIPT))
	_add(spawner, _level)
	var key_points: Array[Marker3D] = []
	var bomb_points: Array[Marker3D] = []
	var coin_points: Array[Marker3D] = []
	for c in key_cells:
		key_points.append(_marker(markers, "KeyMarker", c))
	for c in bomb_cells:
		bomb_points.append(_marker(markers, "BombMarker", c))
	for c in coin_cells:
		coin_points.append(_marker(markers, "CoinMarker", c))
	# coins can also lie on the plaza
	if not _plaza.is_empty():
		var patrol: Node = _tiles[_plaza[0]].get_node_or_null("PatrolPoints")
		if patrol and patrol.get_child_count() > 0:
			var p: Node3D = patrol.get_child(_rng.randi() % patrol.get_child_count())
			var m := Marker3D.new()
			m.name = "CoinMarkerPlaza"
			_add(m, markers)
			m.position = _level.to_local(p.global_position)
			coin_points.append(m)
	spawner.set("key_spawn_points", key_points)
	spawner.set("bomb_spawn_points", bomb_points)
	spawner.set("coin_spawn_points", coin_points)


func _marker(parent: Node, prefix: String, cell: Vector2i) -> Marker3D:
	var m := Marker3D.new()
	m.name = "%s_%d_%d" % [prefix, cell.x, cell.y]
	_add(m, parent)
	m.position = _spot(cell)
	return m
	
	
# ---------------------------------------------------------------- enemies

func _make_navmesh() -> NavigationMesh:
	if navmesh_template:
		return navmesh_template.duplicate() as NavigationMesh   # keeps your tuned settings
	var navmesh := NavigationMesh.new()
	navmesh.agent_radius = 0.5
	# CharacterBody3D can't step up. With the default of 0.25 low props (crates) count as walkable,
	# the path leads over them and the enemies get stuck in front of them. All floors are at the
	# same height (slopes are covered by agent_max_slope), so no climbing is needed. Godot floors
	# this value to whole cell_height steps anyway, so e.g. 0.1 would also end up as 0.
	navmesh.agent_max_climb = 0.0
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_collision_mask = 0b11   # layer 1 (floor) + layer 2 (houses)
	return navmesh


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE_SIZE, cell.y * TILE_SIZE)   # x, z


func _place_enemies(navmesh: NavigationMesh) -> void:
	var plan := _enemy_plan(roundi(width * height * enemy_density))
	if plan.is_empty():
		return

	_walkable = _find_walkable_cells(navmesh)
	var from_start := _distances(_start)
	var free: Array[Vector2i] = []
	for cell: Vector2i in _walkable:
		if cell != _start and cell != _goal and from_start[cell] >= min_steps_from_start:
			free.append(cell)

	if free.size() < plan.size():
		push_warning("Map generator: only %d free cells for %d enemies" % [free.size(), plan.size()])
		plan.resize(free.size())
	if plan.is_empty():
		return

	_enemies_root = Node3D.new()
	_enemies_root.name = "Enemies"
	_add(_enemies_root, _level)
	_patrols_root = Node3D.new()
	_patrols_root.name = "Patrols"
	_add(_patrols_root, _level)

	var taken: Array[Vector2i] = []
	var steps_to_nearest := {}   # cell -> walking steps to the closest enemy placed so far

	for def in plan:
		if def.scene == null:
			push_warning("Map generator: no scene assigned for '%s' enemies, skipped" % def.name)
			continue

		# Cells farthest from all enemies so far come first (random order among equals)
		var candidates := free.filter(func(c): return not taken.has(c))
		_shuffle(candidates)
		candidates.sort_custom(func(a, b): return steps_to_nearest.get(a, 999) > steps_to_nearest.get(b, 999))

		var placed := false
		for cell: Vector2i in candidates:
			var stops: Array[Vector2i] = []
			if def.reach > 0:
				stops = _patrol_cells(cell, def.reach)
				if stops.size() < 2:
					continue   # would just stand there: try the next cell
			var spot: Variant = null
			if def.name == "watchman":
				spot = _watchman_spot(cell, def.scene)
				if spot == null:
					continue   # no room to walk around it in this cell (e.g. a narrow street): try the next cell
			_spawn_enemy(def, cell, stops, taken.size(), spot)
			taken.append(cell)
			var d := _distances(cell)
			for c in d:
				steps_to_nearest[c] = mini(steps_to_nearest.get(c, 999), d[c])
			placed = true
			break
		if not placed:
			push_warning("Map generator: no valid cell found for a '%s' enemy" % def.name)

	print("Map generator: placed %d / %d enemies" % [taken.size(), plan.size()])


# Exact number per type (largest-remainder rounding), shuffled with the seeded RNG
func _enemy_plan(count: int) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	if count <= 0:
		return plan
	var defs: Array[Dictionary] = [
		{"name": "base", "scene": base_enemy, "share": base_share, "reach": base_reach},
		{"name": "paranoid", "scene": paranoid_enemy, "share": paranoid_share, "reach": paranoid_reach},
		{"name": "watchman", "scene": watchman, "share": watchman_share, "reach": watchman_reach},
		{"name": "dog", "scene": guard_dog, "share": dog_share, "reach": dog_reach},
	]
	var total := 0.0
	for d in defs:
		total += d.share
	if total <= 0.0:
		return plan

	var counts: Array[int] = []
	var remainders: Array = []
	var assigned := 0
	for i in defs.size():
		var exact: float = count * defs[i].share / total
		counts.append(int(exact))
		assigned += int(exact)
		remainders.append([exact - int(exact), i])
	remainders.sort_custom(func(a, b): return a[0] > b[0])
	for k in mini(count - assigned, remainders.size()):
		counts[remainders[k][1]] += 1

	for i in defs.size():
		for n in counts[i]:
			plan.append(defs[i])
	_shuffle(plan)
	return plan


# Up to 3 patrol stops about `reach` cells away, as spread out as possible (by walking steps)
func _patrol_cells(origin: Vector2i, reach: int) -> Array[Vector2i]:
	var d := _distances(origin)
	var pool: Array[Vector2i] = []
	for c: Vector2i in d:
		if _walkable.has(c) and d[c] >= maxi(1, reach - 1) and d[c] <= reach:
			pool.append(c)
	_shuffle(pool)

	var stops: Array[Vector2i] = []
	while stops.size() < 3 and not pool.is_empty():
		var stop_dists: Array[Dictionary] = []
		for s in stops:
			stop_dists.append(_distances(s))
		var best_i := 0
		var best_score := -1
		for i in pool.size():
			var score := 999
			for sd in stop_dists:
				score = mini(score, sd[pool[i]])
			if score > best_score:
				best_score = score
				best_i = i
		stops.append(pool.pop_at(best_i))
	return stops


func _spawn_enemy(def: Dictionary, cell: Vector2i, stops: Array[Vector2i], index: int, spot: Variant = null) -> void:
	var enemy := (def.scene as PackedScene).instantiate() as Node3D
	enemy.name = "%s_%02d" % [def.name, index]
	_add(enemy, _enemies_root)
	if spot != null:
		enemy.position = (spot as Vector3) + Vector3.UP * enemy_spawn_height
	else:
		var c := _cell_center(cell)
		enemy.position = Vector3(c.x, _walkable[cell] + enemy_spawn_height, c.y)

	if stops.is_empty():
		return   # watchman: stands still

	# Real Marker3D nodes, so the route is saved in the level and editable in the editor
	var markers: Array[Node3D] = []
	for i in stops.size():
		var sc := _cell_center(stops[i])
		var marker := Marker3D.new()
		marker.name = "%s_WP%d" % [enemy.name, i]
		_add(marker, _patrols_root)
		marker.position = Vector3(sc.x, _walkable[stops[i]], sc.y)
		markers.append(marker)
	enemy.set("patrol_points", markers)


# ---- watchman placement ----

const WATCHMAN_RING_SAMPLES := 48
var _radius_cache := {}

# The spot in this cell closest to its centre where a watchtower doesn't block the way, or null.
# The player's centre can come no closer to the tower than both collision radii (+ margin): on
# that circle around the tower the player has to find a way past it.
func _watchman_spot(cell: Vector2i, scene: PackedScene) -> Variant:
	var ring := _collision_radius(scene) + _collision_radius(load(PLAYER_SCENE)) + watchman_pass_margin
	var c := _cell_center(cell)
	var offsets: Array[Vector2] = []
	var steps := int(TILE_SIZE * 0.5) - 1   # 1 m grid over the cell, not right at its edge
	for ix in range(-steps, steps + 1):
		for iz in range(-steps, steps + 1):
			offsets.append(Vector2(ix, iz))
	offsets.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length_squared() < b.length_squared())

	for off in offsets:
		var p := c + off
		var i := _nav_poly_at(p.x, p.y)
		if i < 0 or _nav_comp[i] != _start_comp:
			continue
		if _can_walk_around(p, ring):
			return Vector3(p.x, _nav_height[i], p.y)
	return null


# Looks at the circle the player walks on around the tower and counts its walkable stretches:
#   all of it walkable -> open space all around: fine
#   one stretch        -> the tower stands at a wall, the player passes on the open side: fine
#   two or more        -> the tower plugs a street, the parts on both sides only meet through it
func _can_walk_around(center: Vector2, radius: float) -> bool:
	var free: Array[bool] = []
	for k in WATCHMAN_RING_SAMPLES:
		var a := TAU * k / WATCHMAN_RING_SAMPLES
		var q := center + Vector2(cos(a), sin(a)) * radius
		var i := _nav_poly_at(q.x, q.y)
		free.append(i >= 0 and _nav_comp[i] == _start_comp)

	var stretches := 0
	for k in WATCHMAN_RING_SAMPLES:
		if free[k] and not free[k - 1]:   # free[-1] is the last sample: the circle wraps around
			stretches += 1
	if stretches == 0:
		return free[0]   # all walkable or all blocked
	return stretches == 1


# Radius of the scene's collision shape on the ground (scale included)
func _collision_radius(scene: PackedScene) -> float:
	if _radius_cache.has(scene):
		return _radius_cache[scene]
	var radius := 0.5
	var node := scene.instantiate()
	for child in node.get_children():
		if child is CollisionShape3D and child.shape:
			var s: Vector3 = child.scale
			var shape: Shape3D = child.shape
			if shape is CapsuleShape3D or shape is CylinderShape3D or shape is SphereShape3D:
				radius = shape.radius * maxf(s.x, s.z)
			elif shape is BoxShape3D:
				# Corner of the box: it can stand rotated
				radius = Vector2(shape.size.x * s.x, shape.size.z * s.z).length() * 0.5
			break
	node.free()
	_radius_cache[scene] = radius
	return radius


# ---- navmesh analysis (reads the baked polygons, no NavigationServer needed) ----

# Cells whose centre lies on the part of the navmesh that is connected to the player start
func _find_walkable_cells(navmesh: NavigationMesh) -> Dictionary:
	_read_navmesh(navmesh)
	var spot := _spot(_start)
	var start_poly := _nav_poly_at(spot.x, spot.z)
	if start_poly < 0:
		push_warning("Map generator: the player start is not on the navmesh, no enemies placed")
		return {}
	_start_comp = _nav_comp[start_poly]

	var cells := {}
	for cell: Vector2i in _open:
		var c := _cell_center(cell)
		var i := _nav_poly_at(c.x, c.y)
		if i >= 0 and _nav_comp[i] == _nav_comp[start_poly]:
			cells[cell] = _nav_height[i]
	return cells


# Polygons that share a vertex belong to the same connected piece (union-find over vertices)
func _read_navmesh(navmesh: NavigationMesh) -> void:
	_nav_polys.clear()
	_nav_rects.clear()
	_nav_comp.clear()
	_nav_height.clear()

	var verts := navmesh.get_vertices()
	var parent: Array[int] = []
	for i in verts.size():
		parent.append(i)

	var polys: Array[PackedInt32Array] = []
	for i in navmesh.get_polygon_count():
		var poly := navmesh.get_polygon(i)
		if poly.size() < 3:
			continue
		var outline := PackedVector2Array()
		var height := 0.0
		for idx in poly:
			outline.append(Vector2(verts[idx].x, verts[idx].z))
			height += verts[idx].y
			var ra := _find(parent, idx)
			var rb := _find(parent, poly[0])
			if ra != rb:
				parent[ra] = rb
		var rect := Rect2(outline[0], Vector2.ZERO)
		for p in outline:
			rect = rect.expand(p)
		polys.append(poly)
		_nav_polys.append(outline)
		_nav_rects.append(rect.grow(0.01))
		_nav_height.append(height / poly.size())

	for poly in polys:
		_nav_comp.append(_find(parent, poly[0]))


func _find(parent: Array[int], i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


# Index of the navmesh polygon under this ground position, or -1 if it isn't walkable there
func _nav_poly_at(x: float, z: float) -> int:
	var p := Vector2(x, z)
	for i in _nav_polys.size():
		if _nav_rects[i].has_point(p) and Geometry2D.is_point_in_polygon(p, _nav_polys[i]):
			return i
	return -1


# ---------------------------------------------------------------- debug

func _layout_ascii() -> String:
	var lines := ["Map %d (%dx%d, seed %d):" % [map_seed, width, height, map_seed]]
	for y in height:
		var top := ""
		var mid := ""
		for x in width:
			var cell := Vector2i(x, y)
			var sides: Array = _open[cell]
			var c := "P" if _plaza.has(cell) else ("*" if _is_dead_end(cell) else "+")
			if cell == _start:
				c = "S"
			elif cell == _goal:
				c = "Z"
			top += "+" + (" " if sides.has("N") else "-") + "+"
			mid += (" " if sides.has("W") else "|") + c + (" " if sides.has("E") else "|")
		lines.append(top)
		lines.append(mid)
	lines.append("S = start  Z = goal (door + end zone)  * = dead end  P = plaza  + = street")
	lines.append("Start cell %s, goal cell %s, %d steps apart" % [_start, _goal, _distances(_start).get(_goal, -1)])
	return "\n".join(lines)
