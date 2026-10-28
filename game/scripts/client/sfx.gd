class_name Sfx
extends Node
## The game's sound effects, played on their own bus (BUS) so a volume setting can scale them.
## No sound files are shipped: each effect is synthesized once, on first use, from a frequency
## sweep and some noise (see _make). Silent in headless runs.

const BUS := &"SFX"
const RATE := 22050
const VOICES := 8
## name: [start Hz, end Hz, seconds, noise share 0..1, volume 0..1]
const SOUNDS := {
	&"swing": [700.0, 250.0, 0.11, 0.85, 0.35],
	&"swing_heavy": [450.0, 120.0, 0.22, 0.85, 0.5],
	&"hit": [200.0, 70.0, 0.1, 0.5, 0.7],
	&"hit_heavy": [130.0, 40.0, 0.2, 0.5, 0.9],
	&"hurt": [240.0, 90.0, 0.22, 0.3, 0.8],
	&"dash": [1000.0, 300.0, 0.15, 0.9, 0.35],
	&"windup": [260.0, 420.0, 0.1, 0.2, 0.3],
	&"death": [320.0, 50.0, 0.35, 0.3, 0.7],
	&"perfect": [880.0, 1320.0, 0.25, 0.0, 0.6],
	&"give_up": [420.0, 260.0, 0.2, 0.0, 0.3],
	&"block": [1200.0, 900.0, 0.08, 0.6, 0.5],
	&"gate": [90.0, 55.0, 0.7, 0.6, 0.6],
}

var _streams := {}
var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var _silent := DisplayServer.get_name() == "headless"


func _ready() -> void:
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var at := AudioServer.bus_count - 1
		AudioServer.set_bus_name(at, BUS)
		AudioServer.set_bus_send(at, &"Master")
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = BUS
		add_child(voice)
		_voices.append(voice)


## Sets the effects' volume, 0 (mute) to 1 (full).
static func set_volume(linear: float) -> void:
	var at := AudioServer.get_bus_index(BUS)
	if at >= 0:
		AudioServer.set_bus_volume_db(at, linear_to_db(clampf(linear, 0.0, 1.0)))


func play(sound: StringName) -> void:
	if _silent or not SOUNDS.has(sound):
		return
	if not _streams.has(sound):
		_streams[sound] = _make(SOUNDS[sound])
	var voice := _voices[_next]
	_next = (_next + 1) % VOICES
	voice.stream = _streams[sound]
	voice.play()


## A sine sweeping from one pitch to another, mixed with white noise, fading out.
static func _make(spec: Array) -> AudioStreamWAV:
	var count := int(RATE * float(spec[2]))
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var phase := 0.0
	for i in count:
		var t := float(i) / count
		phase += TAU * lerpf(spec[0], spec[1], t) / RATE
		var tone := sin(phase) * (1.0 - float(spec[3])) + randf_range(-1.0, 1.0) * float(spec[3])
		bytes.encode_s16(i * 2, int(tone * (1.0 - t) * (1.0 - t) * float(spec[4]) * 32000))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	return stream
