extends Node3D
## The finale ("Murgang" = debris flow): the bomb is planted at the weak spot of the rock dam, the
## player runs to safety, the dam blows up and mud and boulders pour down the mountain, through the
## wall of the quarry and into the town. Then the level is won (level-complete screen).
##
## Sits in the final tile at the foot of the dam; the mud flows along this node's +Z axis.
## The end zone calls play() when the bomb is used there (end_zone.gd, export "finale").
## In generated levels flow_length and widen_after are fitted to the map (meta "flow_reach" of the tile).

@export var fuse_time := 2.2             # seconds from planting to the explosion
@export var flow_length := 60.0          # how far the mud runs (metres along +Z)
@export var flow_time := 5.0             # seconds the mud needs for flow_length
@export var start_width := 7.0           # width where it breaks out of the dam
@export var flow_width := 20.0           # width in the town
@export var widen_after := 17.0          # metres from the dam where it leaves the quarry and spreads out
@export var end_delay := 1.5             # seconds after the mud stopped before the level-complete screen
@export var camera_height := 30.0        # the camera rises to this height to show the town
## Where the player runs to after planting the bomb (away from the path of the mud)
@export var safe_spot: Node3D
## Mud behind the dam: sinks while the dam drains (optional)
@export var reservoir: Node3D
## Parts of the dam that the explosion throws away
@export var blast_rocks: Array[Node3D] = []

@export_group("Sounds")   # (credits: Assets/Sounds/CREDITS.md)
@export var fuse_sound: AudioStream = preload("res://Assets/Sounds/finale/fuse.wav")
@export var explosion_sound: AudioStream = preload("res://Assets/Sounds/finale/explosion.wav")
@export var rumble_sound: AudioStream = preload("res://Assets/Sounds/finale/rumble_loop.mp3")
@export var slide_sound: AudioStream = preload("res://Assets/Sounds/finale/rockslide.wav")
@export var collapse_sound: AudioStream = preload("res://Assets/Sounds/finale/house_collapse.wav")
@export var rumble_volume_db := -4.0
@export var collapse_volume_db := -3.0
## The music gets this much quieter during the finale (and comes back before the level-complete screen)
@export var music_duck_db := -14.0

const BOMB_SCENE := preload("res://Assets/Fantasy Town Assets/simple_bomb.glb")
const ROCK_SCENE := preload("res://Assets/BuiltAssets/Finale/rock.tscn")
const BOMB_POS := Vector3(0, 0, 0.35)    # at the foot of the dam
const SEGMENT_STEP := 2.0                # a new piece of mud every 2 m
const SEGMENT_LENGTH := 3.2
const RUN_SPEED := 6.0                   # the player's sprint speed (player.gd SPRINT_SPEED)
# Node names in the tiles: groups to look into, and things the mud leaves alone
const GROUP_NAMES := ["buildings", "props", "lights", "walls"]
const SKIP_NAMES := ["floor", "dam", "cliffs", "landslide", "safespot", "endzone", "itemspawn", "patrolpoints"]

var _playing := false
var _camera: Camera3D
var _player: Node3D
var _mud_material: StandardMaterial3D
var _mud_box: BoxMesh
var _next_segment := 0.0
var _front: MeshInstance3D
var _front_rocks: Array[Node3D] = []
var _dust: CPUParticles3D
var _victims: Array[Dictionary] = []     # {node, z, kind}, sorted by z (distance along the flow)
var _mounds := 0
var _killed := {}                     # enemies the mud has already got
var _music_bus := -1
var _music_db := 0.0
var _last_collapse := -10.0           # time of the last house sound (they would drown each other out)
var _collapses_playing := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # runs while the rest of the game is frozen


func _input(event: InputEvent) -> void:
	# No pause menu or map during the finale (unpausing would wake the enemies up)
	if _playing and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("toggle_map")
			or (event is InputEventKey and event.pressed and event.keycode == KEY_P)):
		get_viewport().set_input_as_handled()


