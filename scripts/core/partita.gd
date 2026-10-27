class_name ZPartita
extends RefCounted
## Modello completo di una partita di Zargo's Lords, indipendente dalla grafica.
## Ogni comando del giocatore (umano, IA o remoto) passa da `esegui()`, che
## valida l'azione secondo il regolamento, la applica e restituisce gli eventi
## da mostrare. Lo stato è interamente serializzabile con `a_dict()`.

signal cambiata

const FASE_SCHIERAMENTO := "schieramento"
const FASE_ALLEANZE := "alleanze"
const FASE_MOVIMENTO := "movimento"
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
func nuova(scelti: Array, ctrl: Dictionary, seme := 0) -> void:
	rng.seed = seme if seme != 0 else randi()
	popoli.clear()
	for p in ZRegole.POPOLI:
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
		for k in ZRegole.CITTA_PER_POPOLO:
			citta.append({"id": citta.size(), "p": p, "h": [-1, -1], "g": [], "orig": p})
	mese = 1
	turno = 0
	turno_globale = 0
	fase = FASE_SCHIERAMENTO
	alleanze.clear()
	proposte.clear()
	registro.clear()
	vincitori.clear()
	_sporca()
	_log("Il pianeta Zargo attende i suoi Signori. Schieramento %s." % ZRegole.degli(popoli[0]))

