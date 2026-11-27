extends Control
## Level Generator page: every setting of the map and enemy generator, then "Generate & Play".
## Defaults come from Tools/map_generator.tscn. The chosen settings are kept in
## GameManager.generator_settings, so they stay when you come back or retry after dying.

const GENERATOR_SCENE := "res://Tools/map_generator.tscn"
const LEVEL_SELECT_SCENE := "res://Menues/level_select.tscn"
const GAME_SCENE := "res://game_container.tscn"
const TILE_METERS := 12
const FONT_SIZE := 20
const MAX_SEED := 999999

# [setting, label, tooltip, kind]
# kinds: seed, int, tiles (int shown in metres too), percent, share (scaled to 100 %), float, metres, bool
const MAP_OPTIONS := [
	["map_seed", "Seed", "Same seed + same settings = same map", "seed"],
	["width", "Width", "Map width in tiles (one tile = 12 m)", "tiles"],
	["height", "Height", "Map height in tiles (one tile = 12 m)", "tiles"],
	["loop_chance", "Extra connections", "Chance that two neighbouring streets are connected as well,\nso there is more than one way around a guard", "percent"],
	["with_plaza", "Plaza", "One 2x2 plaza inside the map (needs at least 4 x 4 tiles)", "bool"],
	["coin_markers", "Coin spots", "Number of places where coins can spawn", "int"],
	["use_final_tile", "Landslide finale", "The goal is the quarry outside the map: blow up the rock dam\nwith the bomb and the landslide buries the town.\nOff: the goal is the city gate inside the map.", "bool"],
]
const ENEMY_OPTIONS := [
	["enemy_density", "Enemies per tile", "Number of enemies = tiles x this value\n(0.25 on a 5 x 5 map = 6 enemies, 0 = no enemies)", "float"],
	["base_share", "Guards", "Share of normal guards (all four shares are scaled to 100 %)", "share"],
	["paranoid_share", "Paranoid guards", "Share of paranoid guards (they look back)", "share"],
	["watchman_share", "Watchtowers", "Share of watchtowers", "share"],
	["dog_share", "Guard dogs", "Share of guard dogs (they hear you)", "share"],
	["base_reach", "Guard patrol range", "How far guards patrol, in tiles (0 = stand still)", "tiles"],
	["paranoid_reach", "Paranoid patrol range", "How far paranoid guards patrol, in tiles (0 = stand still)", "tiles"],
	["dog_reach", "Dog patrol range", "How far guard dogs patrol, in tiles (0 = stand still)", "tiles"],
	["watchman_reach", "Watchtower range", "Patrol range of watchtowers, in tiles (0 = stand still)", "tiles"],
	["min_steps_from_start", "Safe zone at start", "No enemy closer than this many tiles to the player start", "tiles"],
	["enemy_spawn_height", "Spawn height", "Enemies spawn this many metres above the ground", "metres"],
]
# Ranges for settings that have no @export_range in the generator
const FALLBACK_RANGES := {
	"map_seed": [1, MAX_SEED, 1],
	"coin_markers": [0, 30, 1],
	"enemy_spawn_height": [-1.0, 5.0, 0.1],
}
const SHARE_LABELS := {
	"base_share": "guards", "paranoid_share": "paranoid", "watchman_share": "watchtowers", "dog_share": "dogs",
}

var _defaults := {}
var _ranges := {}          # setting -> [min, max, step]
var _settings := {}
var _kinds := {}           # setting -> kind
var _inputs := {}          # setting -> Range or CheckBox
var _value_labels := {}    # setting -> Label
var _map_summary: Label
var _enemy_summary: Label
var _play_button: Button


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_read_generator_defaults()
	_settings = _defaults.duplicate()
	for setting in GameManager.generator_settings:
		if _settings.has(setting):
			_settings[setting] = GameManager.generator_settings[setting]
	_build_ui()
	_refresh_inputs()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


# Default values and slider ranges straight from the generator, so this page stays in sync with it
func _read_generator_defaults() -> void:
	var generator: Node = load(GENERATOR_SCENE).instantiate()
	_defaults = generator.get_settings()
	for prop in generator.get_property_list():
		if not _defaults.has(prop.name) or prop.hint != PROPERTY_HINT_RANGE:
			continue
		var parts: PackedStringArray = prop.hint_string.split(",")
		if parts.size() >= 2:
			var step := 1.0
			if parts.size() > 2 and parts[2].is_valid_float():
				step = parts[2].to_float()
			_ranges[prop.name] = [parts[0].to_float(), parts[1].to_float(), step]
	generator.free()
	for setting in FALLBACK_RANGES:
		if not _ranges.has(setting):
			_ranges[setting] = FALLBACK_RANGES[setting]


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	root.add_child(_label("Level Generator", 40))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 24)
	scroll.add_child(columns)
	_map_summary = _build_column(columns, "Map", MAP_OPTIONS)
	_enemy_summary = _build_column(columns, "Enemies", ENEMY_OPTIONS)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	root.add_child(buttons)
	_button(buttons, "Back", _on_back_pressed)
	_button(buttons, "Reset", _on_reset_pressed, "Back to the settings of Tools/map_generator.tscn")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	_play_button = _button(buttons, "Generate & Play", _on_play_pressed)
	_play_button.grab_focus()


# A dark panel with a heading, one row per option and a summary line; returns the summary label
func _build_column(parent: Control, heading: String, options: Array) -> Label:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(_label(heading, 28))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for option in options:
		_add_row(grid, option[0], option[1], option[2], option[3])

	var summary := _label("", FONT_SIZE)
	summary.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.custom_minimum_size.x = 300
	box.add_child(summary)
	return summary