# Called by the end zone when the player uses the bomb there
func play() -> void:
	if _playing:
		return
	_playing = true
	GameManager.player_invincible = true   # the bomb is planted: nobody can catch the player any more
	get_tree().paused = true   # player and enemies freeze, only the finale moves
	_fit_to_map()
	_camera = get_viewport().get_camera_3d()
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_collect_victims()
	GameManager.show_message.emit("The fuse is burning. Run!")

	# 1. Bomb with a burning fuse; the player runs away from the dam
	var bomb := BOMB_SCENE.instantiate() as Node3D
	add_child(bomb)
	bomb.position = BOMB_POS + Vector3(0, 0.55, 0)
	bomb.scale = Vector3.ONE * 0.25
	var spark := _glow_sphere(Color(1, 0.8, 0.35), 0.06)
	add_child(spark)
	spark.position = BOMB_POS + Vector3(0, 1.12, 0)
	var spark_light := OmniLight3D.new()
	spark_light.light_color = Color(1, 0.6, 0.25)
	spark_light.omni_range = 4.0
	spark.add_child(spark_light)
	_run_to_safety()
	_duck_music(true, 0.6)
	var fuse := _sound(fuse_sound, -2.0)

	var overview := to_global(BOMB_POS)
	if safe_spot:
		overview = overview.lerp(safe_spot.global_position, 0.5)
	var t := 0.0
	while t < fuse_time:
		var dt := get_process_delta_time()
		t += dt
		spark_light.light_energy = randf_range(0.8, 2.4)
		spark.scale = Vector3.ONE * randf_range(0.6, 1.5)
		_move_camera(overview + Vector3.UP * 17.0, dt, 1.5)
		await get_tree().process_frame

	# 2. Explosion
	bomb.queue_free()
	spark.queue_free()
	if is_instance_valid(fuse):
		fuse.queue_free()
	_sound(explosion_sound, 0.0)
	_explosion()
	_shake(0.6, 0.6)
	_moonlight()
	await _wait(0.45)

	# 3. Rumble, then the mud pours down the mountain into the town
	_shake(0.16, flow_time + 0.8)
	GameManager.show_message.emit("MURGANG!")
	var rumble := _sound(rumble_sound, -30.0, true)
	if rumble:
		create_tween().tween_property(rumble, "volume_db", rumble_volume_db, 0.8)
	_sound(slide_sound, 0.0)
	_start_flow()
	if reservoir:
		create_tween().tween_property(reservoir, "position:y", reservoir.position.y - 2.0, flow_time * 0.8)
	t = 0.0
	var next_victim := 0
	while t < flow_time:
		var dt := get_process_delta_time()
		t += dt
		var front := ease(clampf(t / flow_time, 0.0, 1.0), 0.7) * flow_length   # fast at first, then slowing down
		_update_flow(front, dt)
		while next_victim < _victims.size() and _victims[next_victim].z <= front + 0.5:
			_hit(_victims[next_victim])
			next_victim += 1
		var height := lerpf(17.0, camera_height, clampf(t / 1.5, 0.0, 1.0))
		_move_camera(to_global(Vector3(0, 0, front - 3.0)) + Vector3.UP * height, dt, 3.0)
		await get_tree().process_frame
	_dust.emitting = false
	for rock in _front_rocks:
		create_tween().tween_property(rock, "position:y", rock.position.y - 0.4, 0.8)
	if rumble:
		create_tween().tween_property(rumble, "volume_db", -40.0, end_delay)
	_duck_music(false, end_delay)   # music is back by the time the level-complete screen shows
	await _wait(end_delay)
	if rumble:
		rumble.stop()

	# 4. Level complete
	GameManager.win_level()


