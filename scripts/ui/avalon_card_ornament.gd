extends Control
## Engraved heraldry, entirely decorative and click-through.
var selected := false
var leader := false
var proposed := false
var ballot := -1
var reduced_motion := false
var reveal_age := 5.0
var hover_amount := 0.0
var hover_tween: Tween
var seal: Texture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(not reduced_motion and reveal_age < .35)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if ResourceLoader.exists("res://assets/art/avalon_oath.svg"):
		seal = load("res://assets/art/avalon_oath.svg")

func set_hover(value: bool) -> void:
	set_process(not reduced_motion)
	if is_instance_valid(hover_tween): hover_tween.kill()
	if reduced_motion:
		hover_amount = 1.0 if value else 0.0
		queue_redraw()
	else:
		hover_tween = create_tween()
		hover_tween.tween_property(self, "hover_amount", 1.0 if value else 0.0, .22).set_trans(Tween.TRANS_SINE)

func _process(delta: float) -> void:
	if not reduced_motion: reveal_age += delta
	queue_redraw()
	if reveal_age >= .35 and (not is_instance_valid(hover_tween) or not hover_tween.is_running()):
		set_process(false)

func _draw() -> void:
	var gold := Color("#d9bb79")
	var dim := Color(gold, .25 + hover_amount * .35)
	var w := size.x
	var h := size.y
	# Open corner etching, not another heavy frame around the portrait.
	for sign_x in [-1, 1]:
		for sign_y in [-1, 1]:
			var p := Vector2(7 if sign_x == 1 else w-7, 7 if sign_y == 1 else h-7)
			draw_polyline(PackedVector2Array([p+Vector2(0,sign_y*12), p, p+Vector2(sign_x*12,0)]), dim, 1.0, true)
	if leader:
		var center := Vector2(w*.5, 4)
		var crown := PackedVector2Array([center+Vector2(-13,3),center+Vector2(-16,-5),center+Vector2(-7,0),center+Vector2(0,-9),center+Vector2(7,0),center+Vector2(16,-5),center+Vector2(13,3)])
		draw_colored_polygon(crown, Color("#132c32"))
		crown.append(crown[0])
		draw_polyline(crown, Color(gold,.85),1.1,true)
		draw_circle(center+Vector2(0,-7),1.5,gold,true,-1,true)
	if selected or proposed or ballot >= 0:
		var point := Vector2(w-23, h*.49)
		if seal != null:
			var stamp := 1.0 if reduced_motion else 1.0 + .28 * clampf(1-reveal_age/.35,0,1)
			var extent := Vector2(28,28)*stamp
			var tint := Color(1,1,1,.95 if selected else .55)
			if ballot >= 0: tint = Color("#a1d8c9") if ballot == 1 else Color("#d18b9d")
			draw_texture_rect(seal,Rect2(point-extent*.5,extent),false,tint)
		else:
			draw_circle(point,9,Color(gold,.3),true,-1,true)
			draw_arc(point,10,0,TAU,32,gold,1,true)
