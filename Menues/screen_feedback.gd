extends ColorRect
## Red flash around the screen edges when an enemy spots the player, and when caught a red flash
## that fades to dark before the death menu shows up.

const SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.85, 0.05, 0.05, 1.0);
uniform float intensity = 0.0;   // red edges
uniform float cover = 0.0;       // 1 = whole screen in the tint colour

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;   // round, not stretched with the window
	float edge = smoothstep(0.3, 0.85, length(uv)) * intensity;
	COLOR = vec4(tint.rgb, clamp(max(edge, cover), 0.0, 1.0));
}
"""
const PULSE_COOLDOWN := 1.5   # no new flash for this many seconds (several guards spotting at once)

var _material := ShaderMaterial.new()
var _tween: Tween
var _last_pulse := -100.0
var _dying := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # the death fade runs while the game is frozen
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = SHADER
	_material.shader = shader
	material = _material
	GameManager.player_spotted.connect(_on_player_spotted)
	GameManager.player_died.connect(_on_player_died)


func _on_player_spotted() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _dying or now - _last_pulse < PULSE_COOLDOWN:
		return
	_last_pulse = now
	_restart_tween()
	_tween.tween_property(_material, "shader_parameter/intensity", 0.75, 0.08)
	_tween.tween_property(_material, "shader_parameter/intensity", 0.0, 0.7)


func _on_player_died() -> void:
	if _dying:
		return
	_dying = true
	_restart_tween()
	_material.set_shader_parameter("intensity", 1.0)
	_tween.tween_property(_material, "shader_parameter/cover", 0.35, 0.08)   # red flash
	_tween.set_parallel(true)
	_tween.chain().tween_property(_material, "shader_parameter/tint", Color(0, 0, 0, 1), 0.6)
	_tween.tween_property(_material, "shader_parameter/cover", 0.85, 0.6)    # ...fading to dark


func _restart_tween() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
