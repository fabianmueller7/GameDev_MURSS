extends Control
## Map overlay (M): the walkable streets from the level's navmesh, blended over the running game
## like the overlay maps in Warframe / Path of Exile. Centered on the player and turned like the
## camera, so "up" on the map is "up" on screen. Streets show up once you have been near them.
##
## Works for every level with a baked NavigationRegion3D (hand-made and generated ones).

@export_group("View")
## Metres of the level visible from the top to the bottom of the screen (smaller = zoomed in)
@export var view_height_m := 110.0
@export var fade_time := 0.15

@export_group("Fog of war")
## Streets within this distance of the player get revealed
@export var reveal_radius := 8.0
## true = the whole map is visible from the start
@export var reveal_all := false
## The goal is always shown, also before you found it
@export var always_show_goal := true

@export_group("Colours")
@export var backdrop_color := Color(0, 0, 0, 0.35)
@export var street_color := Color(0.55, 0.75, 1.0, 0.16)
@export var edge_color := Color(0.75, 0.9, 1.0, 0.85)
@export var edge_width_px := 2.0
@export var player_color := Color(1, 1, 1, 1)
@export var goal_color := Color(1.0, 0.8, 0.2, 1)
@export var hiding_color := Color(0.4, 0.7, 1.0, 1)

const MARKER_REFRESH := 0.5   # seconds between looking for items again (they get picked up / dropped)
const EDGE_MARGIN := 28.0     # off-screen goal sticks to the screen edge with this margin

var _open := false
var _tween: Tween
var _region: NavigationRegion3D
var _player: Node3D
var _goal: Node3D
var _polys: Array[PackedVector2Array] = []   # walkable polygons in world XZ
var _poly_rects: Array[Rect2] = []
var _edges: Array = []                       # outline of the streets: [Vector2 a, Vector2 b, polygon index]
var _revealed := PackedByteArray()
var _last_reveal_pos := Vector2.INF
var _markers: Array = []                     # [Vector2 world pos, Color, radius px, polygon index]
var _marker_timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		_set_open(not _open)
		get_viewport().set_input_as_handled()


func _set_open(open: bool) -> void:
	_open = open
	if _tween:
		_tween.kill()
	_tween = create_tween()
	if open:
		visible = true
		_refresh_markers()
		queue_redraw()
		_tween.tween_property(self, "modulate:a", 1.0, fade_time)
	else:
		_tween.tween_property(self, "modulate:a", 0.0, fade_time)
		_tween.tween_callback(hide)


func _process(delta: float) -> void:
	# The level is added after the HUD, so look for it until it is there
	if not is_instance_valid(_region) or not is_instance_valid(_player):
		_try_build()
		if not is_instance_valid(_region):
			return

	# Fog of war keeps updating while the map is closed
	var p := _flat(_player.global_position)
	if p.distance_to(_last_reveal_pos) > 1.0:
		_reveal(p)
		_last_reveal_pos = p

	if visible:
		_marker_timer -= delta
		if _marker_timer <= 0.0:
			_refresh_markers()
		queue_redraw()


# ---------------------------------------------------------------- reading the level

func _try_build() -> void:
	_region = null
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return
	for node in get_tree().root.find_children("*", "NavigationRegion3D", true, false):
		var region := node as NavigationRegion3D
		if region.navigation_mesh and region.navigation_mesh.get_polygon_count() > 0:
			_region = region
			break
	if _region == null:
		return
	_build_polygons()
	_goal = get_tree().root.find_child("EndZone", true, false) as Node3D
	_last_reveal_pos = Vector2.INF


# Keeps only the piece of navmesh the player stands on (flat roof tops etc. are separate pieces)
# and finds the outline: edges that belong to just one polygon.
func _build_polygons() -> void:
	_polys.clear()
	_poly_rects.clear()
	_edges.clear()
	var navmesh := _region.navigation_mesh
	var xf := _region.global_transform
	var verts := navmesh.get_vertices()
	var world: Array[Vector3] = []
	var parent: Array[int] = []
	for i in verts.size():
		world.append(xf * verts[i])
		parent.append(i)

	var polys: Array[PackedInt32Array] = []
	for i in navmesh.get_polygon_count():
		var poly := navmesh.get_polygon(i)
		if poly.size() < 3:
			continue
		polys.append(poly)
		for idx in poly:
			var a := _find(parent, idx)
			var b := _find(parent, poly[0])
			if a != b:
				parent[a] = b

	# Which connected piece does the player stand on?
	var player_pos := _player.global_position
	var p2 := _flat(player_pos)
	var piece := -1
	var best := INF
	for poly in polys:
		var outline := _outline(poly, world)
		var height := 0.0
		for idx in poly:
			height += world[idx].y
		height /= poly.size()
		if absf(height - player_pos.y) > 2.0:
			continue
		var d := 0.0 if Geometry2D.is_point_in_polygon(p2, outline) else _rect_distance(_rect_of(outline), p2)
		if d < best:
			best = d
			piece = _find(parent, poly[0])

	var edge_count := {}   # Vector2i(vertex a, vertex b) -> [count, polygon index]
	for poly in polys:
		if _find(parent, poly[0]) != piece:
			continue
		var outline := _outline(poly, world)
		if absf(_area(outline)) < 0.01:
			continue   # degenerate polygon, cannot be drawn
		var index := _polys.size()
		_polys.append(outline)
		_poly_rects.append(_rect_of(outline))
		for k in poly.size():
			var a := poly[k]
			var b := poly[(k + 1) % poly.size()]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if edge_count.has(key):
				edge_count[key][0] += 1
			else:
				edge_count[key] = [1, index]
	for key: Vector2i in edge_count:
		if edge_count[key][0] == 1:
			_edges.append([_flat(world[key.x]), _flat(world[key.y]), edge_count[key][1]])

	_revealed = PackedByteArray()
	_revealed.resize(_polys.size())
	_revealed.fill(0)


