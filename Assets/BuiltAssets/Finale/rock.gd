@tool
extends MeshInstance3D
## Low-poly boulder, generated from a seed: an icosahedron, subdivided once, pushed in and out a bit
## and drawn with flat faces. Size and shape come from the node's scale and rotation.

@export var rock_seed := 1:
	set(value):
		rock_seed = value
		if is_inside_tree():
			_build()
@export_range(0.0, 0.5, 0.01) var roughness := 0.22:
	set(value):
		roughness = value
		if is_inside_tree():
			_build()

static var _material: StandardMaterial3D
static var _cache := {}   # "seed/roughness" -> ArrayMesh, rocks with the same seed share the mesh


func _ready() -> void:
	_build()


func _build() -> void:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_color = Color(0.42, 0.4, 0.37)
		_material.roughness = 1.0
	var key := "%d/%.2f" % [rock_seed, roughness]
	if not _cache.has(key):
		_cache[key] = _make_mesh()
	mesh = _cache[key]
	material_override = _material


func _make_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = rock_seed
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts: Array[Vector3] = []
	for v in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
			Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
			Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		verts.append(v.normalized())
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4],
		[11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	# Subdivide once: every triangle becomes four, the new corners sit on the sphere
	var mids := {}
	var fine := []
	for f in faces:
		var m: Array[int] = []
		for e in [[f[0], f[1]], [f[1], f[2]], [f[2], f[0]]]:
			var k := Vector2i(mini(e[0], e[1]), maxi(e[0], e[1]))
			if not mids.has(k):
				verts.append(((verts[e[0]] + verts[e[1]]) * 0.5).normalized())
				mids[k] = verts.size() - 1
			m.append(mids[k])
		fine.append_array([[f[0], m[0], m[2]], [f[1], m[1], m[0]], [f[2], m[2], m[1]], [m[0], m[1], m[2]]])
	# Push every corner in or out: lumpy, but still roughly round
	for i in verts.size():
		verts[i] *= 1.0 + rng.randf_range(-roughness, roughness)
	# Flat bottom so it sits on the ground
	for i in verts.size():
		verts[i].y = maxf(verts[i].y, -0.55)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # flat shading: every face gets its own normal
	for f in fine:
		for idx in [f[0], f[2], f[1]]:
			st.add_vertex(verts[idx])
	st.generate_normals()
	return st.commit()
