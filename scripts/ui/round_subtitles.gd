extends Label
## Presentation-only clock. Replacing a sequence cancels it atomically; no timers,
## asynchronous callbacks, or rules advancement can survive a phase change.
const FADE_IN := 0.9
const HOLD := 1.8
const FADE_OUT := 0.9
const GAP := 0.35
var sequence_key := ""
var lines: Array[String] = []
var line_index := 0
var elapsed := 0.0
var reduced_motion := false
var completed := false
var generation := 0

func play(key: String, sentences: Array) -> void:
	if key == sequence_key: return
	sequence_key = key
	lines.assign(sentences)
	line_index = 0
	elapsed = 0.0
	completed = lines.is_empty()
	generation += 1
	_update_text()

func skip() -> void:
	if lines.is_empty(): return
	line_index = lines.size() - 1
	elapsed = FADE_IN
	completed = true
	_update_text()

func _process(delta: float) -> void:
	advance_clock(delta)

func advance_clock(delta: float) -> void:
	if completed or lines.is_empty(): return
	elapsed += maxf(0.0, delta)
	var duration = FADE_IN + HOLD + FADE_OUT + GAP
	while elapsed + 0.000001 >= duration and line_index < lines.size() - 1:
		elapsed = maxf(0.0, elapsed - duration)
		line_index += 1
	if line_index == lines.size() - 1 and elapsed + 0.000001 >= FADE_IN:
		completed = true
	_update_text()

func _update_text() -> void:
	text = "" if lines.is_empty() else lines[line_index]
	if completed or reduced_motion:
		modulate.a = 1.0
	elif elapsed < FADE_IN:
		modulate.a = smoothstep(0.0, FADE_IN, elapsed)
	elif line_index == lines.size()-1 or elapsed < FADE_IN + HOLD:
		modulate.a = 1.0
	else:
		modulate.a = 1.0 - smoothstep(FADE_IN + HOLD, FADE_IN + HOLD + FADE_OUT, elapsed)
