extends PanelContainer
## Small card bottom left with the controls, shown at the start of a level and faded out after a while.

const CONTROLS := [
	["WASD", "Move"],
	["Shift", "Sprint"],
	["Ctrl", "Sneak"],
	["F", "Interact / pick up"],
	["E", "Use item"],
	["Q", "Drop item"],
	["Left / Right", "Switch slot"],
	["M", "Map"],
	["Esc", "Pause"],
]
const FONT_SIZE := 15
const SHOW_TIME := 10.0   # seconds before it fades out
const FADE_TIME := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.55)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	add_child(grid)
	var key_style := StyleBoxFlat.new()
	key_style.bg_color = Color(1, 1, 1, 0.15)
	key_style.set_corner_radius_all(4)
	key_style.content_margin_left = 6
	key_style.content_margin_right = 6
	for entry in CONTROLS:
		var key := Label.new()
		key.text = entry[0]
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.add_theme_font_size_override("font_size", FONT_SIZE)
		key.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		key.add_theme_stylebox_override("normal", key_style)
		grid.add_child(key)
		var action := Label.new()
		action.text = entry[1]
		action.add_theme_font_size_override("font_size", FONT_SIZE)
		grid.add_child(action)

	# Bottom left corner, growing upwards
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = 20
	offset_top = -20
	offset_bottom = -20

	await get_tree().create_timer(SHOW_TIME, false).timeout
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(hide)
