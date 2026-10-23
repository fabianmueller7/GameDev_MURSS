extends CharacterBody3D
class_name Player


const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const DROP_DISTANCE = 1.5
const KNIFE_RANGE = 2.0

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


func _ready() -> void:
	start_position = global_position
	GameManager.add_item(Collectible.ItemType.KNIFE, Collectible.MAX_USES[Collectible.ItemType.KNIFE])

	_setup_animation_tree()

	# Player casts no shadow
	for node in body_mesh.find_children("*", "GeometryInstance3D", true, false):
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		interact()
		return
	if is_hidden:
		return  # No picking up, dropping or using items while hiding

	if event.is_action_pressed("pickup"):
		pickup_item()
	elif event.is_action_pressed("drop"):
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

	nearby_interactables = nearby_interactables.filter(func(n): return is_instance_valid(n))
	if nearby_interactables.is_empty():
		return

	# Interact with the closest thing in range
	var closest: Node3D = nearby_interactables[0]
	for target in nearby_interactables:
		if global_position.distance_to(target.global_position) < global_position.distance_to(closest.global_position):
			closest = target
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


func pickup_item() -> void:
	nearby_items = nearby_items.filter(func(item): return is_instance_valid(item) and not item.is_queued_for_deletion())
	if nearby_items.is_empty():
		return

	# Pick up the closest item in range
	var closest: Collectible = nearby_items[0]
	for item in nearby_items:
		if global_position.distance_to(item.global_position) < global_position.distance_to(closest.global_position):
			closest = item

	if not GameManager.add_item(closest.item_type, closest.remaining_uses()):
		GameManager.show_message.emit("Your inventory is full! Drop something first (Q).")
		return

	GameManager.show_message.emit("You picked up the %s!" % Collectible.item_name(closest.item_type))
	nearby_items.erase(closest)
	closest.queue_free()


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
	GameManager.show_message.emit("You dropped the %s." % Collectible.item_name(item_type))


func respawn() -> void:
	if hiding_spot != null:
		hiding_spot.interact(self)
	global_position = start_position
	velocity = Vector3.ZERO


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
	var uses_left := GameManager.get_selected_uses() - 1
	if uses_left > 0:
		GameManager.show_message.emit("You took out the enemy! Knife uses left: %d" % uses_left)
	else:
		GameManager.show_message.emit("You took out the enemy! Your Knife broke.")
	return true


func _physics_process(delta: float) -> void:
	# While hiding the player does not move at all
	if is_hidden:
		return

	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		facing = direction
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
	_update_animation(direction, delta)


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
	tree.add_node(&"move", AnimationNodeBlend2.new())
	tree.add_node(&"stab_anim", stab)
	tree.add_node(&"stab", stab_shot)
	tree.connect_node(&"move", 0, &"idle")
	tree.connect_node(&"move", 1, &"walk")
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
