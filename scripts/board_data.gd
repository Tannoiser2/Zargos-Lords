class_name ZargosBoardData
extends RefCounted

var terrain: Dictionary = {}

func _init() -> void:
	# Prima passata verificata sulla scansione: acqua e spazi marroni esterni.
	# Gli esagoni non ancora annotati restano pianura fino alla passata manuale.
	var sea_hexes: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(2, 0), Vector2i(13, 0), Vector2i(23, 0), Vector2i(28, 0), Vector2i(35, 0),
		Vector2i(1, 1), Vector2i(14, 1), Vector2i(24, 1), Vector2i(14, 2), Vector2i(14, 4), Vector2i(16, 4),
		Vector2i(20, 4), Vector2i(17, 5), Vector2i(19, 5), Vector2i(17, 6), Vector2i(35, 6), Vector2i(16, 8),
		Vector2i(3, 9), Vector2i(27, 9), Vector2i(29, 9), Vector2i(0, 10), Vector2i(2, 10), Vector2i(3, 10),
		Vector2i(13, 10), Vector2i(18, 10), Vector2i(20, 10), Vector2i(21, 10), Vector2i(24, 10), Vector2i(25, 10),
		Vector2i(27, 10), Vector2i(30, 10), Vector2i(31, 10), Vector2i(33, 10), Vector2i(4, 11), Vector2i(8, 11),
		Vector2i(12, 11), Vector2i(22, 11), Vector2i(25, 11), Vector2i(26, 11), Vector2i(30, 11), Vector2i(34, 11),
		Vector2i(4, 12), Vector2i(5, 12), Vector2i(7, 12), Vector2i(12, 12), Vector2i(22, 12), Vector2i(6, 13),
		Vector2i(10, 13), Vector2i(11, 13), Vector2i(20, 13), Vector2i(22, 13), Vector2i(19, 16), Vector2i(13, 18),
		Vector2i(16, 18), Vector2i(16, 19), Vector2i(12, 20), Vector2i(35, 20), Vector2i(12, 21), Vector2i(0, 22),
		Vector2i(1, 22), Vector2i(3, 22), Vector2i(13, 22), Vector2i(35, 22), Vector2i(1, 23), Vector2i(2, 23),
		Vector2i(11, 23), Vector2i(13, 23), Vector2i(23, 23),
	]
	for hex in sea_hexes:
		terrain[hex] = ZargosRules.Terrain.SEA
	var void_hexes: Array[Vector2i] = [
		Vector2i(14, 0), Vector2i(15, 0), Vector2i(16, 0), Vector2i(17, 0), Vector2i(18, 0), Vector2i(19, 0), Vector2i(20, 0), Vector2i(21, 0),
		Vector2i(16, 1), Vector2i(17, 1), Vector2i(18, 1), Vector2i(19, 1), Vector2i(20, 1),
		Vector2i(16, 2), Vector2i(17, 2), Vector2i(18, 2), Vector2i(19, 2), Vector2i(20, 2),
		Vector2i(18, 3), Vector2i(19, 3), Vector2i(18, 4),
		Vector2i(15, 21), Vector2i(16, 21), Vector2i(17, 21), Vector2i(19, 21), Vector2i(20, 21),
		Vector2i(15, 22), Vector2i(16, 22), Vector2i(17, 22), Vector2i(18, 22), Vector2i(19, 22), Vector2i(20, 22), Vector2i(21, 22),
		Vector2i(14, 23), Vector2i(15, 23), Vector2i(16, 23), Vector2i(17, 23), Vector2i(18, 23), Vector2i(19, 23), Vector2i(20, 23), Vector2i(21, 23),
	]
	for hex in void_hexes:
		terrain[hex] = ZargosRules.Terrain.VOID

func terrain_at(hex: Vector2i) -> ZargosRules.Terrain:
	return terrain.get(hex, ZargosRules.Terrain.PLAIN) as ZargosRules.Terrain

func defense_bonus_at(hex: Vector2i) -> int:
	return ZargosRules.defense_bonus(terrain_at(hex))

func set_terrain(hex: Vector2i, terrain_type: ZargosRules.Terrain) -> void:
	terrain[hex] = terrain_type

func find_movement_cost(start: Vector2i, goal: Vector2i, movement: int, flying: bool, occupied: Callable, stops_movement: Callable = Callable()) -> int:
	return reachable_hexes(start, movement, flying, occupied, stops_movement).get(goal, -1) as int

func reachable_hexes(start: Vector2i, movement: int, flying: bool, occupied: Callable, stops_movement: Callable = Callable()) -> Dictionary:
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
				# Gorghi e zone d'influenza nemiche concludono il movimento.
				var must_stop: bool = stops_movement.is_valid() and bool(stops_movement.call(neighbor))
				if terrain_type != ZargosRules.Terrain.MAGIC_VORTEX and not must_stop:
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

