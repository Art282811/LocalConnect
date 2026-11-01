class_name CameraRig
extends Camera2D
## One continuous camera from the whole continent down to a single town.
## Mouse: drag to pan, wheel to zoom. Trackpad: pinch and two-finger pan.
## Touch: one finger pans, two fingers pinch. A short press without moving is a tap.

signal tapped(world_pos: Vector2, screen_pos: Vector2)
signal zoom_changed(z: float)

const MAX_ZOOM := 3.5
const TAP_SLOP := 10.0

var map_size := Vector2(2000, 2000)
var min_zoom := 0.3
var target_zoom := 0.4

var _dragging := false
var _press_pos := Vector2.ZERO
var _moved := false
var _touches := {}       # finger index -> screen position
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


func view_size() -> Vector2:
	return get_viewport_rect().size


func screen_to_world(p: Vector2) -> Vector2:
	return position + (p - view_size() * 0.5) / zoom.x


func focus(world_pos: Vector2, z: float) -> void:
	position = world_pos
	target_zoom = clampf(z, min_zoom, MAX_ZOOM)


## Direct zoom from input: jumps straight there, keeping `screen_pos` fixed.
func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	_apply_zoom(screen_pos, zoom.x * factor)
	target_zoom = zoom.x


func _apply_zoom(screen_pos: Vector2, z: float) -> void:
	var before := screen_to_world(screen_pos)
	var nz := clampf(z, min_zoom, MAX_ZOOM)
	zoom = Vector2.ONE * nz
	position = before - (screen_pos - view_size() * 0.5) / nz
	_clamp()


func _pan(screen_delta: Vector2) -> void:
	position -= screen_delta / zoom.x
	_clamp()


func _clamp() -> void:
	position.x = clampf(position.x, -100.0, map_size.x + 100.0)
	position.y = clampf(position.y, -100.0, map_size.y + 100.0)


func _process(delta: float) -> void:
	if absf(zoom.x - target_zoom) > 0.0005:
		_apply_zoom(view_size() * 0.5, lerpf(zoom.x, target_zoom, clampf(delta * 8.0, 0.0, 1.0)))
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
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_at(mb.position, 1.15)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_at(mb.position, 1.0 / 1.15)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_dragging = true
					_moved = false
					_press_pos = mb.position
				else:
					if _dragging and not _moved and _touches.size() < 2:
						tapped.emit(screen_to_world(mb.position), mb.position)
					_dragging = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging and _touches.size() < 2:
			if not _moved and mm.position.distance_to(_press_pos) > TAP_SLOP:
				_moved = true
			if _moved:
				_pan(mm.relative)
	elif event is InputEventMagnifyGesture:
		var g := event as InputEventMagnifyGesture
		_zoom_at(g.position, g.factor)
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		_pan(-pg.delta * 12.0)


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
		_zoom_at(mid, dist / _pinch_dist)
	_pan(mid - _pinch_mid)
	_pinch_dist = dist
	_pinch_mid = mid
