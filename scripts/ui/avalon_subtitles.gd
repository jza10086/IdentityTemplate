## Persistent local presentation clock. Phase updates queue the latest status;
## they never replace a visible line or interrupt the three-line prologue.
extends Label
signal intro_finished
const FADE_IN: float = 0.30
const FADE_OUT: float = 0.32
const GAP: float = 0.10
const STATUS_HOLD: float = 1.1
var reduced_motion: bool = false
var intro_active: bool = false
var sequence_key: String = ""
var line_index: int = 0
var elapsed: float = 0.0
var _mode: String = "idle"
var _intro: Array[String] = []
var _pending_key: String = ""
var _pending_text: String = ""
var _current_key: String = ""

func reset() -> void:
	intro_active = false
	_intro.clear()
	_pending_key = ""
	_pending_text = ""
	_current_key = ""
	sequence_key = ""
	line_index = 0
	elapsed = 0.0
	_mode = "idle"
	text = ""
	modulate.a = 0.0

func begin_intro(sentences: Array[String]) -> void:
	reset()
	_intro = sentences.duplicate()
	intro_active = not _intro.is_empty()
	if intro_active:
		_start_line(_intro[0])

## Coalesce frequent network refreshes while preserving the visible line's fade.
func present(key: String, message: String) -> void:
	if sequence_key == key and (_pending_text == message or (text == message and _pending_key.is_empty())):
		return
	sequence_key = key
	_pending_key = key
	_pending_text = message
	if not intro_active and _mode == "idle":
		_start_pending()

func skip() -> void:
	if intro_active:
		intro_active = false
		_intro.clear()
		_mode = "idle"
		text = ""
		modulate.a = 0.0
		_start_pending()
		intro_finished.emit()
	elif not _pending_key.is_empty():
		_start_pending()

func _process(delta: float) -> void:
	advance_clock(delta)

## Explicit clock supports deterministic animation checks without async timer races.
func advance_clock(delta: float) -> void:
	var remaining: float = maxf(delta, 0.0)
	while remaining > 0.0 and _mode != "idle":
		if _mode == "hold" and not intro_active and _pending_key.is_empty():
			elapsed = minf(elapsed + remaining, STATUS_HOLD)
			break
		var duration: float = FADE_IN
		match _mode:
			"hold": duration = maxf(2.7, float(text.length()) * 0.075) if intro_active else STATUS_HOLD
			"fade_out": duration = FADE_OUT
			"gap": duration = GAP
		var step: float = minf(remaining, maxf(duration - elapsed, 0.0))
		elapsed += step
		remaining -= step
		if elapsed + 0.000001 < duration:
			break
		elapsed = 0.0
		match _mode:
			"fade_in": _mode = "hold"
			"hold": _mode = "fade_out"
			"fade_out": _mode = "gap"
			"gap": _next_line()
	_update_alpha()

func _start_line(message: String) -> void:
	text = message
	elapsed = 0.0
	_mode = "fade_in"
	_update_alpha()

func _start_pending() -> void:
	_current_key = _pending_key
	var message: String = _pending_text
	_pending_key = ""
	_pending_text = ""
	if message.is_empty():
		text = ""
		_mode = "idle"
		modulate.a = 0.0
	else:
		_start_line(message)

func _next_line() -> void:
	if intro_active:
		line_index += 1
		if line_index < _intro.size():
			_start_line(_intro[line_index])
			return
		intro_active = false
		_intro.clear()
		_start_pending()
		intro_finished.emit()
	else:
		_start_pending()

func _update_alpha() -> void:
	match _mode:
		"idle", "gap": modulate.a = 0.0
		"fade_in": modulate.a = 1.0 if reduced_motion else smoothstep(0.0, FADE_IN, elapsed)
		"hold": modulate.a = 1.0
		"fade_out": modulate.a = 1.0 if reduced_motion else 1.0 - smoothstep(0.0, FADE_OUT, elapsed)
