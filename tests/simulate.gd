extends SceneTree
## Plays a world with no human for N years and prints a yearly report.
## Run: godot --headless --path . --script res://tests/simulate.gd -- [years] [seed]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var years := int(args[0]) if args.size() > 0 else 20
	var seed_value := int(args[1]) if args.size() > 1 else 12345
	World.set_year_length(720)
	var w := World.new()
	var t0 := Time.get_ticks_msec()
	w.setup(seed_value)
	print("setup: %d ms, %d provinces, %d realms, %d people" % [Time.get_ticks_msec() - t0, w.provinces.size(), w.realms.size(), w.dynasty.people.size()])
	w.spectate()
	var battles := [0]
	w.battle_ended.connect(func(_b: Battle) -> void: battles[0] += 1)
	var news := {}
	w.news_posted.connect(func(text: String, _i: int) -> void:
		for key in ["declares war", "has fallen", "Peace between", "Rebels", "peasants", "Coup", "Civil war", "calls the", "Royal wedding", "inherits", "founds the", "Bandits", "agree", "excommunicates"]:
			if text.contains(key):
				news[key] = int(news.get(key, 0)) + 1
	)
	t0 = Time.get_ticks_msec()
	for d in years * World.DAYS_PER_YEAR:
		w._update_battles(Battle.SECONDS_PER_DAY)
		w.tick_day()
		if w.day % World.DAYS_PER_YEAR == 0:
			_report(w, battles[0])
	print("simulated %d years in %.1f s" % [years, (Time.get_ticks_msec() - t0) / 1000.0])
	print("events: ", news)
	# Save / load round trip.
	if SaveGame.save(w, "user://test_save.json"):
		var back := SaveGame.load_world("user://test_save.json")
		print("save/load: ", "OK" if back != null and back.day == w.day and back.realms.size() == w.realms.size() else "MISMATCH")
	quit()


func _report(w: World, battles: int) -> void:
	var alive := 0
	var biggest: Realm = null
	var starving := 0
	var broke := 0
	var gold := 0.0
	for r: Realm in w.realms:
		if not r.alive:
			continue
		alive += 1
		gold += float(r.res["gold"])
		if r.starving:
			starving += 1
		if r.broke:
			broke += 1
		if biggest == null or r.provinces.size() > biggest.provinces.size():
			biggest = r
	var troops := 0
	for a: Army in w.armies:
		if not a.dead:
			troops += a.troops
	var people := 0
	for c: Character in w.dynasty.people:
		if c.alive():
			people += 1
	# Where the gold comes from and goes (average per realm per day).
	var tax := 0.0
	var trade := 0.0
	var upkeep := 0.0
	var mood := 0.0
	var owned := 0
	var miserable := 0
	var causes := {}
	for r: Realm in w.realms:
		if not r.alive:
			continue
		trade += w.diplomacy.trade_income(r.id) + w.trade.income(r.id)
		for a: Army in w.armies_of(r.id):
			upkeep += a.troops * Economy.SOLDIER_UPKEEP
	for p: Province in w.provinces:
		if p.owner == -1:
			continue
		owned += 1
		tax += float(w.economy.yields(p)["gold"])
		mood += p.happiness
		if p.happiness < 20.0:
			miserable += 1
			for part in w.economy.happiness_parts(p):
				if float(part[1]) < 0.0:
					causes[part[0]] = int(causes.get(part[0], 0)) + 1
	var kinds := {"joined": 0, "holy": 0, "uprising": 0, "chosen": 0}
	for war in w.wars:
		var attacker := w.realms[int(war["a"])]
		if not (war.get("for", []) as Array).is_empty():
			kinds["joined"] += 1
		elif war.get("holy", false):
			kinds["holy"] += 1
		elif w.day - attacker.founded_day < 400:
			kinds["uprising"] += 1
		else:
			kinds["chosen"] += 1
	print("     wars by kind: ", kinds)
	var n := maxf(alive, 1)
	print("     gold/day per realm: taxes %.1f trade %.1f upkeep -%.1f | mood avg %d, miserable %d/%d %s" % [tax / n, trade / n, upkeep / n, int(mood / maxf(owned, 1)), miserable, owned, causes])
	var postures := {}
	for rid in w.strategy.minds:
		if not w.realms[int(rid)].alive:
			continue
		var p: String = w.strategy.minds[rid]["posture"]
		postures[p] = int(postures.get(p, 0)) + 1
	print("Y%-3d realms %-3d biggest %s (%d) unclaimed %-3d wars %-2d battles %-4d troops %-6d avg gold %-6d starving %d broke %d routes %d people %d postures %s" % [
		w.year(), alive, biggest.name, biggest.provinces.size(), w.unclaimed_count(), w.wars.size(), battles,
		troops, int(gold / maxf(alive, 1)), starving, broke, w.trade.routes.size(), people, postures])
