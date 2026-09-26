extends MeshInstance3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
 var mat := StandardMaterial3D.new()
 mat.albedo_color = Color(0, 0, 1)  # red
 material_override = mat


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
 pass
