class_name ZargosRules
extends RefCounted

enum Phase { ALLIANCES, MOVEMENT, COMBAT }
enum Terrain { PLAIN, FOREST, MOUNTAIN, SEA, CLOUD_BRIDGE, MAGIC_VORTEX, CITY, VOID }

const FACTIONS := [&"Cavalieri", &"Draghi", &"Alati", &"Monaci"]
const MONTH_LIMIT := 25
# Reticolo della scansione originale. Non viene disegnato sopra la mappa: serve
# soltanto a posare le pedine sui centri degli esagoni già stampati.
const BOARD_COLUMNS := 36
const BOARD_ROWS := 24

const COMBAT_BANDS := [
	Vector2i(-5, -2), Vector2i(-1, 0), Vector2i(1, 3), Vector2i(4, 7),
	Vector2i(8, 11), Vector2i(12, 15), Vector2i(16, 20), Vector2i(21, 100),
]

# Righe: risultato del dado 1-6. Colonne: differenza di combattimento.
const COMBAT_TABLE := [
	["AE", "A5", "A3", "A1", "D1", "D1", "D3", "D5"],
	["A5", "A3", "A1", "D1", "D1", "D3", "D5", "DE"],
	["A3", "A1", "D1", "D1", "D3", "DE", "D5", "DE"],
	["A1", "A1", "D1", "D3", "D5", "DE", "DE", "DE"],
	["A1", "D1", "D3", "D5", "DE", "DE", "DE", "DE"],
	["D1", "D3", "D5", "DE", "DE", "DE", "DE", "DE"],
]

# Numero di colpi, indicizzati per dado e distanza. Zero significa tiro inefficace.
const ARROW_TABLE := [
	[1, 1, 1, 0, 0, 0, 0, 0],
	[2, 1, 1, 1, 0, 0, 0, 0],
	[2, 2, 1, 1, 1, 0, 0, 0],
	[2, 2, 2, 1, 1, 1, 0, 0],
	[3, 2, 2, 2, 1, 1, 1, 0],
	[3, 3, 2, 2, 2, 1, 1, 1],
]

const FIRE_TABLE := [
	[1, 1, 0, 0, 0],
	[2, 1, 1, 0, 0],
	[2, 2, 1, 1, 0],
	[3, 2, 2, 1, 1],
	[3, 3, 2, 2, 1],
	[4, 3, 3, 2, 2],
]

# La fuga causata dalla visione è movimento massimo meno questo modificatore.
const VISION_MODIFIERS := [
	[2, 3, 4, 5, 6],
	[1, 2, 3, 4, 5],
	[0, 1, 2, 3, 4],
	[0, 0, 1, 2, 3],
	[0, 0, 0, 1, 2],
	[0, 0, 0, 0, 1],
]

const FACTION_COLORS := {
	&"Cavalieri": Color("d8d5c7"),
	&"Draghi": Color("7f9d45"),
	&"Alati": Color("8a76ae"),
	&"Monaci": Color("d2a52c"),
}

const UNIT_TYPES := {
	&"Cavalieri": {
		&"Signore": {"move": 7, "combat": 10, "ability": "Carica"},
		&"Mago": {"move": 5, "combat": 2, "ability": "Visione"},
		&"Fantarcere": {"move": 5, "combat": 2, "ability": "Tiro"},
		&"Fante": {"move": 4, "combat": 5, "ability": ""},
	},
	&"Draghi": {
		&"Signore": {"move": 5, "combat": 6, "ability": "Fiamme"},
		&"Serpente": {"move": 10, "combat": 10, "ability": "Travolgere"},
		&"Lanciafiamme": {"move": 5, "combat": 2, "ability": "Fiamme"},
		&"Fante": {"move": 5, "combat": 3, "ability": ""},
	},
	&"Alati": {
		&"Signore": {"move": 15, "combat": 8, "ability": "Volo"},
		&"Falco": {"move": 12, "combat": 5, "ability": "Volo"},
		&"Fantarcere": {"move": 4, "combat": 2, "ability": "Tiro"},
		&"Fante": {"move": 5, "combat": 4, "ability": ""},
	},
	&"Monaci": {
		&"Signore": {"move": 10, "combat": 7, "ability": "Sparizione"},
		&"Illusionista": {"move": 6, "combat": 2, "ability": "Visione"},
		&"Cavaliere": {"move": 9, "combat": 5, "ability": ""},
		&"Fante": {"move": 5, "combat": 4, "ability": ""},
	},
}

static func terrain_cost(terrain: Terrain, flying: bool = false) -> int:
	if terrain in [Terrain.SEA, Terrain.VOID]:
		return -1
	if terrain == Terrain.MAGIC_VORTEX:
		return 1
	if flying:
		return 1
	match terrain:
		Terrain.FOREST: return 2
		Terrain.MOUNTAIN: return 99
		_: return 1

static func defense_bonus(terrain: Terrain) -> int:
	match terrain:
		Terrain.FOREST: return 1
		Terrain.MOUNTAIN: return 3
		_: return 0

static func hex_distance(a: Vector2i, b: Vector2i) -> int:
	var aq := a.x
	var ar := a.y - (a.x - (a.x & 1)) / 2
	var bq := b.x
	var br := b.y - (b.x - (b.x & 1)) / 2
	return int((abs(aq - bq) + abs(aq + ar - bq - br) + abs(ar - br)) / 2)

static func resolve_combat(attacker_strength: int, defender_strength: int, die: int) -> Dictionary:
	var difference := attacker_strength - defender_strength
	var band := combat_band_index(difference)
	if band < 0:
		return {"result": "IMPOSSIBILE", "retreat": 0, "text": "Differenza fuori tabella: attacco non consentito"}
	var code: String = COMBAT_TABLE[clampi(die, 1, 6) - 1][band]
	if code == "AE": return {"result": code, "retreat": 0, "text": "Attaccante eliminato"}
	if code == "DE": return {"result": code, "retreat": 0, "text": "Difensore eliminato"}
	var distance := int(code.right(1))
	var defender_retreats := code.begins_with("D")
	return {
		"result": code,
		"retreat": distance if defender_retreats else -distance,
		"text": "%s arretra di %d" % ["Difensore" if defender_retreats else "Attaccante", distance],
	}

static func combat_band_index(difference: int) -> int:
	for index in range(COMBAT_BANDS.size()):
		var band: Vector2i = COMBAT_BANDS[index]
		if difference >= band.x and difference <= band.y:
			return index
	return -1

static func arrow_hits(die: int, distance: int) -> int:
	if die < 1 or die > 6 or distance < 1 or distance > 8:
		return 0
	return ARROW_TABLE[die - 1][distance - 1]

static func fire_hits(die: int, distance: int, target_in_forest: bool = false) -> int:
	if die < 1 or die > 6 or distance < 1 or distance > 5:
		return 0
	var adjusted_die := mini(6, die + (2 if target_in_forest else 0))
	return FIRE_TABLE[adjusted_die - 1][distance - 1]

static func vision_retreat(die: int, distance: int, target_max_movement: int) -> int:
	if die < 1 or die > 6 or distance < 1 or distance > 5:
		return 0
	return maxi(0, target_max_movement - VISION_MODIFIERS[die - 1][distance - 1])

