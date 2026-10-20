extends Control
## Presentation only. Rules and private network snapshots live in separate layers.
const SessionScript = preload("res://scripts/session/game_session.gd")
const INK = Color("#0a111d")
const PANEL = Color("#141f2e")
const PAPER = Color("#eee5d5")
const MUTED = Color("#9aa8bc")
const GOLD = Color("#d6a36f")
const LINE = Color("#334052")
const TEAL = Color("#96c6ba")
const ROLES = {"wolf":"狼人", "seer":"预言家", "villager":"村民"}
const ROLE_COPY = {
	"wolf":"藏好身份，在夜色中选择猎物。\n让狼人数量不小于好人，即可获胜。",
	"seer":"每夜查验一名玩家的阵营。\n把真相带回白天，帮助好人找到狼人。",
	"villager":"你没有夜间技能，但拥有关键的一票。\n聆听发言，找出所有狼人。"
}
const PHASES = {"reveal":"身份揭晓", "night":"长夜降临", "dawn":"天光初现", "discussion":"围炉讨论", "vote":"放逐投票", "vote_result":"投票结果", "ended":"终局揭晓", "lobby":"等待入席", "connecting":"正在连接"}
var session: Node
var page = "home"
var root_box: VBoxContainer
var shade: ColorRect
var view: Dictionary = {}
var local_count = 6
var local_names: Array = ["旅人一", "旅人二", "旅人三", "旅人四", "旅人五", "旅人六", "旅人七", "旅人八"]
var nickname = "旅人"
var address = "192.168.1.100"
var port_value = "24567"
var authorized_viewer = -1
var authorized_phase = ""
var peek_identity = false
var role_visible = false
var selected_target = -2
var error_text = ""
var notice_label: Label
var modal: Control
var font: Font
var title_font: Font
var last_phase = ""
# Local presentation preference only; never included in a network snapshot.
var visual_style = "moonveil"
var background_art: TextureRect
var moonveil_title_font: Font
var geometry_title_font: FontVariation

func _is_geometry() -> bool:
	return visual_style == "geometry"

func _is_dark_stage() -> bool:
	return page == "game" and str(view.get("phase", "")) in ["night", "reveal"]

func _tone(c: Color) -> Color:
	if not _is_geometry() or c.a == 0.0: return c
	var dark = _is_dark_stage()
	if c.is_equal_approx(PAPER): return Color("#f7f0df") if dark else Color("#202f41")
	if c.is_equal_approx(INK): return Color("#202f41")
	if c.is_equal_approx(MUTED): return Color("#c2cbd0") if dark else Color("#52616a")
	if c.is_equal_approx(GOLD): return Color("#efa878") if dark else Color("#b64934")
	if c.is_equal_approx(TEAL): return Color("#a9d4bf") if dark else Color("#386759")
	if c.is_equal_approx(Color("#e9ad99")): return Color("#f1af95") if dark else Color("#a13c2c")
	if c.is_equal_approx(LINE): return Color("#52687a") if dark else Color("#c6bba5")
	if c.get_luminance() < 0.30:
		return Color("#293b50") if dark else Color("#fff9ed")
	if c.get_luminance() < 0.50:
		return Color("#63717c") if dark else Color("#c6bba5")
	return c

func _set_visual_style(value: String, persist: bool = true) -> void:
	visual_style = value if value in ["moonveil", "geometry"] else "moonveil"
	if persist:
		var settings = ConfigFile.new()
		settings.set_value("presentation", "style", visual_style)
		var result = settings.save("user://presentation.cfg")
		if result != OK: push_warning("Could not save visual preference: %s" % result)
	_render()


func _ready() -> void:
	font = load("res://assets/fonts/NotoSansSC-Regular.otf")
	title_font = load("res://assets/fonts/MoonveilSerif.otf")
	title_font.fallbacks = [font]
	moonveil_title_font = title_font
	geometry_title_font = FontVariation.new()
	geometry_title_font.base_font = font
	geometry_title_font.variation_embolden = 0.7
	var settings = ConfigFile.new()
	if settings.load("user://presentation.cfg") == OK:
		var saved = str(settings.get_value("presentation", "style", "moonveil"))
		visual_style = saved if saved in ["moonveil", "geometry"] else "moonveil"
	_apply_theme()
	session = SessionScript.new()
	session.name = "GameSession"
	add_child(session)
	session.view_changed.connect(_on_view)
	session.error_occurred.connect(_on_error)
	var art = TextureRect.new()
	background_art = art
	art.texture = load("res://assets/art/background.svg")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	move_child(art, 0)
	shade = ColorRect.new()
	shade.color = Color(0.025, 0.045, 0.075, 0.18)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_render()

