class_name CameraRig
extends Camera2D
## One continuous, smooth camera from the whole continent down to a single soldier.
##
## Mouse:     drag to pan (it glides on when you let go), wheel to zoom at the
##            cursor, double-click to zoom in, right-click to give orders.
## Trackpad:  two-finger drag pans, pinch zooms (macOS sends these as gestures).
## Touch:     one finger pans, two fingers pinch, tap selects.
## Keyboard:  WASD / arrows pan, Q/E or -/= zoom.
## Zoom always eases toward its target and keeps the point under the cursor fixed.

signal tapped(world_pos: Vector2, screen_pos: Vector2)
signal right_tapped(world_pos: Vector2, screen_pos: Vector2)
signal hovered(world_pos: Vector2, screen_pos: Vector2)
signal zoom_changed(z: float)
## Dragging that starts on something the game wants to drag (e.g. your army).
signal drag_moved(world_pos: Vector2, screen_pos: Vector2)
signal drag_released(world_pos: Vector2, screen_pos: Vector2)

const MAX_ZOOM := 10.0
const TAP_SLOP := 8.0
const ZOOM_EASE := 14.0        # higher = snappier zoom easing
const GLIDE_FRICTION := 5.0    # how quickly a flung map slows down
const KEY_PAN_SPEED := 900.0   # screen pixels per second

var map_size := Vector2(2000, 2000)
var min_zoom := 0.3
var target_zoom := 0.4
## Called with the press position; return true to drag that thing instead of the map.
var drag_filter: Callable = Callable()

var _anchor_screen := Vector2.ZERO   # zoom keeps this screen point fixed...
var _anchor_world := Vector2.ZERO    # ...over this world point
var _anchored := false
var _glide_from := Vector2.ZERO
var _glide_to := Vector2.ZERO
var _glide_t := -1.0                 # < 0 when not gliding
var _glide_time := 0.6
var _velocity := Vector2.ZERO        # flung pan, in world units per second
var _last_moves: Array = []          # recent [time, screen delta] for fling speed

var _pressing := false
var _dragging_thing := false
var _press_pos := Vector2.ZERO
var _moved := false
var _touches := {}
var _pinch_dist := 0.0
var _pinch_mid := Vector2.ZERO
var _last_zoom := -1.0


func setup(size: Vector2) -> void:
	map_size = size
	var view := get_viewport_rect().size
	min_zoom = minf(view.x / (size.x + 200.0), view.y / (size.y + 200.0))
	zoom = Vector2.ONE * min_zoom
	target_zoom = min_zoom
	position = size * 0.5
	_glide_t = -1.0
	_velocity = Vector2.ZERO


func view_size() -> Vector2:
	return get_viewport_rect().size


func screen_to_world(p: Vector2) -> Vector2:
	return position + (p - view_size() * 0.5) / zoom.x


func world_to_screen(w: Vector2) -> Vector2:
	return (w - position) * zoom.x + view_size() * 0.5


## Glide smoothly to a place (and zoom level).
func focus(world_pos: Vector2, z: float) -> void:
	_glide_from = position
	_glide_to = world_pos
	_glide_t = 0.0
	_glide_time = clampf(position.distance_to(world_pos) / 1500.0, 0.35, 0.9)
	_anchored = false
	_velocity = Vector2.ZERO
	target_zoom = clampf(z, min_zoom, MAX_ZOOM)


## Zoom toward `screen_pos` by `factor`, eased over the next frames.
func zoom_toward(screen_pos: Vector2, factor: float) -> void:
	target_zoom = clampf(target_zoom * factor, min_zoom, MAX_ZOOM)
	_anchor_screen = screen_pos
	_anchor_world = screen_to_world(screen_pos)
	_anchored = true
	_glide_t = -1.0


func _set_zoom_keep(screen_pos: Vector2, world_pos: Vector2, z: float) -> void:
	var nz := clampf(z, min_zoom, MAX_ZOOM)
	zoom = Vector2.ONE * nz
	position = world_pos - (screen_pos - view_size() * 0.5) / nz
	_clamp()


func _pan(screen_delta: Vector2) -> void:
	position -= screen_delta / zoom.x
	_glide_t = -1.0
	_clamp()


func _clamp() -> void:
	position.x = clampf(position.x, -100.0, map_size.x + 100.0)
	position.y = clampf(position.y, -100.0, map_size.y + 100.0)


