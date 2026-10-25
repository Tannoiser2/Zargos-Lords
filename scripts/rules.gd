class_name ZargosRules
extends RefCounted

enum Phase { ALLIANCES, MOVEMENT, COMBAT }
enum Terrain { PLAIN, FOREST, MOUNTAIN, SEA, CLOUD_BRIDGE, MAGIC_VORTEX, CITY }

const FACTIONS := [&"Cavalieri", &"Draghi", &"Alati", &"Monaci"]
const MONTH_LIMIT := 25
const BOARD_COLUMNS := 18
const BOARD_ROWS := 12

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
	if terrain == Terrain.SEA:
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
	# Tabella provvisoria esplicita: sarà sostituita dalla trascrizione fedele del disco.
	var pressure := difference + die * 2
	if pressure >= 18:
		return {"result": "DE", "retreat": 0, "text": "Difensore eliminato"}
	if pressure >= 9:
		return {"result": "D3", "retreat": 3, "text": "Difensore arretra di 3"}
	if pressure >= 5:
		return {"result": "D1", "retreat": 1, "text": "Difensore arretra di 1"}
	if pressure >= 1:
		return {"result": "NE", "retreat": 0, "text": "Nessun effetto"}
	if pressure >= -4:
		return {"result": "A1", "retreat": -1, "text": "Attaccante arretra di 1"}
	return {"result": "AE", "retreat": 0, "text": "Attaccante eliminato"}

