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

# References to optional aggregated components found in children
var paranoid_component: Node = null
var dog_component: Node = null

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

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	_update_chase_state(delta)

	var speed := chase_speed if chasing else patrol_speed

	if chasing:
		# Once the player hides, keep heading to the last known position instead
		if not player.is_hidden:
			agent.target_position = player.global_position
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

		if paranoid_component and not chasing:
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
	var in_view := forward.angle_to(to_player) < deg_to_rad(view_angle)

	if chasing:
		chase_timer += delta
		if player.is_hidden:
			# Lost the player: search the last known position, then give up
			if agent.is_navigation_finished():
				_stop_chase()
				cooldown_timer = give_up_cooldown
		elif distance < catch_distance:
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
		if dog_component and dog_component.check_hearing(player, distance):
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
	chasing = true
	chase_timer = 0.0
	material.albedo_color = chase_color
	vision_light.light_color = chase_color
	MusicManager.update_chase_state(true)
	
func die() -> void:
	MusicManager.update_chase_state(false)
	queue_free()