func _process(delta: float) -> void:
	# Glide to a focus point.
	if _glide_t >= 0.0:
		_glide_t = minf(_glide_t + delta / _glide_time, 1.0)
		var e := 1.0 - pow(1.0 - _glide_t, 3.0)   # ease out
		position = _glide_from.lerp(_glide_to, e)
		if _glide_t >= 1.0:
			_glide_t = -1.0
	# Fling: keep sliding after a drag, slowing down.
	if _velocity.length() > 5.0 and not _pressing:
		position += _velocity * delta
		_velocity *= exp(-GLIDE_FRICTION * delta)
		_clamp()
	# Keyboard panning.
	var dir := Vector2(
		Input.get_axis("ui_left", "ui_right") + float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		Input.get_axis("ui_up", "ui_down") + float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if dir != Vector2.ZERO:
		_pan(-dir.normalized() * KEY_PAN_SPEED * delta)
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_EQUAL):
		zoom_toward(view_size() * 0.5, 1.0 + 1.5 * delta)
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_MINUS):
		zoom_toward(view_size() * 0.5, 1.0 / (1.0 + 1.5 * delta))
	# Ease zoom toward its target.
	if absf(zoom.x - target_zoom) > 0.0002:
		var k := 1.0 - exp(-ZOOM_EASE * delta)
		var z := exp(lerpf(log(zoom.x), log(target_zoom), k))
		if _anchored:
			_set_zoom_keep(_anchor_screen, _anchor_world, z)
		else:
			_set_zoom_keep(view_size() * 0.5, screen_to_world(view_size() * 0.5), z)
	else:
		_anchored = false
	if absf(zoom.x - _last_zoom) > 0.0001:
		_last_zoom = zoom.x
		zoom_changed.emit(zoom.x)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
		else:
			_touches.erase(t.index)
		if _touches.size() == 2:
			_start_pinch()
		return
	if event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_touches[d.index] = d.position
		if _touches.size() >= 2:
			_update_pinch()
			_moved = true
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					# Trackpads send small fractional steps; mice send whole clicks.
					var steps := mb.factor if mb.factor > 0.0 else 1.0
					var f := pow(1.12, steps)
					zoom_toward(mb.position, f if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / f)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					if mb.double_click:
						zoom_toward(mb.position, 2.0)
					_pressing = true
					_moved = false
					_press_pos = mb.position
					_velocity = Vector2.ZERO
					_last_moves.clear()
					_dragging_thing = drag_filter.is_valid() and bool(drag_filter.call(mb.position))
				else:
					if _dragging_thing:
						drag_released.emit(screen_to_world(mb.position), mb.position)
					elif _pressing and not _moved and _touches.size() < 2:
						tapped.emit(screen_to_world(mb.position), mb.position)
					elif _moved:
						_velocity = _fling_velocity()
					_pressing = false
					_dragging_thing = false
			MOUSE_BUTTON_RIGHT:
				if not mb.pressed:
					right_tapped.emit(screen_to_world(mb.position), mb.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		hovered.emit(screen_to_world(mm.position), mm.position)
		if _pressing and _touches.size() < 2:
			if not _moved and mm.position.distance_to(_press_pos) > TAP_SLOP:
				_moved = true
			if _moved:
				if _dragging_thing:
					drag_moved.emit(screen_to_world(mm.position), mm.position)
				else:
					_pan(mm.relative)
					_last_moves.append([Time.get_ticks_msec(), mm.relative])
					if _last_moves.size() > 6:
						_last_moves.pop_front()
	elif event is InputEventMagnifyGesture:
		var g := event as InputEventMagnifyGesture
		# Pinch follows the fingers directly (no easing lag).
		var z := clampf(zoom.x * g.factor, min_zoom, MAX_ZOOM)
		_set_zoom_keep(g.position, screen_to_world(g.position), z)
		target_zoom = z
		_anchored = false
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		_velocity = Vector2.ZERO
		_pan(-pg.delta * 25.0)


## How fast the map was moving at the end of a drag (world units per second).
func _fling_velocity() -> Vector2:
	var now := Time.get_ticks_msec()
	var sum := Vector2.ZERO
	var first := now
	for m in _last_moves:
		if now - int(m[0]) <= 100:
			sum += m[1]
			first = mini(first, int(m[0]))
	var span := maxf((now - first) / 1000.0, 0.016)
	return -sum / span / zoom.x


func _start_pinch() -> void:
	var pts: Array = _touches.values()
	_pinch_dist = (pts[0] as Vector2).distance_to(pts[1])
	_pinch_mid = ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5
	_moved = true


func _update_pinch() -> void:
	var pts: Array = _touches.values()
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	var dist := a.distance_to(b)
	var mid := (a + b) * 0.5
	if _pinch_dist > 1.0:
		var z := clampf(zoom.x * dist / _pinch_dist, min_zoom, MAX_ZOOM)
		_set_zoom_keep(mid, screen_to_world(mid), z)
		target_zoom = z
	_pan(mid - _pinch_mid)
	_pinch_dist = dist
	_pinch_mid = mid
