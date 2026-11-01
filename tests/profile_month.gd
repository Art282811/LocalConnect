extends SceneTree
## Times the pieces of the monthly update.

func _init() -> void:
	World.set_year_length(720)
	var w := World.new()
	w.setup(777)
	w.spectate()
	for d in 3 * World.DAYS_PER_YEAR:
		w._update_battles(Battle.SECONDS_PER_DAY)
		w.tick_day()
	var t := {"recruit": 0, "strategy": 0, "diplomacy": 0, "religion": 0, "dynasty": 0, "trade": 0}
	var n := 6
	for i in n:
		var s := Time.get_ticks_usec()
		for r: Realm in w.realms:
			if r.alive:
				r.manpower = minf(r.manpower + w.economy.monthly_manpower(r), w.economy.manpower_cap(r))
				w._recruit(r, not r.is_player)
		t["recruit"] += Time.get_ticks_usec() - s
		s = Time.get_ticks_usec(); w.strategy.monthly(); t["strategy"] += Time.get_ticks_usec() - s
		s = Time.get_ticks_usec(); w.diplomacy.monthly(); t["diplomacy"] += Time.get_ticks_usec() - s
		s = Time.get_ticks_usec(); w.religion.monthly(); t["religion"] += Time.get_ticks_usec() - s
		s = Time.get_ticks_usec(); w.dynasty.monthly(); t["dynasty"] += Time.get_ticks_usec() - s
		s = Time.get_ticks_usec(); w.trade.monthly(); t["trade"] += Time.get_ticks_usec() - s
	for k in t:
		print("%-10s %8.1f ms per month" % [k, t[k] / 1000.0 / n])
	quit()
