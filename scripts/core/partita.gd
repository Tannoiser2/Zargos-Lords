class_name ZPartita
extends RefCounted
## Modello completo di una partita di Zargo's Lords, indipendente dalla grafica.
## Ogni comando del giocatore (umano, IA o remoto) passa da `esegui()`, che
## valida l'azione secondo il regolamento, la applica e restituisce gli eventi
## da mostrare. Lo stato è interamente serializzabile con `a_dict()`.

signal cambiata

const FASE_SCHIERAMENTO := "schieramento"
const FASE_ALLEANZE := "alleanze"
const FASE_MAGIA := "magia"          # Zargo's Lords 2, regola opzionale
const FASE_SINGOLI := "singoli"      # attacchi singoli e fiamme del Drago prima di muovere
const FASE_MOVIMENTO := "movimento"
const FASE_LANCI := "lanci"          # frecce, fiamme e visioni
const FASE_COMBATTIMENTO := "combattimento"
const FASE_FINITA := "finita"

var mappa: ZMappa
var popoli: Array[String] = []          # popoli in gioco, nell'ordine di mossa
var controllo := {}                      # popolo -> "umano" | "ia" | "remoto"
var continenti: Array[String] = ["", "", "", ""]  # proprietario iniziale di ogni continente
var pedine: Array[ZPedina] = []
var citta: Array[Dictionary] = []        # {id, p, h, g:[id], orig}
var mese := 1
var turno := 0                           # indice in `popoli` del popolo di mano
var turno_globale := 0
var fase := FASE_SCHIERAMENTO
var alleanze: Array[String] = []         # coppie "A|B" in ordine alfabetico
var proposte: Array[String] = []         # "Proponente>Destinatario"
var singoli_aperti := true               # nessun movimento normale ancora eseguito
var mischia_iniziata := false            # dopo il primo scontro non si tira più
var registro: Array[String] = []
var vincitori: Array[String] = []
var rng := RandomNumberGenerator.new()

# --- Zargo's Lords 2 e regole opzionali ---
var opzioni := {}                        # zl2, magia, passaggi, lampo
var preparazione := {}                   # popolo -> punti preparazione magica
var magia_fatta := false                 # magia lanciata in questa mossa
var terreno_mod := {}                    # "x,y" -> terreno sostituito (Grande frana)
var ponti_temp: Array = []               # [[x,y],[x,y]] ponti di pensiero di questa mossa
var reti: Array = []                     # esagoni con le reti dei ragni [x,y]
var passaggio_usato := false
var trasformazioni := 0                  # tentativi di trasformazione dei fanti amazzoni
var bonus_vittoria := {}                 # popolo -> punti extra (Voragine di fiamme)
var conquiste_lampo := {}                # popolo -> [popolo della città conquistata...]
var punti_lampo := {}                    # popolo -> punti per le città conquistate
var n_conquiste := 0
# --- Iniziativa e fasi alternate (Zargo's Lords 2) ---
var ordine: Array[String] = []           # ordine d'iniziativa del mese
var blocco := 0                          # 0 potere, 1 movimento, 2 combattimento

var _indice := {}
var _indice_valido := false

func _init() -> void:
	mappa = ZMappa.condivisa()

# ---------------------------------------------------------------------------
# Preparazione
# ---------------------------------------------------------------------------

## Crea una nuova partita. `scelti` sono i popoli in gioco (2-4); `ctrl` indica
## chi controlla ciascuno. I continenti vengono estratti a sorte come con le
## carte dei popoli: con due giocatori ognuno riceve due continenti.
func nuova(scelti: Array, ctrl: Dictionary, seme := 0, opz := {}) -> void:
	rng.seed = seme if seme != 0 else randi()
	opzioni = {"zl2": false, "magia": false, "passaggi": false, "lampo": false, "iniziativa": false}
	opzioni.merge(opz, true)
	# I popoli dell'espansione richiedono le regole di Zargo's Lords 2.
	for x in scelti:
		if x in ["Amazzoni", "Aracnidi"]:
			opzioni.zl2 = true
	popoli.clear()
	for p in ZRegole.POPOLI_ZL2:
		if p in scelti:
			popoli.append(p)
	controllo = ctrl.duplicate()
	var indici := [0, 1, 2, 3]
	_mescola(indici)
	continenti = ["", "", "", ""]
	if popoli.size() == 2:
		# Due continenti per popolo: uno a nord e uno a sud, mai adiacenti allo stesso avversario.
		var coppie := [[0, 3], [1, 2]] if rng.randi() % 2 == 0 else [[0, 2], [1, 3]]
		if rng.randi() % 2 == 0:
			coppie.reverse()
		for i in 2:
			for k in coppie[i]:
				continenti[k] = popoli[i]
	else:
		for i in popoli.size():
			continenti[indici[i]] = popoli[i]
	pedine.clear()
	citta.clear()
	for p in popoli:
		for tipo in ZRegole.PEZZI[p]:
			for q in int(ZRegole.PEZZI[p][tipo]["q"]):
				var u := ZPedina.new()
				u.id = pedine.size()
				u.popolo = p
				u.tipo = tipo
				pedine.append(u)
		for k in (ZRegole.CITTA_ZL2 if zl2() else ZRegole.CITTA_PER_POPOLO):
			citta.append({"id": citta.size(), "p": p, "h": [-1, -1], "g": [], "orig": p})
	mese = 1
	turno = 0
	turno_globale = 0
	fase = FASE_SCHIERAMENTO
	alleanze.clear()
	proposte.clear()
	registro.clear()
	vincitori.clear()
	preparazione.clear()
	bonus_vittoria.clear()
	conquiste_lampo.clear()
	punti_lampo.clear()
	n_conquiste = 0
	ordine.clear()
	blocco = 0
	terreno_mod.clear()
	ponti_temp.clear()
	reti.clear()
	for p in popoli:
		preparazione[p] = 0
		bonus_vittoria[p] = 0.0
		conquiste_lampo[p] = []
		punti_lampo[p] = 0.0
	_sporca()
	_log("Il pianeta Zargo attende i suoi Signori. Schieramento %s." % ZRegole.degli(popoli[0]))

