extends Node3D

@onready var navigation_region: NavigationRegion3D = $NavigationRegion3D

@export_group("Enemy scenes")
@export var base_enemy: PackedScene
@export var guard_dog: PackedScene
@export var paranoid_enemy: PackedScene
@export var watchman: PackedScene

@export_group("Spawning")
@export var enemy_count := 20
@export var candidates_per_enemy := 40
@export var min_distance_to_player := 15.0
@export var spawn_height := 0.5

@export_group("Shares (normalized automatically)")
@export var base_share := 0.40
@export var paranoid_share := 0.25
@export var watchman_share := 0.20
@export var dog_share := 0.15

@export_group("Patrol radius (0 = no patrol)")
@export var base_radius := 15.0
@export var paranoid_radius := 15.0
@export var dog_radius := 25.0
@export var watchman_radius := 0.0

@export_group("Level saving")
@export var generate_enemies := true      # saved levels have this set to false
@export var save_key: Key = KEY_F9
@export var save_dir := "res://Levels/Generated"
@export var auto_save := false            # true = every generated level is saved right away

var _snapshot: PackedScene
var _enemies_root: Node3D
var _patrols_root: Node3D


func _ready() -> void:
	# A saved level already contains the baked navmesh and all enemies
	if not generate_enemies:
		return

	await get_tree().physics_frame
	await bake_nav_mesh()
	spawn_enemies()

	_snapshot = _pack_level()
	if auto_save:
		save_level()


func _unhandled_input(event: InputEvent) -> void:
	if generate_enemies and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == save_key:
		save_level()


func bake_nav_mesh() -> void:
	if navigation_region.navigation_mesh == null:
		push_error("[Nav] NavigationRegion3D has no NavigationMesh resource assigned!")
		return

	# Own copy of the resource, so the baked data is embedded in the saved level
	# (an external .tres would only be saved as a reference, without the baked polygons)
	navigation_region.navigation_mesh = navigation_region.navigation_mesh.duplicate()

	print("[Nav] Baking...")
	navigation_region.bake_navigation_mesh()
	await navigation_region.bake_finished
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("[Nav] Polygons: ", navigation_region.navigation_mesh.get_polygon_count())


# ---------------- Spawning ----------------

func spawn_enemies() -> void:
	var map_rid := get_world_3d().navigation_map
	if not NavigationServer3D.map_is_active(map_rid):
		push_warning("[Enemy] Navigation map is not active yet.")
		return

	_enemies_root = _make_container("Enemies")
	_patrols_root = _make_container("Patrols")

	var plan := _build_spawn_plan()
	var positions := _pick_spread_positions(map_rid, plan.size())
	var spawned := mini(plan.size(), positions.size())

	for i in spawned:
		_spawn_one(map_rid, plan[i], positions[i], i)

	print("[Enemy] Spawned %d / %d enemies" % [spawned, enemy_count])