func _reveal(p: Vector2) -> void:
	for i in _polys.size():
		if _revealed[i] == 0 and _rect_distance(_poly_rects[i], p) <= reveal_radius:
			_revealed[i] = 1


func _is_revealed(poly_index: int) -> bool:
	return reveal_all or (poly_index >= 0 and _revealed[poly_index] == 1)


func _refresh_markers() -> void:
	_marker_timer = MARKER_REFRESH
	_markers.clear()
	for node in get_tree().get_nodes_in_group("hiding_spot"):
		var spot := node as Node3D
		if spot:
			_add_marker(spot.global_position, hiding_color, 5.0)
	for node in get_tree().root.find_children("*", "Area3D", true, false):
		var item := node as Collectible
		if item and not item.is_queued_for_deletion():
			var color: Color = Collectible.ITEM_COLORS[item.item_type]
			_add_marker(item.global_position, color.lightened(0.5), 4.0)


func _add_marker(pos: Vector3, color: Color, radius: float) -> void:
	var p := _flat(pos)
	_markers.append([p, color, radius, _nearest_poly(p)])


func _nearest_poly(p: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in _polys.size():
		var d := _rect_distance(_poly_rects[i], p)
		if d < best_d:
			best_d = d
			best = i
	return best


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if not is_instance_valid(_region) or not is_instance_valid(_player):
		return
	var view := size
	draw_rect(Rect2(Vector2.ZERO, view), backdrop_color)

	# World (x, z) -> screen: centred on the player, scaled, turned like the camera
	var zoom := view.y / view_height_m
	var angle := _camera_angle()
	var to_screen := Transform2D(angle, Vector2(zoom, zoom), 0.0, view * 0.5) * Transform2D(0.0, -_flat(_player.global_position))

	draw_set_transform_matrix(to_screen)
	for i in _polys.size():
		if _is_revealed(i):
			draw_colored_polygon(_polys[i], street_color)
	var width := edge_width_px / zoom   # line width is in world units under this transform
	for edge in _edges:
		if _is_revealed(edge[2]):
			draw_line(edge[0], edge[1], edge_color, width)
	draw_set_transform_matrix(Transform2D.IDENTITY)

	for marker in _markers:
		if _is_revealed(marker[3]):
			draw_circle(to_screen * marker[0], marker[2], marker[1])

	if is_instance_valid(_goal):
		var g := _flat(_goal.global_position)
		if always_show_goal or _is_revealed(_nearest_poly(g)):
			var pos := to_screen * g
			var inside := Rect2(Vector2.ONE * EDGE_MARGIN, view - Vector2.ONE * EDGE_MARGIN * 2)
			pos = pos.clamp(inside.position, inside.end)
			_draw_diamond(pos, 9.0, goal_color)

	# Player: arrow in the middle, pointing where they walk
	var facing: Vector3 = _player.get("facing") if _player.get("facing") != null else Vector3.FORWARD
	var dir := Vector2(facing.x, facing.z)
	dir = Vector2.UP if dir.length() < 0.01 else dir.normalized().rotated(angle)
	var c := view * 0.5
	var arrow := PackedVector2Array([c + dir * 13.0, c + dir.rotated(2.5) * 9.0, c + dir.rotated(-2.5) * 9.0])
	draw_colored_polygon(arrow, player_color)
	draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color(0, 0, 0, 0.8), 1.5)


func _draw_diamond(pos: Vector2, r: float, color: Color) -> void:
	var points := PackedVector2Array([pos + Vector2(0, -r), pos + Vector2(r, 0), pos + Vector2(0, r), pos + Vector2(-r, 0)])
	draw_colored_polygon(points, color)
	draw_polyline(points + PackedVector2Array([points[0]]), Color(0, 0, 0, 0.8), 1.5)


# Turn so that the camera's "right" points right on the map
func _camera_angle() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	var right := Vector2(cam.global_basis.x.x, cam.global_basis.x.z)
	return 0.0 if right.length() < 0.01 else -right.angle()


# ---------------------------------------------------------------- helpers

func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _outline(poly: PackedInt32Array, world: Array[Vector3]) -> PackedVector2Array:
	var outline := PackedVector2Array()
	for idx in poly:
		outline.append(_flat(world[idx]))
	return outline


func _rect_of(outline: PackedVector2Array) -> Rect2:
	var rect := Rect2(outline[0], Vector2.ZERO)
	for p in outline:
		rect = rect.expand(p)
	return rect


func _rect_distance(rect: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(rect.position.x - p.x, 0.0), p.x - rect.end.x)
	var dy := maxf(maxf(rect.position.y - p.y, 0.0), p.y - rect.end.y)
	return Vector2(dx, dy).length()


func _area(outline: PackedVector2Array) -> float:
	var a := 0.0
	for i in outline.size():
		a += outline[i].cross(outline[(i + 1) % outline.size()])
	return a * 0.5


func _find(parent: Array[int], i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i
