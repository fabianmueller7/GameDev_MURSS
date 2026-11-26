class_name Enemy
extends CharacterBody3D

@export var patrol_points: Array[Node3D] = []
@export var patrol_speed := 2.0
@export var chase_speed := 4.5
@export var detect_range := 7.0
@export var lose_range := 12.0
@export var max_chase_time := 7.0
@export var give_up_cooldown := 3.0
@export var view_angle := 35.0
@export var catch_distance := 1.4
@export var eye_height := 0.5

# Path following: keep away from corners without changing the navmesh agent radius
@export var nav_agent_radius := 0.5   # Must match agent_radius of the NavigationMesh
@export var corner_clearance := 0.2   # Extra distance kept from corners, on top of the radius difference
@export var waypoint_slack := 0.15    # A path point counts as reached this close (measured on the ground)
@export var stuck_time := 0.8         # Seconds barely moving before a patrolling enemy skips its waypoint

# Suspicion: seeing the player fills a "?" above the enemy; when it is full ("!") the chase starts
@export var detect_time := 0.9               # Seconds of seeing the player at the edge of the view before the chase
@export var close_detect_boost := 1.5        # Up to (1 + this) times faster when the player is close
@export var instant_detect_distance := 2.0   # Closer than this: spotted right away
@export var sneak_detect_scale := 0.6        # Sneaking players fill the "?" this much slower
@export var suspicion_fade_time := 2.0       # Seconds for a full "?" to empty again when the player is gone
@export var look_at_suspicion := 0.4         # From this suspicion on the enemy stops and looks at the player
@export var indicator_height := 1.8          # Height of the "?" / "!" above the enemy's origin

@export var patrol_color := Color(0.8, 0.15, 0.15)
@export var chase_color := Color(1.0, 0.5, 0.0)

# Reaction to noise (the player using an item nearby)
@export var investigate_time := 3.0        # Seconds standing still and looking at the noise
@export var investigate_turn_speed := 6.0
@export var investigate_color := Color(1.0, 0.85, 0.2)

# Reaction to a thrown coin: walk there, wait, then go back to the patrol route
@export var distract_speed := 3.0
@export var distract_wait_time := 5.0
@export var distracted_view_angle := 15.0  # Narrower view while focused on the coin
@export var distract_stop_distance := 1.5  # Stops this far from the coin (leaves room for other enemies)
@export var distracted_hearing_scale := 0.5  # Guard dogs hear only half as far while distracted (0 = deaf)

# 3D model with animations (Idle, Walk, Chase + an attack). Leave empty to keep the old capsule.
@export var model_scene: PackedScene
@export var model_offset := Vector3(0, -1.0, 0)  # Moves the model so its feet stand on the ground
@export var model_scale := 1.0
@export var attack_animation := "Stab"           # The guard dog uses "Attack"
@export var attack_hit_time := 0.4               # Seconds into the attack animation when the hit lands
# The enemy keeps chasing while it winds up, so walking away is not enough; only sprinting gets out of reach
@export var attack_hit_range := 1.6              # The player must still be this close when the hit lands

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var vision_light: SpotLight3D = $SpotLight3D

var patrol_positions: Array[Vector3] = []   # filled by the spawner

var player: Player
var patrol_index := -1
var chasing := false
var chase_timer := 0.0
var cooldown_timer := 0.0
var material := StandardMaterial3D.new()
var is_alerted_from_afar: bool
var investigate_timer := 0.0
var noise_position: Vector3
var distracted := false
var distract_wait_timer := 0.0
var distract_target: Vector3
var distract_arrived := false
var distract_stuck_timer := 0.0
var suspicion := 0.0                 # 0 = calm, 1 = spotted
var indicator: Label3D

# How much fatter the enemy is than the navmesh assumes, and how long it has been stuck
var radius_gap := 0.0
var stuck_timer := 0.0
var path_point := 0              # Index of the path point we are walking to (see _steer_point)