func _mescola(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t

func zl2() -> bool:
	return bool(opzioni.get("zl2", false))

func opzione(k: String) -> bool:
	return bool(opzioni.get(k, false))

func mesi_totali() -> int:
	return ZRegole.MESI_LAMPO if opzione("lampo") else ZRegole.MESI

## Terreno, tenendo conto degli effetti magici di questa mossa.
func terreno(h: Vector2i) -> int:
	var k := "%d,%d" % [h.x, h.y]
	if terreno_mod.has(k):
		return int(terreno_mod[k])
	return mappa.terreno(h)

## Esagoni di terra vicini, compresi i ponti di pensiero di questa mossa.
func vicini(h: Vector2i) -> Array[Vector2i]:
	var out := mappa.vicini_terra(h)
	for pt in ponti_temp:
		var a := Vector2i(int(pt[0][0]), int(pt[0][1]))
		var b := Vector2i(int(pt[1][0]), int(pt[1][1]))
		if a == h and b not in out:
			out.append(b)
		elif b == h and a not in out:
			out.append(a)
	return out

func ha_rete(h: Vector2i) -> bool:
	for r in reti:
		if int(r[0]) == h.x and int(r[1]) == h.y:
			return true
	return false

## Valore di combattimento, raddoppiato da "Spada di luce" nella mossa del lancio.
func valore(u: ZPedina) -> int:
	return u.c() * (2 if u.spada == turno_globale else 1)

func popolo_di_mano() -> String:
	if alternato():
		return ordine[turno] if turno < ordine.size() else ""
	return popoli[turno] if turno < popoli.size() else ""

## Regola dell'iniziativa: ogni mese l'ordine si sorteggia e ogni fase
## (potere, movimento, combattimento) la giocano tutti prima della successiva.
func alternato() -> bool:
	return opzione("iniziativa") and fase != FASE_SCHIERAMENTO and not ordine.is_empty()

func continenti_di(p: String) -> Array[int]:
	var out: Array[int] = []
	for i in 4:
		if continenti[i] == p:
			out.append(i)
	return out

# ---------------------------------------------------------------------------
# Interrogazioni sullo stato
# ---------------------------------------------------------------------------

func _sporca() -> void:
	_indice_valido = false

func _ricostruisci_indice() -> void:
	_indice.clear()
	for u in pedine:
		if u.in_campo():
			if not _indice.has(u.hex):
				_indice[u.hex] = []
			_indice[u.hex].append(u.id)
	_indice_valido = true

## Pedine in campo nell'esagono (al massimo una coppia scorta + scortato).
func pedine_in(h: Vector2i) -> Array[ZPedina]:
	if not _indice_valido:
		_ricostruisci_indice()
	var out: Array[ZPedina] = []
	for id in _indice.get(h, []):
		out.append(pedine[id])
	return out

## La pedina "visibile" di un esagono: in una coppia, la scorta che subisce gli attacchi.
func pedina_in(h: Vector2i) -> ZPedina:
	var lista := pedine_in(h)
	if lista.is_empty():
		return null
	for u in lista:
		if u.scorta >= 0:
			return u
	return lista[0]

func citta_in(h: Vector2i) -> Dictionary:
	for ci in citta:
		if ci.h[0] == h.x and ci.h[1] == h.y:
			return ci
	return {}

func hex_citta(ci: Dictionary) -> Vector2i:
	return Vector2i(int(ci.h[0]), int(ci.h[1]))

func alleati(a: String, b: String) -> bool:
	if a == b:
		return true
	var k := "|".join([a, b] if a < b else [b, a])
	return k in alleanze

func nemici(a: String, b: String) -> bool:
	return a != b and not alleati(a, b)

func citta_di(p: String) -> int:
	var n := 0
	for ci in citta:
		if ci.p == p and ci.h[0] >= 0:
			n += 1
	return n

func pedine_di(p: String, solo_vive := true) -> Array[ZPedina]:
	var out: Array[ZPedina] = []
	for u in pedine:
		if u.popolo == p and (u.viva or not solo_vive):
			out.append(u)
	return out

## Bonus dei Maghi adiacenti dello stesso popolo.
func bonus_maghi(u: ZPedina) -> int:
	var b := 0
	for v in mappa.vicino_geometrico_tutti(u.hex):
		for w in pedine_in(v):
			if w.popolo == u.popolo and w.tipo == "mago" and w.popolo == "Cavalieri" and w.scortato_da < 0 and w.paralisi == 0 and not w.ridotta:
				b += 2
	return b

func bonus_terreno(u: ZPedina) -> int:
	if u.citta >= 0:
		return 0
	return bonus_terreno_hex(u.hex)

func bonus_terreno_hex(h: Vector2i) -> int:
	match terreno(h):
		ZMappa.T.MONTAGNA: return 3
		ZMappa.T.BOSCO: return 1
	return 0

## Zona d'influenza nemica: esagoni adiacenti a un nemico in campo.
func in_zona_nemica(h: Vector2i, p: String, escluso := -1) -> bool:
	for v in mappa.vicino_geometrico_tutti(h):
		for w in pedine_in(v):
			if w.id != escluso and nemici(w.popolo, p) and not w.ingaggiata and w.paralisi == 0 and not w.ridotta:
				return true
	return false

func attaccabile(u: ZPedina) -> bool:
	return u != null and u.in_campo() and u.paralisi == 0 and not u.ridotta

# ---------------------------------------------------------------------------
# Movimento
# ---------------------------------------------------------------------------

## Pezzo che effettivamente si muove: un pezzo scortato viaggia con la sua scorta.
func _guida(u: ZPedina) -> ZPedina:
	if u.scortato_da >= 0:
		return pedine[u.scortato_da]
	return u

func punti_movimento(u: ZPedina) -> int:
	var g := _guida(u)
	if g.singolo or u.singolo:
		return maxi(g.residuo, u.residuo)
	return g.m()

func puo_muovere(u: ZPedina) -> String:
	if fase == FASE_SINGOLI:
		if not (u.singolo and u.residuo > 0):
			return "Ora si fanno gli attacchi singoli: gli altri pezzi muovono nella fase di movimento."
	elif fase != FASE_MOVIMENTO:
		return "Non è la fase di movimento."
	if u.popolo != popolo_di_mano():
		return "Non è la mossa di questo popolo."
	if not u.viva or u.scomparso:
		return "Pezzo non disponibile."
	if u.ridotta:
		return "Pezzo ridotto: resta fermo finché non viene recuperato."
	if u.m() == 0:
		return "Questo pezzo non si muove."
	var g := _guida(u)
	if g.paralisi > 0:
		return "Paralizzato nel gorgo magico per altre %d mosse." % g.paralisi
	if g.mosso or u.mosso:
		return "Ha già mosso."
	if (g.singolo or u.singolo) and punti_movimento(u) <= 0:
		return "Ha esaurito il movimento."
	return ""

## Esagoni raggiungibili: dizionario esagono -> costo. `ignora_zone` serve agli
## attacchi singoli, durante i quali non esistono zone d'influenza.
func raggiungibili(u: ZPedina, ignora_zone := false) -> Dictionary:
	var g := _guida(u)
	var budget := punti_movimento(u)
	var volante := g.vola() and u.scortato_da < 0
	# Manto magico delle Signore Amazzoni: attraversano nemici e zone d'influenza.
	var manto := zl2() and g.popolo == "Amazzoni" and g.tipo == "signore"
	var partenza := g.hex
	var costi := {partenza: 0}
	_padri = {}
	var coda: Array[Vector2i] = [partenza]
	var i := 0
	while i < coda.size():
		var h := coda[i]
		i += 1
		if h != partenza and _ferma_qui(h, g, volante, ignora_zone or manto):
			continue
		for v in vicini(h):
			var t := terreno(v)
			var costo := 1
			if not volante:
				if t == ZMappa.T.BOSCO:
					costo = 2
				elif t == ZMappa.T.MONTAGNA:
					# Una montagna si sale soltanto partendo dai suoi piedi:
					# richiede l'intera mossa.
					if h != partenza:
						continue
					costo = budget
			var nuovo: int = costi[h] + costo
			if nuovo > budget:
				continue
			if _bloccato(v, g, volante or manto):
				continue
			if not costi.has(v) or nuovo < costi[v]:
				costi[v] = nuovo
				_padri[v] = h
				coda.append(v)
	# Rimuove le destinazioni in cui non ci si può fermare.
	var out := {}
	for h in costi:
		if h != partenza and _puo_fermarsi(h, u):
			out[h] = costi[h]
	return out

var _padri := {}

## Percorso (esclusa la partenza) dell'ultimo calcolo di raggiungibili().
func _percorso(dest: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var h := dest
	while _padri.has(h):
		out.push_front(h)
		h = _padri[h]
	return out

func _ferma_qui(h: Vector2i, g: ZPedina, volante: bool, ignora_zone: bool) -> bool:
	var t := terreno(h)
	if t == ZMappa.T.GORGO:
		return true
	if not volante and t == ZMappa.T.MONTAGNA:
		return true
	var ci := citta_in(h)
	if not ci.is_empty() and nemici(ci.p, g.popolo):
		return true
	if not volante and not ignora_zone and in_zona_nemica(h, g.popolo):
		return true
	return false

func _bloccato(h: Vector2i, g: ZPedina, volante: bool) -> bool:
	var ci := citta_in(h)
	if not ci.is_empty() and nemici(ci.p, g.popolo) and not ci.g.is_empty():
		return true
	if volante:
		return false
	if ha_rete(h) and g.popolo != "Aracnidi":
		return true
	for w in pedine_in(h):
		# I pezzi ridotti sono transitabili da qualsiasi nemico.
		if nemici(w.popolo, g.popolo) and not w.ridotta:
			return true
	return false

func _puo_fermarsi(h: Vector2i, u: ZPedina) -> bool:
	var g := _guida(u)
	var ci := citta_in(h)
	if not ci.is_empty():
		if ci.p == g.popolo:
			var posti := 2 if g.scorta >= 0 else 1
			return ci.g.size() + posti <= ZRegole.MAX_GUARNIGIONE and u.scortato_da < 0 and g.scorta < 0
		return nemici(ci.p, g.popolo) and ci.g.is_empty() and g.scorta < 0
	var presenti := pedine_in(h)
	if presenti.is_empty():
		return true
	if zl2():
		# Zargo's Lords 2 (regola D): fino a due pedine dello stesso popolo per esagono.
		return presenti.size() == 1 and presenti[0].popolo == g.popolo and g.scorta < 0 and u.scortato_da < 0 and presenti[0].scorta < 0 and presenti[0].scortato_da < 0
	# Unica sovrapposizione ammessa: un fante che si pone di scorta a un altro pezzo.
	if presenti.size() == 1 and g.scorta < 0 and u.scortato_da < 0:
		return _scorta_possibile(u, presenti[0])
	return false

func _scorta_possibile(fante: ZPedina, altro: ZPedina) -> bool:
	return fante.tipo == "fante" and altro.tipo != "fante" and altro.popolo == fante.popolo \
		and altro.scortato_da < 0 and altro.scorta < 0 and not fante.scorta_cambiata \
		and not altro.scorta_cambiata and altro.paralisi == 0

func _muovi(u: ZPedina, dest: Vector2i, eventi: Array) -> void:
	var g := _guida(u)
	var gruppo: Array[ZPedina] = [g]
	if g.scorta >= 0:
		gruppo.append(pedine[g.scorta])
	var da := g.hex
	var costo: int = raggiungibili(u).get(dest, 0)
	var percorso := _percorso(dest)
	# Carica dei Cavalieri e corsa dei Serpenti: movimento interamente rettilineo.
	var dir := mappa.direzione_retta(da, dest, 16)
	var retto := dir >= 0 and _linea_percorribile(g, da, dir, mappa.distanza(da, dest))
	for w in gruppo:
		if w.citta >= 0:
			_esci_da_citta(w)
		w.hex = dest
		w.mosso = true
		if w.singolo:
			w.residuo = maxi(0, w.residuo - costo)
		w.carica_dir = dir if retto else -1
	_sporca()
	eventi.append({"t": "muovi", "u": g.id, "da": [da.x, da.y], "a": [dest.x, dest.y]})
	if terreno(dest) == ZMappa.T.GORGO:
		for w in gruppo:
			w.paralisi = 3
		_log("%s %s finisce in un gorgo magico: paralizzato per tre mosse." % [g.nome(), ZRegole.degli(g.popolo)])
		eventi.append({"t": "gorgo", "u": g.id})
	var ci := citta_in(dest)
	if not ci.is_empty():
		if ci.p == g.popolo:
			for w in gruppo:
				_entra_in_citta(w, ci)
		else:
			_conquista(ci, g, eventi)
			return
	# I ragni lasciano fino a tre reti negli esagoni attraversati.
	if g.popolo == "Aracnidi" and g.tipo == "ragno":
		var lasciate := 0
		for h in percorso.slice(0, percorso.size() - 1):
			if lasciate >= 3 or reti.size() >= 15:
				break
			if not ha_rete(h):
				reti.append([h.x, h.y])
				lasciate += 1
		if lasciate > 0:
			eventi.append({"t": "reti"})
	var presenti := pedine_in(dest)
	if presenti.size() == 2 and g.scorta < 0 and not zl2():
		var altro: ZPedina = presenti[0] if presenti[1] == g else presenti[1]
		if _scorta_possibile(g, altro):
			g.scorta = altro.id
			altro.scortato_da = g.id
			g.scorta_cambiata = true
			altro.scorta_cambiata = true
			_log("Un fante %s si pone di scorta a %s." % [ZRegole.degli(g.popolo), altro.nome()])

func _linea_percorribile(g: ZPedina, da: Vector2i, dir: int, passi: int) -> bool:
	if passi <= 0:
		return false
	var h := da
	var speso := 0
	var volante := g.vola()
	for i in passi:
		h = mappa.vicino_dir(h, dir)
		if not mappa.terra(h) or _bloccato(h, g, volante):
			return false
		var t := terreno(h)
		if not volante and t == ZMappa.T.MONTAGNA:
			return false
		if i < passi - 1 and (t == ZMappa.T.GORGO or _ferma_qui(h, g, volante, false)):
			return false
		speso += 2 if t == ZMappa.T.BOSCO and not volante else 1
	return speso <= g.m()

func _entra_in_citta(u: ZPedina, ci: Dictionary) -> void:
	if u.id not in ci.g:
		ci.g.append(u.id)
	u.citta = int(ci.id)
	_sporca()

func _esci_da_citta(u: ZPedina) -> void:
	if u.citta >= 0:
		citta[u.citta].g.erase(u.id)
	u.citta = -1
	_sporca()

func _conquista(ci: Dictionary, conquistatore: ZPedina, eventi: Array) -> void:
	var vecchio: String = ci.p
	if opzione("lampo"):
		# Guerra lampo: la città conquistata viene tolta dalla mappa e tenuta
		# dal conquistatore come trofeo.
		_punti_conquista(conquistatore.popolo, vecchio, 1.0)
		for id in ci.g.duplicate():
			pedine[id].viva = false
			pedine[id].citta = -1
		ci.g.clear()
		var hc := hex_citta(ci)
		ci.h = [-1, -1]
		ci.p = ""
		conquistatore.hex = hc
		if conquistatore.scorta >= 0:
			pedine[conquistatore.scorta].hex = hc
		_log("%s conquistano e radono al suolo una città %s!" % [ZRegole.Gli(conquistatore.popolo), ZRegole.degli(vecchio)])
		eventi.append({"t": "conquista", "c": ci.id, "p": conquistatore.popolo, "da": vecchio, "rasa": true, "h": [hc.x, hc.y]})
		_sporca()
		return
	ci.p = conquistatore.popolo
	for id in ci.g.duplicate():
		pedine[id].viva = false
		pedine[id].citta = -1
	ci.g.clear()
	conquistatore.hex = hex_citta(ci)
	if conquistatore.scorta >= 0:
		# La coppia si scioglie ed entrano entrambi in città.
		var s := pedine[conquistatore.scorta]
		s.scortato_da = -1
		conquistatore.scorta = -1
		s.hex = hex_citta(ci)
		_entra_in_citta(s, ci)
	_entra_in_citta(conquistatore, ci)
	_log("%s conquistano una città %s!" % [ZRegole.Gli(conquistatore.popolo), ZRegole.degli(vecchio)])
	eventi.append({"t": "conquista", "c": ci.id, "p": conquistatore.popolo, "da": vecchio})
	_sporca()

## Punteggio della Guerra lampo: 18, 16, 14 ... 4 punti per le prime otto città
## conquistate nella partita, poi 2.
func _punti_conquista(p: String, da: String, frazione: float) -> void:
	n_conquiste += 1
	var punti := 20 - 2 * n_conquiste if n_conquiste <= 8 else 2
	punti_lampo[p] = float(punti_lampo.get(p, 0)) + punti * frazione
	if da != "":
		conquiste_lampo[p].append(da)

# ---------------------------------------------------------------------------
# Ritirate ed eliminazioni
# ---------------------------------------------------------------------------

func _elimina(u: ZPedina, minaccia: String, eventi: Array) -> void:
	if not u.viva:
		return
	u.viva = false
	if u.citta >= 0:
		citta[u.citta].g.erase(u.id)
		u.citta = -1
	_log("%s %s è eliminato." % [u.nome(), ZRegole.degli(u.popolo)])
	eventi.append({"t": "elimina", "u": u.id})
	_sporca()
	if u.scorta >= 0:
		var s := pedine[u.scorta]
		u.scorta = -1
		s.scortato_da = -1
		# Perduta la scorta, lo scortato fugge del suo massimo movimento.
		if s.viva:
			_ritira(s, s.m(), minaccia, eventi)
	if u.scortato_da >= 0:
		pedine[u.scortato_da].scorta = -1
		u.scortato_da = -1

## Arretramento in linea retta, scelto dal popolo che arretra. Si viene eliminati
## se la linea incontra mare, boschi, monti, città o zone d'influenza nemiche;
## un gorgo ferma e paralizza; i pezzi amici sulla linea vengono spinti.
func _ritira(u: ZPedina, passi: int, minaccia: String, eventi: Array) -> void:
	if passi <= 0 or not u.viva:
		return
	if u.citta >= 0:
		# Chi combatte dall'interno di una città vi resta al riparo.
		return
	var u_guida := _guida(u)
	if u_guida.catturata:
		# Preso nella rete di un Reziario: se deve arretrare è eliminato.
		_log("%s %s, preso nella rete, non può arretrare." % [u_guida.nome(), ZRegole.degli(u_guida.popolo)])
		_elimina(u_guida, minaccia, eventi)
		return
	var migliore := {}
	var miglior_punteggio := -INF
	var riduzione := {}
	for dir in 6:
		var prova := _simula_ritirata(u_guida, dir, passi)
		if prova.has("ridotta"):
			# Zargo's Lords 2: contro un ostacolo il pezzo non è eliminato ma ridotto.
			if riduzione.is_empty() or int(prova.passi) > int(riduzione.passi):
				riduzione = prova
			continue
		if prova.is_empty():
			continue
		var punteggio: float = -float(prova.perdite) * 100.0
		var fine: Vector2i = prova.fine
		if in_zona_nemica(fine, u_guida.popolo):
			punteggio -= 5.0
		punteggio += float(mappa.distanza(fine, u_guida.hex))
		punteggio += rng.randf() * 0.1
		if punteggio > miglior_punteggio:
			miglior_punteggio = punteggio
			migliore = prova
	# Sacrificare un pezzo spinto conviene solo se vale meno di chi arretra.
	if not migliore.is_empty() and int(migliore.sacrificio) >= 0 and int(migliore.perdite) > u_guida.c():
		migliore = {}
	if migliore.is_empty() and not riduzione.is_empty():
		var dove := Vector2i(int(riduzione.fine[0]), int(riduzione.fine[1]))
		if dove != u_guida.hex:
			_sposta_gruppo(u_guida, dove, eventi, "ritira")
		u_guida.ridotta = true
		if u_guida.scorta >= 0:
			pedine[u_guida.scorta].ridotta = true
		_log("%s %s arretra contro un ostacolo e viene ridotto." % [u_guida.nome(), ZRegole.degli(u_guida.popolo)])
		eventi.append({"t": "ridotta", "u": u_guida.id})
		return
	if migliore.is_empty():
		_log("%s %s non ha via di fuga." % [u_guida.nome(), ZRegole.degli(u_guida.popolo)])
		var gruppo := [u_guida]
		if u_guida.scorta >= 0:
			gruppo.append(pedine[u_guida.scorta])
		for w in gruppo:
			w.scortato_da = -1
			w.scorta = -1
			_elimina(w, minaccia, eventi)
		return
	if int(migliore.sacrificio) >= 0:
		_elimina(pedine[int(migliore.sacrificio)], minaccia, eventi)
	for spinta in migliore.spinte:
		var w: ZPedina = pedine[spinta[0]]
		var dest := Vector2i(spinta[1][0], spinta[1][1])
		_sposta_gruppo(w, dest, eventi, "ritira")
		if terreno(dest) == ZMappa.T.GORGO:
			w.paralisi = 3
			if w.scorta >= 0:
				pedine[w.scorta].paralisi = 3
	_sposta_gruppo(u_guida, migliore.fine, eventi, "ritira")
	if migliore.gorgo:
		u_guida.paralisi = 3
		if u_guida.scorta >= 0:
			pedine[u_guida.scorta].paralisi = 3
	var passi_fatti := mappa.distanza(Vector2i(migliore.da[0], migliore.da[1]), migliore.fine)
	_log("%s %s arretra di %d %s." % [u_guida.nome(), ZRegole.degli(u_guida.popolo), passi_fatti, "esagono" if passi_fatti == 1 else "esagoni"])

func _sposta_gruppo(w: ZPedina, dest: Vector2i, eventi: Array, tipo: String) -> void:
	var da := w.hex
	w.hex = dest
	if w.scorta >= 0:
		pedine[w.scorta].hex = dest
	_sporca()
	eventi.append({"t": tipo, "u": w.id, "da": [da.x, da.y], "a": [dest.x, dest.y]})

func _ostacolo_ritirata(h: Vector2i, p: String, escludi: Array) -> bool:
	return _tipo_ostacolo(h, p) != ""

## "" = libero; "terreno" = mare, boschi, monti, città o reti; "nemico" = pezzi
## o zone d'influenza nemiche.
func _tipo_ostacolo(h: Vector2i, p: String) -> String:
	if not mappa.terra(h):
		return "terreno"
	if terreno(h) in [ZMappa.T.BOSCO, ZMappa.T.MONTAGNA]:
		return "terreno"
	if not citta_in(h).is_empty():
		return "terreno"
	if ha_rete(h) and p != "Aracnidi":
		return "terreno"
	for w in pedine_in(h):
		if nemici(w.popolo, p):
			return "nemico"
	return "nemico" if in_zona_nemica(h, p) else ""

func _simula_ritirata(u: ZPedina, dir: int, passi: int) -> Dictionary:
	var h := u.hex
	var percorso: Array[Vector2i] = []
	var gorgo := false
	for i in passi:
		h = mappa.vicino_dir(h, dir)
		var ost := _tipo_ostacolo(h, u.popolo)
		if ost == "terreno" and zl2():
			var fine_r: Vector2i = percorso[-1] if not percorso.is_empty() else u.hex
			if not pedine_in(fine_r).is_empty() and fine_r != u.hex:
				return {}
			return {"ridotta": true, "fine": [fine_r.x, fine_r.y], "passi": percorso.size()}
		if ost != "":
			return {}
		percorso.append(h)
		if terreno(h) == ZMappa.T.GORGO:
			gorgo = true
			break
	var fine := percorso[-1]
	var spinte := []
	var perdite := 0
	var sacrificio := -1
	if zl2():
		# Zargo's Lords 2: si passa sopra i propri pezzi; ci si ferma solo dove
		# l'ammassamento lo consente (al massimo due pedine dello stesso popolo).
		var qui := pedine_in(fine).filter(func(w): return w != u and w.id != u.scorta)
		if qui.size() >= 2 or (qui.size() == 1 and qui[0].popolo != u.popolo):
			return {}
		return {"fine": fine, "spinte": [], "perdite": 0, "sacrificio": -1, "gorgo": gorgo, "da": [u.hex.x, u.hex.y]}
	# Pezzi amici sull'esagono finale: vengono spinti avanti lungo la stessa linea.
	var occupante := pedina_in(fine)
	var cursore := fine
	while occupante != null and occupante != u and occupante != pedine[u.scorta if u.scorta >= 0 else u.id]:
		var avanti := mappa.vicino_dir(cursore, dir)
		if _ostacolo_ritirata(avanti, occupante.popolo, []):
			# Si può scegliere di sacrificare il pezzo spinto invece di chi arretra.
			perdite = occupante.c()
			sacrificio = occupante.id
			break
		spinte.push_front([occupante.id, [avanti.x, avanti.y]])
		cursore = avanti
		if terreno(avanti) == ZMappa.T.GORGO:
			break
		occupante = pedina_in(avanti)
	return {"fine": fine, "spinte": spinte, "perdite": perdite, "sacrificio": sacrificio, "gorgo": gorgo, "da": [u.hex.x, u.hex.y]}

# ---------------------------------------------------------------------------
# Combattimento
# ---------------------------------------------------------------------------

func forza_attacco(att: Array, difensore: ZPedina) -> int:
	var tot := 0
	for u in att:
		tot += valore(u) + bonus_maghi(u) + bonus_carica(u, difensore)
	return tot

func forza_difesa(dif: Array) -> int:
	var tot := 0
	for u in dif:
		tot += valore(u) + bonus_maghi(u) + bonus_terreno(u)
	return tot

## Carica del Signore Cavaliere: +3 se l'urto prosegue la linea della carica,
## +1 se il nemico è colpito di fianco.
func bonus_carica(u: ZPedina, dif: ZPedina) -> int:
	if dif == null or u.popolo != "Cavalieri" or u.tipo != "signore" or u.carica_dir < 0 or not u.mosso:
		return 0
	if mappa.vicino_dir(u.hex, u.carica_dir) == dif.hex:
		return 3
	return 1 if mappa.adiacenti(u.hex, dif.hex) else 0

func puo_attaccare(u: ZPedina) -> String:
	if u.popolo != popolo_di_mano():
		return "Non è il suo turno."
	if not u.viva or u.scomparso:
		return "Pezzo non disponibile."
	if u.agito:
		return "Ha già combattuto in questa mossa."
	if u.paralisi > 0:
		return "Paralizzato nel gorgo."
	if u.scortato_da >= 0:
		return "Un pezzo scortato non ha alcun potere."
	if u.ridotta:
		return "Pezzo ridotto: non può combattere."
	if ZRegole.arciere(u.tipo) or u.tipo == "lanciafiamme":
		return "In attacco questo pezzo può soltanto tirare."
	return ""

## Zargo's Lords 2: chi attacca un esagono con due pedine le affronta insieme.
func espandi_difensori(ids: Array) -> Array:
	var nuovi := []
	for id in ids:
		var x := _scorta_di(int(id))
		if x not in nuovi:
			nuovi.append(x)
		if zl2():
			for w in pedine_in(pedine[x].hex):
				if w.id not in nuovi and w.popolo == pedine[x].popolo and not w.ridotta:
					nuovi.append(w.id)
	return nuovi

## Analisi di uno scontro prima di tirare il dado (usata da interfaccia e IA).
func valuta_attacco(att_ids: Array, dif_ids: Array) -> Dictionary:
	dif_ids = espandi_difensori(dif_ids)
	var att: Array[ZPedina] = []
	var dif: Array[ZPedina] = []
	for id in att_ids:
		att.append(pedine[id])
	for id in dif_ids:
		dif.append(pedine[id])
	if att.is_empty() or dif.is_empty():
		return {"ok": false, "errore": "Scegli attaccanti e difensori."}
	var esagoni_dif := {}
	for d in dif:
		esagoni_dif[d.hex] = true
	if att.size() > 1 and esagoni_dif.size() > 1:
		return {"ok": false, "errore": "Si attacca con più pezzi un solo nemico, o con un solo pezzo più nemici."}
	for u in att:
		var e := puo_attaccare(u)
		if e != "":
			return {"ok": false, "errore": "%s: %s" % [u.nome(), e]}
		for d in dif:
			if not mappa.adiacenti(u.hex, d.hex):
				return {"ok": false, "errore": "Ogni attaccante deve essere adiacente al nemico."}
	for d in dif:
		if not nemici(d.popolo, att[0].popolo):
			return {"ok": false, "errore": "Non si attaccano i propri pezzi o gli alleati."}
		if not attaccabile(d):
			return {"ok": false, "errore": "Questo pezzo non è attaccabile."}
	var fa := forza_attacco(att, dif[0])
	var fd := forza_difesa(dif)
	var diff := fa - fd
	if ZRegole.fascia(diff) < 0:
		return {"ok": false, "errore": "Differenza %d: sotto il minimo della tabella (-5), attacco non consentito." % diff, "fa": fa, "fd": fd, "diff": diff}
	return {"ok": true, "fa": fa, "fd": fd, "diff": diff, "prob": ZRegole.probabilita(diff)}

func _risolvi(att: Array[ZPedina], dif: Array[ZPedina], eventi: Array, singolo := false) -> String:
	# Reti dei Reziari: si tirano prima di leggere l'esito dello scontro.
	for u in att:
		if u.popolo == "Aracnidi" and u.tipo == "reziario":
			var dr := rng.randi_range(1, 6)
			var r: String = ZRegole.TABELLA_RETI[dr - 1]
			eventi.append({"t": "rete", "u": u.id, "dado": dr, "esito": r, "dif": dif.map(func(d): return d.id)})
			if r == "E":
				_log("La rete di un Reziario (dado %d) imprigiona e uccide %s." % [dr, _elenco(dif)])
				for u2 in att:
					u2.agito = true
				for d in dif:
					_elimina(d, u.popolo, eventi)
				return "DE"
			if r == "C":
				_log("La rete di un Reziario (dado %d) cattura %s: se arretra è eliminato." % [dr, _elenco(dif)])
				for d in dif:
					d.catturata = true
	var fa := forza_attacco(att, dif[0])
	var fd := forza_difesa(dif)
	var diff := fa - fd
	var dado := rng.randi_range(1, 6)
	var esito := ZRegole.esito_combattimento(diff, dado)
	for u in att:
		u.agito = true
	eventi.append({
		"t": "combattimento", "att": att.map(func(u): return u.id), "dif": dif.map(func(u): return u.id),
		"ha": att.map(func(u): return [u.hex.x, u.hex.y]), "hd": dif.map(func(u): return [u.hex.x, u.hex.y]),
		"pa": att[0].popolo, "pd": dif[0].popolo,
		"fa": fa, "fd": fd, "diff": diff, "fascia": ZRegole.fascia(diff), "dado": dado, "esito": esito, "singolo": singolo,
	})
	_log("%s %s (%d) contro %s (%d): dado %d, differenza %d » %s" % [
		"Attacco singolo:" if singolo else "Scontro:", _elenco(att), fa, _elenco(dif), fd, dado, diff, esito])
	# La zona d'influenza del difensore cessa durante lo scontro (non conta per
	# chi gli sta intorno) e riprende alla fine; se arretrano gli attaccanti,
	# devono comunque evitarla.
	for d in dif:
		d.ingaggiata = not esito.begins_with("A")
	_applica_esito(esito, att, dif, eventi)
	for d in dif:
		d.ingaggiata = false
		d.catturata = false
	return esito

func _applica_esito(esito: String, att: Array[ZPedina], dif: Array[ZPedina], eventi: Array) -> void:
	var p_att := att[0].popolo
	var p_dif := dif[0].popolo
	if esito == "AE":
		for u in att:
			_elimina(u, p_dif, eventi)
	elif esito == "DE":
		for d in dif:
			_elimina(d, p_att, eventi)
	elif esito.begins_with("A"):
		for u in att:
			_ritira(u, int(esito.right(1)), p_dif, eventi)
	elif esito.begins_with("D"):
		for d in dif:
			var passi := int(esito.right(1))
			# Zargo's Lords 2, regola H: D5 vale D4 per i fanti dei Cavalieri
			# e i fantarcieri degli Alati.
			if zl2() and passi == 5 and ((d.popolo == "Cavalieri" and d.tipo == "fante") or (d.popolo == "Alati" and d.tipo == "fantarcere")):
				passi = 4
			_ritira(d, passi, p_att, eventi)

func _elenco(lista: Array) -> String:
	var nomi := {}
	for u in lista:
		var k: String = u.nome()
		nomi[k] = nomi.get(k, 0) + 1
	var parti: PackedStringArray = []
	for k in nomi:
		parti.append(("%d × %s" % [nomi[k], k]) if nomi[k] > 1 else k)
	return "%s %s" % [", ".join(parti), ZRegole.degli(lista[0].popolo)]

## Assedio: occorrono almeno tanti assedianti quanti pezzi di guarnigione;
## la guarnigione combatte come un solo pezzo e, non potendo arretrare,
## viene eliminata da qualsiasi esito favorevole all'attaccante.
func valuta_assedio(att_ids: Array, cid: int) -> Dictionary:
	if cid < 0 or cid >= citta.size():
		return {"ok": false, "errore": "Città inesistente."}
	var ci: Dictionary = citta[cid]
	if att_ids.is_empty():
		return {"ok": false, "errore": "Scegli gli assedianti."}
	for id in att_ids:
		var u := pedine[id]
		var e := puo_attaccare(u)
		if e != "":
			return {"ok": false, "errore": "%s: %s" % [u.nome(), e]}
		if not mappa.adiacenti(u.hex, hex_citta(ci)):
			return {"ok": false, "errore": "Gli assedianti devono essere adiacenti alla città."}
		if not nemici(ci.p, u.popolo):
			return {"ok": false, "errore": "Non si assedia una città amica."}
	return {"ok": true, "assedianti": att_ids.size()}

func _assedio(att: Array[ZPedina], ci: Dictionary, eventi: Array) -> void:
	var p_att := att[0].popolo
	if ci.g.is_empty():
		_conquista(ci, att[0], eventi)
		for u in att:
			u.agito = true
		return
	var gu: Array[ZPedina] = []
	for id in ci.g:
		gu.append(pedine[id])
	eventi.append({"t": "rivela", "c": ci.id, "g": ci.g.duplicate()})
	if att.size() < gu.size():
		_log("La guarnigione si rivela: %d pezzi. Servono almeno altrettanti assedianti." % gu.size())
		for u in att:
			u.agito = true
		eventi.append({"t": "assedio_respinto", "c": ci.id, "n": gu.size()})
		return
	var fa := 0
	for u in att:
		fa += valore(u) + bonus_maghi(u)
	var fd := 0
	for g in gu:
		fd += valore(g)
	var diff := fa - fd
	for u in att:
		u.agito = true
	if ZRegole.fascia(diff) < 0:
		_log("Assedianti troppo deboli contro la guarnigione (%d contro %d): eliminati." % [fa, fd])
		eventi.append({"t": "combattimento", "att": att.map(func(u): return u.id), "dif": ci.g.duplicate(), "fa": fa, "fd": fd, "diff": diff, "fascia": -1, "dado": 0, "esito": "AE", "citta": ci.id, "ha": att.map(func(u): return [u.hex.x, u.hex.y]), "hd": [ci.h], "pa": att[0].popolo, "pd": ci.p})
		for u in att:
			_elimina(u, ci.p, eventi)
		return
	var dado := rng.randi_range(1, 6)
	var esito := ZRegole.esito_combattimento(diff, dado)
	eventi.append({"t": "combattimento", "att": att.map(func(u): return u.id), "dif": ci.g.duplicate(), "fa": fa, "fd": fd, "diff": diff, "fascia": ZRegole.fascia(diff), "dado": dado, "esito": esito, "citta": ci.id, "ha": att.map(func(u): return [u.hex.x, u.hex.y]), "hd": [ci.h], "pa": att[0].popolo, "pd": ci.p})
	_log("Assedio a una città %s: %d contro %d, dado %d » %s" % [ZRegole.degli(ci.p), fa, fd, dado, esito])
	if zl2() and esito in ["D1", "D3"]:
		# Zargo's Lords 2, regola I: contro una città D1 e D3 valgono A1.
		esito = "A1"
	if esito.begins_with("D"):
		# Il primo assediante entra: si preferisce un fante.
		var entra: ZPedina = att[0]
		for u in att:
			if u.tipo == "fante" and u.scorta < 0:
				entra = u
				break
		_conquista(ci, entra, eventi)
	elif esito == "AE":
		for u in att:
			_elimina(u, ci.p, eventi)
	else:
		for u in att:
			_ritira(u, int(esito.right(1)), ci.p, eventi)

# ---------------------------------------------------------------------------
# Tiri: frecce, fiamme, visioni
# ---------------------------------------------------------------------------

func tipo_tiro(u: ZPedina) -> String:
	if u.ridotta:
		return ""
	if ZRegole.arciere(u.tipo):
		return "frecce"
	if u.popolo == "Amazzoni" and u.tipo == "arciere":
		return "cavallo"
	if u.popolo == "Aracnidi" and u.tipo == "signore":
		return "dardi"
	if ZRegole.fiamme(u.popolo, u.tipo):
		return "fiamme"
	if ZRegole.visioni(u.popolo, u.tipo):
		return "visione"
	return ""

func gittata(u: ZPedina) -> int:
	var t := tipo_tiro(u)
	if zl2():
		# Zargo's Lords 2: portata base 2; la magia minore la allunga.
		match t:
			"frecce": return 8 if accanto_a_incantatore(u) else 2
			"cavallo": return 5 if accanto_a_incantatore(u) else 2
			"fiamme":
				if u.tipo == "signore":
					return 5
				return 5 if accanto_a_incantatore(u, ["signore"]) else 2
			"visione", "dardi": return 5
		return 0
	match t:
		"frecce": return 8
		"fiamme", "visione", "cavallo", "dardi": return 5
	return 0

## Tipi di pezzo che praticano la magia (Signori, Maghi, Monaci Illusionisti).
const INCANTATORI := ["signore", "mago", "illusionista"]

func incantatore(u: ZPedina) -> bool:
	return u.tipo in INCANTATORI

## Magia minore (Frecce incantate, Pioggia di fiamme): il tiratore deve stare
## nella zona d'influenza di un incantatore attivo del suo popolo.
func accanto_a_incantatore(u: ZPedina, tipi: Array = INCANTATORI) -> bool:
	for v in mappa.vicino_geometrico_tutti(u.hex):
		for w in pedine_in(v):
			if w.popolo == u.popolo and w.tipo in tipi and w.attivo() and w.muta < turno_globale:
				return true
	return false

func valuta_tiro(u: ZPedina, b: ZPedina) -> Dictionary:
	var tipo := tipo_tiro(u)
	if tipo == "":
		return {"ok": false, "errore": "Questo pezzo non può tirare."}
	if u.popolo != popolo_di_mano():
		return {"ok": false, "errore": "Non è il suo turno."}
	if not u.viva or u.scomparso or u.paralisi > 0 or u.scortato_da >= 0:
		return {"ok": false, "errore": "Pezzo non disponibile."}
	if u.agito:
		return {"ok": false, "errore": "Ha già agito in questa mossa."}
	if fase == FASE_SINGOLI:
		if not (u.popolo == "Draghi" and u.tipo == "signore" and not u.mosso):
			return {"ok": false, "errore": "Prima di muovere può fiammeggiare solo il Signore Drago; gli altri lanci si fanno nella fase dei lanci."}
	elif fase != FASE_LANCI:
		return {"ok": false, "errore": "Frecce, fiamme e visioni si lanciano nella fase dei lanci, dopo il movimento."}
	if b == null or not nemici(b.popolo, u.popolo):
		return {"ok": false, "errore": "Scegli un nemico."}
	if not attaccabile(b):
		return {"ok": false, "errore": "Archi, fuoco e visioni non hanno presa su città e pezzi nei gorghi."}
	var d := mappa.distanza(u.hex, b.hex)
	if d > gittata(u):
		return {"ok": false, "errore": "Bersaglio fuori portata (%d esagoni, massimo %d)." % [d, gittata(u)]}
	if tipo in ["frecce", "cavallo", "dardi"]:
		var e := _linea_di_tiro(u, b)
		if e != "":
			return {"ok": false, "errore": e}
		var serve: int = ZRegole.FRECCE_NECESSARIE[_tab_popolo(b)][b.tipo]
		if tipo == "dardi":
			serve -= 1   # le frecce avvelenate sono più efficaci
		return {"ok": true, "tipo": tipo, "distanza": d, "servono": serve, "gia": b.colpi}
	var ostacolo := _linea_di_tiro(u, b)
	if ostacolo != "":
		return {"ok": false, "errore": ostacolo}
	if tipo == "fiamme":
		var serve: int = ZRegole.VAMPE_NECESSARIE[_tab_popolo(b)][b.tipo]
		if serve == 0:
			return {"ok": false, "errore": "Il popolo dei Draghi è immune al fuoco."}
		return {"ok": true, "tipo": tipo, "distanza": d, "servono": serve, "gia": b.colpi}
	return {"ok": true, "tipo": tipo, "distanza": d}

func _tab_popolo(b: ZPedina) -> String:
	return "Magia" if b.tipo == "megadrago" else b.popolo

## Esagoni attraversati dal tiro, esclusi tiratore e bersaglio: la retta fra i
## centri (o, attraverso le cuciture dei bordi, il percorso più breve).
func esagoni_in_mezzo(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var d := mappa.distanza(a, b)
	var pa := mappa.centro_px(a)
	var pb := mappa.centro_px(b)
	if pa.distance_to(pb) <= (d + 0.5) * mappa.raggio_px * sqrt(3.0):
		var passi := maxi(2, d * 6)
		for i in range(1, passi):
			var h := mappa.esagono_da_px(pa.lerp(pb, i / float(passi)))
			if h != a and h != b and h not in out:
				out.append(h)
		return out
	var h := a
	while h != b and out.size() < 20:
		var migliore := h
		for v in mappa.vicino_geometrico_tutti(h):
			if mappa.distanza(v, b) < mappa.distanza(migliore, b):
				migliore = v
		if migliore == h:
			break
		h = migliore
		if h != b:
			out.append(h)
	return out

func _linea_di_tiro(u: ZPedina, b: ZPedina) -> String:
	var tipo := tipo_tiro(u)
	var frecce := tipo in ["frecce", "cavallo", "dardi"]
	if frecce:
		if terreno(u.hex) == ZMappa.T.BOSCO and u.citta < 0:
			return "Non si può tirare da dentro un bosco."
		if terreno(b.hex) == ZMappa.T.BOSCO:
			return "Non si può tirare dentro un bosco."
	if zl2() and terreno(b.hex) == ZMappa.T.MONTAGNA:
		return "Non si tira dentro una montagna."
	var lungo: Array[Vector2i] = []
	if tipo == "frecce" and not zl2():
		# Gioco base: le frecce volano soltanto in linea retta lungo gli esagoni.
		var dir := mappa.direzione_retta(u.hex, b.hex, 8)
		if dir < 0:
			return "Le frecce volano soltanto in linea retta lungo gli esagoni."
		var h := u.hex
		while true:
			h = mappa.vicino_dir(h, dir)
			if h == b.hex:
				break
			lungo.append(h)
	else:
		lungo = esagoni_in_mezzo(u.hex, b.hex)
	for h in lungo:
		var t := terreno(h)
		if t in [ZMappa.T.MARE, ZMappa.T.PONTE, ZMappa.T.VUOTO]:
			return "Frecce, fiamme e visioni non passano sopra il mare né sopra i ponti di nuvole."
		if not citta_in(h).is_empty():
			return "Una città blocca la linea di tiro."
		if t == ZMappa.T.MONTAGNA or t == ZMappa.T.GORGO:
			return "La linea di tiro è bloccata da %s." % ZMappa.NOMI_TERRENO[t].to_lower()
		if frecce and t == ZMappa.T.BOSCO:
			return "La linea di tiro è bloccata da un bosco."
	return ""

func _tiro(u: ZPedina, b: ZPedina, eventi: Array) -> void:
	var v := valuta_tiro(u, b)
	var dado := rng.randi_range(1, 6)
	u.agito = true
	if v.tipo == "visione":
		var fuga := ZRegole.fuga_visione(dado, v.distanza, b.m())
		eventi.append({"t": "tiro", "tipo": "visione", "u": u.id, "b": b.id, "dado": dado, "distanza": v.distanza, "fuga": fuga})
		_log("Visione di %s su %s %s: dado %d, distanza %d » fuga di %d." % [u.nome(), b.nome(), ZRegole.degli(b.popolo), dado, v.distanza, fuga])
		_ritira(b, fuga, u.popolo, eventi)
		return
	# Zargo's Lords 2: +1 al dado contro un esagono con due pedine; le fiamme
	# contro un bosco +2.
	var dado_mod := dado
	if zl2() and pedine_in(b.hex).size() >= 2:
		dado_mod += 1
	if v.tipo == "fiamme" and terreno(b.hex) == ZMappa.T.BOSCO:
		dado_mod += 2
	dado_mod = mini(dado_mod, 6)
	var colpi := 0
	match v.tipo:
		"frecce": colpi = ZRegole.frecce(dado_mod, v.distanza)
		"fiamme": colpi = ZRegole.vampe(dado_mod, v.distanza)
		_: colpi = ZRegole.colpi_arcieri_cavallo(dado_mod, v.distanza)
	b.colpi += colpi
	var eliminato: bool = b.colpi >= int(v.servono)
	eventi.append({"t": "tiro", "tipo": v.tipo, "u": u.id, "b": b.id, "dado": dado, "dm": dado_mod, "distanza": v.distanza, "colpi": colpi, "totale": b.colpi, "servono": v.servono, "eliminato": eliminato})
	_log("%s di %s su %s: dado %d, distanza %d » %d a segno (%d/%d)." % [{"frecce": "Frecce", "fiamme": "Fiamme", "cavallo": "Frecce", "dardi": "Frecce avvelenate"}[v.tipo], u.nome(), b.nome(), dado, v.distanza, colpi, b.colpi, v.servono])
	if eliminato:
		_elimina(b, u.popolo, eventi)

# ---------------------------------------------------------------------------
# Attacchi singoli
# ---------------------------------------------------------------------------

func puo_attacco_singolo(u: ZPedina) -> String:
	if fase != FASE_SINGOLI or u.popolo != popolo_di_mano():
		return "Gli attacchi singoli si fanno nella loro fase, prima di qualsiasi altro movimento."
	if not ZRegole.attacco_singolo(u.popolo, u.tipo):
		return "Solo Alati, Falchi, Serpenti e Pantere attaccano singolarmente."
	if u.scortato_da >= 0 or u.paralisi > 0 or not u.attivo():
		return "Pezzo non disponibile."
	if u.singolo:
		if u.tipo == "serpente" and u.residuo > 0 and u.carica_dir >= 0:
			return ""
		return "Ha già compiuto il suo attacco singolo."
	if u.mosso or u.agito:
		return "Ha già agito."
	return ""

## Esagoni da cui il pezzo può attaccare singolarmente il bersaglio.
func basi_attacco_singolo(u: ZPedina, b: ZPedina) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if puo_attacco_singolo(u) != "" or not attaccabile(b) or not nemici(b.popolo, u.popolo):
		return out
	var serpente_in_corsa := u.tipo == "serpente" and u.singolo
	if mappa.adiacenti(u.hex, b.hex):
		if not serpente_in_corsa or mappa.vicino_dir(u.hex, u.carica_dir) == b.hex:
			out.append(u.hex)
	if serpente_in_corsa:
		# Il serpente travolge in linea retta: prosegue solo lungo la stessa direzione.
		var h := u.hex
		var speso := 0
		while true:
			h = mappa.vicino_dir(h, u.carica_dir)
			var t := terreno(h)
			if not mappa.terra(h) or not pedine_in(h).is_empty() or not citta_in(h).is_empty() or t in [ZMappa.T.MONTAGNA, ZMappa.T.GORGO]:
				break
			speso += 2 if t == ZMappa.T.BOSCO else 1
			if speso > u.residuo:
				break
			if mappa.vicino_dir(h, u.carica_dir) == b.hex:
				out.append(h)
				break
		return out
	var rag := raggiungibili(u, true)
	for v in mappa.vicino_geometrico_tutti(b.hex):
		if rag.has(v) and pedine_in(v).is_empty() and citta_in(v).is_empty():
			if u.tipo == "serpente" and v != u.hex:
				# Il serpente carica in linea retta fino al nemico.
				var dir := mappa.direzione_retta(u.hex, v, 16)
				if dir < 0 or dir != mappa.direzione_retta(v, b.hex, 2) or not _linea_percorribile(u, u.hex, dir, mappa.distanza(u.hex, v)):
					continue
			out.append(v)
	return out

func _attacco_singolo(u: ZPedina, b: ZPedina, base: Vector2i, eventi: Array) -> void:
	var budget := u.residuo if u.singolo else u.m()
	var costo := 0
	if base != u.hex:
		if u.tipo == "serpente" and u.singolo:
			var h := u.hex
			while h != base:
				h = mappa.vicino_dir(h, u.carica_dir)
				costo += 2 if terreno(h) == ZMappa.T.BOSCO else 1
		else:
			costo = int(raggiungibili(u, true).get(base, 0))
		var da := u.hex
		u.hex = base
		_sporca()
		eventi.append({"t": "muovi", "u": u.id, "da": [da.x, da.y], "a": [base.x, base.y]})
	if u.tipo == "serpente":
		u.carica_dir = mappa.direzione_retta(base, b.hex, 2)
	singoli_aperti = true
	var att: Array[ZPedina] = [u]
	var dif: Array[ZPedina] = [b]
	var esito := _risolvi(att, dif, eventi, true)
	u.singolo = true
	u.agito = true
	var vinto := esito.begins_with("D") and u.viva and u.hex == base
	if vinto:
		u.residuo = maxi(0, budget - costo)
		u.mosso = false
		if u.tipo == "serpente" and u.residuo > 0:
			# Il serpente avanza nell'esagono lasciato libero e può proseguire la carica.
			var avanti := mappa.vicino_dir(u.hex, u.carica_dir)
			var costo_avanti := 2 if terreno(avanti) == ZMappa.T.BOSCO else 1
			if mappa.terra(avanti) and pedine_in(avanti).is_empty() and citta_in(avanti).is_empty() and terreno(avanti) not in [ZMappa.T.GORGO, ZMappa.T.MONTAGNA] and costo_avanti <= u.residuo:
				var da := u.hex
				u.hex = avanti
				u.residuo -= costo_avanti
				_sporca()
				eventi.append({"t": "muovi", "u": u.id, "da": [da.x, da.y], "a": [avanti.x, avanti.y]})
	else:
		u.residuo = 0
		u.mosso = true

# ---------------------------------------------------------------------------
# Esecuzione dei comandi
# ---------------------------------------------------------------------------

func esegui(az: Dictionary) -> Dictionary:
	var eventi: Array = []
	var errore := _esegui(az, eventi)
	if errore != "":
		return {"ok": false, "errore": errore, "eventi": []}
	_controlla_vittoria(eventi)
	cambiata.emit()
	return {"ok": true, "errore": "", "eventi": eventi}

func _hex(v) -> Vector2i:
	return Vector2i(int(v[0]), int(v[1]))

## Chi attacca una coppia scorta + scortato colpisce sempre la scorta.
func _scorta_di(id: int) -> int:
	var u := pedine[id]
	return u.scortato_da if u.scortato_da >= 0 else id

func _esegui(az: Dictionary, eventi: Array) -> String:
	if fase == FASE_FINITA:
		return "La partita è terminata."
	if az.has("b"):
		az = az.duplicate()
		az.b = _scorta_di(int(az.b))
	if az.has("att"):
		az = az.duplicate()
		var unici := []
		for id in az.att:
			if int(id) not in unici:
				unici.append(int(id))
		az.att = unici
	if az.has("dif"):
		az = az.duplicate()
		az.dif = espandi_difensori(az.dif)
	match String(az.get("a", "")):
		"piazza":
			return _piazza(pedine[int(az.u)], _hex(az.h))
		"piazza_citta":
			return _piazza_citta(citta[int(az.c)], _hex(az.h))
		"togli":
			return _togli_schierata(pedine[int(az.u)])
		"auto_schieramento":
			if fase != FASE_SCHIERAMENTO:
				return "Lo schieramento è concluso."
			schieramento_automatico(popolo_di_mano())
			return ""
		"fine_schieramento":
			return _fine_schieramento(eventi)
		"proponi":
			return _proponi(String(az.a2), eventi)
		"rispondi":
			return _rispondi(String(az.da), String(az.a2), bool(az.si), eventi)
		"rompi":
			return _rompi(String(az.con))
		"fase":
			return _avanza_fase(eventi)
		"muovi":
			var u := pedine[int(az.u)]
			var e := puo_muovere(u)
			if e != "":
				return e
			var dest := _hex(az.h)
			if not raggiungibili(u).has(dest):
				return "Destinazione non raggiungibile."
			_muovi(u, dest, eventi)
			return ""
		"singolo":
			var u := pedine[int(az.u)]
			var b := pedine[int(az.b)]
			var e := puo_attacco_singolo(u)
			if e != "":
				return e
			var base := _hex(az.h)
			if base not in basi_attacco_singolo(u, b):
				return "Il bersaglio non è raggiungibile per un attacco singolo."
			_attacco_singolo(u, b, base, eventi)
			return ""
		"scompari":
			return _scompari(pedine[int(az.u)], eventi)
		"ricompari":
			return _ricompari(pedine[int(az.u)], _hex(az.h), eventi)
		"togli_scorta":
			return _togli_scorta(pedine[int(az.u)])
		"trasforma":
			return _trasforma(pedine[int(az.u)], eventi)
		"passaggio":
			return _passaggio(pedine[int(az.u)], int(az.c), eventi)
		"magia":
			return _magia(String(az.s), _hex(az.h), az.get("h2", null), int(az.get("punti", 0)), eventi)
		"tiro":
			var u := pedine[int(az.u)]
			var b := pedine[int(az.b)]
			var v := valuta_tiro(u, b)
			if not v.ok:
				return v.errore
			_tiro(u, b, eventi)
			return ""
		"attacco":
			if fase != FASE_COMBATTIMENTO:
				return "Gli scontri corpo a corpo si risolvono nella fase dei combattimenti."
			var v := valuta_attacco(az.att, az.dif)
			if not v.ok:
				return v.errore
			mischia_iniziata = true
			var att: Array[ZPedina] = []
			var dif: Array[ZPedina] = []
			for id in az.att:
				att.append(pedine[int(id)])
			for id in az.dif:
				dif.append(pedine[int(id)])
			_risolvi(att, dif, eventi)
			return ""
		"assedio":
			if fase != FASE_COMBATTIMENTO:
				return "Gli assedi si risolvono nella fase di combattimento."
			var v := valuta_assedio(az.att, int(az.c))
			if not v.ok:
				return v.errore
			mischia_iniziata = true
			var att: Array[ZPedina] = []
			for id in az.att:
				att.append(pedine[int(id)])
			_assedio(att, citta[int(az.c)], eventi)
			return ""
	return "Comando sconosciuto."

# --- Schieramento ----------------------------------------------------------

func puo_schierare_in(p: String, h: Vector2i) -> bool:
	return mappa.terra(h) and continenti[mappa.continente(h)] == p if mappa.continente(h) >= 0 else false

func _piazza(u: ZPedina, h: Vector2i) -> String:
	if fase != FASE_SCHIERAMENTO or u.popolo != popolo_di_mano():
		return "Non è il momento di schierare questo pezzo."
	if not puo_schierare_in(u.popolo, h):
		return "Si schiera soltanto sui propri continenti."
	var ci := citta_in(h)
	if not ci.is_empty():
		if ci.p != u.popolo:
			return "Città altrui."
		if u.citta == ci.id:
			return ""
		if ci.g.size() >= ZRegole.MAX_GUARNIGIONE:
			return "Una città ospita al massimo quattro pezzi di guarnigione."
		_esci_da_citta(u)
		u.hex = h
		u.schierata = true
		_entra_in_citta(u, ci)
		return ""
	var presenti := pedine_in(h)
	if not presenti.is_empty() and presenti[0] != u:
		return "Esagono già occupato."
	_esci_da_citta(u)
	u.hex = h
	u.schierata = true
	_sporca()
	return ""

func _togli_schierata(u: ZPedina) -> String:
	if fase != FASE_SCHIERAMENTO or u.popolo != popolo_di_mano():
		return "Non è il momento."
	_esci_da_citta(u)
	u.schierata = false
	u.hex = Vector2i(-1, -1)
	_sporca()
	return ""

func citta_valida(ci: Dictionary, h: Vector2i) -> String:
	if not puo_schierare_in(ci.p, h):
		return "Le città si pongono sui propri continenti."
	if mappa.costa(h):
		return "Le città non possono essere piazzate in esagoni di costa."
	if terreno(h) == ZMappa.T.GORGO:
		return "Non si costruisce in un gorgo magico."
	if zl2():
		# Zargo's Lords 2, regola B: niente boschi, montagne, gorghi, coste e
		# ponti, né esagoni adiacenti.
		if terreno(h) != ZMappa.T.PIANURA:
			return "Le città vanno in pianura."
		for v in mappa.vicino_geometrico_tutti(h):
			if terreno(v) != ZMappa.T.PIANURA or mappa.costa(v):
				return "Le città non possono essere adiacenti a boschi, montagne, gorghi, coste o ponti."
	for altra in citta:
		if altra.id != ci.id and altra.h[0] >= 0 and mappa.distanza(hex_citta(altra), h) < ZRegole.DISTANZA_MIN_CITTA:
			return "Le città devono distare almeno quattro esagoni l'una dall'altra."
	var presenti := pedine_in(h)
	if not presenti.is_empty():
		return "Esagono occupato."
	return ""

func _piazza_citta(ci: Dictionary, h: Vector2i) -> String:
	if fase != FASE_SCHIERAMENTO or ci.p != popolo_di_mano():
		return "Non è il momento di piazzare questa città."
	var e := citta_valida(ci, h)
	if e != "":
		return e
	ci.h = [h.x, h.y]
	for id in ci.g:
		pedine[id].hex = h
	_sporca()
	return ""

func schieramento_automatico(p: String) -> void:
	var conts := continenti_di(p)
	var mie_citta: Array[Dictionary] = []
	for ci in citta:
		if ci.p == p:
			mie_citta.append(ci)
	# 1. Città, ben distribuite sui continenti del popolo.
	for k in mie_citta.size():
		var ci: Dictionary = mie_citta[k]
		if ci.h[0] >= 0:
			continue
		var cont: int = conts[k % conts.size()]
		var candidati := mappa.esagoni_continente(cont)
		_mescola(candidati)
		var scelto := Vector2i(-1, -1)
		var miglior := -INF
		for h in candidati.slice(0, 160):
			if citta_valida(ci, h) != "":
				continue
			var punteggio := 0.0
			var piu_vicina := 99
			for altra in citta:
				if altra.h[0] >= 0 and altra.id != ci.id:
					piu_vicina = mini(piu_vicina, mappa.distanza(hex_citta(altra), h))
			punteggio += minf(piu_vicina, 9) * 2.0
			if terreno(h) == ZMappa.T.MONTAGNA:
				punteggio += 3.0
			punteggio += rng.randf() * 4.0
			if punteggio > miglior:
				miglior = punteggio
				scelto = h
		if scelto.x >= 0:
			ci.h = [scelto.x, scelto.y]
	# 2. Guarnigioni: due fanti in ogni città.
	var fanti: Array[ZPedina] = []
	var altri: Array[ZPedina] = []
	for u in pedine:
		if u.popolo == p and not u.schierata:
			(fanti if u.tipo == "fante" else altri).append(u)
	for ci in mie_citta:
		while ci.g.size() < 2 and not fanti.is_empty() and ci.h[0] >= 0:
			var f: ZPedina = fanti.pop_back()
			f.hex = hex_citta(ci)
			f.schierata = true
			_entra_in_citta(f, ci)
	# 3. Il resto attorno alle città, i Signori in prima linea.
	var resto: Array[ZPedina] = altri + fanti
	var per_cont := {}
	for cont in conts:
		var es := mappa.esagoni_continente(cont)
		var cc: Array[Vector2i] = []
		for ci in mie_citta:
			if ci.h[0] >= 0 and mappa.continente(hex_citta(ci)) == cont:
				cc.append(hex_citta(ci))
		var ordinati := []
		for h in es:
			if terreno(h) == ZMappa.T.GORGO or not citta_in(h).is_empty():
				continue
			var d := 99
			for c in cc:
				d = mini(d, mappa.distanza(c, h))
			ordinati.append([absf(d - 3.0) + rng.randf() * 2.5, h])
		ordinati.sort_custom(func(a, b): return a[0] < b[0])
		per_cont[cont] = ordinati
	var i := 0
	for u in resto:
		var cont: int = conts[i % conts.size()]
		i += 1
		var lista: Array = per_cont[cont]
		while not lista.is_empty():
			var h: Vector2i = lista.pop_front()[1]
			if pedine_in(h).is_empty():
				u.hex = h
				u.schierata = true
				_sporca()
				break
	_sporca()

func _fine_schieramento(eventi: Array) -> String:
	if fase != FASE_SCHIERAMENTO:
		return "Lo schieramento è concluso."
	var p := popolo_di_mano()
	for ci in citta:
		if ci.p == p and ci.h[0] < 0:
			schieramento_automatico(p)
			break
	for u in pedine:
		if u.popolo == p and not u.schierata:
			schieramento_automatico(p)
			break
	for u in pedine:
		if u.popolo == p and not u.schierata:
			u.viva = false   # nessun posto libero sui continenti: il pezzo resta fuori dal gioco
	_log("%s hanno schierato le loro forze." % ZRegole.Gli(p))
	turno += 1
	if turno >= popoli.size():
		turno = 0
		_log("Schieramento concluso. Ora si possono discutere le prime alleanze.")
		if opzione("iniziativa"):
			_inizia_mese(eventi)
		else:
			_inizia_turno(eventi)
	return ""

# --- Alleanze --------------------------------------------------------------

func _proponi(a: String, eventi: Array) -> String:
	var p := popolo_di_mano()
	if popoli.size() < 3:
		return "Le alleanze esistono solo con tre o quattro giocatori."
	if fase != FASE_ALLEANZE:
		return "Le alleanze si propongono prima della propria mossa."
	if a == p or a not in popoli or alleati(a, p):
		return "Proposta non valida."
	var k := "%s>%s" % [p, a]
	if k not in proposte:
		proposte.append(k)
	_log("%s propongono un'alleanza %s." % [ZRegole.Gli(p), ZRegole.agli(a)])
	eventi.append({"t": "proposta", "da": p, "a": a})
	return ""

func _rispondi(da: String, a: String, si: bool, eventi: Array) -> String:
	var k := "%s>%s" % [da, a]
	if k not in proposte:
		return "Nessuna proposta in sospeso."
	proposte.erase(k)
	if si:
		var coppia := "|".join([da, a] if da < a else [a, da])
		if coppia not in alleanze:
			alleanze.append(coppia)
		_log("Alleanza stretta tra %s e %s." % [da, a])
	else:
		_log("%s rifiutano l'alleanza %s." % [ZRegole.Gli(a), ZRegole.degli(da)])
	eventi.append({"t": "risposta", "da": da, "a": a, "si": si})
	_sporca()
	return ""

func _rompi(con: String) -> String:
	var p := popolo_di_mano()
	if fase != FASE_ALLEANZE:
		return "Un'alleanza si può tradire soltanto prima della propria mossa."
	var coppia := "|".join([p, con] if p < con else [con, p])
	if coppia not in alleanze:
		return "Nessuna alleanza da rompere."
	alleanze.erase(coppia)
	_log("%s tradiscono l'alleanza con %s!" % [ZRegole.Gli(p), ZRegole.gli(con)])
	return ""

# --- Monaci -----------------------------------------------------------------

func _scompari(u: ZPedina, eventi: Array) -> String:
	if fase != FASE_MOVIMENTO or u.popolo != popolo_di_mano():
		return "Non è il momento."
	if u.popolo != "Monaci" or u.tipo != "signore":
		return "Solo i Signori Monaci possono sparire."
	if u.mosso or u.agito or not u.in_campo() or u.scortato_da >= 0 or u.paralisi > 0 or u.mese_scomparsa == turno_globale:
		return "I Monaci non possono prima muovere e poi scomparire."
	u.scomparso = true
	u.mese_scomparsa = turno_globale
	u.mosso = true
	_sporca()
	_log("Un Signore Monaco scompare.")
	eventi.append({"t": "scompare", "u": u.id})
	return ""

func destinazioni_ricomparsa(u: ZPedina) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dist := {u.hex: 0}
	var coda: Array[Vector2i] = [u.hex]
	var i := 0
	while i < coda.size():
		var h := coda[i]
		i += 1
		if dist[h] >= u.m():
			continue
		for v in vicini(h):
			# Da scomparsi non si attraversano né il mare senza ponti né i gorghi.
			if terreno(v) == ZMappa.T.GORGO or dist.has(v):
				continue
			dist[v] = dist[h] + 1
			coda.append(v)
	for h in dist:
		if pedine_in(h).is_empty() and citta_in(h).is_empty():
			out.append(h)
	return out

func _ricompari(u: ZPedina, h: Vector2i, eventi: Array) -> String:
	if fase != FASE_MOVIMENTO or u.popolo != popolo_di_mano() or not u.scomparso:
		return "Non è il momento."
	if u.mese_scomparsa >= turno_globale:
		return "Ricompare alla mossa successiva."
	if h not in destinazioni_ricomparsa(u):
		return "Troppo lontano o esagono non valido."
	var da := u.hex
	u.scomparso = false
	u.hex = h
	u.mosso = false
	u.mese_scomparsa = turno_globale  # la sparizione è già una mossa: niente nuova sparizione ora
	_sporca()
	_log("Il Signore Monaco ricompare.")
	eventi.append({"t": "ricompare", "u": u.id, "da": [da.x, da.y], "a": [h.x, h.y]})
	return ""

func _togli_scorta(u: ZPedina) -> String:
	if fase != FASE_MOVIMENTO or u.popolo != popolo_di_mano():
		return "Non è il momento."
	var fante := u if u.scorta >= 0 else (pedine[u.scortato_da] if u.scortato_da >= 0 else null)
	if fante == null:
		return "Nessuna scorta da togliere."
	var altro := pedine[fante.scorta]
	if fante.scorta_cambiata or altro.scorta_cambiata:
		return "In una mossa non si può sovrapporre e togliere la stessa scorta."
	fante.scorta = -1
	altro.scortato_da = -1
	fante.scorta_cambiata = true
	altro.scorta_cambiata = true
	_log("La scorta viene tolta: il pezzo riacquista i suoi poteri.")
	return ""

# --- Amazzoni: trasformazioni ----------------------------------------------------

func puo_trasformare(u: ZPedina) -> String:
	if u.popolo != "Amazzoni" or u.popolo != popolo_di_mano() or not u.attivo():
		return "Solo Donne-Pantera e fanti amazzoni si trasformano."
	if u.trasformata >= turno_globale:
		return "Si è appena trasformata: niente altre trasformazioni in questa mossa."
	if u.tipo == "donna":
		if fase != FASE_SINGOLI:
			return "Le Donne-Pantera si trasformano all'inizio della mossa (fase degli attacchi singoli)."
		if u.mosso or u.agito:
			return "Ha già agito."
		return ""
	if u.tipo == "fante":
		if fase not in [FASE_LANCI, FASE_COMBATTIMENTO] or mischia_iniziata:
			return "I fanti tentano la trasformazione dopo il movimento e prima degli scontri."
		if trasformazioni >= 2:
			return "Si possono tentare al massimo due trasformazioni di fanti per mossa."
		if u.agito:
			return "Ha già agito."
		return ""
	return "Questo pezzo non si trasforma."

func _trasforma(u: ZPedina, eventi: Array) -> String:
	var e := puo_trasformare(u)
	if e != "":
		return e
	if u.tipo == "donna":
		u.origine = "donna"
		u.tipo = "pantera"
		u.trasformata = turno_globale
		_log("Una Donna-Pantera si trasforma in Pantera.")
		eventi.append({"t": "trasforma", "u": u.id})
		return ""
	trasformazioni += 1
	u.trasformata = turno_globale
	var d := rng.randi_range(1, 6)
	if d % 2 == 0:
		u.origine = "fante"
		u.tipo = "pantera0"
		_log("Un fante amazzone si trasforma in Pantera (dado %d)." % d)
		eventi.append({"t": "trasforma", "u": u.id, "dado": d, "ok": true})
	else:
		_log("Un fante amazzone non riesce a trasformarsi (dado %d)." % d)
		eventi.append({"t": "trasforma", "u": u.id, "dado": d, "ok": false})
	return ""

# --- Passaggi segreti (regola opzionale 1) --------------------------------------

func puo_passaggio(u: ZPedina) -> String:
	if not opzione("passaggi"):
		return "Regola dei passaggi segreti non attiva."
	if fase != FASE_MOVIMENTO or u.popolo != popolo_di_mano():
		return "I passaggi segreti si usano nella fase di movimento."
	if passaggio_usato:
		return "Un solo trasferimento per mossa."
	if u.citta < 0:
		return "Si trasferisce un pezzo da una propria città a un'altra."
	if u.mosso:
		return "Ha già mosso."
	return ""

func _passaggio(u: ZPedina, cid: int, eventi: Array) -> String:
	var e := puo_passaggio(u)
	if e != "":
		return e
	var ci: Dictionary = citta[cid]
	if ci.p != u.popolo or int(ci.id) == u.citta or ci.h[0] < 0:
		return "Scegli un'altra città del tuo popolo."
	if ci.g.size() >= ZRegole.MAX_GUARNIGIONE:
		return "Quella città è piena."
	var da := u.hex
	_esci_da_citta(u)
	u.hex = hex_citta(ci)
	u.mosso = true
	_entra_in_citta(u, ci)
	passaggio_usato = true
	_log("Un pezzo %s attraversa un passaggio segreto." % ZRegole.degli(u.popolo))
	eventi.append({"t": "passaggio", "u": u.id, "da": [da.x, da.y], "a": ci.h.duplicate()})
	return ""

# --- Magia (regola opzionale 2) -----------------------------------------------------

## Signori del popolo di mano in grado di fare magie.
func signori_magici(p: String) -> Array[ZPedina]:
	var out: Array[ZPedina] = []
	for u in pedine:
		if u.popolo == p and incantatore(u) and u.viva and u.schierata and not u.scomparso and not u.ridotta and u.muta < turno_globale:
			out.append(u)
	return out

func puo_fare_magia() -> bool:
	return opzione("magia") and not magia_fatta and not signori_magici(popolo_di_mano()).is_empty()

func entro_raggio_magia(p: String, h: Vector2i) -> bool:
	for u in signori_magici(p):
		if mappa.distanza(u.hex, h) <= ZRegole.RAGGIO_MAGIA:
			return true
	return false

func _esagoni_entro(h: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = [h]
	var dist := {h: 0}
	var i := 0
	while i < out.size():
		var x := out[i]
		i += 1
		if dist[x] >= r:
			continue
		for v in mappa.vicino_geometrico_tutti(x):
			if not dist.has(v):
				dist[v] = dist[x] + 1
				out.append(v)
	return out

## Verifica il bersaglio di una magia prima di tirare il dado.
func valuta_magia(s: String, h: Vector2i, h2 = null) -> String:
	if not ZRegole.MAGIE.has(s):
		return "Magia sconosciuta."
	if fase != FASE_MAGIA:
		return "Le magie si fanno all'inizio della propria mossa."
	if magia_fatta:
		return "Una sola magia per mossa."
	var p := popolo_di_mano()
	if not entro_raggio_magia(p, h):
		return "Il bersaglio deve essere entro 10 esagoni da un tuo incantatore (Signore, Mago o Illusionista)."
	match s:
		"frana":
			if terreno(h) != ZMappa.T.MONTAGNA:
				return "Scegli un esagono di montagna."
		"ponte":
			if h2 == null:
				return "Scegli le due coste da collegare."
			var b := Vector2i(int(h2[0]), int(h2[1]))
			if not (mappa.terra(h) and mappa.terra(b) and mappa.costa(h) and mappa.costa(b)):
				return "Il ponte unisce due esagoni di costa."
			var d := mappa.distanza(h, b)
			if d < 2 or d > 4:
				return "Un ponte di pensiero attraversa al massimo 3 esagoni di mare."
			if b in mappa.vicini_terra(h):
				return "Quelle coste sono già collegate."
		"rinascita":
			var ci := citta_in(h)
			if ci.is_empty() or ci.p != p:
				return "Scegli una tua città."
		"voragine":
			var ci := citta_in(h)
			if ci.is_empty() or not nemici(ci.p, p):
				return "Scegli una città nemica."
		"megadrago":
			if not mappa.terra(h) or not pedine_in(h).is_empty() or not citta_in(h).is_empty():
				return "Il mega drago compare in un esagono di terra libero."
		"odalische":
			var ok := false
			for w in pedine_in(h):
				if nemici(w.popolo, p) and incantatore(w):
					ok = true
			if not ok:
				return "Scegli un incantatore nemico (Signore, Mago o Illusionista)."
	return ""

func _magia(s: String, h: Vector2i, h2, punti: int, eventi: Array) -> String:
	var e := valuta_magia(s, h, h2)
	if e != "":
		return e
	var p := popolo_di_mano()
	punti = clampi(punti, 0, int(preparazione.get(p, 0)))
	preparazione[p] = int(preparazione.get(p, 0)) - punti
	magia_fatta = true
	var d := rng.randi_range(1, 6)
	var tot := d + punti
	var m: Dictionary = ZRegole.MAGIE[s]
	var ok := tot >= int(m.min)
	var extra := tot - int(m.min)
	eventi.append({"t": "magia", "s": s, "h": [h.x, h.y], "dado": d, "punti": punti, "totale": tot, "ok": ok, "p": p})
	if not ok:
		_log("%s tentano %s: dado %d + %d = %d, serviva %d. La magia fallisce." % [ZRegole.Gli(p), m.nome, d, punti, tot, m.min])
		return ""
	_log("%s lanciano %s: dado %d + %d = %d (minimo %d)." % [ZRegole.Gli(p), m.nome, d, punti, tot, m.min])
	match s:
		"frana":
			var varco: Array[Vector2i] = [h]
			var i := 0
			while i < varco.size() and varco.size() < 1 + extra:
				for v in mappa.vicino_geometrico_tutti(varco[i]):
					if terreno(v) == ZMappa.T.MONTAGNA and v not in varco and varco.size() < 1 + extra:
						varco.append(v)
				i += 1
			for v in varco:
				terreno_mod["%d,%d" % [v.x, v.y]] = ZMappa.T.PIANURA
		"ponte":
			ponti_temp.append([[h.x, h.y], [int(h2[0]), int(h2[1])]])
			eventi.append({"t": "ponti"})
		"coraggio":
			var ridotte := pedine.filter(func(u): return u.popolo == p and u.viva and u.ridotta)
			ridotte.sort_custom(func(a, b): return mappa.distanza(a.hex, h) < mappa.distanza(b.hex, h))
			for u in ridotte.slice(0, 1 + extra):
				u.ridotta = false
				eventi.append({"t": "recupero", "u": u.id})
		"spada":
			for v in _esagoni_entro(h, extra):
				for u in pedine_in(v):
					if u.popolo == p:
						u.spada = turno_globale
		"rinascita":
			var ci := citta_in(h)
			var morti := pedine.filter(func(u): return u.popolo == p and u.tipo == "signore" and not u.viva)
			for u in morti.slice(0, 1 + extra):
				u.viva = true
				u.ridotta = false
				u.schierata = true
				u.colpi = 0
				u.paralisi = 0
				u.hex = hex_citta(ci)
				if ci.g.size() < ZRegole.MAX_GUARNIGIONE:
					_entra_in_citta(u, ci)
				else:
					u.citta = -1
					for v in mappa.vicini_terra(h):
						if pedine_in(v).is_empty() and citta_in(v).is_empty():
							u.hex = v
							break
				_log("Un Signore %s rinasce." % ZRegole.degli(p))
		"odalische":
			var lord := pedine.filter(func(u): return u.viva and incantatore(u) and nemici(u.popolo, p) and u.in_campo())
			lord.sort_custom(func(a, b): return mappa.distanza(a.hex, h) < mappa.distanza(b.hex, h))
			for u in lord.slice(0, 1 + extra):
				u.muta = turno_globale + (1 if alternato() else popoli.size())
		"megadrago":
			var posti: Array[Vector2i] = [h]
			for v in mappa.vicini_terra(h):
				if pedine_in(v).is_empty() and citta_in(v).is_empty() and not in_zona_nemica(v, "__nessuno__"):
					posti.append(v)
			for i in mini(1 + extra, posti.size()):
				var u := ZPedina.new()
				u.id = pedine.size()
				u.popolo = p
				u.tipo = "megadrago"
				u.hex = posti[i]
				u.schierata = true
				u.mosso = true
				pedine.append(u)
				eventi.append({"t": "evoca", "u": u.id})
		"sonno":
			for v in _esagoni_entro(h, extra):
				for u in pedine_in(v):
					if nemici(u.popolo, p) and u.tipo != "megadrago":
						u.ridotta = true
						eventi.append({"t": "ridotta", "u": u.id})
		"terremoto":
			for v in _esagoni_entro(h, extra):
				for u in pedine_in(v):
					if nemici(u.popolo, p):
						_elimina(u, p, eventi)
		"voragine":
			var nemiche := citta.filter(func(c): return c.h[0] >= 0 and nemici(c.p, p))
			nemiche.sort_custom(func(a, b): return mappa.distanza(hex_citta(a), h) < mappa.distanza(hex_citta(b), h))
			for ci in nemiche.slice(0, 1 + extra):
				for id in ci.g.duplicate():
					_elimina(pedine[id], p, eventi)
				var hc := hex_citta(ci)
				var vecchio: String = ci.p
				ci.h = [-1, -1]
				ci.p = ""
				if opzione("lampo"):
					_punti_conquista(p, vecchio, 0.5)
				else:
					bonus_vittoria[p] = float(bonus_vittoria.get(p, 0.0)) + 0.5
				_log("Una città %s sprofonda in una voragine di fiamme!" % ZRegole.degli(vecchio))
				eventi.append({"t": "conquista", "c": ci.id, "p": p, "da": vecchio, "rasa": true, "h": [hc.x, hc.y]})
	_sporca()
	return ""

# --- Avanzamento dei turni -----------------------------------------------------

func _avanza_fase(eventi: Array) -> String:
	if alternato():
		_avanza_alternato(eventi)
		return ""
	match fase:
		FASE_SCHIERAMENTO:
			return _fine_schieramento(eventi)
		FASE_ALLEANZE:
			_entra_in_fase(FASE_MAGIA if opzione("magia") else FASE_SINGOLI, eventi)
		FASE_MAGIA:
			if not magia_fatta:
				preparazione[popolo_di_mano()] = mini(ZRegole.MAX_PREPARAZIONE, int(preparazione.get(popolo_di_mano(), 0)) + 1)
				_log("%s accumulano un punto di preparazione magica (%d)." % [ZRegole.Gli(popolo_di_mano()), preparazione[popolo_di_mano()]])
			_entra_in_fase(FASE_SINGOLI, eventi)
		FASE_SINGOLI:
			_entra_in_fase(FASE_MOVIMENTO, eventi)
		FASE_MOVIMENTO:
			_chiudi_movimento(eventi)
			_entra_in_fase(FASE_LANCI, eventi)
		FASE_LANCI:
			_entra_in_fase(FASE_COMBATTIMENTO, eventi)
		FASE_COMBATTIMENTO:
			_fine_turno(eventi)
	return ""

## Entra in una fase; le fasi in cui non c'è nulla da fare vengono saltate.
func _entra_in_fase(f: String, eventi: Array) -> void:
	fase = f
	if f == FASE_MAGIA and not puo_fare_magia():
		if not magia_fatta:
			preparazione[popolo_di_mano()] = mini(ZRegole.MAX_PREPARAZIONE, int(preparazione.get(popolo_di_mano(), 0)) + 1)
		if alternato():
			_fine_attivazione(eventi)
			return
		fase = FASE_SINGOLI
		f = FASE_SINGOLI
	if f == FASE_SINGOLI and not ha_azioni_singole():
		fase = FASE_MOVIMENTO
	if fase == FASE_LANCI and not ha_lanci():
		fase = FASE_COMBATTIMENTO
	if fase == FASE_COMBATTIMENTO and zl2():
		_elimina_ridotte_adiacenti(eventi)
	eventi.append({"t": "fase", "fase": fase})

## Qualche pezzo può fare un attacco singolo o fiammeggiare prima di muovere?
func ha_azioni_singole() -> bool:
	var p := popolo_di_mano()
	var vecchia := fase
	fase = FASE_SINGOLI
	var ok := false
	for u in pedine:
		if u.popolo != p or not u.in_campo():
			continue
		if u.popolo == "Amazzoni" and u.tipo == "donna" and puo_trasformare(u) == "":
			ok = true
			break
		if ZRegole.attacco_singolo(u.popolo, u.tipo) and puo_attacco_singolo(u) == "":
			for b in pedine:
				if attaccabile(b) and nemici(b.popolo, p) and mappa.distanza(u.hex, b.hex) <= u.m() + 1:
					if not basi_attacco_singolo(u, b).is_empty():
						ok = true
						break
		elif u.popolo == "Draghi" and u.tipo == "signore":
			for b in pedine:
				if attaccabile(b) and nemici(b.popolo, p) and mappa.distanza(u.hex, b.hex) <= 5 and valuta_tiro(u, b).ok:
					ok = true
					break
		if ok:
			break
	fase = vecchia
	return ok

## Qualche tiratore ha un bersaglio valido?
func ha_lanci() -> bool:
	var p := popolo_di_mano()
	var vecchia := fase
	fase = FASE_LANCI
	var ok := false
	for u in pedine:
		if u.popolo == "Amazzoni" and u.tipo == "fante" and puo_trasformare(u) == "":
			ok = true
			break
		if u.popolo != p or tipo_tiro(u) == "" or u.agito or not u.viva or u.scomparso:
			continue
		for b in pedine:
			if attaccabile(b) and nemici(b.popolo, p) and mappa.distanza(u.hex, b.hex) <= gittata(u) and valuta_tiro(u, b).ok:
				ok = true
				break
		if ok:
			break
	fase = vecchia
	return ok

func _chiudi_movimento(eventi: Array) -> void:
	var p := popolo_di_mano()
	# I Monaci scomparsi nella mossa precedente devono ricomparire: se il giocatore
	# non li ha collocati, riappaiono dove erano spariti.
	for u in pedine:
		if u.popolo == p and u.viva and u.scomparso and u.mese_scomparsa < turno_globale:
			var dove := u.hex
			if not pedine_in(dove).is_empty() or not citta_in(dove).is_empty():
				# L'esagono di partenza è stato occupato: il più vicino libero.
				var libere := destinazioni_ricomparsa(u)
				if libere.is_empty():
					continue
				libere.sort_custom(func(a, b): return mappa.distanza(u.hex, a) < mappa.distanza(u.hex, b))
				dove = libere[0]
			var da := u.hex
			u.hex = dove
			u.scomparso = false
			u.mese_scomparsa = turno_globale
			_sporca()
			eventi.append({"t": "ricompare", "u": u.id, "da": [da.x, da.y], "a": [dove.x, dove.y]})
	# Due pezzi rimasti sovrapposti senza scorta tornano a formare una coppia
	# (solo nel gioco base: con Zargo's Lords 2 l'ammassamento è libero).
	_sporca()
	for u in pedine:
		if zl2():
			break
		if u.popolo == p and u.in_campo() and u.tipo == "fante" and u.scorta < 0:
			for w in pedine_in(u.hex):
				if w != u and w.tipo != "fante" and w.scortato_da < 0 and w.popolo == p:
					u.scorta = w.id
					w.scortato_da = u.id

func _fine_turno(eventi: Array) -> void:
	_chiudi_mossa(eventi)
	turno += 1
	if turno >= popoli.size():
		turno = 0
		if mese >= mesi_totali():
			_termina(eventi)
			return
		mese += 1
	_inizia_turno(eventi)

# --- Iniziativa e fasi alternate ------------------------------------------------

func _avanza_alternato(eventi: Array) -> void:
	match fase:
		FASE_ALLEANZE:
			if opzione("magia"):
				_entra_in_fase(FASE_MAGIA, eventi)
			else:
				_fine_attivazione(eventi)
		FASE_MAGIA:
			if not magia_fatta:
				preparazione[popolo_di_mano()] = mini(ZRegole.MAX_PREPARAZIONE, int(preparazione.get(popolo_di_mano(), 0)) + 1)
				_log("%s accumulano un punto di preparazione magica (%d)." % [ZRegole.Gli(popolo_di_mano()), preparazione[popolo_di_mano()]])
			_fine_attivazione(eventi)
		FASE_SINGOLI:
			_entra_in_fase(FASE_MOVIMENTO, eventi)
		FASE_MOVIMENTO:
			_chiudi_movimento(eventi)
			_fine_attivazione(eventi)
		FASE_LANCI:
			_entra_in_fase(FASE_COMBATTIMENTO, eventi)
		FASE_COMBATTIMENTO:
			_recupera_ridotti(eventi)
			_fine_attivazione(eventi)

## Inizio del mese con l'iniziativa: si sorteggia l'ordine dei popoli.
func _inizia_mese(eventi: Array) -> void:
	turno_globale += 1
	ordine.assign(popoli.duplicate())
	_mescola(ordine)
	blocco = 0
	turno = 0
	for u in pedine:
		u.mosso = false
		u.agito = false
		u.singolo = false
		u.residuo = 0
		u.scorta_cambiata = false
		u.carica_dir = -1
		if u.paralisi > 0:
			u.paralisi -= 1
	_log("— Mese %d dell'Anno di Zargo — iniziativa: %s" % [mese, ", ".join(ordine)])
	fase = FASE_ALLEANZE
	_attiva(eventi)

## Il popolo di mano comincia la sua parte della fase corrente.
func _attiva(eventi: Array) -> void:
	var p := popolo_di_mano()
	if pedine_di(p).filter(func(u): return u.tipo != "megadrago").is_empty() and citta_di(p) == 0:
		_fine_attivazione(eventi)
		return
	match blocco:
		0:
			magia_fatta = false
			proposte.assign(proposte.filter(func(k): return not k.begins_with(p + ">")))
			eventi.append({"t": "turno", "p": p, "mese": mese, "blocco": 0})
			_log("Fase del potere: %s." % ZRegole.gli(p))
			if popoli.size() >= 3:
				fase = FASE_ALLEANZE
				eventi.append({"t": "fase", "fase": fase})
			elif opzione("magia"):
				_entra_in_fase(FASE_MAGIA, eventi)
			else:
				_fine_attivazione(eventi)
		1:
			passaggio_usato = false
			trasformazioni = 0
			singoli_aperti = true
			if p == "Amazzoni":
				for u in pedine:
					if u.popolo == p and u.pantera() and u.origine != "":
						u.tipo = u.origine
						u.origine = ""
						u.trasformata = turno_globale
						if u.viva:
							eventi.append({"t": "trasforma", "u": u.id})
			eventi.append({"t": "turno", "p": p, "mese": mese, "blocco": 1})
			_log("Fase di movimento: %s." % ZRegole.gli(p))
			_entra_in_fase(FASE_SINGOLI, eventi)
		2:
			mischia_iniziata = false
			for u in pedine:
				u.colpi = 0
				u.ingaggiata = false
			eventi.append({"t": "turno", "p": p, "mese": mese, "blocco": 2})
			_log("Fase di combattimento: %s." % ZRegole.gli(p))
			_entra_in_fase(FASE_LANCI, eventi)
	_sporca()

func _fine_attivazione(eventi: Array) -> void:
	turno += 1
	if turno >= ordine.size():
		turno = 0
		blocco += 1
		if blocco > 2:
			_pulizia_fine_mossa(eventi)
			if mese >= mesi_totali():
				_termina(eventi)
				return
			mese += 1
			_inizia_mese(eventi)
			return
	_attiva(eventi)

## Fine della mossa del popolo di mano: recupero dei pezzi ridotti, reti,
## mega draghi ed effetti magici che valgono "per questa mossa".
func _chiudi_mossa(eventi: Array) -> void:
	_recupera_ridotti(eventi)
	_pulizia_fine_mossa(eventi)

func _recupera_ridotti(eventi: Array) -> void:
	var p := popolo_di_mano()
	if zl2():
		for u in pedine:
			if u.popolo != p or not u.viva or not u.ridotta:
				continue
			var signore_vicino := false
			if u.tipo != "signore":
				for v in [u.hex] + mappa.vicino_geometrico_tutti(u.hex):
					for w in pedine_in(v):
						if w.popolo == p and w.tipo == "signore" and w.attivo():
							signore_vicino = true
				if not signore_vicino:
					continue
			var d := rng.randi_range(1, 6)
			if d >= 4:
				u.ridotta = false
				_log("%s %s si riprende (dado %d)." % [u.nome(), ZRegole.degli(p), d])
				eventi.append({"t": "recupero", "u": u.id})
			elif d == 1 or u.tipo == "signore":
				_log("%s %s non si riprende (dado %d) ed è perduto." % [u.nome(), ZRegole.degli(p), d])
				_elimina(u, "", eventi)
	if p == "Aracnidi" and not reti.is_empty():
		reti.clear()
		eventi.append({"t": "reti"})
	_sporca()

func _pulizia_fine_mossa(eventi: Array) -> void:
	for u in pedine:
		if u.tipo == "megadrago" and u.viva:
			u.viva = false
			eventi.append({"t": "elimina", "u": u.id})
	terreno_mod.clear()
	if not ponti_temp.is_empty():
		ponti_temp.clear()
		eventi.append({"t": "ponti"})
	_sporca()

## Zargo's Lords 2: chi termina adiacente a pezzi nemici ridotti li elimina
## automaticamente nella propria fase di combattimento.
func _elimina_ridotte_adiacenti(eventi: Array) -> void:
	var p := popolo_di_mano()
	for u in pedine:
		if u.viva and u.ridotta and u.in_campo() and nemici(u.popolo, p):
			for v in mappa.vicino_geometrico_tutti(u.hex):
				var trovato := false
				for w in pedine_in(v):
					if w.popolo == p and w.attivo():
						trovato = true
				if trovato:
					_log("%s %s, ridotto e circondato, viene eliminato." % [u.nome(), ZRegole.degli(u.popolo)])
					_elimina(u, p, eventi)
					break

func _inizia_turno(eventi: Array) -> void:
	turno_globale += 1
	var p := popolo_di_mano()
	magia_fatta = false
	passaggio_usato = false
	trasformazioni = 0
	# All'inizio della mossa amazzone tutte le Pantere tornano umane.
	if p == "Amazzoni":
		for u in pedine:
			if u.popolo == p and u.pantera() and u.origine != "":
				u.tipo = u.origine
				u.origine = ""
				u.trasformata = turno_globale + 1
				if u.viva:
					eventi.append({"t": "trasforma", "u": u.id})
	# Un popolo senza più pezzi né città salta la sua mossa.
	if pedine_di(p).filter(func(u): return u.tipo != "megadrago").is_empty() and citta_di(p) == 0:
		_log("%s sono scomparsi da Zargo." % ZRegole.Gli(p))
		_fine_turno(eventi)
		return
	for u in pedine:
		u.colpi = 0
		u.ingaggiata = false
		if u.popolo == p:
			u.mosso = false
			u.agito = false
			u.singolo = false
			u.residuo = 0
			u.scorta_cambiata = false
			u.carica_dir = -1
			if u.paralisi > 0:
				u.paralisi -= 1
	# Le proposte rimaste senza risposta decadono quando il proponente torna a muovere.
	proposte.assign(proposte.filter(func(k): return not k.begins_with(p + ">")))
	singoli_aperti = true
	mischia_iniziata = false
	if popoli.size() >= 3:
		fase = FASE_ALLEANZE
	else:
		_entra_in_fase(FASE_SINGOLI, eventi)
	if turno == 0:
		_log("— Mese %d dell'Anno di Zargo —" % mese)
	_log("Muovono %s." % ZRegole.gli(p))
	eventi.append({"t": "turno", "p": p, "mese": mese})
	_sporca()

## Punteggio finale: città controllate (più metà per ogni città sprofondata),
## oppure punti della Guerra lampo.
func punteggio(p: String) -> float:
	if opzione("lampo"):
		var pp: float = float(punti_lampo.get(p, 0))
		var diversi := {}
		for x in conquiste_lampo.get(p, []):
			diversi[x] = true
		if diversi.size() >= 2:
			pp *= diversi.size()
		var persi := 0
		for u in pedine:
			if u.popolo == p and u.tipo == "signore" and not u.viva:
				persi += 1
		pp -= mini(30, persi * 5)
		return pp
	return float(citta_di(p)) + float(bonus_vittoria.get(p, 0.0))

static func numero(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, roundf(x)) else "%.1f" % x

func _termina(eventi: Array) -> void:
	fase = FASE_FINITA
	var migliore := -INF
	vincitori.clear()
	for p in popoli:
		var n := punteggio(p)
		if n > migliore:
			migliore = n
			vincitori = [p]
		elif n == migliore:
			vincitori.append(p)
	_log("%s %s con %s %s." % ["La Guerra lampo è finita." if opzione("lampo") else "L'Anno di Zargo è finito.", " e ".join(vincitori), ZPartita.numero(migliore), "punti" if opzione("lampo") else "città"])
	eventi.append({"t": "fine", "vincitori": vincitori})

func _controlla_vittoria(eventi: Array) -> void:
	if fase in [FASE_SCHIERAMENTO, FASE_FINITA]:
		return
	var vivi: Array[String] = []
	for p in popoli:
		if citta_di(p) > 0 or not pedine_di(p).filter(func(u): return u.tipo != "megadrago").is_empty():
			vivi.append(p)
	# Vittoria anticipata: su Zargo è rimasto un solo popolo.
	if vivi.size() <= 1:
		_termina(eventi)

func _log(testo: String) -> void:
	registro.append(testo)
	if registro.size() > 300:
		registro = registro.slice(registro.size() - 300)

# ---------------------------------------------------------------------------
# Serializzazione
# ---------------------------------------------------------------------------

func a_dict() -> Dictionary:
	return {
		"v": 2, "popoli": popoli, "controllo": controllo, "continenti": continenti,
		"pedine": pedine.map(func(u): return u.a_dict()), "citta": citta.duplicate(true),
		"mese": mese, "turno": turno, "tg": turno_globale, "fase": fase, "alleanze": alleanze,
		"proposte": proposte, "sa": singoli_aperti, "mi": mischia_iniziata, "registro": registro.slice(maxi(0, registro.size() - 60)),
		"vincitori": vincitori, "seme": str(rng.seed), "stato": str(rng.state),
		"opz": opzioni, "prep": preparazione, "mf": magia_fatta, "tm": terreno_mod, "pt": ponti_temp,
		"reti": reti, "pu": passaggio_usato, "tra": trasformazioni, "bv": bonus_vittoria,
		"cl": conquiste_lampo, "pl": punti_lampo, "nc": n_conquiste,
		"ord": ordine, "bl": blocco,
	}

func da_dict(d: Dictionary) -> void:
	popoli.assign(d.popoli)
	controllo = d.controllo.duplicate()
	continenti.assign(d.continenti)
	pedine.clear()
	for x in d.pedine:
		pedine.append(ZPedina.da_dict(x))
	citta.clear()
	for x in d.citta:
		var ci: Dictionary = x.duplicate(true)
		ci.id = int(ci.id)
		ci.h = [int(ci.h[0]), int(ci.h[1])]
		ci.g = ci.get("g", []).map(func(v): return int(v))
		citta.append(ci)
	mese = int(d.mese)
	turno = int(d.turno)
	turno_globale = int(d.tg)
	fase = String(d.fase)
	alleanze.assign(d.get("alleanze", []))
	proposte.assign(d.get("proposte", []))
	singoli_aperti = bool(d.sa)
	mischia_iniziata = bool(d.mi)
	registro.assign(d.get("registro", []))
	vincitori.assign(d.get("vincitori", []))
	opzioni = d.get("opz", {}).duplicate()
	preparazione = {}
	for k in d.get("prep", {}):
		preparazione[k] = int(d.prep[k])
	magia_fatta = bool(d.get("mf", false))
	terreno_mod = {}
	for k in d.get("tm", {}):
		terreno_mod[k] = int(d.tm[k])
	ponti_temp = d.get("pt", []).duplicate(true)
	reti = d.get("reti", []).duplicate(true)
	passaggio_usato = bool(d.get("pu", false))
	trasformazioni = int(d.get("tra", 0))
	bonus_vittoria = d.get("bv", {}).duplicate()
	conquiste_lampo = {}
	for k in d.get("cl", {}):
		conquiste_lampo[k] = Array(d.cl[k])
	for p2 in popoli:
		if not conquiste_lampo.has(p2):
			conquiste_lampo[p2] = []
	punti_lampo = d.get("pl", {}).duplicate()
	n_conquiste = int(d.get("nc", 0))
	ordine.assign(d.get("ord", []))
	blocco = int(d.get("bl", 0))
	rng.seed = int(String(d.seme))
	rng.state = int(String(d.stato))
	_sporca()
	cambiata.emit()