func _apply_theme() -> void:
	var t = Theme.new()
	t.default_font = font
	t.default_font_size = 18
	t.set_color("font_color", "Label", _tone(PAPER))
	t.set_color("font_color", "Button", _tone(PAPER))
	t.set_color("font_hover_color", "Button", _tone(PAPER))
	t.set_color("font_pressed_color", "Button", _tone(PAPER))
	t.set_color("font_disabled_color", "Button", Color("#657185"))
	t.set_color("font_color", "LineEdit", _tone(PAPER))
	t.set_color("font_placeholder_color", "LineEdit", _tone(MUTED))
	t.set_stylebox("normal", "LineEdit", _style(Color("#101a29"), LINE, 9, 16))
	t.set_stylebox("focus", "LineEdit", _style(Color("#162236"), GOLD, 9, 16))
	t.set_constant("caret_width", "LineEdit", 2)
	t.set_color("caret_color", "LineEdit", _tone(GOLD))
	t.set_constant("separation", "VBoxContainer", 14)
	t.set_constant("separation", "HBoxContainer", 14)
	t.set_constant("h_separation", "GridContainer", 14)
	t.set_constant("v_separation", "GridContainer", 14)
	t.set_color("font_color", "CheckBox", _tone(PAPER))
	theme = t

func _style(bg: Color, border: Color = Color.TRANSPARENT, radius: int = 12, pad: int = 20) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = _tone(bg)
	s.border_color = _tone(border)
	s.set_border_width_all(1 if border.a > 0 else 0)
	s.set_corner_radius_all(2 if _is_geometry() else radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s

func _label(text: String, size_px: int = 18, color: Color = PAPER, parent: Node = null) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", _tone(color))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if parent: parent.add_child(l)
	return l

func _title(text: String, size_px: int, parent: Node) -> Label:
	var l = _label(text, size_px, PAPER, parent)
	l.add_theme_font_override("font", title_font)
	return l

func _button(text: String, callback: Callable, primary: bool = false, minimum: Vector2 = Vector2(0, 52)) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = minimum
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("normal", _style(GOLD if primary else Color("#192536"), Color.TRANSPARENT if primary else LINE, 9, 14))
	b.add_theme_stylebox_override("hover", _style(Color("#e9ba86") if primary else Color("#26354b"), GOLD, 9, 14))
	b.add_theme_stylebox_override("pressed", _style(Color("#b98959") if primary else Color("#121c2d"), GOLD, 9, 14))
	b.add_theme_stylebox_override("disabled", _style(Color("#17202e"), Color("#293344"), 9, 14))
	b.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, PAPER, 9, 14))
	if _is_geometry():
		b.add_theme_stylebox_override("normal", _style(Color("#eda17c") if primary else PANEL, INK, 2, 14))
		b.add_theme_stylebox_override("hover", _style(Color("#f3bb98") if primary else Color("#e8d8b9"), GOLD, 2, 14))
		b.add_theme_stylebox_override("pressed", _style(Color("#de8b64") if primary else PANEL, GOLD, 2, 14))
		b.add_theme_color_override("font_hover_color", INK)
		b.add_theme_color_override("font_disabled_color", Color("#788287"))
	if primary:
		b.add_theme_color_override("font_color", INK)
		b.add_theme_color_override("font_hover_color", INK)
		b.add_theme_color_override("font_pressed_color", INK)
	b.pressed.connect(callback)
	return b

func _panel(parent: Node, bg: Color = PANEL, border: Color = LINE, padding: int = 24) -> VBoxContainer:
	var p = PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(bg, border, 16, padding))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var v = VBoxContainer.new()
	p.add_child(v)
	return v

func _row(parent: Node, gap: int = 14) -> HBoxContainer:
	var r = HBoxContainer.new()
	r.add_theme_constant_override("separation", gap)
	parent.add_child(r)
	return r

func _spacer(parent: Node, vertical: bool = true) -> Control:
	var c = Control.new()
	if vertical: c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else: c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(c)
	return c

func _chip(text: String, parent: Node, color: Color = GOLD) -> void:
	var p = PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(Color(color, 0.08), Color(color, 0.3), 18, 10))
	parent.add_child(p)
	var l = _label(text, 14, color, p)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF

func _field(label_text: String, value: String, changed: Callable, parent: Node, placeholder: String = "") -> LineEdit:
	_label(label_text, 15, MUTED, parent)
	var e = LineEdit.new()
	e.text = value
	e.placeholder_text = placeholder
	e.custom_minimum_size.y = 54
	e.max_length = 32
	e.text_changed.connect(changed)
	parent.add_child(e)
	return e

func _navigate(next: String) -> void:
	page = next
	error_text = ""
	_render()

func _render() -> void:
	title_font = geometry_title_font if _is_geometry() else moonveil_title_font
	_apply_theme()
	if is_instance_valid(background_art):
		var backdrop = "res://assets/art/geometric/backdrop_night.svg" if _is_dark_stage() else "res://assets/art/geometric/backdrop_day.svg"
		background_art.texture = load(backdrop if _is_geometry() else "res://assets/art/background.svg")
	if is_instance_valid(root_box):
		root_box.get_parent().queue_free()
		remove_child(root_box.get_parent())
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 25)
	add_child(margin)
	root_box = VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 24)
	margin.add_child(root_box)
	shade.color.a = 0.0 if _is_geometry() else (0.12 if page == "home" else 0.68)
	_header()
	match page:
		"home": _home()
		"local": _local_setup()
		"host", "join": _network_setup()
		"rules": _rules_page()
		"game": _game()
	notice_label = _label(error_text, 15, Color("#e9ad99"), root_box)
	notice_label.visible = not error_text.is_empty()
	_footer()
	root_box.modulate.a = 0.0
	create_tween().tween_property(root_box, "modulate:a", 1.0, 0.20)

