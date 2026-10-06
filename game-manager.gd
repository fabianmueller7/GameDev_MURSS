extends Node

# Inventory tracking
var has_key: bool = false
var has_bomb: bool = false

# Signal to notify HUD or other systems of changes
signal inventory_updated(item_name)
signal show_message(text)