# References to optional aggregated components found in children
var paranoid_component: Node = null
var dog_component: Node = null

# Model / animation state
var model: Node3D
var anim: AnimationPlayer
var attacking := false
var attack_timer := 0.0
var attack_length := 0.0
var attack_hit_done := false
var touching_player := false     # Bumped into the player during the last physics frame
var observed_contact := 0.0      # Measured distance at which our bodies actually touch

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player") as Player
	material.albedo_color = patrol_color
	mesh.material_override = material

	vision_light.spot_range = detect_range
	vision_light.spot_angle = view_angle
	vision_light.light_color = patrol_color

	# The navmesh keeps paths nav_agent_radius away from walls. If the capsule is wider,
	# the difference is added to every corner, so the body still clears the wall.
	radius_gap = maxf(_body_radius(self) - nav_agent_radius, 0.0)
	# We step through the path ourselves (see _steer_point), the agent's own index is not used
	agent.path_changed.connect(func() -> void: path_point = 0)
	# Targets close to a wall (waypoints, coins) can be up to radius_gap out of the capsule's reach
	agent.target_desired_distance = maxf(agent.target_desired_distance, radius_gap + 0.25)

	# Aggregate components dynamically from children nodes
	paranoid_component = get_node_or_null("ParanoidComponent")
	dog_component = get_node_or_null("GuardDogComponent")

	_setup_model()
	_setup_indicator()

func _physics_process(delta: float) -> void:
	if attacking:
		_attack_tick(delta)
	_move(delta)  # Keeps chasing during the wind-up: the enemy lunges after the player
	_check_player_contact()
	_update_animation()
	_update_indicator()


func _move(delta: float) -> void:
	_update_view_cone(delta)
	if not is_on_floor():
		velocity += get_gravity() * delta

	_update_chase_state(delta)

	# Heard a noise: stand still and look towards it (detection keeps running meanwhile)
	if investigate_timer > 0.0 and not chasing:
		_investigate(delta)
		move_and_slide()
		return

	# Arrived at the coin: stand still and watch it until the wait time is over
	if distracted and distract_arrived and not chasing:
		_watch_coin(delta)
		move_and_slide()
		return

	var speed := chase_speed if chasing else (distract_speed if distracted else patrol_speed)

	if chasing:
		# Once the player hides, keep heading to the last known position instead
		if not player.is_hidden:
			agent.target_position = player.global_position
	elif distracted:
		_check_distraction_arrival(delta)
	elif agent.is_navigation_finished() and _patrol_count() > 0:
		patrol_index = (patrol_index + 1) % _patrol_count()
		agent.target_position = _patrol_pos(patrol_index)

	# Delegate behavior modifications to components if they exist

	if agent.is_navigation_finished() or speed == 0.0:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
	else:
		var direction := _steer_point() - global_position
		direction.y = 0
		direction = direction.normalized()
		
		velocity.x = move_toward(velocity.x, direction.x * speed, speed * delta * 8.0)
		velocity.z = move_toward(velocity.z, direction.z * speed, speed * delta * 8.0)

		if paranoid_component and not chasing and not distracted:
			var is_looking_back = paranoid_component.process_behavior(self, delta)
			if is_looking_back:
				direction = -direction

		if direction.length() > 0.01:
			look_at(global_position + direction, Vector3.UP)

	move_and_slide()
	_check_stuck(delta, speed)


# Wants to walk but hardly moves (e.g. a gap the navmesh allows but the capsule doesn't fit
# through): a patrolling enemy gives up on this waypoint and walks to the next one.
# Chasing ends on its own through max_chase_time, coins through distract_stuck_timer.
func _check_stuck(delta: float, speed: float) -> void:
	var real := get_real_velocity()
	real.y = 0
	var trying := speed > 0.0 and not agent.is_navigation_finished()
	stuck_timer = stuck_timer + delta if trying and real.length() < speed * 0.25 else 0.0
	if stuck_timer > stuck_time:
		stuck_timer = 0.0
		if not chasing and not distracted and _patrol_count() > 1:
			patrol_index = (patrol_index + 1) % _patrol_count()
			agent.target_position = _patrol_pos(patrol_index)