func _header() -> void:
	var r = _row(root_box)
	var mark = _label("◈", 32, GOLD, r)
	mark.custom_minimum_size.x = 35
	mark.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var brand = _title("月隐镇", 27, r)
	brand.autowrap_mode = TextServer.AUTOWRAP_OFF
	brand.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var small = _label("IDENTITY PARTY", 12, MUTED, r)
	small.autowrap_mode = TextServer.AUTOWRAP_OFF
	small.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_spacer(r, false)
	if page == "home":
		r.add_child(_button("风格：几何剧场" if _is_geometry() else "风格：月夜原版", func(): _set_visual_style("moonveil" if _is_geometry() else "geometry"), false, Vector2(180,44)))
		_chip("4–8 人  ·  身份推理", r)
		r.add_child(_button("游戏指南", func(): _navigate("rules"), false, Vector2(122, 44)))
	else:
		var route = "狼人杀 / " + (PHASES.get(str(view.get("phase", "")), "游戏房间") if page == "game" else {"local":"同屏开局", "host":"创建房间", "join":"加入房间", "rules":"游戏指南"}.get(page, ""))
		_label(route, 15, MUTED, r)
		r.add_child(_button("离开房间" if page == "game" else "返回大厅", _request_leave if page == "game" else func(): _navigate("home"), false, Vector2(120, 44)))

func _home() -> void:
	if _is_geometry():
		_geometry_home()
		return
	var hero = HBoxContainer.new()
	hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(hero)
	var left = VBoxContainer.new()
	left.custom_minimum_size.x = 650
	left.add_theme_constant_override("separation", 18)
	hero.add_child(left)
	_spacer(left)
	_label("第一章  /  狼人杀", 17, GOLD, left)
	_title("月色之下，\n谁在说谎？", 68, left)
	_label("一场关于直觉、伪装与信任的夜谈。\n邀上朋友，走进月隐镇。天黑之后，故事才刚刚开始。", 19, MUTED, left)
	var actions = _row(left, 12)
	actions.add_child(_button("创建房间  →", func(): _navigate("host"), true, Vector2(210, 60)))
	actions.add_child(_button("加入房间", func(): _navigate("join"), false, Vector2(165, 60)))
	var sub = _row(left)
	sub.add_child(_button("同屏传递 · 开始一局", func(): _navigate("local"), false, Vector2(240, 48)))
	_label("无需账号  /  面对面也能玩", 14, MUTED, sub)
	_spacer(left)
	_spacer(hero, false)
	var side = VBoxContainer.new()
	side.custom_minimum_size.x = 185
	hero.add_child(side)
	_spacer(side)
	var quote = _label("每个人都有故事。\n有些人，还有秘密。", 17, Color("#c1cad7"), side)
	quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label("—  MOONVEIL CHRONICLES", 10, MUTED, side).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var cards = _row(root_box, 16)
	for role in ["wolf", "seer", "villager"]:
		var v = _panel(cards, Color(0.055, 0.09, 0.14, 0.88), Color("#354153"), 18)
		var r = _row(v, 18)
		var art = _role_art(role, Vector2(92, 116))
		r.add_child(art)
		var text_box = VBoxContainer.new()
		text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(text_box)
		_label({"wolf":"01  /  暗夜阵营", "seer":"02  /  好人阵营", "villager":"03  /  好人阵营"}[role], 12, GOLD, text_box)
		_title(ROLES[role], 25, text_box)
		_label({"wolf":"隐匿于人群，等待夜幕。", "seer":"凝视迷雾，追寻真相。", "villager":"相信线索，也相信直觉。"}[role], 15, MUTED, text_box)

func _section_header(eyebrow: String, title: String, desc: String) -> void:
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	root_box.add_child(v)
	_label(eyebrow, 13, GOLD, v)
	_title(title, 36, v)
	_label(desc, 17, MUTED, v)

func _preset_text(count: int) -> String:
	var wolves = 2 if count >= 7 else 1
	return "%d 狼人  ·  1 预言家  ·  %d 村民" % [wolves, count - wolves - 1]

func _local_setup() -> void:
	_section_header("PASS & PLAY", "围坐一桌，秘密入席", "所有人共用一台设备。查看身份与夜间行动时，请把屏幕交给对应玩家。")
	var bar = _row(root_box)
	_label("入席人数", 19, PAPER, bar)
	for n in range(4, 9):
		bar.add_child(_button(str(n) + " 人", func(): local_count = n; _render(), n == local_count, Vector2(85, 46)))
	_spacer(bar, false)
	_chip("本地同屏", bar, TEAL)
	var grid = GridContainer.new()
	grid.columns = 4
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(grid)
	for i in range(local_count):
		var v = _panel(grid, Color("#131e2e"), LINE, 20)
		_label("%02d  /  玩家" % (i + 1), 13, GOLD, v)
		var line = LineEdit.new()
		line.text = local_names[i]
		line.max_length = 12
		line.custom_minimum_size = Vector2(160, 48)
		line.text_changed.connect(func(t: String): local_names[i] = t)
		v.add_child(line)
		_label("身份将在开局后秘密分配", 13, MUTED, v)
	var bottom = _panel(root_box, Color("#192537"), Color("#46505e"), 20)
	var r = _row(bottom, 24)
	var copy = VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(copy)
	_label(_preset_text(local_count), 20, PAPER, copy)
	_label("4 人体验局首夜平安；其余人数首夜正常行动。" if local_count == 4 else "夜间全员依次操作，白天公开讨论。讨论后由当前持机人推进。", 14, MUTED, copy)
	r.add_child(_button("分配身份，开始游戏  →", _start_local, true, Vector2(280, 60)))

