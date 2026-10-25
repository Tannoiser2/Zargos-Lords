class_name ZargosBoardData
extends RefCounted

var terrain: Dictionary = {}

func _init() -> void:
	# Nessun terreno fittizio: finché la scansione non è classificata esagono
	# per esagono, le caselle non annotate usano il costo normale.
	pass

func terrain_at(hex: Vector2i) -> ZargosRules.Terrain:
	return terrain.get(hex, ZargosRules.Terrain.PLAIN) as ZargosRules.Terrain

func defense_bonus_at(hex: Vector2i) -> int:
	return ZargosRules.defense_bonus(terrain_at(hex))

func set_terrain(hex: Vector2i, terrain_type: ZargosRules.Terrain) -> void:
	terrain[hex] = terrain_type

func find_movement_cost(start: Vector2i, goal: Vector2i, movement: int, flying: bool, occupied: Callable) -> int:
	return reachable_hexes(start, movement, flying, occupied).get(goal, -1) as int

func reachable_hexes(start: Vector2i, movement: int, flying: bool, occupied: Callable) -> Dictionary:
	var frontier: Array[Vector2i] = [start]
	var costs := {start: 0}
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		for neighbor in neighbors(current):
			if not is_on_board(neighbor):
				continue
			if neighbor != start and occupied.call(neighbor):
				continue
			var terrain_type := terrain_at(neighbor)
			var step_cost := ZargosRules.terrain_cost(terrain_type, flying)
			if step_cost < 0:
				continue
			if terrain_type == ZargosRules.Terrain.MOUNTAIN and not flying:
				step_cost = movement
			var new_cost: int = costs[current] + step_cost
			if new_cost > movement:
				continue
			if not costs.has(neighbor) or new_cost < costs[neighbor]:
				costs[neighbor] = new_cost
				# Entrare in un gorgo conclude sempre il movimento.
				if terrain_type != ZargosRules.Terrain.MAGIC_VORTEX:
					frontier.append(neighbor)
	return costs

static func neighbors(hex: Vector2i) -> Array[Vector2i]:
	var offsets_even: Array[Vector2i] = [Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1)]
	var offsets_odd: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	var output: Array[Vector2i] = []
	for offset in (offsets_odd if hex.x & 1 else offsets_even):
		output.append(hex + offset)
	return output

static func is_on_board(hex: Vector2i) -> bool:
	return hex.x >= 0 and hex.y >= 0 and hex.x < ZargosRules.BOARD_COLUMNS and hex.y < ZargosRules.BOARD_ROWS

