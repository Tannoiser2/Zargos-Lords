extends SceneTree

func _init() -> void:
	assert(ZargosRules.hex_distance(Vector2i(0, 0), Vector2i(0, 0)) == 0)
	assert(ZargosRules.hex_distance(Vector2i(3, 3), Vector2i(4, 3)) == 1)
	assert(ZargosRules.terrain_cost(ZargosRules.Terrain.FOREST) == 2)
	assert(ZargosRules.terrain_cost(ZargosRules.Terrain.SEA) == -1)
	assert(ZargosRules.defense_bonus(ZargosRules.Terrain.MOUNTAIN) == 3)
	assert(ZargosRules.resolve_combat(12, 5, 4).result == "D3")
	var state := ZargosGameState.new()
	for i in range(3): state.advance_phase()
	assert(state.active_faction() == &"Draghi")
	print("ZargosRules: tutti i test superati")
	quit()