# The map generator stores on the final tile how far the town reaches behind its entry
func _fit_to_map() -> void:
	var tile := get_parent() as Node3D
	if tile == null or not tile.has_meta("flow_reach"):
		return
	var to_entry: float = float(tile.get_meta("depth", 24.0)) * 0.5 - position.z
	widen_after = to_entry
	flow_length = to_entry + float(tile.get_meta("flow_reach"))


# ---------------------------------------------------------------- player

func _run_to_safety() -> void:
	if not is_instance_valid(_player) or safe_spot == null:
		return
	var goal := safe_spot.global_position
	goal.y = _player.global_position.y
	var way := goal - _player.global_position
	var model := _player.get("body_mesh") as Node3D
	var anim_tree := _player.get("anim_tree") as AnimationTree
	if model and way.length() > 0.1:
		model.rotation.y = atan2(way.x, way.z)
	var set_blend := func(v: float) -> void:
		anim_tree.set("parameters/move/blend_amount", v)
	var tween := create_tween()
	if anim_tree:
		anim_tree.process_mode = Node.PROCESS_MODE_ALWAYS   # keeps animating while the game is paused
		anim_tree.set("parameters/walk_speed/scale", 1.7)
		tween.tween_method(set_blend, 0.0, 1.0, 0.15)
	tween.parallel().tween_property(_player, "global_position", goal, clampf(way.length() / RUN_SPEED, 0.5, fuse_time - 0.2))
	if anim_tree:
		tween.tween_method(set_blend, 1.0, 0.0, 0.2)
	# then look back at the dam
	tween.tween_callback(func() -> void:
		var back := to_global(BOMB_POS) - goal
		if model and back.length() > 0.1:
			model.rotation.y = atan2(back.x, back.z))


# ---------------------------------------------------------------- explosion

func _explosion() -> void:
	var center := BOMB_POS + Vector3(0, 1.0, 0)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1, 0.7, 0.35)
	flash.omni_range = 24.0
	flash.light_energy = 0.0
	add_child(flash)
	flash.position = center + Vector3(0, 0.5, 0)
	var tween := create_tween()
	tween.tween_property(flash, "light_energy", 14.0, 0.05)
	tween.tween_property(flash, "light_energy", 0.0, 0.9)
	tween.tween_callback(flash.queue_free)

	var fireball := _glow_sphere(Color(1, 0.55, 0.15), 1.0)
	add_child(fireball)
	fireball.position = center
	fireball.scale = Vector3.ONE * 0.2
	var fb := create_tween()
	fb.tween_property(fireball, "scale", Vector3.ONE * 3.5, 0.25).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	fb.tween_property(fireball, "scale", Vector3.ONE * 0.1, 0.35)
	fb.tween_callback(fireball.queue_free)

	var smoke := _particles(Color(0.35, 0.32, 0.3, 0.8), 1.0, 1.8)
	smoke.position = center
	smoke.one_shot = true
	smoke.explosiveness = 0.9
	smoke.amount = 40
	smoke.direction = Vector3.UP
	smoke.spread = 80.0
	smoke.initial_velocity_min = 3.0
	smoke.initial_velocity_max = 7.0
	add_child(smoke)
	smoke.emitting = true

	# The weak spot of the dam is blown away
	for rock in blast_rocks:
		if not is_instance_valid(rock):
			continue
		var away := rock.global_position - to_global(BOMB_POS)
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else global_basis.z
		var goal := rock.global_position + away * randf_range(4, 9) + Vector3.UP * randf_range(3, 7)
		var spin := rock.rotation + Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3))
		var rt := create_tween().set_parallel(true)
		rt.tween_property(rock, "global_position", goal, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		rt.tween_property(rock, "rotation", spin, 0.7)
		rt.tween_property(rock, "scale", Vector3.ZERO, 0.4).set_delay(0.3)
	# and some rubble flies around
	for i in 12:
		var piece := ROCK_SCENE.instantiate() as Node3D
		piece.set("rock_seed", 100 + i)
		add_child(piece)
		piece.position = center + Vector3(randf_range(-1, 1), 0, randf_range(-0.5, 0.5))
		piece.scale = Vector3.ONE * randf_range(0.2, 0.45)
		var dir := Vector3(randf_range(-1, 1), 0, randf_range(-0.2, 1)).normalized()
		var pt := create_tween().set_parallel(true)
		pt.tween_property(piece, "position", piece.position + dir * randf_range(3, 9) + Vector3.UP * randf_range(1, 4), 0.6)
		pt.tween_property(piece, "scale", Vector3.ZERO, 0.3).set_delay(0.5)
		pt.chain().tween_callback(piece.queue_free)


# Cold light over the whole map, so the town can be seen from above while it gets buried
func _moonlight() -> void:
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.62, 0.7, 0.92)
	moon.light_energy = 0.0
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 90.0
	add_child(moon)
	moon.global_rotation = Vector3(deg_to_rad(-55), deg_to_rad(35), 0)
	create_tween().tween_property(moon, "light_energy", 0.5, 1.5)