# The point the enemy actually walks to: the next point of the path, but at a corner pushed away
# from the wall the path bends around.
# We step through the path ourselves instead of using the agent's path index: the agent compares
# 3D distances, and since our origin sits in the middle of the body while the navmesh floats at a
# varying height above the floor, a small path_desired_distance would often never be reached.
# Here only the distance on the ground counts.
func _steer_point() -> Vector3:
	agent.get_next_path_position()  # Must be called every frame: keeps the agent's path up to date
	var path := agent.get_current_navigation_path()
	if path.is_empty():
		return global_position
	path_point = clampi(path_point, 0, path.size() - 1)
	var target := _path_target(path, path_point)
	while path_point < path.size() - 1 and _flat_distance_to(target) < waypoint_slack:
		path_point += 1
		target = _path_target(path, path_point)
	return target


func _path_target(path: PackedVector3Array, i: int) -> Vector3:
	if i <= 0 or i >= path.size() - 1:
		return path[i]  # Start or final target: nothing to round
	return _offset_corner(path[i - 1], path[i], path[i + 1])


func _flat_distance_to(point: Vector3) -> float:
	var d := point - global_position
	d.y = 0
	return d.length()


func _offset_corner(prev: Vector3, corner: Vector3, next: Vector3) -> Vector3:
	var to_prev := prev - corner
	var to_next := next - corner
	to_prev.y = 0
	to_next.y = 0
	if to_prev.length() < 0.01 or to_next.length() < 0.01:
		return corner
	# The two directions add up to a vector pointing into the obstacle the path wraps around
	var inward := to_prev.normalized() + to_next.normalized()
	if inward.length() < 0.1:
		return corner  # Nearly straight: no real corner here
	var pushed := corner - inward.normalized() * _corner_offset()
	# In narrow corridors the push could leave the navmesh: clamp it back onto it
	return NavigationServer3D.map_get_closest_point(agent.get_navigation_map(), pushed)


func _corner_offset() -> float:
	return radius_gap + corner_clearance


func _update_chase_state(delta: float) -> void:
	if player == null:
		return
	cooldown_timer = max(cooldown_timer - delta, 0.0)

	var to_player := player.global_position - global_position
	var distance := to_player.length()
	to_player.y = 0
	var forward := -global_transform.basis.z
	var in_view := forward.angle_to(to_player) < deg_to_rad(_current_view_angle())

	if chasing:
		chase_timer += delta
		if player.is_hidden:
			# Lost the player: search the last known position, then give up
			if agent.is_navigation_finished():
				_stop_chase()
				cooldown_timer = give_up_cooldown
		elif touching_player or _flat_distance_to_player() < _effective_catch_distance():
			if attacking:
				pass  # Already swinging
			elif anim and anim.has_animation(attack_animation):
				_start_attack()
			else:
				print("caught player")
				GameManager.trigger_death()
				_stop_chase()
		elif chase_timer >= max_chase_time:
			_stop_chase()
			cooldown_timer = give_up_cooldown
		elif distance > lose_range and !is_alerted_from_afar:
			_stop_chase()
	elif cooldown_timer <= 0.0:
		var spotted := false

		# Standard sight check
		if distance < _current_detect_range() and in_view and _can_see_player():
			spotted = true

		# Delegate detection rules if the Guard Dog component is attached
		var hearing_scale := distracted_hearing_scale if distracted else 1.0
		if dog_component and dog_component.check_hearing(player, distance, hearing_scale):
			if _can_see_player():
				spotted = true

		if _add_suspicion(spotted, distance, delta):
			start_chase()
	else:
		_add_suspicion(false, distance, delta)   # just gave up: the "?" empties


