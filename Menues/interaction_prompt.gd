extends Label
## "[F] Hide", "[E] Unlock" ... shown above the thing the player can use right now.
## The text comes from the object's get_prompt(player) (collectible, hiding barrel, door, end zone).

@export var height := 1.6   # metres above the object

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 20)
	add_theme_color_override("font_color", Color(1, 1, 1))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.set_corner_radius_all(5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	add_theme_stylebox_override("normal", style)
	visible = false


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	var target: Node3D = _current_target(player) if player else null
	var prompt := ""
	if target and target.has_method("get_prompt"):
		prompt = str(target.call("get_prompt", player))
	var cam := get_viewport().get_camera_3d()
	if prompt == "" or cam == null:
		visible = false
		return
	var world_pos := target.global_position + Vector3.UP * height
	if cam.is_position_behind(world_pos):
		visible = false
		return
	text = prompt
	visible = true
	reset_size()
	position = cam.unproject_position(world_pos) - size * Vector2(0.5, 1.0)


# While hiding: the barrel. Otherwise the closest thing in reach (item, barrel, door, end zone).
func _current_target(player: Player) -> Node3D:
	if player.is_hidden and is_instance_valid(player.hiding_spot):
		return player.hiding_spot
	var best: Node3D = null
	var best_d := INF
	var candidates: Array = []
	candidates.append_array(player.nearby_items)
	candidates.append_array(player.nearby_interactables)
	candidates.append_array(player.nearby_targets)
	for c in candidates:
		var node := c as Node3D
		if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var d := player.global_position.distance_to(node.global_position)
		if d < best_d:
			best_d = d
			best = node
	return best