func _start_local() -> void:
	var names: Array = []
	for i in range(local_count):
		var n = str(local_names[i]).strip_edges()
		names.append(n if not n.is_empty() else "旅人" + str(i + 1))
	authorized_viewer = -1
	peek_identity = false
	session.start_local(names)

func _network_setup() -> void:
	var hosting = page == "host"
	_section_header("LOCAL NETWORK", "为朋友点亮一盏灯" if hosting else "赴一场月下之约", "连接同一个局域网。由一人创建房间，其他人通过房主的 IP 地址加入。")
	var layout = _row(root_box, 28)
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var form = _panel(layout, Color("#131e2e"), LINE, 30)
	form.get_parent().custom_minimum_size.x = 555
	_field("你的昵称", nickname, func(t): nickname = t, form)
	if not hosting:
		_field("房主的局域网 IP", address, func(t): address = t, form, "例如 192.168.1.8")
	var port = _field("端口", port_value, func(t): port_value = t, form)
	port.max_length = 5
	_label("默认 24567 · 房主与其他玩家须使用同一端口", 13, MUTED, form)
	_spacer(form)
	form.add_child(_button("创建房间  →" if hosting else "连接房间  →", _connect_network.bind(hosting), true, Vector2(0, 58)))
	var info = _panel(layout, Color(0.055, 0.09, 0.14, 0.65), LINE, 30)
	_title("让相聚更简单", 28, info)
	for entry in [
		["01", "连接同一网络", "每位玩家在自己的电脑上打开项目。"],
		["02", "分享房间地址", "房主的局域网 IP 会显示在等候室中。"],
		["03", "准备好，再入夜", "4–8 人全部准备后，房主即可开始。"]
	]:
		_label(entry[0] + "  " + entry[1], 19, GOLD, info)
		_label(entry[2], 16, MUTED, info)
	_spacer(info)
	_label("当前版本支持局域网直连。无公网匹配、语音或断线重连。\n发言请使用面对面交流或你们已有的语音工具。", 14, MUTED, info)

func _connect_network(hosting: bool) -> void:
	if not port_value.is_valid_int() or int(port_value) < 1024 or int(port_value) > 65535:
		_on_error("请输入 1024–65535 之间的有效端口。")
		return
	if nickname.strip_edges().is_empty():
		_on_error("请先填写昵称。")
		return
	page = "game"
	var err = session.host_lan(nickname.strip_edges(), int(port_value)) if hosting else session.join_lan(nickname.strip_edges(), address.strip_edges(), int(port_value))
	if err != OK:
		page = "host" if hosting else "join"
		_render()

func _rules_page() -> void:
	_section_header("HOW TO PLAY", "把真相留到天亮", "轻量版狼人杀。没有法官，也能完成一整局。")
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(scroll)
	var columns = _row(scroll, 20)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var left = _panel(columns)
	_title("一夜，一日，一次选择", 26, left)
	for s in [
		"01  秘密查看身份\n狼人知道队友；预言家与村民只知道自己。",
		"02  夜间行动\n狼人各自选猎物；预言家查验阵营；村民确认休息。",
		"03  天亮与讨论\n公布昨夜的离场者，存活玩家交流线索。",
		"04  放逐投票\n每名存活玩家一票，可以弃票。唯一最高票离场。"
	]: _label(s, 17, MUTED, left)
	var right = _panel(columns)
	_title("约定好的规则", 26, right)
	_label("好人：所有狼人离场即获胜。\n狼人：存活狼人数量不少于好人即获胜。", 18, PAPER, right)
	_label("4 人：1 狼人 + 1 预言家 + 2 村民，首夜平安。\n5–6 人：1 狼人 + 1 预言家，其余村民。\n7–8 人：2 狼人 + 1 预言家，其余村民。", 17, MUTED, right)
	_label("白天平票或全员弃票：无人离场，进入下一夜。\n狼人意见不一：最高票目标中取座次靠前者。\n夜间不能选择自己；狼人不能袭击队友。\n离场者身份直到终局才公开。", 16, MUTED, right)
	_label("4 人局是快速体验规则，推理空间较小；推荐 6–8 人。\n本版没有女巫、猎人、警长或遗言阶段。", 14, GOLD, right)
	var r = _row(root_box)
	_spacer(r, false)
	r.add_child(_button("我知道了，开始相聚  →", func(): _navigate("home"), true, Vector2(300, 54)))