# Container nodes keep the saved scene tidy; owner = self makes pack() include them
func _make_container(node_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	add_child(node)
	node.owner = self
	return node


func _build_spawn_plan() -> Array[Dictionary]:
	var defs: Array[Dictionary] = [
		{"name": "base", "scene": base_enemy, "share": base_share, "radius": base_radius},
		{"name": "paranoid", "scene": paranoid_enemy, "share": paranoid_share, "radius": paranoid_radius},
		{"name": "watchman", "scene": watchman, "share": watchman_share, "radius": watchman_radius},
		{"name": "dog", "scene": guard_dog, "share": dog_share, "radius": dog_radius},
	]

	var total_share := 0.0
	for d in defs:
		total_share += d.share

	var counts: Array[int] = []
	var remainders: Array = []
	var assigned := 0
	for i in defs.size():
		var exact: float = enemy_count * defs[i].share / total_share
		counts.append(int(exact))
		assigned += int(exact)
		remainders.append([exact - int(exact), i])

	remainders.sort_custom(func(a, b): return a[0] > b[0])
	for k in mini(enemy_count - assigned, remainders.size()):
		counts[remainders[k][1]] += 1

	var plan: Array[Dictionary] = []
	for i in defs.size():
		for n in counts[i]:
			plan.append(defs[i])
	plan.shuffle()
	return plan


func _pick_spread_positions(map_rid: RID, count: int) -> Array[Vector3]:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var chosen: Array[Vector3] = []

	for i in count:
		var best := Vector3.ZERO
		var best_score := -1.0

		for c in candidates_per_enemy:
			var p := NavigationServer3D.map_get_random_point(map_rid, 1, true)
			if p == Vector3.ZERO:
				continue
			if player and _flat_distance(p, player.global_position) < min_distance_to_player:
				continue

			var score := INF
			for other in chosen:
				score = minf(score, _flat_distance(p, other))

			if score > best_score:
				best_score = score
				best = p

		if best_score >= 0.0:
			chosen.append(best)

	return chosen


func _spawn_one(map_rid: RID, def: Dictionary, spawn_pos: Vector3, index: int) -> void:
	var scene: PackedScene = def.scene
	if scene == null:
		push_warning("[Enemy] Scene for '%s' is not assigned, skipping." % def.name)
		return

	var enemy := scene.instantiate() as Node3D
	enemy.name = "%s_%02d" % [def.name, index]
	_enemies_root.add_child(enemy)
	enemy.owner = self
	enemy.global_position = spawn_pos + Vector3(0, spawn_height, 0)

	# Radius 0 = stationary (watchman): no patrol points
	var radius: float = def.radius
	if radius <= 0.0:
		return

	# Waypoints are real Marker3D nodes, so they are saved in the scene and editable in the editor
	var markers: Array[Node3D] = []
	var waypoints := _make_waypoints(map_rid, spawn_pos, radius)
	for i in waypoints.size():
		var marker := Marker3D.new()
		marker.name = "%s_WP%d" % [enemy.name, i]
		_patrols_root.add_child(marker)
		marker.owner = self
		marker.global_position = waypoints[i]
		markers.append(marker)

	enemy.set("patrol_points", markers)


func _make_waypoints(map_rid: RID, origin: Vector3, radius: float) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var base_angle := randf() * TAU

	for i in 3:
		var wp := origin
		for attempt in 6:
			var angle := base_angle + i * TAU / 3.0 + randf_range(-0.5, 0.5)
			var target := origin + Vector3(cos(angle), 0, sin(angle)) * radius
			var candidate := NavigationServer3D.map_get_closest_point(map_rid, target)
			if _is_reachable(map_rid, origin, candidate):
				wp = candidate
				break
		points.append(wp)

	return points


func _is_reachable(map_rid: RID, from: Vector3, to: Vector3) -> bool:
	var path := NavigationServer3D.map_get_path(map_rid, from, to, true)
	return not path.is_empty() and path[path.size() - 1].distance_to(to) < 1.0


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---------------- Saving ----------------

# Packed right after spawning, so the snapshot has the enemies at their spawn positions
# (not wherever they have walked to by the time you press the key)
func _pack_level() -> PackedScene:
	var packed := PackedScene.new()
	var was := generate_enemies
	generate_enemies = false   # the loaded level must not bake and spawn again
	var err := packed.pack(self)
	generate_enemies = was

	if err != OK:
		push_error("[Save] pack() failed: %s" % error_string(err))
		return null
	return packed


func save_level() -> void:
	if _snapshot == null:
		push_warning("[Save] No level snapshot available yet.")
		return

	DirAccess.make_dir_recursive_absolute(save_dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := "%s/level_%s.tscn" % [save_dir, stamp]

	var err := ResourceSaver.save(_snapshot, path)
	if err == OK:
		print("[Save] Level saved: ", path)
	else:
		push_error("[Save] Could not save %s: %s" % [path, error_string(err)])
