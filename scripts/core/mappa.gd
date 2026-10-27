class_name ZMappa
extends RefCounted
## Mappa logica di Zargo: terreno di ogni esagono, continenti, ponti di nuvole
## e cuciture planetarie dei bordi. I dati sono in assets/data/board.json,
## ricavati esagono per esagono dalla mappa del modulo Tabletop Simulator.

enum T { VUOTO, PIANURA, BOSCO, MONTAGNA, GORGO, MARE, PONTE }

const CARATTERI := {" ": T.VUOTO, ".": T.PIANURA, "f": T.BOSCO, "m": T.MONTAGNA, "v": T.GORGO, "~": T.MARE, "b": T.PONTE}
const NOMI_TERRENO := {
	T.VUOTO: "Vuoto cosmico", T.PIANURA: "Pianura", T.BOSCO: "Bosco", T.MONTAGNA: "Montagna",
	T.GORGO: "Gorgo magico", T.MARE: "Mare", T.PONTE: "Ponte di nuvole",
}

# Esagoni a punta in alto, righe dispari spostate di mezzo esagono a destra.
const VICINI_PARI: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]
const VICINI_DISPARI: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 1)]

var colonne := 0
var righe := 0
var raggio_px := 35.55
var origine_px := Vector2.ZERO
var dimensione_px := Vector2(4096, 2749)
var nomi_continenti: Array = []
var _terreno := PackedByteArray()
var _continente := PackedInt32Array()
var _cuciture := {}  # Vector2i -> Array[Vector2i] (bordi planetari)
var _ponti := {}     # Vector2i -> Array[Vector2i] (estremità dei ponti di nuvole)
var _cache_distanze := {}

static var _condivisa: ZMappa

static func condivisa() -> ZMappa:
	if _condivisa == null:
		_condivisa = ZMappa.new()
		_condivisa.carica("res://assets/data/board.json")
	return _condivisa

func carica(percorso: String) -> void:
	var testo := FileAccess.get_file_as_string(percorso)
	var d: Dictionary = JSON.parse_string(testo)
	colonne = int(d.columns)
	righe = int(d.rows)
	raggio_px = float(d.hex_radius_px)
	origine_px = Vector2(d.origin_px[0], d.origin_px[1])
	dimensione_px = Vector2(d.image_size[0], d.image_size[1])
	nomi_continenti = d.continent_names
	_terreno.resize(colonne * righe)
	_continente.resize(colonne * righe)
	for r in righe:
		var riga: String = d.terrain[r]
		var cont: String = d.continent[r]
		for c in colonne:
			_terreno[r * colonne + c] = CARATTERI.get(riga[c], T.VUOTO)
			_continente[r * colonne + c] = -1 if cont[c] == "-" else int(cont[c])
	for coppia in d.wrap_links:
		_collega(_cuciture, Vector2i(coppia[0][0], coppia[0][1]), Vector2i(coppia[1][0], coppia[1][1]))
	for coppia in d.bridges:
		_collega(_ponti, Vector2i(coppia[0][0], coppia[0][1]), Vector2i(coppia[1][0], coppia[1][1]))

## Coppie di estremità dei ponti di nuvole, ognuna una volta sola.
func coppie_ponti() -> Array:
	var out := []
	for a in _ponti:
		for b in _ponti[a]:
			if a.x < b.x or (a.x == b.x and a.y < b.y):
				out.append([a, b])
	return out

func _collega(dove: Dictionary, a: Vector2i, b: Vector2i) -> void:
	if not dove.has(a):
		dove[a] = []
	if not dove.has(b):
		dove[b] = []
	if b not in dove[a]:
		dove[a].append(b)
	if a not in dove[b]:
		dove[b].append(a)

func dentro(h: Vector2i) -> bool:
	return h.x >= 0 and h.y >= 0 and h.x < colonne and h.y < righe

func terreno(h: Vector2i) -> int:
	return _terreno[h.y * colonne + h.x] if dentro(h) else T.VUOTO

func continente(h: Vector2i) -> int:
	return _continente[h.y * colonne + h.x] if dentro(h) else -1

func terra(h: Vector2i) -> bool:
	return terreno(h) in [T.PIANURA, T.BOSCO, T.MONTAGNA, T.GORGO]

func acqua(h: Vector2i) -> bool:
	return terreno(h) in [T.MARE, T.PONTE]

