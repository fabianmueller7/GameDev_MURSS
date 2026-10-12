extends Node

const SLOT_COUNT := 4

# Inventory: each slot holds a Collectible.ItemType (or null when empty)
# and how many uses that item has left
var slots: Array = []
var slot_uses: Array = []
var selected_slot: int = 0

# Signal to notify HUD or other systems of changes
signal inventory_updated
signal show_message(text)

func _ready() -> void:
	slots.resize(SLOT_COUNT)
	slot_uses.resize(SLOT_COUNT)
	slot_uses.fill(0)

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
