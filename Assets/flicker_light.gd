extends Light3D
## Makes a light flicker like a flame (torch, lantern, candle): brightness and range wobble a little,
## with an occasional short dip like a gust of wind. Works on OmniLight3D and SpotLight3D.
## Every light starts at a random point, so neighbouring lights never flicker in sync.

## How much the brightness changes (0.08 = +-8 %)
@export_range(0.0, 1.0, 0.01) var energy_variation := 0.08
## How much the reach of the light changes (OmniLight3D only)
@export_range(0.0, 0.5, 0.01) var range_variation := 0.02
## How fast the flame moves
@export_range(0.1, 30.0, 0.1) var speed := 1.5
## Chance per second for a short dip (gust of wind)
@export_range(0.0, 1.0, 0.01) var gust_chance := 0.03
## How dark a gust makes the light (0.15 = 15 % darker at the deepest point)
@export_range(0.0, 1.0, 0.05) var gust_strength := 0.15

var _base_energy := 1.0
var _base_range := 0.0
var _noise := FastNoiseLite.new()
var _time := 0.0
var _gust := 0.0


func _ready() -> void:
	_base_energy = light_energy
	var omni := self as Light3D as OmniLight3D
	if omni:
		_base_range = omni.omni_range
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.fractal_octaves = 1   # one smooth layer, no jitter
	_noise.seed = randi()
	_time = randf() * 1000.0


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta * speed
	# Slow, smooth wobble with a very small, slightly faster one on top
	var wobble := clampf(_noise.get_noise_1d(_time) + 0.15 * _noise.get_noise_1d(_time * 2.3 + 500.0), -1.0, 1.0)

	# Gust: drops quickly, then the flame recovers
	if _gust <= 0.0 and randf() < gust_chance * delta:
		_gust = 1.0
	var dip := 0.0
	if _gust > 0.0:
		dip = sin(_gust * PI) * gust_strength
		_gust = maxf(_gust - delta * 0.8, 0.0)   # a gust takes over a second

	light_energy = maxf(_base_energy * (1.0 + wobble * energy_variation) * (1.0 - dip), 0.0)
	if _base_range > 0.0:
		(self as Light3D as OmniLight3D).omni_range = _base_range * (1.0 + wobble * range_variation)
