extends CharacterBody3D
class_name Player


const BASE_SPEED = 5.0
const WALK_SPEED = BASE_SPEED * 0.7    # Normal walking: 30% slower than before
const SPRINT_SPEED = BASE_SPEED * 1.2  # Sprinting (Shift): 20% faster than the old walking speed

# Stamina goes from 0.0 (empty) to 1.0 (full)
const MAX_SPRINT_TIME = 5.0  # Seconds of sprinting with full stamina
const STAMINA_REGEN = 0.1    # Regenerates 10% per second while not sprinting
const JUMP_VELOCITY = 4.5
const DROP_DISTANCE = 1.5
const KNIFE_RANGE = 2.0

# Sounds
@export var footstep_sounds: Array[AudioStream] = [
	preload("res://Assets/Sounds/footsteps/footstep_light_01.wav"),
	preload("res://Assets/Sounds/footsteps/footstep_light_03.wav"),
	preload("res://Assets/Sounds/footsteps/footstep_light_04.wav"),
	preload("res://Assets/Sounds/footsteps/footstep_light_05.wav"),
	preload("res://Assets/Sounds/footsteps/footstep_light_06.wav"),
]
@export var breathing_sound: AudioStream = preload("res://Assets/Sounds/heavy_breathing.wav")
@export var stab_sound: AudioStream = preload("res://Assets/Sounds/stabbing.wav")
@export var pickup_sound: AudioStream = preload("res://Assets/Sounds/collect_item.wav")
@export var pickup_volume_db := 3.0
@export var drop_sound: AudioStream = preload("res://Assets/Sounds/drop_item.wav")
@export var drop_volume_db := 3.0
@export var footstep_volume_db := 0.0
@export var breathing_volume_db := 4.0

var start_position: Vector3
var collectible_scene: PackedScene = preload("res://Assets/collectible.tscn")

# Collectibles currently in pickup range, and the direction we last walked in (for dropping)
var nearby_items: Array[Collectible] = []
# Things in range that items can be used on (door, end zone); they implement try_use_item()
var nearby_targets: Array[Node] = []
var facing := Vector3.FORWARD
# Things in range that react to the interact key (hiding barrels); they implement interact(player)
var nearby_interactables: Array[Node] = []

# Hiding state: the spot we are hiding in (null when not hiding) and where to climb out again
var hiding_spot: Node3D = null
var is_hidden := false
var exit_position: Vector3

@onready var body_mesh: Node3D = $Model
@onready var body_collision: CollisionShape3D = $CollisionShape3D
@onready var anim: AnimationPlayer = $Model/AnimationPlayer

# Bones the stab animation may move; everything else keeps doing Idle/Walk
const STAB_BONES := ["UpperArm_R", "ForeArm_R", "Hand_R"]
var anim_tree: AnimationTree
var move_blend := 0.0  # 0 = Idle, 1 = Walk
var walk_anim_speed := 1.0  # Walk animation plays faster while sprinting

var stamina := 1.0
# Set when stamina runs out; sprinting stays blocked until Shift is released
var exhausted := false
var is_sprinting := false

var footstep_player: AudioStreamPlayer
var breathing_player: AudioStreamPlayer
var stab_player: AudioStreamPlayer
var pickup_player: AudioStreamPlayer
var drop_player: AudioStreamPlayer
var stride_length := 1.5     # Distance per footstep, matched to the Walk animation in _ready()
var step_distance := 0.0     # Distance walked since the last footstep
var is_breathing := false
var breathing_tween: Tween