# Fills the "?" while the player is seen (faster when close, slower when sneaking) and empties it
# otherwise. Returns true once the enemy is sure: time to chase (or ring the alarm).
func _add_suspicion(sees: bool, distance: float, delta: float) -> bool:
	if sees:
		if distance < instant_detect_distance:
			suspicion = 1.0
		else:
			var closeness := 1.0 - clampf(distance / maxf(_current_detect_range(), 0.1), 0.0, 1.0)
			var rate := (1.0 + close_detect_boost * closeness) / maxf(detect_time, 0.01)
			if player.is_crouching:
				rate *= sneak_detect_scale
			suspicion = minf(suspicion + rate * delta, 1.0)
		# Something moved over there: stop and have a closer look
		if suspicion >= look_at_suspicion and suspicion < 1.0 and investigate_timer <= 0.0:
			hear_noise(player.global_position)
	else:
		suspicion = maxf(suspicion - delta / maxf(suspicion_fade_time, 0.01), 0.0)
	return suspicion >= 1.0


# ---------------- "?" / "!" above the enemy ----------------

func _setup_indicator() -> void:
	indicator = Label3D.new()
	indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	indicator.no_depth_test = true   # visible above roofs too
	indicator.font_size = 96
	indicator.pixel_size = 0.006
	indicator.outline_size = 18
	indicator.outline_modulate = Color(0, 0, 0, 0.85)
	indicator.position = Vector3(0, indicator_height, 0)
	indicator.visible = false
	add_child(indicator)


# Chasing (or ringing the alarm for watchtowers)
func _is_alarmed() -> bool:
	return chasing


func _update_indicator() -> void:
	if indicator == null:
		return
	if _is_alarmed():
		indicator.visible = true
		indicator.text = "!"
		indicator.modulate = Color(1.0, 0.35, 0.15)
		indicator.scale = Vector3.ONE * 1.2
	elif suspicion > 0.02:
		indicator.visible = true
		indicator.text = "?"
		indicator.modulate = Color(1.0, 0.85, 0.25, lerpf(0.35, 1.0, suspicion))
		indicator.scale = Vector3.ONE * lerpf(0.6, 1.1, suspicion)
	else:
		indicator.visible = false

func _can_see_player() -> bool:
	if player.is_hidden:
		return false
	var from := global_position + Vector3.UP * eye_height
	var to := player.global_position + Vector3.UP * eye_height
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	return not result.is_empty() and result.collider == player


# Called by the player when using an item nearby
func hear_noise(source: Vector3) -> void:
	if chasing:
		return
	investigate_timer = investigate_time
	noise_position = source
	material.albedo_color = investigate_color
	vision_light.light_color = investigate_color


func _investigate(delta: float) -> void:
	investigate_timer -= delta
	velocity.x = move_toward(velocity.x, 0, patrol_speed)
	velocity.z = move_toward(velocity.z, 0, patrol_speed)

	var to_noise := noise_position - global_position
	to_noise.y = 0
	if to_noise.length() > 0.01:
		# Forward is -Z (same as look_at)
		var target_yaw := atan2(-to_noise.x, -to_noise.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(delta * investigate_turn_speed, 1.0))

	if investigate_timer <= 0.0:
		# Nothing found: back to the normal patrol (or keep checking out the coin)
		var color := investigate_color if distracted else patrol_color
		material.albedo_color = color
		vision_light.light_color = color


# Focused on a coin: narrower field of view until the distraction is over
func _current_view_angle() -> float:
	return distracted_view_angle if distracted else view_angle


# Paranoid guards see less far while looking back over their shoulder. The look-back only
# happens on the normal patrol, so it doesn't count while chasing, distracted or investigating.
func _current_detect_range() -> float:
	if paranoid_component and not chasing and not distracted and investigate_timer <= 0.0:
		return detect_range * paranoid_component.detect_range_scale()
	return detect_range


