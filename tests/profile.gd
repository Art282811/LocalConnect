extends SceneTree
## Times each part of the daily simulation. Warms up for some years first.
## Run: godot --headless --path . --script res://tests/profile.gd -- [warmup_years] [profile_days]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var warm := int(args[0]) if args.size() > 0 else 2
	var days := int(args[1]) if args.size() > 1 else 360
	World.set_year_length(720)
	var w := World.new()
	w.setup(777)
	w.spectate()
	for d in warm * World.DAYS_PER_YEAR:
		w._update_battles(Battle.SECONDS_PER_DAY)
		w.tick_day()
	var t := {}
	var parts := ["battles", "move", "resolve", "occupy", "economy", "winter", "ai", "monthly", "seasonal"]
	for p in parts:
		t[p] = 0
	for d in days:
		var s := Time.get_ticks_usec()
		w._update_battles(Battle.SECONDS_PER_DAY)
		t["battles"] += Time.get_ticks_usec() - s
		w.day += 1
		s = Time.get_ticks_usec(); w._move_armies(); t["move"] += Time.get_ticks_usec() - s
		s = Time.get_ticks_usec(); w._resolve_battles(); t["resolve"] += Time.get_ticks_usec() - s
		s = Time.get_ticks_usec(); w._progress_occupations(); t["occupy"] += Time.get_ticks_usec() - s
		s = Time.get_ticks_usec(); w.economy.tick_day(); t["economy"] += Time.get_ticks_usec() - s
		s = Time.get_ticks_usec()
		if w.season() == 3:
			w._winter_attrition()
		t["winter"] += Time.get_ticks_usec() - s
		s = Time.get_ticks_usec()
		for r: Realm in w.realms:
			if r.alive and (r.id + w.day) % 5 == 0:
				w._ai_think(r)
		w.strategy.daily()
		t["ai"] += Time.get_ticks_usec() - s
		s = Time.get_ticks_usec()
		if w.day % 30 == 0:
			w._monthly()
		t["monthly"] += Time.get_ticks_usec() - s
		s = Time.get_ticks_usec()
		if w.day % World.DAYS_PER_SEASON == 0:
			w._seasonal()
		t["seasonal"] += Time.get_ticks_usec() - s
	var total := 0
	for p in parts:
		total += int(t[p])
	print("armies %d, battles now %d, routes %d, realms %d" % [w.armies.size(), w.battles.size(), w.trade.routes.size(), w.realms.size()])
	for p in parts:
		print("%-9s %7.2f ms/day  %4.1f%%" % [p, t[p] / 1000.0 / days, 100.0 * t[p] / maxf(total, 1)])
	print("TOTAL     %7.2f ms/day  (%.0f days/s)" % [total / 1000.0 / days, days * 1000000.0 / maxf(total, 1)])
	quit()