func _ready() -> void:
	start_position = global_position
	_setup_animation_tree()
	_setup_sounds()

	# Player casts no shadow
	for node in body_mesh.find_children("*", "GeometryInstance3D", true, false):
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		
	GameManager.player_died.connect(_on_player_died)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		interact()
		return
	if is_hidden:
		return  # No picking up, dropping or using items while hiding

	if event.is_action_pressed("drop"):
		drop_item()
	elif event.is_action_pressed("use_item"):
		use_item()
	elif event.is_action_pressed("slot_next"):
		GameManager.select_slot(GameManager.selected_slot + 1)
	elif event.is_action_pressed("slot_prev"):
		GameManager.select_slot(GameManager.selected_slot - 1)
	else:
		for i in GameManager.SLOT_COUNT:
			if event.is_action_pressed("slot_%d" % (i + 1)):
				GameManager.select_slot(i)


func add_nearby_item(item: Collectible) -> void:
	if not nearby_items.has(item):
		nearby_items.append(item)


func remove_nearby_item(item: Collectible) -> void:
	nearby_items.erase(item)


func add_nearby_target(target: Node) -> void:
	if not nearby_targets.has(target):
		nearby_targets.append(target)


func remove_nearby_target(target: Node) -> void:
	nearby_targets.erase(target)


func add_nearby_interactable(target: Node) -> void:
	if not nearby_interactables.has(target):
		nearby_interactables.append(target)


func remove_nearby_interactable(target: Node) -> void:
	nearby_interactables.erase(target)


func interact() -> void:
	# While hiding, the interact key always means "climb out again"
	if hiding_spot != null:
		hiding_spot.interact(self)
		return

	nearby_items = nearby_items.filter(func(item): return is_instance_valid(item) and not item.is_queued_for_deletion())
	nearby_interactables = nearby_interactables.filter(func(n): return is_instance_valid(n))

	# Items and world objects (barrels) share the F key: use whatever is closest
	var candidates: Array = []
	candidates.append_array(nearby_items)
	candidates.append_array(nearby_interactables)
	if candidates.is_empty():
		return

	var closest: Node3D = candidates[0]
	for target in candidates:
		if global_position.distance_to(target.global_position) < global_position.distance_to(closest.global_position):
			closest = target

	if closest is Collectible:
		pickup_item(closest)
	else:
		closest.interact(self)


# Called by a hiding spot: the player disappears inside it and can no longer be seen or caught
func enter_hiding_spot(spot: Node3D) -> void:
	hiding_spot = spot
	is_hidden = true
	exit_position = global_position
	velocity = Vector3.ZERO
	global_position = Vector3(spot.global_position.x, global_position.y, spot.global_position.z)
	body_mesh.visible = false
	body_collision.set_deferred("disabled", true)


# Called by a hiding spot: the player climbs out where they got in
func leave_hiding_spot() -> void:
	hiding_spot = null
	is_hidden = false
	global_position = exit_position
	body_mesh.visible = true
	body_collision.set_deferred("disabled", false)


func pickup_item(item: Collectible) -> void:
	if not GameManager.add_item(item.item_type, item.remaining_uses()):
		GameManager.show_message.emit("Your inventory is full! Drop something first (Q).")
		return

	pickup_player.play()
	GameManager.show_message.emit("You picked up the %s!" % Collectible.item_name(item.item_type))
	nearby_items.erase(item)
	item.queue_free()


func drop_item() -> void:
	var uses := GameManager.get_selected_uses()
	var item_type = GameManager.take_selected_item()
	if item_type == null:
		return

	var dropped: Collectible = collectible_scene.instantiate()
	get_tree().current_scene.add_child(dropped)
	dropped.global_position = global_position + facing * DROP_DISTANCE
	dropped.item_type = item_type
	dropped.uses = uses
	drop_player.play()
	GameManager.show_message.emit("You dropped the %s." % Collectible.item_name(item_type))


func respawn() -> void:
	if hiding_spot != null:
		hiding_spot.interact(self)
	global_position = start_position
	velocity = Vector3.ZERO
	stamina = 1.0
	exhausted = false
	GameManager.stamina_changed.emit(stamina, exhausted)


