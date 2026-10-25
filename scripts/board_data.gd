class_name ZargosBoardData
extends RefCounted

var terrain: Dictionary = {}
var distance_cache: Dictionary = {}

func _init() -> void:
	# Maschera ricavata sui centri del reticolo stampato della scansione originale.
	# Le coste vengono considerate terrestri quando il centro dell'esagono e' a
	# terra; laghi, canali e mare aperto sono invece non transitabili.
	var sea_hexes: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(0, 13), Vector2i(0, 21), Vector2i(0, 22), Vector2i(1, 0), Vector2i(1, 21), Vector2i(1, 22), Vector2i(1, 23),
		Vector2i(2, 0), Vector2i(2, 13), Vector2i(2, 23), Vector2i(3, 0), Vector2i(3, 12), Vector2i(3, 13), Vector2i(3, 23), Vector2i(4, 11),
		Vector2i(4, 12), Vector2i(4, 23), Vector2i(5, 10), Vector2i(6, 10), Vector2i(7, 10), Vector2i(8, 12), Vector2i(9, 0), Vector2i(9, 11),
		Vector2i(10, 0), Vector2i(10, 10), Vector2i(11, 9), Vector2i(11, 10), Vector2i(12, 2), Vector2i(12, 3), Vector2i(12, 11), Vector2i(12, 12),
		Vector2i(13, 0), Vector2i(13, 1), Vector2i(13, 3), Vector2i(13, 4), Vector2i(13, 12), Vector2i(13, 22), Vector2i(13, 23), Vector2i(14, 4),
		Vector2i(14, 12), Vector2i(14, 19), Vector2i(14, 21), Vector2i(14, 22), Vector2i(15, 11), Vector2i(15, 14), Vector2i(15, 15), Vector2i(15, 19),
		Vector2i(16, 4), Vector2i(16, 5), Vector2i(16, 13), Vector2i(16, 14), Vector2i(16, 15), Vector2i(16, 16), Vector2i(16, 19), Vector2i(17, 5),
		Vector2i(17, 11), Vector2i(17, 15), Vector2i(17, 16), Vector2i(17, 17), Vector2i(18, 6), Vector2i(18, 13), Vector2i(18, 14), Vector2i(18, 17),
		Vector2i(19, 5), Vector2i(19, 6), Vector2i(19, 7), Vector2i(19, 17), Vector2i(20, 6), Vector2i(20, 9), Vector2i(20, 10), Vector2i(20, 11),
		Vector2i(20, 13), Vector2i(20, 19), Vector2i(21, 12), Vector2i(21, 21), Vector2i(22, 10), Vector2i(22, 11), Vector2i(22, 12), Vector2i(22, 23),
		Vector2i(23, 10), Vector2i(23, 22), Vector2i(23, 23), Vector2i(24, 13), Vector2i(24, 22), Vector2i(24, 23), Vector2i(25, 11), Vector2i(25, 12),
		Vector2i(25, 15), Vector2i(25, 22), Vector2i(26, 12), Vector2i(27, 12), Vector2i(27, 13), Vector2i(27, 21), Vector2i(27, 22), Vector2i(27, 23),
		Vector2i(28, 13), Vector2i(28, 22), Vector2i(28, 23), Vector2i(29, 12), Vector2i(29, 13), Vector2i(29, 23), Vector2i(30, 12), Vector2i(30, 13),
		Vector2i(31, 12), Vector2i(32, 12), Vector2i(33, 11), Vector2i(33, 12), Vector2i(34, 12), Vector2i(34, 16), Vector2i(34, 17), Vector2i(35, 0),
		Vector2i(35, 2), Vector2i(35, 11), Vector2i(35, 12), Vector2i(35, 16), Vector2i(35, 17), Vector2i(35, 22),
	]
	for hex in sea_hexes:
		terrain[_legacy_coordinate(hex)] = ZargosRules.Terrain.SEA
	var void_hexes: Array[Vector2i] = [
		Vector2i(14, 0), Vector2i(14, 23), Vector2i(15, 0), Vector2i(15, 1), Vector2i(15, 21), Vector2i(15, 22), Vector2i(15, 23), Vector2i(16, 0),
		Vector2i(16, 1), Vector2i(16, 2), Vector2i(16, 3), Vector2i(16, 20), Vector2i(16, 21), Vector2i(16, 22), Vector2i(16, 23), Vector2i(17, 0),
		Vector2i(17, 1), Vector2i(17, 2), Vector2i(17, 3), Vector2i(17, 4), Vector2i(17, 18), Vector2i(17, 19), Vector2i(17, 20), Vector2i(17, 21),
		Vector2i(17, 22), Vector2i(17, 23), Vector2i(18, 0), Vector2i(18, 1), Vector2i(18, 2), Vector2i(18, 3), Vector2i(18, 4), Vector2i(18, 5),
		Vector2i(18, 18), Vector2i(18, 19), Vector2i(18, 20), Vector2i(18, 21), Vector2i(18, 22), Vector2i(18, 23), Vector2i(19, 0), Vector2i(19, 1),
		Vector2i(19, 2), Vector2i(19, 3), Vector2i(19, 19), Vector2i(19, 20), Vector2i(19, 21), Vector2i(19, 22), Vector2i(19, 23), Vector2i(20, 0),
		Vector2i(20, 1), Vector2i(20, 2), Vector2i(20, 21), Vector2i(20, 22), Vector2i(20, 23), Vector2i(21, 0), Vector2i(21, 22), Vector2i(21, 23),
	]
	for hex in void_hexes:
		terrain[_legacy_coordinate(hex)] = ZargosRules.Terrain.VOID
	# Corridoi di nuvole verificati sulla fascia equatoriale della scansione.
	# Sono distinti dal mare: anche le unità volanti possono attraversarli, ma
	# soltanto seguendo il ponte da una costa all'altra.
	var cloud_bridge_hexes: Array[Vector2i] = [
		Vector2i(0, 13),
		Vector2i(4, 12),
		Vector2i(8, 12), Vector2i(9, 11),
		Vector2i(12, 11), Vector2i(12, 12), Vector2i(13, 12), Vector2i(14, 12), Vector2i(15, 11),
		Vector2i(20, 9), Vector2i(20, 10), Vector2i(20, 11), Vector2i(20, 13),
		Vector2i(22, 10), Vector2i(22, 11), Vector2i(22, 12),
		Vector2i(28, 13),
		Vector2i(35, 11), Vector2i(35, 12),
	]
	for hex in cloud_bridge_hexes:
		terrain[_legacy_coordinate(hex)] = ZargosRules.Terrain.CLOUD_BRIDGE
	var forest_hexes: Array[Vector2i] = [
		# Continente nord-occidentale
		Vector2i(1, 17), Vector2i(3, 20), Vector2i(4, 20), Vector2i(8, 21),
		Vector2i(11, 16), Vector2i(12, 16), Vector2i(15, 14), Vector2i(16, 14),
		# Continente nord-orientale
		Vector2i(31, 22), Vector2i(32, 22), Vector2i(26, 20), Vector2i(24, 17),
		Vector2i(21, 15), Vector2i(33, 13), Vector2i(35, 16),
		# Continente sud-orientale
		Vector2i(20, 9), Vector2i(21, 9), Vector2i(22, 9), Vector2i(23, 8),
		Vector2i(24, 8), Vector2i(23, 7), Vector2i(24, 7), Vector2i(25, 7),
		Vector2i(28, 7), Vector2i(29, 7), Vector2i(29, 6), Vector2i(24, 4),
		Vector2i(25, 4), Vector2i(26, 4), Vector2i(27, 3), Vector2i(28, 3),
	]
	for hex in forest_hexes:
		terrain[_legacy_coordinate(_scan_coordinate(hex))] = ZargosRules.Terrain.FOREST
	var mountain_hexes: Array[Vector2i] = [
		# Catena nord-occidentale
		Vector2i(10, 21), Vector2i(11, 21), Vector2i(8, 20), Vector2i(9, 20),
		Vector2i(8, 19), Vector2i(9, 19), Vector2i(6, 18), Vector2i(7, 18),
		Vector2i(5, 17), Vector2i(7, 17), Vector2i(3, 16), Vector2i(4, 16),
		Vector2i(1, 15), Vector2i(0, 15),
		# Catene nord-orientali
		Vector2i(25, 22), Vector2i(25, 21), Vector2i(24, 20), Vector2i(23, 19),
		Vector2i(23, 18), Vector2i(22, 17), Vector2i(22, 16), Vector2i(29, 17),
		Vector2i(29, 16), Vector2i(29, 15), Vector2i(35, 15), Vector2i(35, 14), Vector2i(34, 13),
		# Catene sud-occidentali
		Vector2i(3, 7), Vector2i(3, 6), Vector2i(4, 6), Vector2i(3, 5),
		Vector2i(4, 5), Vector2i(5, 5), Vector2i(5, 4), Vector2i(6, 4),
		Vector2i(9, 6), Vector2i(10, 6), Vector2i(10, 5), Vector2i(10, 4),
		Vector2i(11, 4), Vector2i(10, 3), Vector2i(11, 3), Vector2i(11, 2),
		Vector2i(12, 2), Vector2i(11, 1), Vector2i(11, 8), Vector2i(12, 7),
		Vector2i(13, 7), Vector2i(14, 7),
		# Catene sud-orientali
		Vector2i(22, 7), Vector2i(22, 6), Vector2i(22, 5), Vector2i(22, 4),
		Vector2i(22, 3), Vector2i(23, 3), Vector2i(23, 2), Vector2i(24, 2),
		Vector2i(25, 2), Vector2i(30, 8), Vector2i(31, 8), Vector2i(31, 7),
		Vector2i(30, 6), Vector2i(31, 6), Vector2i(30, 5), Vector2i(31, 5),
		Vector2i(30, 4), Vector2i(31, 4), Vector2i(33, 9), Vector2i(34, 9),
	]
	for hex in mountain_hexes:
		terrain[_legacy_coordinate(_scan_coordinate(hex))] = ZargosRules.Terrain.MOUNTAIN
	var vortex_hexes: Array[Vector2i] = [
		Vector2i(8, 18), Vector2i(7, 15), Vector2i(1, 14),
		Vector2i(32, 23), Vector2i(31, 21), Vector2i(24, 16), Vector2i(20, 15), Vector2i(35, 17), Vector2i(33, 13),
		Vector2i(6, 10), Vector2i(0, 7), Vector2i(15, 6), Vector2i(6, 1),
		Vector2i(31, 9), Vector2i(19, 8), Vector2i(29, 1), Vector2i(32, 1),
	]
	for hex in vortex_hexes:
		terrain[_legacy_coordinate(_scan_coordinate(hex))] = ZargosRules.Terrain.MAGIC_VORTEX
	_apply_bitmap_terrain_map()

