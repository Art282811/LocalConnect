class_name Hud
extends CanvasLayer
## Mobile-first HUD built in code: top bar (date, realm, speed), news feed,
## info panel with action buttons, spawn prompt, chronicle and game-over panels.

signal speed_chosen(speed: float)
signal steward_toggled(on: bool)
signal spectate_pressed
signal new_world_pressed
signal rise_again_pressed
signal realm_pressed
signal battle_alert_pressed

const SPEEDS := [0.0, 0.25, 1.0, 2.0, 4.0]

const INK := Color(0.24, 0.16, 0.09)
const PARCHMENT := Color(0.94, 0.89, 0.76, 0.95)
const FEED_SIZE := 5
const FEED_SECONDS := 14.0

var date_label: Label
var resource_panel: PanelContainer
var resource_text: RichTextLabel
var realm_button: Button
var battle_button: Button
var realm_label: Label
var speed_buttons: Array[Button] = []
var steward_button: Button
var feed: VBoxContainer
var info_panel: PanelContainer
var info_title: Label
var info_body: RichTextLabel
var info_actions: HFlowContainer
var spawn_panel: PanelContainer
var log_panel: PanelContainer
var log_text: RichTextLabel
var over_panel: PanelContainer


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)

	_build_top_bar(root)
	_build_feed(root)
	_build_info(root)
	_build_spawn(root)
	_build_log(root)
	_build_game_over(root)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	var panel := StyleBoxFlat.new()
	panel.bg_color = PARCHMENT
	panel.border_color = INK
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(10)
	t.set_stylebox("panel", "PanelContainer", panel)

	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.85, 0.76, 0.58)
	btn.border_color = INK
	btn.set_border_width_all(2)
	btn.set_corner_radius_all(5)
	btn.content_margin_left = 14
	btn.content_margin_right = 14
	btn.content_margin_top = 8
	btn.content_margin_bottom = 8
	var hover := btn.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.90, 0.81, 0.63)
	var pressed := btn.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.66, 0.36, 0.24)
	var disabled := btn.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.8, 0.76, 0.68)
	disabled.border_color = Color(INK, 0.4)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		t.set_color(c, "Button", INK)
	t.set_color("font_pressed_color", "Button", Color(0.98, 0.94, 0.85))
	t.set_color("font_hover_pressed_color", "Button", Color(0.98, 0.94, 0.85))
	t.set_color("font_disabled_color", "Button", Color(INK, 0.45))
	t.set_color("font_color", "Label", INK)
	t.set_color("default_color", "RichTextLabel", INK)
	return t


func _button(text: String, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(52, 44)
	parent.add_child(b)
	return b


func _build_top_bar(root: Control) -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)

	date_label = Label.new()
	date_label.custom_minimum_size.x = 250
	row.add_child(date_label)
	realm_label = Label.new()
	realm_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	realm_label.clip_text = true
	row.add_child(realm_label)

	var group := ButtonGroup.new()
	battle_button = _button("Battle!", row)
	battle_button.add_theme_color_override("font_color", Color(0.6, 0.08, 0.05))
	battle_button.pressed.connect(func() -> void: battle_alert_pressed.emit())
	battle_button.visible = false

	var labels := ["II", "¼", "1x", "2x", "4x"]
	for i in labels.size():
		var b := _button(labels[i], row)
		b.toggle_mode = true
		b.button_group = group
		var speed: float = SPEEDS[i]
		b.pressed.connect(func() -> void: speed_chosen.emit(speed))
		speed_buttons.append(b)

	realm_button = _button("Realm", row)
	realm_button.pressed.connect(func() -> void: realm_pressed.emit())
	realm_button.visible = false

	steward_button = _button("Steward", row)
	steward_button.toggle_mode = true
	steward_button.tooltip_text = "Let the AI run your realm's wars and armies"
	steward_button.toggled.connect(func(on: bool) -> void: steward_toggled.emit(on))

	var log_btn := _button("Chronicle", row)
	log_btn.pressed.connect(_toggle_log)

	resource_panel = PanelContainer.new()
	resource_panel.position = Vector2(10, 66)
	resource_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resource_panel.visible = false
	root.add_child(resource_panel)
	resource_text = RichTextLabel.new()
	resource_text.bbcode_enabled = true
	resource_text.fit_content = true
	resource_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	resource_text.scroll_active = false
	resource_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resource_text.add_theme_font_size_override("normal_font_size", 16)
	resource_text.add_theme_font_size_override("bold_font_size", 16)
	resource_panel.add_child(resource_text)


func _build_feed(root: Control) -> void:
	feed = VBoxContainer.new()
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed.position = Vector2(10, 116)
	feed.custom_minimum_size = Vector2(440, 0)
	feed.add_theme_constant_override("separation", 4)
	root.add_child(feed)