func use_item() -> void:
	var item_type = GameManager.get_selected_item()
	if item_type == null:
		GameManager.show_message.emit("Nothing selected to use.")
		return

	var used := false
	if item_type == Collectible.ItemType.KNIFE:
		anim_tree.set("parameters/stab/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		used = use_knife()
	else:
		for target in nearby_targets:
			if target.try_use_item(item_type):
				used = true
				break
		if not used:
			GameManager.show_message.emit("You can't use the %s here." % Collectible.item_name(item_type))

	if used:
		GameManager.use_selected_item()


# Kills the closest enemy within reach. Returns true if the knife was used.
func use_knife() -> bool:
	var target: Node3D = null
	for enemy in get_tree().get_nodes_in_group("enemy"):
		var distance := global_position.distance_to(enemy.global_position)
		if distance <= KNIFE_RANGE and (target == null or distance < global_position.distance_to(target.global_position)):
			target = enemy

	if target == null:
		GameManager.show_message.emit("No enemy close enough to stab.")
		return false

	target.die()
	stab_player.play()
	var uses_left := GameManager.get_selected_uses() - 1
	if uses_left > 0:
		GameManager.show_message.emit("You took out the enemy! Knife uses left: %d" % uses_left)
	else:
		GameManager.show_message.emit("You took out the enemy! Your Knife broke.")
	return true


func _physics_process(delta: float) -> void:
	# While hiding the player does not move at all (but stamina still regenerates)
	if is_hidden:
		_update_stamina(false, delta)
		return

	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	is_sprinting = _update_stamina(direction != Vector3.ZERO, delta)
	var speed := SPRINT_SPEED if is_sprinting else WALK_SPEED
	if direction:
		facing = direction
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, SPRINT_SPEED)
		velocity.z = move_toward(velocity.z, 0, SPRINT_SPEED)

	move_and_slide()
	_update_animation(direction, delta)
	_update_footsteps(delta)


# Drains stamina while sprinting and regenerates it otherwise.
# Returns true if the player sprints this frame.
func _update_stamina(moving: bool, delta: float) -> bool:
	var sprint_held := Input.is_action_pressed("sprint")
	if not sprint_held:
		exhausted = false

	var old_stamina := stamina
	var old_exhausted := exhausted
	var sprinting := moving and sprint_held and not exhausted and stamina > 0.0

	if sprinting:
		stamina = maxf(stamina - delta / MAX_SPRINT_TIME, 0.0)
		if stamina <= 0.0:
			exhausted = true
	else:
		stamina = minf(stamina + STAMINA_REGEN * delta, 1.0)

	if stamina != old_stamina or exhausted != old_exhausted:
		GameManager.stamina_changed.emit(stamina, exhausted)
	_update_breathing(not sprinting and stamina < 1.0)
	return sprinting


func _setup_sounds() -> void:
	footstep_player = AudioStreamPlayer.new()
	footstep_player.volume_db = footstep_volume_db
	footstep_player.max_polyphony = 3  # Steps may overlap a little while sprinting
	add_child(footstep_player)

	breathing_player = AudioStreamPlayer.new()
	breathing_player.stream = breathing_sound
	breathing_player.volume_db = breathing_volume_db
	breathing_player.finished.connect(_on_breathing_finished)
	add_child(breathing_player)

	stab_player = AudioStreamPlayer.new()
	stab_player.stream = stab_sound
	add_child(stab_player)

	pickup_player = AudioStreamPlayer.new()
	pickup_player.stream = pickup_sound
	pickup_player.volume_db = pickup_volume_db
	add_child(pickup_player)

	drop_player = AudioStreamPlayer.new()
	drop_player.stream = drop_sound
	drop_player.volume_db = drop_volume_db
	add_child(drop_player)

	# One Walk cycle = two steps, so a footstep lines up with the animation at any speed
	stride_length = WALK_SPEED * anim.get_animation("Walk").length / 2.0
	step_distance = stride_length * 0.5