func _apply_bitmap_terrain_map() -> void:
	var file := FileAccess.open("res://assets/data/terrain_map.json", FileAccess.READ)
	if not file:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var terrain_types := {
		"sea": ZargosRules.Terrain.SEA,
		"forest": ZargosRules.Terrain.FOREST,
		"mountain": ZargosRules.Terrain.MOUNTAIN,
		"void": ZargosRules.Terrain.VOID,
	}
	for terrain_name: String in terrain_types:
		for coordinates: Array in parsed.get(terrain_name, []):
			var hex := Vector2i(int(coordinates[0]), int(coordinates[1]))
			# I ponti di nuvole e i vortici verificati a mano hanno precedenza
			# sulla classificazione cromatica della bitmap.
			if terrain.get(hex) not in [ZargosRules.Terrain.CLOUD_BRIDGE, ZargosRules.Terrain.MAGIC_VORTEX]:
				terrain[hex] = terrain_types[terrain_name]

func _legacy_coordinate(old_hex: Vector2i) -> Vector2i:
	# Migrazione provvisoria delle annotazioni della scansione 36x24 sulla
	# griglia 67x52 misurata direttamente sulla bitmap Mappa 2.png.
	return Vector2i(
		roundi(float(old_hex.x) * float(ZargosRules.BOARD_COLUMNS - 1) / 35.0),
		roundi(float(old_hex.y) * float(ZargosRules.BOARD_ROWS - 1) / 23.0)
	)

