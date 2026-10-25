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
	game._set_grid_visible(true)
	assert(game.grid_overlay.visible)
	var old_camera_position: Vector3 = game.camera_rig.position
	game._pan_camera(Vector2(40, 25))
	assert(game.camera_rig.position != old_camera_position)
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
	game.queue_free()
	await process_frame
	var observer = packed.instantiate()
	root.add_child(observer)
	await process_frame
	assert(observer.faction_controller_selectors.size() == 4)
	for selector in observer.faction_controller_selectors.values():
		selector.select(1)
	observer._start_menu_game()
	observer.ai_enabled = false
	assert(observer.human_faction == &"")
	assert(observer.state.factions.size() == 4)
	assert(not observer.deployment_mode)
	print("Snapshot online: serializzazione e ripristino superati")
	quit()
