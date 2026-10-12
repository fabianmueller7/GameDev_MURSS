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


func _ready() -> void:
	start_position = global_position
	GameManager.add_item(Collectible.ItemType.KNIFE, Collectible.MAX_USES[Collectible.ItemType.KNIFE])


func _unhandled_input(event: InputEvent) -> void:
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
	global_position = start_position
	velocity = Vector3.ZERO


func use_item() -> void:
	var item_type = GameManager.get_selected_item()
	if item_type == null:
		GameManager.show_message.emit("Nothing selected to use.")
		return

	var used := false
	if item_type == Collectible.ItemType.KNIFE:
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