func _scan_coordinate(old_hex: Vector2i) -> Vector2i:
	# Le prime annotazioni erano state lette dal basso verso l'alto, mentre la
	# texture e le coordinate di gioco partono dal bordo superiore della mappa.
	return Vector2i(old_hex.x, 23 - old_hex.y)

func terrain_at(hex: Vector2i) -> ZargosRules.Terrain:
	return terrain.get(hex, ZargosRules.Terrain.PLAIN) as ZargosRules.Terrain

static func continent_at(hex: Vector2i) -> StringName:
	if not is_on_board(hex):
		return &""
	if hex.y < ZargosRules.BOARD_ROWS / 2:
		return &"Cavalieri" if hex.x < ZargosRules.BOARD_COLUMNS / 2 else &"Draghi"
	return &"Alati" if hex.x < ZargosRules.BOARD_COLUMNS / 2 else &"Monaci"

func is_deployment_hex(hex: Vector2i) -> bool:
	return is_on_board(hex) and terrain_at(hex) not in [
		ZargosRules.Terrain.SEA,
		ZargosRules.Terrain.CLOUD_BRIDGE,
		ZargosRules.Terrain.VOID,
	]

func defense_bonus_at(hex: Vector2i) -> int:
	return ZargosRules.defense_bonus(terrain_at(hex))