# ---------------------------------------------------------------- the debris flow

func _width_at(z: float) -> float:
	return lerpf(start_width, flow_width, clampf((z - widen_after) / 14.0, 0.0, 1.0))


func _start_flow() -> void:
	_mud_material = StandardMaterial3D.new()
	_mud_material.albedo_color = Color(0.32, 0.23, 0.15)
	_mud_material.roughness = 0.4   # wet mud shines a little
	_mud_box = BoxMesh.new()
	_mud_box.material = _mud_material
	_next_segment = 0.0

	# The front: a lumpy wave of mud with boulders rolling in it
	_front = ROCK_SCENE.instantiate() as MeshInstance3D
	_front.set("rock_seed", 300)
	add_child(_front)
	_front.material_override = _mud_material
	_front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 10:
		var rock := ROCK_SCENE.instantiate() as Node3D
		rock.set("rock_seed", 200 + i)
		add_child(rock)
		rock.scale = Vector3.ONE * randf_range(0.45, 1.0)
		rock.set_meta("side", randf_range(-0.45, 0.45))   # share of the width
		rock.set_meta("lag", randf_range(0.0, 3.5))       # metres behind the front
		rock.rotation.y = randf_range(0, TAU)
		_front_rocks.append(rock)

	_dust = _particles(Color(0.4, 0.34, 0.28, 0.55), 1.3, 1.8)
	_dust.amount = 80
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.direction = Vector3(0, 1, 0)
	_dust.spread = 40.0
	_dust.initial_velocity_min = 1.5
	_dust.initial_velocity_max = 3.5
	add_child(_dust)
	_dust.emitting = true
	_update_flow(0.1, 0.0)


func _update_flow(front: float, dt: float) -> void:
	while _next_segment < front:
		_spawn_segment(_next_segment)
		_next_segment += SEGMENT_STEP
	var width := _width_at(front)
	_front.scale = Vector3(width * 0.55, 0.9, 1.5)
	_front.position = Vector3(0, 0.25, front)
	_dust.position = Vector3(0, 0.6, front)
	_dust.emission_box_extents = Vector3(width * 0.5, 0.3, 1.0)
	for rock in _front_rocks:
		var z := maxf(front - float(rock.get_meta("lag")), 0.0)
		rock.position = Vector3(float(rock.get_meta("side")) * _width_at(z), 0.45 * rock.scale.y, z)
		rock.rotate(Vector3.RIGHT, dt * 5.0 / rock.scale.x)   # rolling forward (around this node's X axis)


