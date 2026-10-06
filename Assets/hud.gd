extends CanvasLayer

@onready var message_label: Label = $Label

func _ready() -> void:
	# Connect to GameManager signals
	GameManager.show_message.connect(_on_show_message)
	
	# Show the initial objective text at the beginning of the play
	show_temp_message("Objective: Find the Key to open the door, collect the Bomb, and reach the end!", 6.0)

func _on_show_message(text: String) -> void:
	show_temp_message(text, 3.0)

func show_temp_message(text: String, duration: float) -> void:
	message_label.text = text
	message_label.visible = true
	
	# Simple timer to hide the message
	await get_tree().create_timer(duration).timeout
	message_label.text = ""