func set_terrain(hex: Vector2i, terrain_type: ZargosRules.Terrain) -> void:
	terrain[hex] = terrain_type
	distance_cache.clear()

func find_movement_cost(start: Vector2i, goal: Vector2i, movement: int, flying: bool, occupied: Callable, stops_movement: Callable = Callable()) -> int:
	return reachable_hexes(start, movement, flying, occupied, stops_movement).get(goal, -1) as int

func reachable_hexes(start: Vector2i, movement: int, flying: bool, occupied: Callable, stops_movement: Callable = Callable()) -> Dictionary:
	var frontier: Array[Vector2i] = [start]
	var costs := {start: 0}
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		for neighbor in planetary_neighbors(current):
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

func planetary_neighbors(hex: Vector2i) -> Array[Vector2i]:
	var output: Array[Vector2i] = []
	for candidate in neighbors(hex):
		if is_on_board(candidate) and terrain_at(candidate) != ZargosRules.Terrain.VOID:
			if candidate not in output:
				output.append(candidate)
			continue
		var linked := _linked_border_hex(hex, candidate)
		if linked != hex and is_on_board(linked) and terrain_at(linked) != ZargosRules.Terrain.VOID and linked not in output:
			output.append(linked)
	return output

func planetary_distance(start: Vector2i, goal: Vector2i) -> int:
	if start == goal:
		return 0
	var cache_key := Vector4i(start.x, start.y, goal.x, goal.y)
	if distance_cache.has(cache_key):
		return distance_cache[cache_key] as int
	var frontier: Array[Vector2i] = [start]
	var distances := {start: 0}
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		for neighbor in planetary_neighbors(current):
			if distances.has(neighbor):
				continue
			var distance: int = distances[current] + 1
			if neighbor == goal:
				distance_cache[cache_key] = distance
				distance_cache[Vector4i(goal.x, goal.y, start.x, start.y)] = distance
				return distance
			distances[neighbor] = distance
			frontier.append(neighbor)
	distance_cache[cache_key] = 999
	return 999

func _linked_border_hex(origin: Vector2i, attempted: Vector2i) -> Vector2i:
	# I bordi esterni sinistro e destro si ricongiungono alla stessa altezza.
	if attempted.x < 0:
		return Vector2i(ZargosRules.BOARD_COLUMNS - 1, clampi(attempted.y, 0, ZargosRules.BOARD_ROWS - 1))
	if attempted.x >= ZargosRules.BOARD_COLUMNS:
		return Vector2i(0, clampi(attempted.y, 0, ZargosRules.BOARD_ROWS - 1))
	# I due lembi superiori e inferiori sono speculari, come nella figura 1.
	if attempted.y < 0:
		return Vector2i(clampi(ZargosRules.BOARD_COLUMNS - 1 - attempted.x, 0, ZargosRules.BOARD_COLUMNS - 1), 0)
	if attempted.y >= ZargosRules.BOARD_ROWS:
		return Vector2i(clampi(ZargosRules.BOARD_COLUMNS - 1 - attempted.x, 0, ZargosRules.BOARD_COLUMNS - 1), ZargosRules.BOARD_ROWS - 1)
	# Lo stesso principio unisce i due tagli centrali marroni della scansione.
	if terrain_at(attempted) == ZargosRules.Terrain.VOID and attempted.x >= 29 and attempted.x <= 50:
		return Vector2i(ZargosRules.BOARD_COLUMNS - 1 - attempted.x, attempted.y)
	return origin

static func neighbors(hex: Vector2i) -> Array[Vector2i]:
	var offsets_even: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(0, 1), Vector2i(-1, 1)]
	var offsets_odd: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(0, 1)]
	var output: Array[Vector2i] = []
	for offset in (offsets_odd if hex.y & 1 else offsets_even):
		output.append(hex + offset)
	return output

static func is_on_board(hex: Vector2i) -> bool:
	return hex.x >= 0 and hex.y >= 0 and hex.x < ZargosRules.BOARD_COLUMNS and hex.y < ZargosRules.BOARD_ROWS