# The spotlight smoothly follows the current field of view and range
func _update_view_cone(delta: float) -> void:
	var t := minf(delta * 5.0, 1.0)
	vision_light.spot_angle = lerpf(vision_light.spot_angle, _current_view_angle(), t)
	vision_light.spot_range = lerpf(vision_light.spot_range, _current_detect_range(), t)


# Called by a thrown coin that landed nearby
func distract(target: Vector3) -> void:
	if chasing:
		return
	distracted = true
	distract_arrived = false
	distract_stuck_timer = 0.0
	distract_wait_timer = distract_wait_time
	distract_target = target
	investigate_timer = 0.0  # Go there right away
	agent.target_position = target
	material.albedo_color = investigate_color
	vision_light.light_color = investigate_color


# Arrived when close enough (horizontally, the coin lies on the ground), when the navigation
# says so, or when stuck (e.g. another enemy is already standing at the coin)
func _check_distraction_arrival(delta: float) -> void:
	var to_coin := distract_target - global_position
	to_coin.y = 0
	var moving := Vector2(velocity.x, velocity.z).length() > 0.3
	distract_stuck_timer = 0.0 if moving else distract_stuck_timer + delta

	if to_coin.length() <= distract_stop_distance or agent.is_navigation_finished() or distract_stuck_timer > 0.75:
		distract_arrived = true


func _watch_coin(delta: float) -> void:
	velocity.x = 0
	velocity.z = 0
	var to_coin := distract_target - global_position
	to_coin.y = 0
	if to_coin.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-to_coin.x, -to_coin.z), minf(delta * investigate_turn_speed, 1.0))

	distract_wait_timer -= delta
	if distract_wait_timer <= 0.0:
		_end_distraction()


func _end_distraction() -> void:
	distracted = false
	distract_arrived = false
	material.albedo_color = patrol_color
	vision_light.light_color = patrol_color
	_return_to_patrol()


# The player respawned at the start (pause menu "Respawn"): stop chasing and leave them alone for a moment
func on_player_respawned() -> void:
	attacking = false
	stuck_timer = 0.0
	if chasing:
		_stop_chase()
	suspicion = 0.0
	cooldown_timer = give_up_cooldown


func _stop_chase() -> void:
	chasing = false
	suspicion = 0.0
	is_alerted_from_afar = false
	material.albedo_color = patrol_color
	vision_light.light_color = patrol_color
	MusicManager.update_chase_state(false)
	_return_to_patrol()


func _return_to_patrol() -> void:
	if _patrol_count() == 0:
		return
	var closest_index := 0
	var closest_distance := INF
	for i in _patrol_count():
		var d := global_position.distance_to(_patrol_pos(i))
		if d < closest_distance:
			closest_distance = d
			closest_index = i
	patrol_index = closest_index
	agent.target_position = _patrol_pos(patrol_index)
	
func ordered_to_chase(player: Player) -> void:
	is_alerted_from_afar = true
	player = player
	start_chase()
	
func start_chase() -> void:
	chase_timer = 0.0
	investigate_timer = 0.0
	distracted = false
	suspicion = 1.0
	if chasing:
		return  # Already chasing (e.g. the watchtower keeps alerting us): just keep going
	chasing = true
	GameManager.player_spotted.emit()
	material.albedo_color = chase_color
	vision_light.light_color = chase_color
	MusicManager.update_chase_state(true)
	
# ---------------- Model and animations ----------------

func _setup_model() -> void:
	if model_scene == null:
		return
	model = model_scene.instantiate() as Node3D
	add_child(model)
	model.position = model_offset
	model.rotation.y = PI  # The models look along +Z, the enemy walks along -Z (look_at)
	model.scale = Vector3.ONE * model_scale
	mesh.visible = false  # Hide the old capsule
	anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim == null:
		push_warning("No AnimationPlayer found in the model of " + name)
		return
	for loop_name in ["Idle", "Walk", "Chase"]:
		if anim.has_animation(loop_name):
			anim.get_animation(loop_name).loop_mode = Animation.LOOP_LINEAR
	if anim.has_animation(attack_animation):
		attack_length = anim.get_animation(attack_animation).length
	elif attack_animation != "":
		push_warning("Model of %s has no animation '%s'" % [name, attack_animation])
	_play("Idle")