# One piece of the mud: rises up out of the ground right behind the front
func _spawn_segment(z: float) -> void:
	var width := _width_at(z + SEGMENT_LENGTH * 0.5) * randf_range(0.85, 1.05)
	var height := randf_range(0.7, 1.1)
	var segment := MeshInstance3D.new()
	segment.mesh = _mud_box
	segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(segment)
	segment.position = Vector3(randf_range(-0.6, 0.6), 0.0, z + SEGMENT_LENGTH * 0.5)
	segment.rotation.y = randf_range(-0.06, 0.06)
	segment.scale = Vector3(width, 0.05, SEGMENT_LENGTH)
	var tween := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT)
	tween.tween_property(segment, "scale:y", height, 0.35)
	tween.tween_property(segment, "position:y", height * 0.5 - 0.1, 0.35)
	# now and then a rock stays stuck in the mud
	if randf() < 0.5:
		var rock := ROCK_SCENE.instantiate() as Node3D
		rock.set("rock_seed", 400 + int(z))
		add_child(rock)
		rock.scale = Vector3.ONE * randf_range(0.25, 0.55)
		rock.position = Vector3(randf_range(-0.4, 0.4) * width, height - 0.1, z + randf_range(0, SEGMENT_LENGTH))
		rock.rotation = Vector3(randf_range(0, TAU), randf_range(0, TAU), 0)


# ---------------------------------------------------------------- what the mud hits

# Houses, walls, props, lights and enemies in the path of the mud, in the order the front reaches them
func _collect_victims() -> void:
	_victims.clear()
	var map: Node = get_parent().get_parent() if get_parent() else null   # tiles are children of the map
	if map:
		for tile in map.get_children():
			_collect_from(tile, true)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		_add_victim(enemy as Node3D, "enemy")
	_victims.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.z < b.z)


func _collect_from(holder: Node, is_tile: bool) -> void:
	for child in holder.get_children():
		var node := child as Node3D
		if node == null or node == self or node is Marker3D or node is Area3D:
			continue
		var low := String(node.name).to_lower()
		if SKIP_NAMES.any(func(s: String) -> bool: return low.begins_with(s)):
			continue
		if is_tile and GROUP_NAMES.has(low):
			_collect_from(node, false)
			continue
		var kind := "prop"
		if node is Light3D or ["light", "lantern", "lamp", "candle", "torch"].any(func(s: String) -> bool: return low.contains(s)):
			kind = "light"
		elif ["wall", "fence", "gate", "door"].any(func(s: String) -> bool: return low.contains(s)):
			kind = "wall"
		elif holder.name == "Buildings" or ["house", "manor", "church", "tower", "building", "cottage", "chapel", "fountain"].any(func(s: String) -> bool: return low.contains(s)):
			kind = "house"
		_add_victim(node, kind)


func _add_victim(node: Node3D, kind: String) -> void:
	if node == null or not node.is_inside_tree():
		return
	var p := to_local(node.global_position)
	var margin: float = {"house": 2.0, "wall": 1.0, "enemy": 0.8}.get(kind, 0.3)
	if p.z > -1.0 and p.z < flow_length + 1.0 and absf(p.x) < _width_at(p.z) * 0.5 + margin:
		_victims.append({"node": node, "z": p.z - (2.0 if kind == "house" else 0.0), "kind": kind})


func _hit(victim: Dictionary) -> void:
	var node := victim.node as Node3D
	if not is_instance_valid(node):
		return
	var flow := global_basis.z.normalized()
	var across := global_basis.x.normalized()
	match victim.kind:
		"house":   # breaks apart, tilts, sinks and gets buried
			_wreck_house(node)
		"wall":    # falls over in the direction of the flow
			var axis := node.global_basis.x.normalized()   # walls and fences are built along their X axis
			var push := axis.cross(Vector3.UP).dot(flow)
			if absf(push) < 0.3:
				_topple(node, across, deg_to_rad(12), 0.5, Vector3.ZERO, 0.6)
			else:
				_topple(node, axis * signf(push), deg_to_rad(randf_range(70, 85)), 0.3, flow * 0.5, 0.6)
		"enemy":
			_kill_enemy(node)
		"light":
			var lights := node.find_children("*", "Light3D", true, false)
			if node is Light3D:
				lights.append(node)
			for light in lights:
				create_tween().tween_property(light, "light_energy", 0.0, 0.4)
			if node is StaticBody3D:   # lamp post
				_topple(node, across, deg_to_rad(75), 0.3, flow * 0.5, 0.7)
		_:         # crates, barrels, carts... are swept away
			_topple(node, Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() + across,
					randf_range(1.0, 2.5), 1.2, flow * randf_range(3, 6), 0.9)


