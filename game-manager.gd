extends Node

const SLOT_COUNT := 4
# Completed levels survive closing the game (user:// = the game's own folder in the user's AppData)
const PROGRESS_FILE := "user://progress.cfg"
# Maps from the Level Generator page are built on the fly, they are not tracked as completed
const GENERATOR_SCENE := "res://Tools/map_generator.tscn"

# Inventory: each slot holds a Collectible.ItemType (or null when empty)
# and how many uses that item has left
var slots: Array = []
var slot_uses: Array = []
var selected_slot: int = 0
var current_level_path: String = "res://Levels/level_1.tscn"
# Settings chosen on the Level Generator page (empty = the defaults of Tools/map_generator.tscn)
var generator_settings: Dictionary = {}
# Level paths the player has finished (path -> true), loaded from PROGRESS_FILE
var completed_levels: Dictionary = {}


# Signal to notify HUD or other systems of changes
signal inventory_updated
signal show_message(text)
signal player_died
signal level_won
signal stamina_changed(value: float, exhausted: bool)  # value: 0.0 (empty) to 1.0 (full)


func _ready() -> void:
	slots.resize(SLOT_COUNT)
	slot_uses.resize(SLOT_COUNT)
	slot_uses.fill(0)
	_load_progress()


# ---- level progress ----

# The player finished the current level: remember it and show the victory screen
func win_level() -> void:
	if current_level_path != GENERATOR_SCENE and not completed_levels.has(current_level_path):
		completed_levels[current_level_path] = true
		_save_progress()
	level_won.emit()

func is_level_completed(level_path: String) -> bool:
	return completed_levels.has(level_path)

func _save_progress() -> void:
	var file := ConfigFile.new()
	file.set_value("progress", "completed_levels", completed_levels.keys())
	var err := file.save(PROGRESS_FILE)
	if err != OK:
		push_error("Could not save the progress to %s (%s)" % [PROGRESS_FILE, error_string(err)])

func _load_progress() -> void:
	completed_levels.clear()
	var file := ConfigFile.new()
	if file.load(PROGRESS_FILE) != OK:
		return  # First start: nothing finished yet
	for level_path in file.get_value("progress", "completed_levels", []):
		completed_levels[str(level_path)] = true

func has_item(item_type: Collectible.ItemType) -> bool:
	return slots.has(item_type)

# Puts the item into the selected slot if it is free, otherwise into the first free slot.
# Returns false when the inventory is full.
func add_item(item_type: Collectible.ItemType, uses: int) -> bool:
	var slot := selected_slot if slots[selected_slot] == null else slots.find(null)
	if slot == -1:
		return false
	slots[slot] = item_type
	slot_uses[slot] = uses
	inventory_updated.emit()
	return true

func get_selected_item() -> Variant:
	return slots[selected_slot]

func get_selected_uses() -> int:
	return slot_uses[selected_slot]

# Uses up one use of the selected item; the item disappears when none are left
func use_selected_item() -> void:
	slot_uses[selected_slot] -= 1
	if slot_uses[selected_slot] <= 0:
		slots[selected_slot] = null
	inventory_updated.emit()

# Removes the item in the selected slot and returns it (null if the slot was empty)
func take_selected_item() -> Variant:
	var item = slots[selected_slot]
	if item != null:
		slots[selected_slot] = null
		inventory_updated.emit()
	return item

func select_slot(index: int) -> void:
	selected_slot = wrapi(index, 0, SLOT_COUNT)
	inventory_updated.emit()
	
func trigger_death() -> void:
	print("player dead registered")
	player_died.emit()
	
func reset_game() -> void:
	# Clear out inventory items and uses
	slots.clear()
	slot_uses.clear()
	slots.resize(SLOT_COUNT)
	slot_uses.resize(SLOT_COUNT)
	selected_slot = 0
	inventory_updated.emit()
	add_item(Collectible.ItemType.KNIFE, Collectible.MAX_USES[Collectible.ItemType.KNIFE])
	get_tree().reload_current_scene()