func _add_row(grid: GridContainer, setting: String, text: String, tip: String, kind: String) -> void:
	_kinds[setting] = kind
	var name_label := _label(text, FONT_SIZE)
	name_label.tooltip_text = tip
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS   # so the tooltip shows
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(name_label)

	var r: Array = _ranges.get(setting, [0, 1, 1])
	match kind:
		"bool":
			var check := CheckBox.new()
			check.tooltip_text = tip
			check.toggled.connect(func(on: bool): _set_setting(setting, on))
			grid.add_child(check)
			_inputs[setting] = check
		"percent", "share", "float":
			var slider := HSlider.new()
			slider.min_value = r[0]
			slider.max_value = r[1]
			slider.step = r[2]
			slider.custom_minimum_size = Vector2(180, 28)
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			slider.tooltip_text = tip
			slider.value_changed.connect(func(v: float): _set_setting(setting, v))
			grid.add_child(slider)
			_inputs[setting] = slider
		_:   # seed, int, tiles, metres
			var spin := SpinBox.new()
			spin.min_value = r[0]
			spin.max_value = r[1]
			spin.step = r[2]
			spin.rounded = kind != "metres"
			spin.custom_minimum_size.x = 140
			spin.tooltip_text = tip
			spin.get_line_edit().add_theme_font_size_override("font_size", FONT_SIZE)
			if spin.rounded:
				spin.value_changed.connect(func(v: float): _set_setting(setting, roundi(v)))
			else:
				spin.value_changed.connect(func(v: float): _set_setting(setting, v))
			_inputs[setting] = spin
			if kind == "seed":
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 8)
				row.add_child(spin)
				var dice := Button.new()
				dice.text = "Random"
				dice.tooltip_text = "Pick a random seed"
				dice.add_theme_font_size_override("font_size", FONT_SIZE)
				dice.pressed.connect(func(): spin.value = randi_range(1, MAX_SEED))
				row.add_child(dice)
				grid.add_child(row)
			else:
				grid.add_child(spin)

	var value_label := _label("", FONT_SIZE)
	value_label.custom_minimum_size.x = 72
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	grid.add_child(value_label)
	_value_labels[setting] = value_label


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label


func _button(parent: Control, text: String, callback: Callable, tip := "") -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.add_theme_font_size_override("font_size", 28)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


# ---------------------------------------------------------------- values

func _set_setting(setting: String, value) -> void:
	_settings[setting] = value
	_update_labels()


func _refresh_inputs() -> void:
	for setting in _inputs:
		var input = _inputs[setting]
		if input is CheckBox:
			input.set_pressed_no_signal(bool(_settings[setting]))
		else:
			input.set_value_no_signal(float(_settings[setting]))
	_update_labels()


func _update_labels() -> void:
	var total_share := 0.0
	for setting in SHARE_LABELS:
		total_share += float(_settings[setting])

	for setting in _value_labels:
		var v = _settings[setting]
		var text := ""
		match _kinds[setting]:
			"percent":
				text = "%d %%" % roundi(float(v) * 100)
			"share":
				text = "%d %%" % (roundi(float(v) / total_share * 100) if total_share > 0 else 0)
			"float":
				text = "%.2f" % float(v)
			"tiles":
				text = "%d m" % (int(v) * TILE_METERS)
		_value_labels[setting].text = text

	var w := int(_settings["width"])
	var h := int(_settings["height"])
	var map_text := "%d x %d tiles = %d x %d m" % [w, h, w * TILE_METERS, h * TILE_METERS]
	if bool(_settings["with_plaza"]) and (w < 4 or h < 4):
		map_text += "\nToo small for a plaza (needs 4 x 4 tiles)"
	_map_summary.text = map_text

	var count := roundi(w * h * float(_settings["enemy_density"]))
	if count <= 0 or total_share <= 0.0:
		_enemy_summary.text = "No enemies"
		return
	var counts := _enemy_counts(count, total_share)
	var parts: PackedStringArray = []
	for setting in SHARE_LABELS:
		if counts[setting] > 0:
			parts.append("%d %s" % [counts[setting], SHARE_LABELS[setting]])
	_enemy_summary.text = "Up to %d enemies: %s" % [count, ", ".join(parts)]


# Same rounding as the generator (largest remainder), so the preview matches the real numbers
func _enemy_counts(count: int, total_share: float) -> Dictionary:
	var counts := {}
	var remainders := []
	var assigned := 0
	for setting in SHARE_LABELS:
		var exact: float = count * float(_settings[setting]) / total_share
		counts[setting] = int(exact)
		assigned += int(exact)
		remainders.append([exact - int(exact), setting])
	remainders.sort_custom(func(a, b): return a[0] > b[0])
	for k in mini(count - assigned, remainders.size()):
		counts[remainders[k][1]] += 1
	return counts


# ---------------------------------------------------------------- buttons

func _on_play_pressed() -> void:
	GameManager.generator_settings = _settings.duplicate()
	_play_button.disabled = true
	_play_button.text = "Generating..."
	# Let the text show before the game freezes for a moment while the map is built
	await get_tree().process_frame
	await get_tree().process_frame
	GameManager.current_level_path = GENERATOR_SCENE
	SceneFader.change_scene(GAME_SCENE)
	GameManager.reset_game()


func _on_reset_pressed() -> void:
	_settings = _defaults.duplicate()
	GameManager.generator_settings = {}
	_refresh_inputs()


func _on_back_pressed() -> void:
	GameManager.generator_settings = _settings.duplicate()
	SceneFader.change_scene(LEVEL_SELECT_SCENE)