# ---- enemies ----

# Knocked over, pushed along and buried in the mud, then gone for good (same as the knife: die())
func _kill_enemy(enemy: Node3D) -> void:
	if enemy == null or _killed.has(enemy) or not is_instance_valid(enemy):
		return
	_killed[enemy] = true
	enemy.remove_from_group("enemy")   # dead right away: no more tension music, not stabbable
	_topple(enemy, global_basis.x, deg_to_rad(80), 1.2, global_basis.z.normalized() * 2.0, 0.6)
	get_tree().create_timer(0.9).timeout.connect(func() -> void:
		if not is_instance_valid(enemy):
			return
		if enemy.has_method("die"):
			enemy.call("die")
		else:
			enemy.queue_free())


# ---- houses ----

# The houses are built out of kit pieces (walls, windows, roof...). The mud knocks the walls on the
# uphill side into the house, the roof caves in or slides off, the chimney falls, the other walls get
# crooked. The whole house tilts and sinks, and a mound of mud piles up around it.
func _wreck_house(house: Node3D) -> void:
	var flow := global_basis.z.normalized()
	var across := global_basis.x.normalized()
	var pieces: Array[Node3D] = []
	_find_pieces(house, pieces)
	var boxes: Array[AABB] = []
	var bounds := AABB()
	for i in range(pieces.size() - 1, -1, -1):
		var box := _global_aabb(pieces[i])
		if box.size == Vector3.ZERO:
			pieces.remove_at(i)
			continue
		boxes.push_front(box)
		bounds = box if bounds.size == Vector3.ZERO else bounds.merge(box)
	if pieces.is_empty():
		_topple(house, across, deg_to_rad(randf_range(6, 12)), randf_range(0.7, 1.1), flow * 0.4, 1.0)
		return

	var center := bounds.get_center()
	var base := bounds.position.y
	var height := maxf(bounds.size.y, 0.1)
	var depth := maxf(absf(bounds.size.dot(flow)), 0.1)   # walls and flow are both along the world axes
	for i in pieces.size():
		var piece := pieces[i]
		var c := boxes[i].get_center()
		var up := (c.y - base) / height                     # 0 = ground, 1 = top of the roof
		var side := (c - center).dot(flow) / (depth * 0.5)  # -1 = side the mud comes from
		var foot := Vector3(c.x, base, c.z)                 # turn walls around the ground below them
		if String(piece.name).to_lower().contains("chimney"):
			_break_piece(piece, across.rotated(Vector3.UP, randf_range(-0.6, 0.6)), randf_range(1.2, 1.5),
					foot, flow * 0.8 + Vector3.DOWN * 0.8, 0.7, randf_range(0.05, 0.2))
		elif up > 0.6:   # roof
			if randf() < 0.35:   # slides off
				_break_piece(piece, across, randf_range(0.5, 1.1), c, flow * randf_range(2.0, 4.0)
						+ Vector3.DOWN * (c.y - base) * 0.8, 0.8, randf_range(0.15, 0.4))
			else:                # caves in
				_break_piece(piece, _random_flat(), randf_range(0.15, 0.4), c, Vector3.DOWN * randf_range(0.6, 1.4)
						+ flow * randf_range(0.2, 0.8), 0.6, randf_range(0.15, 0.35))
		elif side < -0.45:  # the walls the mud hits first fall into the house
			_break_piece(piece, across, randf_range(1.15, 1.45), foot, Vector3.DOWN * 0.3, 0.5, randf_range(0.0, 0.12))
		else:               # the rest gets crooked
			_break_piece(piece, _random_flat(), randf_range(0.05, 0.18), foot, Vector3.DOWN * 0.1, 0.5, randf_range(0.0, 0.3))
	_topple(house, across, deg_to_rad(randf_range(6, 12)), randf_range(0.7, 1.1), flow * 0.4, 1.0)
	_mud_mound(bounds, flow, across)
	_dust_burst(Vector3(center.x, base + 1.0, center.z) - flow * depth * 0.5)
	_collapse_sound(center)
	# enemies right next to the house end up under the mound
	var buried := bounds.grow(1.0)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		var p := (enemy as Node3D).global_position
		if p.x > buried.position.x and p.x < buried.end.x and p.z > buried.position.z and p.z < buried.end.z:
			_kill_enemy(enemy as Node3D)


