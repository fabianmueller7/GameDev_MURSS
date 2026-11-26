extends CanvasLayer
## Autoload "SceneFader": fades to black, changes the scene, fades back in.
## Use SceneFader.change_scene(path) / SceneFader.reload_scene() instead of the SceneTree functions.
## The screen stays black while the new scene sets itself up (e.g. a generated map being built).

const FADE_TIME := 0.25

var _rect: ColorRect
var _busy := false
var _target := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0, 1)   # the game starts black and fades in
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	_fade_to(0.0)


func change_scene(path: String) -> void:
	_target = path
	if not _busy:
		_run()


# Restart the current scene. If a scene change is already on its way, that one wins:
# the new scene starts fresh anyway.
func reload_scene() -> void:
	if _busy:
		return
	_target = get_tree().current_scene.scene_file_path
	_run()


func _run() -> void:
	_busy = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP   # no clicks while fading
	get_tree().paused = true                         # the world freezes while it fades out
	await _fade_to(1.0)
	get_tree().paused = false
	get_tree().change_scene_to_file(_target)
	# The new scene is added at the end of this frame; give it a frame to set itself up
	await get_tree().process_frame
	await get_tree().process_frame
	_busy = false
	await _fade_to(0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _fade_to(alpha: float) -> Signal:
	var tween := create_tween()
	tween.tween_property(_rect, "color:a", alpha, FADE_TIME)
	return tween.finished