func _on_view(snapshot: Dictionary) -> void:
	view = snapshot
	var phase = str(view.get("phase", ""))
	if phase != last_phase:
		selected_target = -2
		authorized_viewer = -1
		role_visible = false
		last_phase = phase
		peek_identity = false
	if session.mode == "none":
		page = "home"
	elif page != "game":
		page = "game"
	if session.mode == "local" and phase in ["reveal", "night", "vote"] and not peek_identity:
		var pending: Array = session.pending_local_ids()
		if not pending.is_empty() and not pending.has(session.self_id):
			authorized_viewer = -1
			session.set_local_viewer(int(pending[0]))
			return
	_render()

func _on_error(message: String) -> void:
	error_text = message
	if is_instance_valid(notice_label):
		notice_label.text = message
		notice_label.show()

func _game() -> void:
	var phase = str(view.get("phase", "connecting"))
	if phase == "lobby":
		_lobby()
		return
	if phase in ["connecting", ""]:
		_section_header("CONNECTING", "正在寻找房间…", "请确认房主已创建房间，并与你使用相同的 IP 与端口。")
		_spacer(root_box)
		root_box.add_child(_button("取消连接", _leave))
		return
	if phase == "ended":
		_ending()
		return
	if phase == "reveal" and session.mode == "lan" and view.get("submitted_ids", []).has(session.self_id):
		_section_header("A SECRET KEPT", "身份已收好，静候入夜", "等待其他玩家确认身份。你的身份卡已经隐藏。")
		_spacer(root_box)
		_label("已确认 %d / %d" % [view.get("submitted_ids", []).size(), view.get("players", []).size()], 24, GOLD, root_box)
		return
	if peek_identity or (phase in ["reveal", "night", "vote"] and session.mode == "local") or phase == "reveal":
		if authorized_viewer != session.self_id or authorized_phase != phase:
			_handoff()
			return
	if peek_identity or phase == "reveal":
		_identity()
		return
	_match_board()

func _lobby() -> void:
	var players: Array = view.get("players", [])
	_section_header("THE GATHERING", "夜尚未深，等你入席", "每个人准备好后，由房主开始游戏。")
	var info = _row(root_box)
	_chip("%d / 8 人已入席" % players.size(), info, TEAL)
	_chip("局域网房间", info)
	_spacer(info, false)
	_label("房间地址  " + str(view.get("address", address)) + ":" + str(view.get("port", port_value)), 17, PAPER, info)
	var grid = GridContainer.new()
	grid.columns = 4
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(grid)
	for i in range(8):
		var v = _panel(grid, Color("#131e2e") if i < players.size() else Color(0.05,0.08,0.12,0.55), LINE, 20)
		_label("%02d  /  座位" % (i + 1), 12, GOLD if i < players.size() else MUTED, v)
		if i < players.size():
			var p: Dictionary = players[i]
			_title(str(p.name), 25, v)
			var text = "已准备" if p.get("ready", false) else "等待准备"
			if int(p.id) == 1: text += " · 房主"
			if int(p.id) == session.self_id: text += " · 你"
			_label(text, 14, TEAL if p.get("ready", false) else MUTED, v)
		else:
			_title("待入席", 25, v).modulate.a = 0.4
			_label("等待朋友加入", 14, MUTED, v)
	var r = _row(root_box, 18)
	var details = VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(details)
	_label(_preset_text(players.size()) if players.size() >= 4 else "至少需要 4 位玩家", 19, PAPER, details)
	_label(str(view.get("status", "")), 14, MUTED, details)
	var ready = false
	var all_ready = players.size() >= 4
	for p in players:
		if int(p.id) == session.self_id: ready = p.get("ready", false)
		if not p.get("ready", false): all_ready = false
	r.add_child(_button("取消准备" if ready else "我准备好了", func(): session.set_ready(not ready), not ready, Vector2(180, 58)))
	if session.is_host:
		var start = _button("开始游戏  →", func(): session.start_match(), true, Vector2(190,58))
		start.disabled = not all_ready
		r.add_child(start)