# Kit pieces of a house (glTF instances or meshes), also inside groups like "Model"
func _find_pieces(node: Node, out: Array[Node3D]) -> void:
	for child in node.get_children():
		if not (child is Node3D) or child is CollisionShape3D or child is Light3D or child is Area3D:
			continue
		var path := child.scene_file_path.to_lower()
		if child is MeshInstance3D or path.ends_with(".gltf") or path.ends_with(".glb") or path.ends_with(".fbx") or path.ends_with(".obj"):
			out.append(child)
		else:
			_find_pieces(child, out)


func _global_aabb(piece: Node3D) -> AABB:
	var meshes := piece.find_children("*", "MeshInstance3D", true, false)
	if piece is MeshInstance3D:
		meshes.append(piece)
	var box := AABB()
	for node in meshes:
		var m := node as MeshInstance3D
		if m.mesh == null:
			continue
		var b: AABB = m.global_transform * m.mesh.get_aabb()
		box = b if box.size == Vector3.ZERO else box.merge(b)
	return box


# Turns a piece around a horizontal axis through `pivot` and moves it (all in world space, but
# animated in its parent's space, so it adds up with the tilting of the whole house)
func _break_piece(piece: Node3D, axis: Vector3, angle: float, pivot: Vector3, move: Vector3, duration: float, delay: float) -> void:
	var parent := piece.get_parent() as Node3D
	if parent == null:
		return
	var to_parent := parent.global_transform.affine_inverse()
	var local_axis := (to_parent.basis * axis).normalized()
	var local_pivot := to_parent * pivot
	var local_move := to_parent.basis * move
	var start := piece.transform
	var step := func(k: float) -> void:
		if is_instance_valid(piece):
			var turn := Basis(local_axis, angle * k)
			piece.transform = Transform3D(turn, local_pivot - turn * local_pivot + local_move * k) * start
	create_tween().tween_method(step, 0.0, 1.0, duration).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _random_flat() -> Vector3:
	var a := randf_range(0, TAU)
	return Vector3(cos(a), 0, sin(a))


