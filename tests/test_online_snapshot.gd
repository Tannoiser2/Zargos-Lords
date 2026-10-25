extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var game = packed.instantiate()
	root.add_child(game)
	await process_frame
	game._start_new_game(2, 0)
	await process_frame
	var snapshot: Dictionary = game._make_online_snapshot()
	assert(snapshot.factions.size() == 2)
	assert(snapshot.units.size() == 16)
	assert(snapshot.cities.size() == 24)
	game.state.month = 7
	game._apply_online_snapshot(snapshot)
	assert(game.state.month == 1)
	var unit_count := 0
	var city_count := 0
	for child in game.get_children():
		if child is CardboardUnit:
			unit_count += 1
		elif child is CardboardCity:
			city_count += 1
	assert(unit_count == 16)
	assert(city_count == 24)
	print("Snapshot online: serializzazione e ripristino superati")
	quit()
