extends PanelContainer
## Top left of the HUD: the objectives of the current level and which ones are done.
## Reads the level itself (doors with door-trigger.gd, end zones with end_zone.gd), so it fits
## hand-made and generated levels, with or without bomb.

const REFRESH := 0.25        # seconds between updates
const SCAN_TIMEOUT := 3.0    # stop looking for doors / end zones if the level has none
const DONE_COLOR := Color(0.55, 0.9, 0.5)
const OPEN_COLOR := Color(1, 1, 1, 0.9)

var _box: VBoxContainer
var _labels: Array[Label] = []
var _timer := 0.0
var _scan_time := 0.0
var _scanned := false
var _doors: Array[Node] = []
var _ends: Array[Node] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2(20, 20)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.5)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 2)
	add_child(_box)
	var title := Label.new()
	title.text = "Objectives"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_box.add_child(title)
	visible = false


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH
	if not _scanned:
		_scan_time += REFRESH
		_scan()
	_refresh()


func _scan() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	_doors.clear()
	_ends.clear()
	for node in scene.find_children("*", "Area3D", true, false):
		var script := node.get_script() as Script
		if script == null:
			continue
		if script.resource_path.ends_with("door-trigger.gd"):
			_doors.append(node)
		elif script.resource_path.ends_with("end_zone.gd"):
			_ends.append(node)
	_scanned = not (_doors.is_empty() and _ends.is_empty()) or _scan_time > SCAN_TIMEOUT


func _refresh() -> void:
	var lines: Array = []   # [text, done]
	_doors = _doors.filter(func(d): return is_instance_valid(d))
	_ends = _ends.filter(func(e): return is_instance_valid(e))
	if not _doors.is_empty():
		var opened := _doors.filter(func(d): return d.get("is_open")).size()
		var all_open := opened == _doors.size()
		lines.append(["Find the Key", all_open or GameManager.has_item(Collectible.ItemType.KEY)])
		if _doors.size() == 1:
			lines.append(["Unlock the Door", all_open])
		else:
			lines.append(["Unlock the Doors (%d/%d)" % [opened, _doors.size()], all_open])
	if _ends.any(func(e): return e.get("needs_bomb")):
		lines.append(["Find the Bomb", GameManager.has_item(Collectible.ItemType.BOMB)])
		lines.append(["Use the Bomb at the target", false])
	elif not _ends.is_empty():
		lines.append(["Escape through the exit", false])

	visible = not lines.is_empty()
	while _labels.size() < lines.size():
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 18)
		_box.add_child(label)
		_labels.append(label)
	for i in _labels.size():
		_labels[i].visible = i < lines.size()
		if i < lines.size():
			var done: bool = lines[i][1]
			_labels[i].text = ("[x] " if done else "[  ] ") + lines[i][0]
			_labels[i].add_theme_color_override("font_color", DONE_COLOR if done else OPEN_COLOR)
