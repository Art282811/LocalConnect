class_name Settings
extends RefCounted
## Player preferences, kept in user://settings.cfg between sessions.

const PATH := "user://settings.cfg"
const UI_SCALES := [1.0, 1.2, 1.4]
const UI_SCALE_NAMES := ["Normal", "Large", "Huge"]

static var music := true
static var sfx := true
static var ui_scale_index := 0
static var tutorial_done := false
static var autosave := true
static var pace_index := 1
const PACES := [360, 720, 1080]
const PACE_NAMES := ["Brisk (9 min a year at 1x)", "Normal (18 min a year at 1x)", "Epic (27 min a year at 1x)"]


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	music = bool(cfg.get_value("audio", "music", true))
	sfx = bool(cfg.get_value("audio", "sfx", true))
	ui_scale_index = clampi(int(cfg.get_value("display", "ui_scale", 0)), 0, UI_SCALES.size() - 1)
	tutorial_done = bool(cfg.get_value("game", "tutorial_done", false))
	autosave = bool(cfg.get_value("game", "autosave", true))
	pace_index = clampi(int(cfg.get_value("game", "pace", 1)), 0, PACES.size() - 1)


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music)
	cfg.set_value("audio", "sfx", sfx)
	cfg.set_value("display", "ui_scale", ui_scale_index)
	cfg.set_value("game", "tutorial_done", tutorial_done)
	cfg.set_value("game", "autosave", autosave)
	cfg.set_value("game", "pace", pace_index)
	cfg.save(PATH)


static func year_days() -> int:
	return int(PACES[pace_index])


static func ui_scale() -> float:
	return float(UI_SCALES[ui_scale_index])