func _handoff() -> void:
	var player_name = _player_name(session.self_id)
	var center = CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(center)
	var v = _panel(center, Color("#111d2e"), Color("#536071"), 42)
	v.get_parent().custom_minimum_size = Vector2(660, 440)
	_label("PRIVATE MOMENT", 13, GOLD, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _is_geometry(): v.add_child(_geometry_image("privacy", Vector2(0, 80)))
	_title("请将屏幕交给", 28, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title(player_name, 48, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label("确认周围没有其他人观看后，再揭开你的秘密。\n本页不显示任何身份或行动信息。", 17, MUTED, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spacer(v)
	v.add_child(_button("我是「%s」，查看秘密  →" % player_name, func(): authorized_viewer = session.self_id; authorized_phase = str(view.get("phase", "")); _render(), true, Vector2(0, 62)))
	if peek_identity: v.add_child(_button("返回公共讨论", _close_peek))

func _role_art(role: String, minimum: Vector2) -> TextureRect:
	var img = TextureRect.new()
	img.texture = load(("res://assets/art/geometric/role_%s.svg" if _is_geometry() else "res://assets/art/role_%s.svg") % role)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.custom_minimum_size = minimum
	return img

func _identity() -> void:
	var role = str(view.get("your_role", "villager"))
	var body = _row(root_box, 38)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var art_panel = _panel(body, Color("#101b2b"), Color("#665c54"), 12)
	art_panel.get_parent().custom_minimum_size.x = 400
	var art = _role_art(role, Vector2(360, 400))
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art_panel.add_child(art)
	var info = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 20)
	body.add_child(info)
	_spacer(info)
	_label("%s  /  仅你可见" % _player_name(session.self_id), 15, GOLD, info)
	_title("你是，" + ROLES.get(role, "村民"), 46, info)
	_chip("狼人阵营" if role == "wolf" else "好人阵营", _row(info), GOLD if role == "wolf" else TEAL)
	_label(ROLE_COPY.get(role, ""), 20, MUTED, info)
	if role == "wolf" and not view.get("your_allies", []).is_empty():
		var names = PackedStringArray()
		for id in view.your_allies: names.append(_player_name(int(id)))
		_label("你的狼队友：" + "、".join(names), 18, GOLD, info)
	_private_notes(info)
	_spacer(info)
	info.add_child(_button("收起秘密，返回讨论  →" if peek_identity else "记住身份，收起卡牌  →", _close_peek if peek_identity else func(): _submit_action("reveal_ack"), true, Vector2(0, 62)))
	_label("请勿截屏或向其他玩家展示此页。", 13, MUTED, info)

func _private_notes(parent: Node) -> void:
	var notes: Array = view.get("your_notes", [])
	if notes.is_empty(): return
	var v = _panel(parent, Color("#182b36"), Color("#426166"), 18)
	_label("你的查验记录", 15, TEAL, v)
	for note in notes.slice(maxi(0, notes.size()-4)):
		_label(str(note), 16, PAPER, v)

func _match_board() -> void:
	var phase = str(view.phase)
	var top = _row(root_box, 12)
	for pair in [["night", "01 夜晚"], ["dawn", "02 天亮"], ["discussion", "03 讨论"], ["vote", "04 投票"]]:
		var current = phase == pair[0] or (phase == "vote_result" and pair[0] == "vote")
		_chip(pair[1], top, GOLD if current else MUTED)
	_spacer(top, false)
	_label("第 %d 夜 / 第 %d 天" % [int(view.get("round", 1)), int(view.get("round",1))], 16, MUTED, top)
	var body = _row(root_box, 24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var side = _panel(body, Color("#121d2c"), LINE, 25)
	side.get_parent().custom_minimum_size.x = 280
	side.get_parent().size_flags_horizontal = Control.SIZE_FILL
	_label("MOONVEIL", 12, GOLD, side)
	_title(PHASES.get(phase, phase), 30, side)
	_label(_phase_description(phase), 16, MUTED, side)
	var alive = 0
	for p in view.get("players", []):
		if p.get("alive", true): alive += 1
	_label("%d / %d 位玩家存活" % [alive, view.get("players", []).size()], 18, PAPER, side)
	_spacer(side)
	if session.mode == "lan":
		side.add_child(_button("收起身份" if role_visible else "查看我的身份", func(): role_visible = not role_visible; _render(), false, Vector2(0, 48)))
		if role_visible:
			_label("你的身份 · " + ROLES.get(str(view.get("your_role", "")), "未知"), 19, GOLD, side)
			_private_notes(side)
	elif phase == "discussion":
		side.add_child(_button("私密查阅身份 / 记录", _choose_peek, false, Vector2(0,52)))
	if phase in ["night", "vote"]:
		_label("已提交 %d / %d" % [view.get("submitted_ids", []).size(), alive], 14, TEAL, side)
	else:
		_label("公共画面 · 可供全员查看", 13, TEAL, side)
	var main = VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 18)
	body.add_child(main)
	if phase in ["night", "vote"]:
		_action_board(main)
	else:
		_public_board(main)

func _phase_description(phase: String) -> String:
	return {
		"night":"天黑请闭眼。\n每位存活玩家在自己的回合秘密行动。",
		"dawn":"夜色褪去，\n小镇迎来新的清晨。",
		"discussion":"轮流发言，交换线索。\n发言结束后，房主开启投票。" if session.mode == "lan" else "轮流发言，交换线索。\n发言结束后，持机人开启投票。",
		"vote":"相信你的判断。\n投票提交后不可修改。",
		"vote_result":"小镇已经作出选择。\n准备好迎接下一个夜晚。"
	}.get(phase, "")

func _action_board(parent: Node) -> void:
	var phase = str(view.phase)
	var role = str(view.get("your_role", "villager"))
	var mine: Dictionary = _player(session.self_id)
	var submitted = view.get("submitted_ids", []).has(session.self_id)
	if not mine.get("alive", true) or submitted:
		var v = _panel(parent)
		v.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
		_title("静候天明" if phase == "night" else "等待投票结束", 34, v)
		_label("你已提交，本轮选择已锁定。" if submitted else "你已离场，可以继续观察局势。请不要透露游戏信息。", 19, MUTED, v)
		_roster(v, false)
		return
	var title = "选择你要放逐的玩家" if phase == "vote" else {"wolf":"选择今晚的猎物", "seer":"选择你要查验的玩家", "villager":"今晚，请安心休息"}.get(role, "夜间行动")
	_label("%s  /  仅你可见" % _player_name(session.self_id), 14, GOLD, parent)
	_title(title, 30, parent)
	if phase == "night" and role == "villager":
		var r = _row(parent, 28)
		r.size_flags_vertical = Control.SIZE_EXPAND_FILL
		r.add_child(_role_art("villager", Vector2(220,290)))
		var v = VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(v)
		_spacer(v)
		_label("闭上眼睛，听见风穿过森林。\n你的力量，留在明天的讨论与投票中。", 21, MUTED, v)
		_spacer(v)
		parent.add_child(_button("确认休息，结束回合  →", func(): _submit_action("night_action", -1), true, Vector2(0,58)))
		return
	if phase == "night" and role == "seer": _private_notes(parent)
	if phase == "night" and role == "wolf":
		_label("狼人不可袭击队友。多人意见不一致时，按票数与座次结算。", 14, MUTED, parent)
	_roster(parent, true)
	var r = _row(parent)
	if phase == "vote":
		r.add_child(_button("弃票" + ("  ✓" if selected_target == -1 else ""), func(): selected_target = -1; _render(), selected_target == -1, Vector2(120,54)))
	_spacer(r, false)
	var text = "确认放逐票" if phase == "vote" else ("确认查验" if role == "seer" else "确认袭击")
	var confirm = _button(text + "  →", func(): _submit_action("vote" if phase == "vote" else "night_action", selected_target), true, Vector2(230,56))
	confirm.disabled = selected_target == -2
	r.add_child(confirm)

func _roster(parent: Node, selectable: bool) -> void:
	var grid = GridContainer.new()
	grid.columns = 4
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(grid)
	var index = 0
	for p in view.get("players", []):
		index += 1
		var alive = p.get("alive", true)
		var id = int(p.id)
		var allied = view.get("your_allies", []).has(id)
		var allowed = alive and id != session.self_id
		if str(view.get("phase", "")) == "night" and str(view.get("your_role", "")) == "wolf" and allied: allowed = false
		var is_selected = selected_target == id
		var box = PanelContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.custom_minimum_size = Vector2(155, 135)
		box.add_theme_stylebox_override("panel", _style(Color("#2b3540") if is_selected else Color("#172334"), GOLD if is_selected else LINE, 13, 16))
		grid.add_child(box)
		var v = VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(v)
		var status = "存活" if alive else "已离场"
		if id == session.self_id: status += " · 你"
		if allied and str(view.get("phase", "")) == "night": status += " · 队友"
		_label("%02d  /  %s" % [index, status], 12, TEAL if alive else MUTED, v)
		if _is_geometry():
			# Public-seat portraits never derive from a hidden identity.
			v.add_child(_geometry_image("seat_%d" % ((index - 1) % 4), Vector2(0, 44)))
		_label(str(p.name), 20, PAPER if alive else MUTED, v)
		if view.get("phase", "") == "ended":
			_label(ROLES.get(str(p.get("role", "")), "未知"), 14, GOLD, v)
		elif selectable and allowed:
			var b = _button("已选择  ✓" if is_selected else "选择", func(): selected_target = id; _render(), is_selected, Vector2(0,36))
			b.add_theme_font_size_override("font_size", 14)
			v.add_child(b)
		elif selectable:
			_label("不可选择", 13, MUTED, v)
		if not alive: box.modulate.a = 0.55

func _public_board(parent: Node) -> void:
	var phase = str(view.phase)
	var result = str(view.get("last_result", ""))
	_title("让每个人说完，再作判断。" if phase == "discussion" else (result if not result.is_empty() else PHASES.get(phase, "")), 29, parent)
	if phase == "discussion":
		_label("建议按座次发言，每人 30–60 秒。预言家可在私密记录中查看查验结果。", 15, MUTED, parent)
	_roster(parent, false)
	var events: Array = view.get("events", [])
	if not events.is_empty():
		var record = _panel(parent, Color("#101b29"), LINE, 15)
		_label("小镇纪事", 12, GOLD, record)
		for event in events.slice(maxi(0, events.size()-2)):
			_label(str(event), 14, MUTED, record)
	var r = _row(parent)
	_spacer(r, false)
	if session.is_host or session.mode == "local":
		var text = {"dawn":"进入白天讨论", "discussion":"结束讨论，开始投票", "vote_result":"天黑，请闭眼"}.get(phase, "继续")
		r.add_child(_button(text + "  →", func(): authorized_viewer = -1; session.advance(), true, Vector2(290,58)))
	else:
		_label("等待房主推进阶段…", 17, MUTED, r)

func _submit_action(action: String, target: int = -1) -> void:
	authorized_viewer = -1
	selected_target = -2
	session.submit(action, target)

func _choose_peek() -> void:
	_show_modal("谁要查阅秘密？", "仅对应玩家可操作。查阅结束后，请收起秘密再交回设备。", [])
	var list = modal.get_meta("content") as VBoxContainer
	for p in view.get("players", []):
		list.add_child(_button(str(p.name), func(): _dismiss_modal(); peek_identity = true; authorized_viewer = -1; session.set_local_viewer(int(p.id))))
	list.add_child(_button("取消", _dismiss_modal))

func _close_peek() -> void:
	peek_identity = false
	authorized_viewer = -1
	_render()

func _ending() -> void:
	var village = str(view.get("winner", "")) == "village"
	_section_header("THE FINAL REVEAL", "晨光终至，好人获胜" if village else "长夜未尽，狼人获胜", "所有秘密都已揭晓。谢谢你们，一起完成这段月下故事。")
	_roster(root_box, false)
	var r = _row(root_box, 22)
	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(box)
	_label(str(view.get("last_result", "")), 18, PAPER, box)
	_label("可回看最终身份，再开始新的一局。", 15, MUTED, box)
	r.add_child(_button("回到大厅", _leave, false, Vector2(150,58)))
	if session.is_host or session.mode == "local":
		r.add_child(_button("再来一局  →" if session.mode == "local" else "返回等候室  →", func(): authorized_viewer = -1; session.rematch(), true, Vector2(220,58)))
	else:
		_label("等待房主开启下一局", 16, MUTED, r)

func _player(id: int) -> Dictionary:
	for p in view.get("players", []):
		if int(p.id) == id: return p
	return {}

func _player_name(id: int) -> String:
	return str(_player(id).get("name", "旅人"))

func _request_leave() -> void:
	_show_modal("要离开这场夜谈吗？", "离开会结束当前本地游戏。联机局中任何玩家离开，本局都会终止并返回等候室。", [
		["继续游戏", _dismiss_modal, false],
		["确认离开", func(): _dismiss_modal(); _leave(), true]
	])

func _show_modal(title: String, text: String, actions: Array) -> void:
	_dismiss_modal()
	modal = ColorRect.new()
	modal.color = Color(0.015,0.025,0.045,0.93)
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var v = _panel(center, PANEL, LINE, 30)
	v.get_parent().custom_minimum_size.x = 600
	v.get_parent().custom_minimum_size.y = 280
	_title(title, 29, v)
	_label(text, 17, MUTED, v)
	_spacer(v)
	modal.set_meta("content", v)
	for action in actions: v.add_child(_button(action[0], action[1], action[2]))

func _dismiss_modal() -> void:
	if is_instance_valid(modal):
		modal.queue_free()
		remove_child(modal)
	modal = null

func _leave() -> void:
	peek_identity = false
	authorized_viewer = -1
	role_visible = false
	session.leave()
	page = "home"
	_render()

func _footer() -> void:
	var r = _row(root_box)
	_label("月隐镇  /  几何剧场 · GEOMETRIC THEATRE" if _is_geometry() else "月隐镇  /  狼人杀", 12, MUTED, r)
	_spacer(r, false)
	_label("面对面的相聚，各自心中的秘密。", 12, MUTED, r)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if is_instance_valid(modal): _dismiss_modal()
		elif peek_identity: _close_peek()
		elif page == "game": _request_leave()
		elif page != "home": _navigate("home")


func _geometry_image(asset: String, minimum: Vector2) -> TextureRect:
	var image = TextureRect.new()
	image.texture = load("res://assets/art/geometric/%s.svg" % asset)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = minimum
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image

func _geometry_home() -> void:
	var hero = _row(root_box, 36)
	hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var copy = VBoxContainer.new()
	copy.custom_minimum_size.x = 610
	copy.add_theme_constant_override("separation", 17)
	hero.add_child(copy)
	_spacer(copy)
	_label("ACT 01   /   几何剧场", 15, GOLD, copy)
	_title("每张面孔，\n都有另一面。", 63, copy)
	_label("一场关于直觉、伪装与信任的游戏。\n圆形、方形、三角形。相同的座位，不同的秘密。", 19, MUTED, copy)
	var actions = _row(copy, 12)
	actions.add_child(_button("创建房间  →", func(): _navigate("host"), true, Vector2(210,60)))
	actions.add_child(_button("加入房间", func(): _navigate("join"), false, Vector2(165,60)))
	var sub = _row(copy)
	sub.add_child(_button("同屏传递 · 开始一局", func(): _navigate("local"), false, Vector2(240,48)))
	_label("4–8 人 / 无需账号", 14, MUTED, sub)
	_spacer(copy)
	var stage = _geometry_image("ensemble", Vector2(480, 340))
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero.add_child(stage)
	var cards = _row(root_box, 16)
	for role in ["wolf", "seer", "villager"]:
		var card = _panel(cards, PANEL, LINE, 16)
		var row = _row(card, 18)
		row.add_child(_role_art(role, Vector2(82, 110)))
		var words = VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(words)
		_label({"wolf":"01 / 伪装", "seer":"02 / 洞察", "villager":"03 / 信任"}[role], 12, GOLD, words)
		_title(ROLES[role], 26, words)
		_label({"wolf":"在沉默中，藏住锋芒。", "seer":"换个角度，看见真相。", "villager":"每一次选择，都有分量。"}[role], 15, MUTED, words)