# Plays a random footstep every stride while walking or sprinting on the ground
func _update_footsteps(delta: float) -> void:
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or ground_speed < 0.1:
		step_distance = stride_length * 0.5  # First step comes quickly after starting to move
		return

	step_distance += ground_speed * delta
	if step_distance >= stride_length:
		step_distance -= stride_length
		footstep_player.stream = footstep_sounds.pick_random()
		footstep_player.pitch_scale = randf_range(0.92, 1.08)
		footstep_player.play()


# Heavy breathing while stamina regenerates, fades out once it is full (or we sprint again)
func _update_breathing(regenerating: bool) -> void:
	if regenerating == is_breathing:
		return
	is_breathing = regenerating
	if breathing_tween:
		breathing_tween.kill()

	if is_breathing:
		breathing_player.volume_db = breathing_volume_db
		if not breathing_player.playing:
			breathing_player.play()
	else:
		breathing_tween = create_tween()
		breathing_tween.tween_property(breathing_player, "volume_db", -40.0, 0.6)
		breathing_tween.tween_callback(breathing_player.stop)


# Loops the breathing as long as we are still out of breath
func _on_breathing_finished() -> void:
	if is_breathing:
		breathing_player.play()


# Builds an AnimationTree: Idle/Walk drive the whole body,
# Stab is layered on top and only moves the right arm, so you can stab while walking
func _setup_animation_tree() -> void:
	anim.get_animation("Idle").loop_mode = Animation.LOOP_LINEAR
	anim.get_animation("Walk").loop_mode = Animation.LOOP_LINEAR

	var idle := AnimationNodeAnimation.new()
	idle.animation = &"Idle"
	var walk := AnimationNodeAnimation.new()
	walk.animation = &"Walk"
	var stab := AnimationNodeAnimation.new()
	stab.animation = &"Stab"

	# One-shot that plays Stab once, filtered to the right arm bones
	var stab_shot := AnimationNodeOneShot.new()
	stab_shot.fadein_time = 0.05
	stab_shot.fadeout_time = 0.15
	stab_shot.filter_enabled = true
	var stab_anim := anim.get_animation("Stab")
	for i in stab_anim.get_track_count():
		var path := stab_anim.track_get_path(i)
		if path.get_concatenated_subnames() in STAB_BONES:
			stab_shot.set_filter_path(path, true)

	var tree := AnimationNodeBlendTree.new()
	tree.add_node(&"idle", idle)
	tree.add_node(&"walk", walk)
	tree.add_node(&"walk_speed", AnimationNodeTimeScale.new())
	tree.add_node(&"move", AnimationNodeBlend2.new())
	tree.add_node(&"stab_anim", stab)
	tree.add_node(&"stab", stab_shot)
	tree.connect_node(&"move", 0, &"idle")
	tree.connect_node(&"walk_speed", 0, &"walk")
	tree.connect_node(&"move", 1, &"walk_speed")
	tree.connect_node(&"stab", 0, &"move")
	tree.connect_node(&"stab", 1, &"stab_anim")
	tree.connect_node(&"output", 0, &"stab")

	anim.stop()
	anim_tree = AnimationTree.new()
	anim_tree.tree_root = tree
	body_mesh.add_child(anim_tree)
	anim_tree.anim_player = anim_tree.get_path_to(anim)
	anim_tree.active = true


# Turns the model towards the walking direction and fades between Idle and Walk
func _update_animation(direction: Vector3, delta: float) -> void:
	if direction:
		body_mesh.rotation.y = atan2(direction.x, direction.z)
	var target := 1.0 if direction else 0.0
	move_blend = move_toward(move_blend, target, delta * 6.0)
	anim_tree.set("parameters/move/blend_amount", move_blend)

	# Speed up the walk cycle while sprinting so the feet keep up
	var anim_target := SPRINT_SPEED / WALK_SPEED if is_sprinting else 1.0
	walk_anim_speed = move_toward(walk_anim_speed, anim_target, delta * 4.0)
	anim_tree.set("parameters/walk_speed/scale", walk_anim_speed)
	
func _on_player_died() -> void:
	respawn()