func _play(anim_name: String, blend := 0.2) -> void:
	if anim and anim.has_animation(anim_name) and anim.current_animation != anim_name:
		anim.play(anim_name, blend)


# Walk while patrolling or going to a coin, Chase while hunting, Idle while standing
func _update_animation() -> void:
	if anim == null or attacking:
		return
	var moving := Vector2(velocity.x, velocity.z).length() > 0.3
	if moving and chasing:
		_play("Chase")
	elif moving:
		_play("Walk")
	else:
		_play("Idle")


# Close enough: swing while still running after the player. The hit only counts if the player
# is still in reach when it lands, so walking away fails but sprinting away can work.
func _start_attack() -> void:
	attacking = true
	attack_timer = 0.0
	attack_hit_done = false
	anim.play(attack_animation, 0.1)


func _attack_tick(delta: float) -> void:
	attack_timer += delta
	if not attack_hit_done and attack_timer >= attack_hit_time:
		attack_hit_done = true
		var distance := _flat_distance_to_player()
		if chasing and not player.is_hidden and distance <= maxf(attack_hit_range, _contact_distance() + 0.15):
			print("caught player")
			GameManager.trigger_death()
			_stop_chase()
		else:
			attacking = false  # Missed: straight back into the chase animation
			return
	if attack_timer >= attack_length:
		attacking = false


# Distance on the ground only. The bodies' centres sit at different heights (a dog is much lower
# than the player), so the 3D distance would never get small enough to catch or hit.
func _flat_distance_to_player() -> float:
	var d := player.global_position - global_position
	d.y = 0
	return d.length()


# Running into the player always counts as catching them, whatever the numbers say
func _check_player_contact() -> void:
	touching_player = false
	for i in get_slide_collision_count():
		if get_slide_collision(i).get_collider() == player:
			touching_player = true
			observed_contact = maxf(observed_contact, _flat_distance_to_player())


# How close the two bodies can get before they touch (measured once they have touched)
func _contact_distance() -> float:
	return maxf(_body_radius(self) + _body_radius(player), observed_contact)


# Catch slightly before the bodies touch, even if catch_distance is set smaller than that
func _effective_catch_distance() -> float:
	return maxf(catch_distance, _contact_distance() + 0.1)


func _body_radius(body: Node) -> float:
	for child in body.get_children():
		if child is CollisionShape3D and child.shape:
			var s: Vector3 = child.scale
			var shape: Shape3D = child.shape
			if shape is CapsuleShape3D:
				return shape.radius * maxf(s.x, s.z)
			if shape is CylinderShape3D:
				return shape.radius * maxf(s.x, s.z)
			if shape is SphereShape3D:
				return shape.radius * maxf(s.x, s.z)
			if shape is BoxShape3D:
				return maxf(shape.size.x * s.x, shape.size.z * s.z) * 0.5
	return 0.5


func die() -> void:
	queue_free()


# Removed while chasing (killed, level reloaded, back to menu): the chase is over for the music
func _exit_tree() -> void:
	if chasing:
		chasing = false
		if is_instance_valid(MusicManager) and MusicManager.is_inside_tree():
			MusicManager.update_chase_state(false)
			
			
func set_patrol_waypoints(points: Array[Vector3]) -> void:
	patrol_positions = points
	patrol_index = 0
	if not patrol_positions.is_empty():
		agent.target_position = patrol_positions[0]


# Works with both spawned waypoints (Vector3) and hand-placed Node3D patrol points
func _patrol_count() -> int:
	return patrol_positions.size() if not patrol_positions.is_empty() else patrol_points.size()


func _patrol_pos(i: int) -> Vector3:
	return patrol_positions[i] if not patrol_positions.is_empty() else patrol_points[i].global_position
