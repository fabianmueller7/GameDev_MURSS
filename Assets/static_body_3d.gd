extends StaticBody3D

var mesh: MeshInstance3D

func _ready() -> void:
	for child in get_children():
		if child is MeshInstance3D:
			mesh = child
			break

	if mesh == null:
		push_warning("Kein MeshInstance3D-Kind gefunden bei: " + str(get_path()))
		return

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.RED
	mesh.material_override = mat

func _process(delta: float) -> void:
	pass