func _build_info(root: Control) -> void:
	info_panel = PanelContainer.new()
	info_panel.anchor_left = 0.0
	info_panel.anchor_top = 1.0
	info_panel.anchor_right = 0.0
	info_panel.anchor_bottom = 1.0
	info_panel.offset_left = 10
	info_panel.offset_right = 520
	info_panel.offset_bottom = -10
	info_panel.offset_top = -10
	info_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	info_panel.visible = false
	root.add_child(info_panel)
	var col := VBoxContainer.new()
	info_panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	info_title = Label.new()
	info_title.add_theme_font_size_override("font_size", 24)
	info_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info_title)
	var close := _button("X", head)
	close.pressed.connect(hide_info)
	info_body = RichTextLabel.new()
	info_body.bbcode_enabled = true
	info_body.fit_content = true
	info_body.scroll_active = false
	info_body.custom_minimum_size.x = 480
	col.add_child(info_body)
	info_actions = HFlowContainer.new()
	col.add_child(info_actions)


func _build_spawn(root: Control) -> void:
	spawn_panel = PanelContainer.new()
	spawn_panel.anchor_left = 0.5
	spawn_panel.anchor_right = 0.5
	spawn_panel.offset_top = 70
	spawn_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(spawn_panel)
	var col := VBoxContainer.new()
	spawn_panel.add_child(col)
	var title := Label.new()
	title.text = "Pick your spawn"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var hint := Label.new()
	hint.text = "Tap any province. Unclaimed land: found a new realm there.\nOwned land: take the throne of that realm. Pinch or scroll to zoom."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	_button("Just watch", row).pressed.connect(func() -> void: spectate_pressed.emit())
	_button("New world", row).pressed.connect(func() -> void: new_world_pressed.emit())


func _build_log(root: Control) -> void:
	log_panel = PanelContainer.new()
	log_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	log_panel.offset_left = 60
	log_panel.offset_right = -60
	log_panel.offset_top = 70
	log_panel.offset_bottom = -20
	log_panel.visible = false
	root.add_child(log_panel)
	var col := VBoxContainer.new()
	log_panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := Label.new()
	title.text = "Chronicle of the realms"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_button("Close", head).pressed.connect(_toggle_log)
	log_text = RichTextLabel.new()
	log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_text.scroll_following = true
	col.add_child(log_text)


func _build_game_over(root: Control) -> void:
	over_panel = PanelContainer.new()
	over_panel.set_anchors_preset(Control.PRESET_CENTER)
	over_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	over_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	over_panel.visible = false
	root.add_child(over_panel)
	var col := VBoxContainer.new()
	over_panel.add_child(col)
	var title := Label.new()
	title.text = "Your realm has fallen"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var body := Label.new()
	body.text = "The world goes on without you."
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	_button("Rise again", row).pressed.connect(_on_rise_again)
	_button("Keep watching", row).pressed.connect(_on_keep_watching)


func _on_rise_again() -> void:
	over_panel.visible = false
	show_spawn(true)
	rise_again_pressed.emit()


func _on_keep_watching() -> void:
	over_panel.visible = false
	spectate_pressed.emit()


# --- Public API used by main.gd ---------------------------------------------

func set_date(text: String) -> void:
	date_label.text = text


func set_realm_text(text: String) -> void:
	realm_label.text = text


func set_speed(speed: float) -> void:
	var idx := SPEEDS.find(speed)
	if idx >= 0:
		speed_buttons[idx].set_pressed_no_signal(true)


## Shows the treasury row; pass "" to hide it (no realm of your own).
func set_resources(bbcode: String) -> void:
	resource_panel.visible = bbcode != ""
	realm_button.visible = bbcode != ""
	if bbcode != "":
		resource_text.text = bbcode
		resource_panel.reset_size()


func set_battle_alert(text: String) -> void:
	battle_button.visible = text != ""
	battle_button.text = text


func set_steward(on: bool) -> void:
	steward_button.set_pressed_no_signal(on)


func show_spawn(on: bool) -> void:
	spawn_panel.visible = on


func show_game_over() -> void:
	over_panel.visible = true


func add_news(text: String) -> void:
	var item := PanelContainer.new()
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size.x = 420
	lbl.add_theme_font_size_override("font_size", 16)
	item.add_child(lbl)
	feed.add_child(item)
	feed.move_child(item, 0)
	while feed.get_child_count() > FEED_SIZE:
		var old := feed.get_child(feed.get_child_count() - 1)
		feed.remove_child(old)
		old.queue_free()
	var tw := item.create_tween()
	tw.tween_interval(FEED_SECONDS)
	tw.tween_property(item, "modulate:a", 0.0, 1.5)
	tw.tween_callback(item.queue_free)


func refresh_log(lines: Array[String]) -> void:
	if log_panel.visible:
		log_text.text = "\n".join(PackedStringArray(lines))


func _toggle_log() -> void:
	log_panel.visible = not log_panel.visible


func show_info(title: String, body: String, actions: Array) -> void:
	## actions: Array of [label: String, callback: Callable, enabled: bool]
	info_title.text = title
	info_body.text = body
	for c in info_actions.get_children():
		info_actions.remove_child(c)
		c.queue_free()
	for act in actions:
		var b := _button(act[0], info_actions)
		b.pressed.connect(act[1])
		if act.size() > 2:
			b.disabled = not act[2]
	info_panel.visible = true
	# Shrink to fit the new content.
	info_panel.reset_size()


func hide_info() -> void:
	info_panel.visible = false


func is_log_open() -> bool:
	return log_panel.visible


func update_info_body(body: String) -> void:
	if info_panel.visible:
		info_body.text = body