## Esagono di costa: terra adiacente al mare (le città non vi si possono porre).
func costa(h: Vector2i) -> bool:
	for v in vicino_geometrico_tutti(h):
		if acqua(v):
			return true
	return false

func vicino_dir(h: Vector2i, dir: int) -> Vector2i:
	var off: Vector2i = (VICINI_DISPARI if h.y & 1 else VICINI_PARI)[dir]
	var v := h + off
	# Ai bordi orientale e occidentale il pianeta si richiude su se stesso.
	if (dir == 0 or dir == 3) and (not dentro(v) or terreno(v) == T.VUOTO) and _cuciture.has(h):
		for altro in _cuciture[h]:
			if altro.y == h.y and ((dir == 0 and altro.x < h.x) or (dir == 3 and altro.x > h.x)):
				return altro
	return v

func vicino_geometrico_tutti(h: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dir in 6:
		var v := vicino_dir(h, dir)
		if dentro(v) and terreno(v) != T.VUOTO and v not in out:
			out.append(v)
	if _cuciture.has(h):
		for v in _cuciture[h]:
			if v not in out:
				out.append(v)
	return out

## Esagoni di terra raggiungibili con un passo, inclusi i ponti di nuvole
## (che collegano una costa all'altra) e le cuciture dei bordi.
func vicini_terra(h: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for v in vicino_geometrico_tutti(h):
		if terra(v):
			out.append(v)
	if _ponti.has(h):
		for v in _ponti[h]:
			if v not in out:
				out.append(v)
	return out

func ponte_tra(a: Vector2i, b: Vector2i) -> bool:
	return _ponti.has(a) and b in _ponti[a]

func estremi_ponti() -> Dictionary:
	return _ponti

func adiacenti(a: Vector2i, b: Vector2i) -> bool:
	return b in vicino_geometrico_tutti(a)

## Distanza in esagoni attraverso qualsiasi esagono della mappa (anche il mare),
## come si conta sul tabellone per frecce, fiamme e visioni.
func distanza(a: Vector2i, b: Vector2i) -> int:
	if a == b:
		return 0
	var chiave := a
	if not _cache_distanze.has(chiave):
		_cache_distanze[chiave] = _bfs(a)
	return int(_cache_distanze[chiave].get(b, 999))

func _bfs(a: Vector2i) -> Dictionary:
	var dist := {a: 0}
	var coda: Array[Vector2i] = [a]
	var i := 0
	while i < coda.size():
		var h := coda[i]
		i += 1
		if dist[h] >= 12:
			continue
		for v in vicino_geometrico_tutti(h):
			if not dist.has(v):
				dist[v] = dist[h] + 1
				coda.append(v)
	return dist

## Direzione della linea esagonale retta che va da a a b (o -1).
func direzione_retta(a: Vector2i, b: Vector2i, massimo := 12) -> int:
	for dir in 6:
		var h := a
		for passo in massimo:
			h = vicino_dir(h, dir)
			if not dentro(h):
				break
			if h == b:
				return dir
	return -1

func linea(a: Vector2i, dir: int, passi: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var h := a
	for i in passi:
		h = vicino_dir(h, dir)
		out.append(h)
	return out

func esagoni_continente(indice: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in righe:
		for c in colonne:
			if _continente[r * colonne + c] == indice and terra(Vector2i(c, r)):
				out.append(Vector2i(c, r))
	return out

## Centro dell'esagono in pixel sulla mappa Mappa 2.png.
func centro_px(h: Vector2i) -> Vector2:
	var dx := sqrt(3.0) * raggio_px
	return Vector2(origine_px.x + h.x * dx + (dx * 0.5 if h.y & 1 else 0.0), origine_px.y + h.y * 1.5 * raggio_px)

func esagono_da_px(p: Vector2) -> Vector2i:
	var r0 := int(round((p.y - origine_px.y) / (1.5 * raggio_px)))
	var migliore := Vector2i(-1, -1)
	var best := INF
	for r in range(r0 - 1, r0 + 2):
		var dx := sqrt(3.0) * raggio_px
		var c0 := int(round((p.x - origine_px.x - (dx * 0.5 if r & 1 else 0.0)) / dx))
		for c in range(c0 - 1, c0 + 2):
			var h := Vector2i(c, r)
			if not dentro(h):
				continue
			var d := centro_px(h).distance_squared_to(p)
			if d < best:
				best = d
				migliore = h
	return migliore
