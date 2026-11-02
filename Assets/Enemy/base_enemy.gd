class_name Enemy
extends CharacterBody3D

@export var patrol_points: Array[Node3D] = []
@export var patrol_speed := 2.0
@export var chase_speed := 4.5
@export var detect_range := 8.0
@export var lose_range := 12.0
@export var max_chase_time := 7.0
@export var give_up_cooldown := 3.0
@export var view_angle := 35.0
@export var catch_distance := 1.2
@export var eye_height := 0.5

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

	# Aggregate components dynamically from children nodes
	paranoid_component = get_node_or_null("ParanoidComponent")
	dog_component = get_node_or_null("GuardDogComponent")

	_setup_model()

func _physics_process(delta: float) -> void:
	if attacking:
		_attack_tick(delta)
	_move(delta)  # Keeps chasing during the wind-up: the enemy lunges after the player
	_check_player_contact()
	_update_animation()


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
	elif agent.is_navigation_finished() and not patrol_points.is_empty():
		patrol_index = (patrol_index + 1) % patrol_points.size()
		agent.target_position = patrol_points[patrol_index].global_position

	# Delegate behavior modifications to components if they exist

	if agent.is_navigation_finished() or speed == 0.0:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
	else:
		var direction := agent.get_next_path_position() - global_position
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
		if distance < detect_range and in_view and _can_see_player():
			spotted = true

		# Delegate detection rules if the Guard Dog component is attached
		var hearing_scale := distracted_hearing_scale if distracted else 1.0
		if dog_component and dog_component.check_hearing(player, distance, hearing_scale):
			if _can_see_player():
				spotted = true

		if spotted:
			start_chase()

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


# The spotlight smoothly follows the current field of view
func _update_view_cone(delta: float) -> void:
	vision_light.spot_angle = lerpf(vision_light.spot_angle, _current_view_angle(), minf(delta * 5.0, 1.0))


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


func _stop_chase() -> void:
	chasing = false
	is_alerted_from_afar = false
	material.albedo_color = patrol_color
	vision_light.light_color = patrol_color
	MusicManager.update_chase_state(false)
	_return_to_patrol()


func _return_to_patrol() -> void:
	if patrol_points.is_empty():
		return
	var closest_index := 0
	var closest_distance := INF
	for i in patrol_points.size():
		var d := global_position.distance_to(patrol_points[i].global_position)
		if d < closest_distance:
			closest_distance = d
			closest_index = i
	patrol_index = closest_index
	agent.target_position = patrol_points[patrol_index].global_position
	
func ordered_to_chase(player: Player) -> void:
	is_alerted_from_afar = true
	player = player
	start_chase()
	
func start_chase() -> void:
	chase_timer = 0.0
	investigate_timer = 0.0
	distracted = false
	if chasing:
		return  # Already chasing (e.g. the watchtower keeps alerting us): just keep going
	chasing = true
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
	else:
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