# Mud piles up around the house, higher on the side it came from
func _mud_mound(bounds: AABB, flow: Vector3, across: Vector3) -> void:
	var mound := ROCK_SCENE.instantiate() as MeshInstance3D
	_mounds += 1
	mound.set("rock_seed", 500 + _mounds)
	mound.set("roughness", 0.15)
	add_child(mound)
	mound.material_override = _mud_material
	mound.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var depth := absf(bounds.size.dot(flow))
	var width := absf(bounds.size.dot(across))
	var c := to_local(bounds.get_center())
	mound.position = Vector3(c.x, 0.0, c.z - depth * 0.15)
	mound.rotation.y = PI * randi_range(0, 1)
	var height := randf_range(1.6, 2.3)
	var size := Vector3(width * 0.5 + 1.0, height / 1.22, depth * 0.5 + 1.2)   # (the rock mesh is about 1 m in radius, 1.22 high)
	mound.scale = Vector3(size.x * 0.6, 0.05, size.z * 0.6)
	create_tween().tween_property(mound, "scale", size, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _dust_burst(where: Vector3) -> void:
	var dust := _particles(Color(0.42, 0.36, 0.3, 0.6), 1.4, 1.6)
	dust.one_shot = true
	dust.explosiveness = 0.8
	dust.amount = 24
	dust.direction = Vector3.UP
	dust.spread = 70.0
	dust.initial_velocity_min = 2.0
	dust.initial_velocity_max = 4.5
	add_child(dust)
	dust.global_position = where
	dust.emitting = true
	get_tree().create_timer(2.5).timeout.connect(dust.queue_free)


# ---- sounds ----

# Plays a sound once (or looping) that keeps playing while the game is paused; frees itself when done
func _sound(stream: AudioStream, volume_db: float, loop := false) -> AudioStreamPlayer:
	if stream == null:
		return null
	if loop and "loop" in stream:
		stream.set("loop", true)   # mp3 / ogg
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	player.play()
	if not loop:
		player.finished.connect(player.queue_free)
	return player


# Every house makes a crash where it stands; a new one starts at most every 0.35 s and never more
# than three at once, with a slightly different pitch each time
func _collapse_sound(where: Vector3) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if collapse_sound == null or now - _last_collapse < 0.35 or _collapses_playing >= 3:
		return
	_last_collapse = now
	_collapses_playing += 1
	var player := AudioStreamPlayer3D.new()
	player.stream = collapse_sound
	player.volume_db = collapse_volume_db
	player.unit_size = 25.0   # the camera is 17-30 m above the town
	player.pitch_scale = randf_range(0.85, 1.15)
	add_child(player)
	player.global_position = where
	player.play()
	player.finished.connect(func() -> void:
		_collapses_playing -= 1
		player.queue_free())


func _duck_music(down: bool, duration: float) -> void:
	if down:
		_music_bus = AudioServer.get_bus_index("Music")
		if _music_bus < 0:
			return
		_music_db = AudioServer.get_bus_volume_db(_music_bus)
	if _music_bus < 0:
		return
	var from := AudioServer.get_bus_volume_db(_music_bus)
	var to := _music_db + music_duck_db if down else _music_db
	create_tween().tween_method(func(db: float) -> void: AudioServer.set_bus_volume_db(_music_bus, db), from, to, duration)


func _exit_tree() -> void:
	# never leave the music quiet (e.g. if the scene changes in the middle of the finale)
	if _music_bus >= 0:
		AudioServer.set_bus_volume_db(_music_bus, _music_db)
	# the next level starts normal again
	if _playing:
		GameManager.player_invincible = false


# Turns the node around a horizontal axis through its foot, sinks and pushes it, all at once
func _topple(node: Node3D, axis: Vector3, angle: float, sink: float, push: Vector3, duration: float) -> void:
	var start := node.global_transform
	axis = axis.normalized()
	var step := func(k: float) -> void:
		if is_instance_valid(node):
			node.global_transform = Transform3D(Basis(axis, angle * k) * start.basis,
					start.origin + push * k + Vector3.DOWN * sink * k)
	create_tween().tween_method(step, 0.0, 1.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


# ---------------------------------------------------------------- helpers

func _move_camera(goal: Vector3, dt: float, speed: float) -> void:
	if is_instance_valid(_camera):
		_camera.global_position = _camera.global_position.lerp(goal, 1.0 - exp(-speed * dt))


func _shake(strength: float, duration: float) -> void:
	if is_instance_valid(_camera) and _camera.has_method("shake"):
		_camera.shake(strength, duration)


func _wait(seconds: float) -> Signal:
	return get_tree().create_timer(seconds).timeout   # timers keep running while paused


func _glow_sphere(color: Color, radius: float) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.material = material
	var node := MeshInstance3D.new()
	node.mesh = sphere
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _particles(color: Color, size: float, lifetime: float) -> CPUParticles3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	quad.material = material
	var p := CPUParticles3D.new()
	p.mesh = quad
	p.lifetime = lifetime
	p.gravity = Vector3(0, -1.0, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = ramp
	return p
