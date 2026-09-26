extends CharacterBody3D

## Waypoints the enemy walks between (Marker3D nodes placed in the level).
@export var patrol_points: Array[Node3D] = []
@export var patrol_speed := 2.0
@export var chase_speed := 4.5
## Start chasing when the player is closer than this (and inside the view cone).
@export var detect_range := 8.0
## Give up the chase when the player is farther than this.
@export var lose_range := 12.0
## Half of the field-of-view angle, in degrees.
@export var view_angle := 35.0
## The player gets caught when the enemy is closer than this.
@export var catch_distance := 1.2
## Height above the node's origin that the sight ray starts from and aims at.
@export var eye_height := 0.5
## Color while patrolling.
@export var patrol_color := Color(0.8, 0.15, 0.15)
## Color while chasing the player.
@export var chase_color := Color(1.0, 0.5, 0.0)

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var vision_light: SpotLight3D = $SpotLight3D

var player: Player
var patrol_index := -1
var chasing := false
var material := StandardMaterial3D.new()


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player") as Player

	# Each enemy gets its own material, so changing one enemy's color doesn't affect the others.
	material.albedo_color = patrol_color
	mesh.material_override = material

	# Make the light cone match the actual detection area.
	vision_light.spot_range = detect_range
	vision_light.spot_angle = view_angle
	vision_light.light_color = patrol_color


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	_update_chase_state()

	var speed := chase_speed if chasing else patrol_speed

	if chasing:
		agent.target_position = player.global_position
	elif agent.is_navigation_finished() and not patrol_points.is_empty():
		# Reached the current waypoint: go to the next one.
		patrol_index = (patrol_index + 1) % patrol_points.size()
		agent.target_position = patrol_points[patrol_index].global_position

	if agent.is_navigation_finished():
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
	else:
		var direction := agent.get_next_path_position() - global_position
		direction.y = 0
		direction = direction.normalized()
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		if direction.length() > 0.01:
			look_at(global_position + direction, Vector3.UP)

	move_and_slide()


func _update_chase_state() -> void:
	if player == null:
		return
	var to_player := player.global_position - global_position
	var distance := to_player.length()
	to_player.y = 0
	var forward := -global_transform.basis.z
	var in_view := forward.angle_to(to_player) < deg_to_rad(view_angle)

	if chasing and distance < catch_distance:
		player.respawn()
		_stop_chase()
	elif not chasing and distance < detect_range and in_view and _can_see_player():
		chasing = true
		material.albedo_color = chase_color
		vision_light.light_color = chase_color
	elif chasing and distance > lose_range:
		_stop_chase()


func _can_see_player() -> bool:
	# Cast a ray from the enemy's eyes to the player. If the first thing it hits
	# is the player, nothing is in the way.
	var from := global_position + Vector3.UP * eye_height
	var to := player.global_position + Vector3.UP * eye_height
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]  # don't let the ray hit the enemy itself
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	return not result.is_empty() and result.collider == player


func _stop_chase() -> void:
	chasing = false
	material.albedo_color = patrol_color
	vision_light.light_color = patrol_color
	_return_to_patrol()


func _return_to_patrol() -> void:
	if patrol_points.is_empty():
		return
	# Find the waypoint closest to where the enemy is now.
	var closest_index := 0
	var closest_distance := INF
	for i in patrol_points.size():
		var d := global_position.distance_to(patrol_points[i].global_position)
		if d < closest_distance:
			closest_distance = d
			closest_index = i
	patrol_index = closest_index
	agent.target_position = patrol_points[patrol_index].global_position
