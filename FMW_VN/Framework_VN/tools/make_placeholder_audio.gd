extends SceneTree

## Writes the placeholder music and sound effects the demo story uses:
##
##     godot --headless --path . --script res://Framework_VN/tools/make_placeholder_audio.gd
##     godot --headless --path . --import
##
## Everything is a few sine-wave notes, so the framework has something to play
## before you bring in real audio. Plain, small WAVs on purpose - like the flat
## coloured placeholder pictures. Replace them under the same names and the demo
## keeps working, or point the story at your own files.

const SAMPLE_RATE := 22050
const OUT_DIR := "res://VN/assets/audio"
const PEAK := 0.45

var _buffer := PackedFloat32Array()


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# A calm loop: slow major arpeggio over a low drone.
	_new_buffer(8.0)
	_tone(0.0, 8.0, _midi(48), 0.16, 0.0)
	_arp(0.0, 0.5, [60, 64, 67, 71, 67, 64, 60, 64, 67, 71, 72, 71, 67, 64, 62, 64], 0.22)
	_write("music_calm.wav", _buffer)

	# A warmer loop in A minor for the rooftop scene.
	_new_buffer(8.0)
	_tone(0.0, 8.0, _midi(45), 0.16, 0.0)
	_arp(0.0, 0.6, [57, 60, 64, 69, 64, 60, 57, 60, 64, 72, 69, 64, 60, 57, 55, 57], 0.22)
	_write("music_sunset.wav", _buffer)

	# Short effects.
	_new_buffer(0.14)
	_tone(0.0, 0.14, 1320.0, 0.5, 18.0)
	_write("sfx_blip.wav", _buffer)

	_new_buffer(0.36)
	_tone(0.0, 0.16, _midi(76), 0.45, 10.0)
	_tone(0.14, 0.22, _midi(83), 0.45, 8.0)
	_write("sfx_confirm.wav", _buffer)

	print("FMW_VN: placeholder audio written to %s" % OUT_DIR)
	quit(0)


func _new_buffer(seconds: float) -> void:
	_buffer = PackedFloat32Array()
	_buffer.resize(int(seconds * SAMPLE_RATE))
	_buffer.fill(0.0)


func _midi(note: int) -> float:
	return 440.0 * pow(2.0, (note - 69) / 12.0)


## Adds one decaying sine note into the buffer.
func _tone(start_seconds: float, duration: float, frequency: float, gain: float, decay: float) -> void:
	var start := int(start_seconds * SAMPLE_RATE)
	var count := int(duration * SAMPLE_RATE)
	for i in count:
		var index := start + i
		if index < 0 or index >= _buffer.size():
			continue
		var t := float(i) / float(SAMPLE_RATE)
		var envelope := exp(-decay * t) if decay > 0.0 else 1.0
		# Fade the very start and end so notes never click.
		envelope *= minf(1.0, t * 120.0)
		var value := sin(TAU * frequency * t) * envelope * gain
		_buffer[index] = clampf(_buffer[index] + value, -PEAK, PEAK)


func _arp(start_seconds: float, step: float, notes: Array, gain: float) -> void:
	for i in notes.size():
		_tone(start_seconds + i * step, step * 2.5, _midi(notes[i]), gain, 3.0)


func _write(file_name: String, samples: PackedFloat32Array) -> void:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes

	var path := ProjectSettings.globalize_path(OUT_DIR.path_join(file_name))
	if stream.save_to_wav(path) != OK:
		printerr("FMW_VN: could not write %s" % path)
	else:
		print("  %s (%.1fs)" % [file_name, stream.get_length()])
