class_name Watchtower
extends Enemy

@export var rotation_interval := 5.0  # Time spent looking in one direction
@export var rotation_angle_step := 90.0 # Degrees to rotate each interval

var watch_timer := 0.0
var target_yaw := 0.0

func _ready() -> void:
	super._ready()
	# Disable components or movement agents that watchtowers don't need
	if agent:
		agent.queue_free()

func _physics_process(delta: float) -> void:
	# Watchtowers don't walk, use gravity, or follow patrol points, 
	# but they DO need to check if they spot the player.
	_update_chase_state(delta)
	_update_view_cone(delta)

	# Watching a coin: narrow view until the time is up
	if distracted:
		distract_wait_timer -= delta
		if distract_wait_timer <= 0.0:
			distracted = false

	# Handle looking into different directions every 5 seconds
	watch_timer += delta
	if watch_timer >= rotation_interval:
		watch_timer = 0.0
		target_yaw += deg_to_rad(rotation_angle_step)

	# Smoothly rotate towards the target view direction
	var current_rot = rotation.y
	rotation.y = lerp_angle(current_rot, target_yaw, delta * 3.0)

# Heard a noise: turn towards it and keep looking there for investigate_time
func hear_noise(source: Vector3) -> void:
	var to_noise := source - global_position
	target_yaw = atan2(-to_noise.x, -to_noise.z)
	watch_timer = rotation_interval - investigate_time

# A coin landed nearby: look at it for distract_wait_time (away from the player, hopefully)
func distract(target: Vector3) -> void:
	var to_coin := target - global_position
	target_yaw = atan2(-to_coin.x, -to_coin.z)
	watch_timer = rotation_interval - distract_wait_time
	distracted = true
	distract_wait_timer = distract_wait_time

# Override what happens when the player is spotted
func _update_chase_state(delta: float) -> void:
	if player == null:
		return

	var to_player := player.global_position - global_position
	var distance := to_player.length()
	to_player.y = 0
	var forward := -global_transform.basis.z
	var in_view := forward.angle_to(to_player) < deg_to_rad(_current_view_angle())

	# If the watchtower sees the player, alert everyone instead of chasing
	if distance < detect_range and in_view and _can_see_player():
		_alert_nearby_guards()

func _alert_nearby_guards() -> void:
	print("Watchtower spotted the player! Alerting guards...")
	# Find all enemies in a radius or group and force them to chase
	for node in get_tree().get_nodes_in_group("enemy"):
		if node is Enemy and not node is Watchtower:
			node.ordered_to_chase(player)
