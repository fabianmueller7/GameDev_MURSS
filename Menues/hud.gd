extends CanvasLayer

const SLOT_SIZE := Vector2(80, 80)

@onready var message_label: Label = $Label
@onready var slot_container: HBoxContainer = $InventoryBar
@onready var stamina_bar: ProgressBar = $StaminaBar

const STAMINA_COLOR := Color(0.35, 0.8, 0.4)
const EXHAUSTED_COLOR := Color(0.9, 0.3, 0.2)
var stamina_fill: StyleBoxFlat

var slot_panels: Array[Panel] = []
var slot_labels: Array[Label] = []
var uses_labels: Array[Label] = []
var message_id: int = 0

func _ready() -> void:
	# Connect to GameManager signals
	GameManager.show_message.connect(_on_show_message)
	GameManager.inventory_updated.connect(update_inventory)
	GameManager.stamina_changed.connect(_on_stamina_changed)

	setup_stamina_bar()

	build_inventory_slots()
	update_inventory()

	_add_extras()

	# Objectives top left, controls bottom left (fade out after a few seconds)
	message_label.text = ""


# Objectives (top left) and prompts above objects go under the map overlay,
# the red screen flashes above it but under the menus
func _add_extras() -> void:
	var map_index: int = $MapOverlay.get_index()
	var tracker: Control = preload("res://Menues/objective_tracker.gd").new()
	add_child(tracker)
	move_child(tracker, map_index)
	var prompt: Control = preload("res://Menues/interaction_prompt.gd").new()
	add_child(prompt)
	move_child(prompt, map_index + 1)
	var controls: Control = preload("res://Menues/controls_hint.gd").new()
	add_child(controls)
	move_child(controls, map_index + 2)
	var feedback: Control = preload("res://Menues/screen_feedback.gd").new()
	add_child(feedback)
	move_child(feedback, $PauseMenu.get_index())

func build_inventory_slots() -> void:
	for i in GameManager.SLOT_COUNT:
		var panel := Panel.new()
		panel.custom_minimum_size = SLOT_SIZE
		slot_container.add_child(panel)

		var number := Label.new()
		number.text = str(i + 1)
		number.position = Vector2(6, 2)
		number.add_theme_font_size_override("font_size", 14)
		panel.add_child(number)
		
		var item_label := Label.new()
		item_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		item_label.add_theme_font_size_override("font_size", 18)
		panel.add_child(item_label)

		# Remaining uses, bottom left of the slot (only for items with more than one use)
		var uses_label := Label.new()
		uses_label.position = Vector2(6, SLOT_SIZE.y - 22)
		uses_label.add_theme_font_size_override("font_size", 14)
		panel.add_child(uses_label)

		slot_panels.append(panel)
		slot_labels.append(item_label)
		uses_labels.append(uses_label)

func update_inventory() -> void:
	for i in slot_panels.size():
		var item = GameManager.slots[i]
		var selected := i == GameManager.selected_slot

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.6)
		style.set_corner_radius_all(6)
		style.set_border_width_all(4 if selected else 2)
		style.border_color = Color(1, 0.85, 0.2) if selected else Color(1, 1, 1, 0.3)
		slot_panels[i].add_theme_stylebox_override("panel", style)

		if item == null:
			slot_labels[i].text = ""
			uses_labels[i].text = ""
		else:
			slot_labels[i].text = Collectible.item_name(item)
			slot_labels[i].add_theme_color_override("font_color", Collectible.ITEM_COLORS[item].lightened(0.4))
			uses_labels[i].text = "x%d" % GameManager.slot_uses[i] if Collectible.MAX_USES[item] > 1 else ""

func setup_stamina_bar() -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0, 0, 0, 0.6)
	background.set_corner_radius_all(4)
	stamina_fill = StyleBoxFlat.new()
	stamina_fill.bg_color = STAMINA_COLOR
	stamina_fill.set_corner_radius_all(4)
	stamina_bar.add_theme_stylebox_override("background", background)
	stamina_bar.add_theme_stylebox_override("fill", stamina_fill)
	stamina_bar.value = 1.0

# Bar turns red when stamina ran out, until the player releases Shift
func _on_stamina_changed(value: float, exhausted: bool) -> void:
	stamina_bar.value = value
	stamina_fill.bg_color = EXHAUSTED_COLOR if exhausted else STAMINA_COLOR

func _on_show_message(text: String) -> void:
	show_temp_message(text, 3.0)

func show_temp_message(text: String, duration: float) -> void:
	message_id += 1
	var id := message_id
	message_label.text = text
	message_label.visible = true

	# Simple timer to hide the message (unless a newer message replaced it meanwhile)
	await get_tree().create_timer(duration).timeout
	if id == message_id:
		message_label.text = ""