func _mescola(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t

func popolo_di_mano() -> String:
	return popoli[turno] if turno < popoli.size() else ""

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
			if w.popolo == u.popolo and w.tipo == "mago" and w.popolo == "Cavalieri" and w.scortato_da < 0 and w.paralisi == 0:
				b += 2
	return b

func bonus_terreno(u: ZPedina) -> int:
	if u.citta >= 0:
		return 0
	return bonus_terreno_hex(u.hex)

func bonus_terreno_hex(h: Vector2i) -> int:
	match mappa.terreno(h):
		ZMappa.T.MONTAGNA: return 3
		ZMappa.T.BOSCO: return 1
	return 0

## Zona d'influenza nemica: esagoni adiacenti a un nemico in campo.
func in_zona_nemica(h: Vector2i, p: String, escluso := -1) -> bool:
	for v in mappa.vicino_geometrico_tutti(h):
		for w in pedine_in(v):
			if w.id != escluso and nemici(w.popolo, p) and not w.ingaggiata and w.paralisi == 0:
				return true
	return false

func attaccabile(u: ZPedina) -> bool:
	return u != null and u.in_campo() and u.paralisi == 0

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
	if fase != FASE_MOVIMENTO:
		return "Non è la fase di movimento."
	if u.popolo != popolo_di_mano():
		return "Non è la mossa di questo popolo."
	if not u.viva or u.scomparso:
		return "Pezzo non disponibile."
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
	var partenza := g.hex
	var costi := {partenza: 0}
	var coda: Array[Vector2i] = [partenza]
	var i := 0
	while i < coda.size():
		var h := coda[i]
		i += 1
		if h != partenza and _ferma_qui(h, g, volante, ignora_zone):
			continue
		for v in mappa.vicini_terra(h):
			var t := mappa.terreno(v)
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
			if _bloccato(v, g, volante):
				continue
			if not costi.has(v) or nuovo < costi[v]:
				costi[v] = nuovo
				coda.append(v)
	# Rimuove le destinazioni in cui non ci si può fermare.
	var out := {}
	for h in costi:
		if h != partenza and _puo_fermarsi(h, u):
			out[h] = costi[h]
	return out

func _ferma_qui(h: Vector2i, g: ZPedina, volante: bool, ignora_zone: bool) -> bool:
	var t := mappa.terreno(h)
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
	for w in pedine_in(h):
		if nemici(w.popolo, g.popolo):
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
	if mappa.terreno(dest) == ZMappa.T.GORGO:
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
	var presenti := pedine_in(dest)
	if presenti.size() == 2 and g.scorta < 0:
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
		var t := mappa.terreno(h)
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
	var migliore := {}
	var miglior_punteggio := -INF
	for dir in 6:
		var prova := _simula_ritirata(u_guida, dir, passi)
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
		if mappa.terreno(dest) == ZMappa.T.GORGO:
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
	if not mappa.terra(h):
		return true
	if mappa.terreno(h) in [ZMappa.T.BOSCO, ZMappa.T.MONTAGNA]:
		return true
	if not citta_in(h).is_empty():
		return true
	for w in pedine_in(h):
		if nemici(w.popolo, p):
			return true
	return in_zona_nemica(h, p)

func _simula_ritirata(u: ZPedina, dir: int, passi: int) -> Dictionary:
	var h := u.hex
	var percorso: Array[Vector2i] = []
	var gorgo := false
	for i in passi:
		h = mappa.vicino_dir(h, dir)
		if _ostacolo_ritirata(h, u.popolo, []):
			return {}
		percorso.append(h)
		if mappa.terreno(h) == ZMappa.T.GORGO:
			gorgo = true
			break
	var fine := percorso[-1]
	var spinte := []
	var perdite := 0
	var sacrificio := -1
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
		if mappa.terreno(avanti) == ZMappa.T.GORGO:
			break
		occupante = pedina_in(avanti)
	return {"fine": fine, "spinte": spinte, "perdite": perdite, "sacrificio": sacrificio, "gorgo": gorgo, "da": [u.hex.x, u.hex.y]}

# ---------------------------------------------------------------------------
# Combattimento
# ---------------------------------------------------------------------------

func forza_attacco(att: Array, difensore: ZPedina) -> int:
	var tot := 0
	for u in att:
		tot += u.c() + bonus_maghi(u) + bonus_carica(u, difensore)
	return tot

func forza_difesa(dif: Array) -> int:
	var tot := 0
	for u in dif:
		tot += u.c() + bonus_maghi(u) + bonus_terreno(u)
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
	if ZRegole.arciere(u.tipo) or u.tipo == "lanciafiamme":
		return "In attacco questo pezzo può soltanto tirare."
	return ""

## Analisi di uno scontro prima di tirare il dado (usata da interfaccia e IA).
func valuta_attacco(att_ids: Array, dif_ids: Array) -> Dictionary:
	var att: Array[ZPedina] = []
	var dif: Array[ZPedina] = []
	for id in att_ids:
		att.append(pedine[id])
	for id in dif_ids:
		dif.append(pedine[id])
	if att.is_empty() or dif.is_empty():
		return {"ok": false, "errore": "Scegli attaccanti e difensori."}
	if att.size() > 1 and dif.size() > 1:
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
			_ritira(d, int(esito.right(1)), p_att, eventi)

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
		fa += u.c() + bonus_maghi(u)
	var fd := 0
	for g in gu:
		fd += g.c()
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
	if ZRegole.arciere(u.tipo):
		return "frecce"
	if ZRegole.fiamme(u.popolo, u.tipo):
		return "fiamme"
	if ZRegole.visioni(u.popolo, u.tipo):
		return "visione"
	return ""

func gittata(u: ZPedina) -> int:
	match tipo_tiro(u):
		"frecce": return 8
		"fiamme", "visione": return 5
	return 0

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
	if fase == FASE_MOVIMENTO:
		if not (u.popolo == "Draghi" and u.tipo == "signore" and not u.mosso):
			return {"ok": false, "errore": "Si tira nella fase di combattimento (solo il Drago può fiammeggiare prima di muovere)."}
	elif fase != FASE_COMBATTIMENTO:
		return {"ok": false, "errore": "Non è il momento di tirare."}
	elif mischia_iniziata:
		return {"ok": false, "errore": "I lanci si risolvono prima dei combattimenti."}
	if b == null or not nemici(b.popolo, u.popolo):
		return {"ok": false, "errore": "Scegli un nemico."}
	if not attaccabile(b):
		return {"ok": false, "errore": "Archi, fuoco e visioni non hanno presa su città e pezzi nei gorghi."}
	var d := mappa.distanza(u.hex, b.hex)
	if d > gittata(u):
		return {"ok": false, "errore": "Bersaglio fuori portata (%d esagoni, massimo %d)." % [d, gittata(u)]}
	if tipo == "frecce":
		var e := _linea_di_tiro(u, b)
		if e != "":
			return {"ok": false, "errore": e}
		var serve: int = ZRegole.FRECCE_NECESSARIE[b.popolo][b.tipo]
		return {"ok": true, "tipo": tipo, "distanza": d, "servono": serve, "gia": b.colpi}
	if tipo == "fiamme":
		var serve: int = ZRegole.VAMPE_NECESSARIE[b.popolo][b.tipo]
		if serve == 0:
			return {"ok": false, "errore": "Il popolo dei Draghi è immune al fuoco."}
		return {"ok": true, "tipo": tipo, "distanza": d, "servono": serve, "gia": b.colpi}
	return {"ok": true, "tipo": tipo, "distanza": d}

func _linea_di_tiro(u: ZPedina, b: ZPedina) -> String:
	if mappa.terreno(u.hex) == ZMappa.T.BOSCO and u.citta < 0:
		return "Non si può tirare da dentro un bosco."
	if mappa.terreno(b.hex) == ZMappa.T.BOSCO:
		return "Non si può tirare dentro un bosco."
	var dir := mappa.direzione_retta(u.hex, b.hex, 8)
	if dir < 0:
		return "Le frecce volano soltanto in linea retta lungo gli esagoni."
	var h := u.hex
	while true:
		h = mappa.vicino_dir(h, dir)
		if h == b.hex:
			break
		var t := mappa.terreno(h)
		if t in [ZMappa.T.MONTAGNA, ZMappa.T.BOSCO, ZMappa.T.GORGO]:
			return "La linea di tiro è bloccata da %s." % ZMappa.NOMI_TERRENO[t].to_lower()
		if not citta_in(h).is_empty():
			return "Una città blocca la linea di tiro."
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
	var colpi := ZRegole.frecce(dado, v.distanza) if v.tipo == "frecce" else ZRegole.vampe(dado, v.distanza)
	b.colpi += colpi
	var eliminato: bool = b.colpi >= int(v.servono)
	eventi.append({"t": "tiro", "tipo": v.tipo, "u": u.id, "b": b.id, "dado": dado, "distanza": v.distanza, "colpi": colpi, "totale": b.colpi, "servono": v.servono, "eliminato": eliminato})
	_log("%s di %s su %s: dado %d, distanza %d » %d a segno (%d/%d)." % ["Frecce" if v.tipo == "frecce" else "Fiamme", u.nome(), b.nome(), dado, v.distanza, colpi, b.colpi, v.servono])
	if eliminato:
		_elimina(b, u.popolo, eventi)

# ---------------------------------------------------------------------------
# Attacchi singoli
# ---------------------------------------------------------------------------

func puo_attacco_singolo(u: ZPedina) -> String:
	if fase != FASE_MOVIMENTO or u.popolo != popolo_di_mano():
		return "Gli attacchi singoli si fanno all'inizio della fase di movimento."
	if not ZRegole.attacco_singolo(u.popolo, u.tipo):
		return "Solo Alati, Falchi e Serpenti attaccano singolarmente."
	if u.scortato_da >= 0 or u.paralisi > 0 or not u.in_campo():
		return "Pezzo non disponibile."
	if u.singolo:
		if u.tipo == "serpente" and u.residuo > 0 and u.carica_dir >= 0:
			return ""
		return "Ha già compiuto il suo attacco singolo."
	if u.mosso or u.agito:
		return "Ha già agito."
	if not singoli_aperti:
		return "Gli attacchi singoli vanno effettuati prima di qualsiasi altro movimento."
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
			var t := mappa.terreno(h)
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
				costo += 2 if mappa.terreno(h) == ZMappa.T.BOSCO else 1
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
			var costo_avanti := 2 if mappa.terreno(avanti) == ZMappa.T.BOSCO else 1
			if mappa.terra(avanti) and pedine_in(avanti).is_empty() and citta_in(avanti).is_empty() and mappa.terreno(avanti) not in [ZMappa.T.GORGO, ZMappa.T.MONTAGNA] and costo_avanti <= u.residuo:
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
		var nuovi := []
		for id in az.dif:
			var s := _scorta_di(int(id))
			if s not in nuovi:
				nuovi.append(s)
		az.dif = nuovi
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
			if not u.singolo and not _guida(u).singolo:
				singoli_aperti = false
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
				return "Gli scontri si risolvono nella fase di combattimento."
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
	if mappa.terreno(h) == ZMappa.T.GORGO:
		return "Non si costruisce in un gorgo magico."
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
			if mappa.terreno(h) == ZMappa.T.MONTAGNA:
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
			if mappa.terreno(h) == ZMappa.T.GORGO or not citta_in(h).is_empty():
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
	singoli_aperti = false
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
		for v in mappa.vicini_terra(h):
			# Da scomparsi non si attraversano né il mare senza ponti né i gorghi.
			if mappa.terreno(v) == ZMappa.T.GORGO or dist.has(v):
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

# --- Avanzamento dei turni -----------------------------------------------------

func _avanza_fase(eventi: Array) -> String:
	match fase:
		FASE_SCHIERAMENTO:
			return _fine_schieramento(eventi)
		FASE_ALLEANZE:
			fase = FASE_MOVIMENTO
		FASE_MOVIMENTO:
			_chiudi_movimento(eventi)
			fase = FASE_COMBATTIMENTO
		FASE_COMBATTIMENTO:
			_fine_turno(eventi)
	return ""

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
	# Due pezzi rimasti sovrapposti senza scorta tornano a formare una coppia.
	_sporca()
	for u in pedine:
		if u.popolo == p and u.in_campo() and u.tipo == "fante" and u.scorta < 0:
			for w in pedine_in(u.hex):
				if w != u and w.tipo != "fante" and w.scortato_da < 0 and w.popolo == p:
					u.scorta = w.id
					w.scortato_da = u.id

func _fine_turno(eventi: Array) -> void:
	turno += 1
	if turno >= popoli.size():
		turno = 0
		if mese >= ZRegole.MESI:
			_termina(eventi)
			return
		mese += 1
	_inizia_turno(eventi)

func _inizia_turno(eventi: Array) -> void:
	turno_globale += 1
	var p := popolo_di_mano()
	# Un popolo senza più pezzi né città salta la sua mossa.
	if pedine_di(p).is_empty() and citta_di(p) == 0:
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
	fase = FASE_ALLEANZE if popoli.size() >= 3 else FASE_MOVIMENTO
	if turno == 0:
		_log("— Mese %d dell'Anno di Zargo —" % mese)
	_log("Muovono %s." % ZRegole.gli(p))
	eventi.append({"t": "turno", "p": p, "mese": mese})
	_sporca()

func _termina(eventi: Array) -> void:
	fase = FASE_FINITA
	var migliore := -1
	vincitori.clear()
	for p in popoli:
		var n := citta_di(p)
		if n > migliore:
			migliore = n
			vincitori = [p]
		elif n == migliore:
			vincitori.append(p)
	_log("L'Anno di Zargo è finito. %s con %d città." % [" e ".join(vincitori), migliore])
	eventi.append({"t": "fine", "vincitori": vincitori})

func _controlla_vittoria(eventi: Array) -> void:
	if fase in [FASE_SCHIERAMENTO, FASE_FINITA]:
		return
	var vivi: Array[String] = []
	for p in popoli:
		if citta_di(p) > 0 or not pedine_di(p).is_empty():
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
	rng.seed = int(String(d.seme))
	rng.state = int(String(d.stato))
	_sporca()
	cambiata.emit()
