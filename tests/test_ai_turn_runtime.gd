extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.faction_controllers = {
		&"Cavalieri": "ai", &"Draghi": "human", &"Alati": "off", &"Monaci": "off",
	}
	game.human_faction = &"Draghi"
	var factions: Array[StringName] = [&"Cavalieri", &"Draghi"]
	game._launch_game(factions)
	game.deployment_mode = false
	game.ai_enabled = true
	var started := Time.get_ticks_msec()
	await game._run_ai_turn()
	var elapsed := Time.get_ticks_msec() - started
	assert(elapsed < 5000, "Il turno IA deve terminare senza bloccare l'interfaccia")
	assert(game.state.active_faction() == &"Draghi")
	print("Turno IA completo in %d ms con %d pedine" % [elapsed, game._units_for_faction(&"Cavalieri").size()])
	quit()
