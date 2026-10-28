class_name ZIA
extends RefCounted
## Avversario artificiale. Restituisce un'azione alla volta, così l'interfaccia
## può animare ogni passo; le azioni passano dalle stesse regole del giocatore.
##
## A ogni mossa prepara un piano:
##  - una mappa della minaccia (forza nemica che può raggiungere ogni esagono);
##  - le proprie città in pericolo, con i pezzi più vicini mandati a difenderle;
##  - gli obiettivi d'attacco (città nemiche, più appetibili se sguarnite o
##    deboli rispetto alle forze che si possono radunare);
## poi muove i pezzi verso gli obiettivi senza esporli da soli, raduna più
## pezzi attorno ai nemici che conviene attaccare e combatte solo quando le
## probabilità della ruota lo giustificano.

var _turno_visto := -1
var _fatti := {}            # chiavi delle azioni già considerate in questa fase
var _fase_vista := ""
var _tentativi := 0
var _piano_fatto := false
var _campo := {}            # distanza pesata dall'obiettivo d'attacco più vicino
var _minaccia := {}         # esagono -> forza nemica che può attaccarlo
var _difesa := {}           # id città propria -> forza che manca per difenderla
var _difensori := {}        # id pedina -> id città da difendere
var _vicinanza := {}        # esagono -> distanza dal nemico attivo più vicino
var _ultima_proposta := {}  # popolo -> mese dell'ultima proposta fatta
static var _dist_terra := {}
## Parametri di gioco (tarati con tests/torneo_ia.gd).
var par := {"rischio": 1.0, "attacco": 2.5, "soglia": 0.25, "guarnigione": 2, "unione": 0.08, "difesa": 0.7}  # esagono -> {esagono: passi via terra} (entro 16)

func _reset_se_serve(g: ZPartita) -> void:
	var chiave := g.fase + g.popolo_di_mano()
	if g.turno_globale != _turno_visto or chiave != _fase_vista:
		if g.turno_globale != _turno_visto or not _fase_vista.ends_with(g.popolo_di_mano()):
			_piano_fatto = false
		_turno_visto = g.turno_globale
		_fase_vista = chiave
		_fatti.clear()
		_tentativi = 0

## Da chiamare quando l'azione proposta è stata rifiutata dalle regole.
func scarta(az: Dictionary) -> void:
	if az.has("u"):
		_fatti[int(az.u)] = true
	if az.has("att"):
		for id in az.att:
			_fatti[int(id)] = true

func prossima_azione(g: ZPartita) -> Dictionary:
	_reset_se_serve(g)
	_tentativi += 1
	if _tentativi > 600:
		return {"a": "fase"}
	if not _piano_fatto and g.fase != ZPartita.FASE_SCHIERAMENTO:
		_prepara_piano(g)
	match g.fase:
		ZPartita.FASE_SCHIERAMENTO:
			for u in g.pedine:
				if u.popolo == g.popolo_di_mano() and not u.schierata:
					return {"a": "auto_schieramento"}
			return {"a": "fine_schieramento"}
		ZPartita.FASE_ALLEANZE:
			return _alleanze(g)
		ZPartita.FASE_MAGIA:
			return _magia(g)
		ZPartita.FASE_SINGOLI:
			return _singoli(g)
		ZPartita.FASE_MOVIMENTO:
			return _movimento(g)
		ZPartita.FASE_LANCI:
			return _lanci(g)
		ZPartita.FASE_COMBATTIMENTO:
			return _combattimento(g)
	return {}

# --- Valori -----------------------------------------------------------------------

func _valore(u: ZPedina) -> float:
	var v := float(u.c())
	if u.tipo == "signore":
		v += 6.0
	if u.tipo in ["mago", "illusionista", "fantarcere", "lanciafiamme", "arciere", "reziario"]:
		v += 2.0
	if u.tipo == "megadrago":
		v = 2.0
	return v

## Passi via terra (ponti compresi) da `a`, fino a 16.
func _distanze(g: ZPartita, a: Vector2i) -> Dictionary:
	if _dist_terra.has(a):
		return _dist_terra[a]
	var dist := {a: 0}
	var coda: Array[Vector2i] = [a]
	var i := 0
	while i < coda.size():
		var h := coda[i]
		i += 1
		if dist[h] >= 16:
			continue
		for v in g.mappa.vicini_terra(h):
			if not dist.has(v):
				dist[v] = dist[h] + 1
				coda.append(v)
	_dist_terra[a] = dist
	return dist

func _passi(g: ZPartita, a: Vector2i, b: Vector2i) -> int:
	return int(_distanze(g, a).get(b, 99))

# --- Piano della mossa --------------------------------------------------------------

func _prepara_piano(g: ZPartita) -> void:
	_piano_fatto = true
	var io := g.popolo_di_mano()
	# 1. Minaccia: ogni nemico attivo minaccia gli esagoni entro movimento + 1.
	_minaccia.clear()
	for u in g.pedine:
		if not u.attivo() or not g.nemici(u.popolo, io) or u.paralisi > 0:
			continue
		var portata := u.m() + 1
		if u.tipo == "pantera0":
			portata = 1
		var d := _distanze(g, u.hex)
		var forza := float(u.c())
		for h in d:
			if d[h] <= portata:
				_minaccia[h] = float(_minaccia.get(h, 0.0)) + forza
	# Distanza (in esagoni) dal nemico attivo più vicino, per i tiratori.
	_vicinanza.clear()
	var cv: Array[Vector2i] = []
	for u in g.pedine:
		if u.attivo() and g.nemici(u.popolo, io) and not _vicinanza.has(u.hex):
			_vicinanza[u.hex] = 0
			cv.append(u.hex)
	var j := 0
	while j < cv.size():
		var h := cv[j]
		j += 1
		if int(_vicinanza[h]) >= 10:
			continue
		for v in g.mappa.vicino_geometrico_tutti(h):
			if not _vicinanza.has(v):
				_vicinanza[v] = int(_vicinanza[h]) + 1
				cv.append(v)
	# 2. Città proprie in pericolo e pezzi assegnati a difenderle.
	_difesa.clear()
	_difensori.clear()
	for ci in g.citta:
		if ci.p != io or ci.h[0] < 0:
			continue
		var hc := g.hex_citta(ci)
		var minaccia := float(_minaccia.get(hc, 0.0))
		if minaccia <= 0.0:
			continue
		var guarnigione := 0.0
		for id in ci.g:
			guarnigione += g.pedine[id].c()
		# Una guarnigione di N pezzi richiede almeno N assedianti: più pezzi, più sicura.
		var manca: float = minaccia * float(par.difesa) - guarnigione - ci.g.size() * 3.0
		if ci.g.size() < ZRegole.MAX_GUARNIGIONE and manca > 0.0:
			_difesa[int(ci.id)] = manca
	if not _difesa.is_empty():
		var liberi: Array[ZPedina] = []
		for u in g.pedine:
			if u.popolo == io and u.in_campo() and not u.ridotta and u.scortato_da < 0 and u.tipo != "megadrago":
				liberi.append(u)
		for cid in _difesa:
			var hc := g.hex_citta(g.citta[cid])
			var vicini := liberi.filter(func(u): return not _difensori.has(u.id) and _passi(g, u.hex, hc) <= u.m() * 2)
			vicini.sort_custom(func(a, b): return _passi(g, a.hex, hc) < _passi(g, b.hex, hc))
			var serve: float = _difesa[cid]
			var posti: int = ZRegole.MAX_GUARNIGIONE - g.citta[cid].g.size()
			for u in vicini:
				if serve <= 0.0 or posti <= 0:
					break
				_difensori[u.id] = cid
				serve -= u.c() + 3.0
				posti -= 1
	# 3. Obiettivi d'attacco: campo di distanze pesate verso le città nemiche.
	_campo.clear()
	var forza_mia := {}
	var sorgenti := {}
	for ci in g.citta:
		if ci.h[0] < 0 or not g.nemici(ci.p, io):
			continue
		var hc := g.hex_citta(ci)
		var vicine := 0.0
		for u in g.pedine:
			if u.popolo == io and u.in_campo() and _passi(g, u.hex, hc) <= 10:
				vicine += u.c()
		var costo: float = 0.0 if ci.g.is_empty() else 3.0 + ci.g.size() * 2.0
		# Le città dove si possono radunare più forze sono più vicine "di fatto".
		costo -= minf(vicine / 10.0, 4.0)
		costo += float(_minaccia.get(hc, 0.0)) / 15.0
		if g.mese >= g.mesi_totali() - 3:
			costo -= 3.0   # nel finale contano solo le città
		sorgenti[hc] = maxf(costo, 0.0)
	for u in g.pedine:
		if u.attivo() and g.nemici(u.popolo, io) and not sorgenti.has(u.hex):
			# I pezzi nemici sono obiettivi minori; i Signori un po' più appetibili.
			sorgenti[u.hex] = 7.0 if u.tipo != "signore" else 5.0
	var coda: Array[Vector2i] = []
	for h in sorgenti:
		_campo[h] = sorgenti[h]
		coda.append(h)
	var i := 0
	while i < coda.size():
		var h := coda[i]
		i += 1
		for v in g.vicini(h):
			var costo := 2.0 if g.terreno(v) in [ZMappa.T.BOSCO, ZMappa.T.MONTAGNA] else 1.0
			var nd: float = _campo[h] + costo
			if not _campo.has(v) or nd < _campo[v] - 0.01:
				_campo[v] = nd
				coda.append(v)

func _distanza_obiettivo(h: Vector2i) -> float:
	return float(_campo.get(h, 200.0))

## Forza amica che può dare man forte in `h` (pezzi adiacenti), escluso `u`.
func _sostegno(g: ZPartita, u: ZPedina, h: Vector2i) -> float:
	var s := 0.0
	for v in g.mappa.vicino_geometrico_tutti(h):
		for w in g.pedine_in(v):
			if w != u and (w.popolo == u.popolo or g.alleati(w.popolo, u.popolo)) and w.attivo():
				s += w.c()
	return s

## Rischio di restare in `h`: forza nemica che può arrivarci meno la propria
## difesa (valore, terreno, Maghi vicini) e quella dei vicini.
func _rischio(g: ZPartita, u: ZPedina, h: Vector2i) -> float:
	var nemico := float(_minaccia.get(h, 0.0))
	if nemico <= 0.0:
		return 0.0
	var difesa := float(u.c() + g.bonus_terreno_hex(h)) + _sostegno(g, u, h) * 0.6
	var eccesso := nemico - difesa
	if eccesso <= -3.0:
		return 0.0
	return (eccesso + 3.0) * _valore(u) / 8.0

# --- Diplomazia ----------------------------------------------------------------

func _capofila(g: ZPartita) -> String:
	var best := ""
	var n := -1.0
	for p in g.popoli:
		var c := float(g.citta_di(p)) * 10.0 + g.pedine_di(p).size() / 5.0
		if c > n:
			n = c
			best = p
	return best

## Risposta di un popolo controllato dall'IA a una proposta d'alleanza:
## accetta se non ha già un alleato e chi propone non è in testa.
static func accetta_alleanza(g: ZPartita, da: String, a: String) -> bool:
	for k in g.alleanze:
		if a in k.split("|"):
			return false
	var migliore := 0
	for p in g.popoli:
		if p != da:
			migliore = maxi(migliore, g.citta_di(p))
	return g.citta_di(da) <= migliore and g.citta_di(da) <= g.citta_di(a) + 1

func _alleanze(g: ZPartita) -> Dictionary:
	var io := g.popolo_di_mano()
	var capo := _capofila(g)
	if not _fatti.has(-10):
		_fatti[-10] = true
		for k in g.alleanze:
			var parti := k.split("|")
			if io not in parti:
				continue
			var altro := parti[0] if parti[1] == io else parti[1]
			# Si tradisce l'alleato che è in testa, o nel finale se una sua città
			# sguarnita è a portata.
			if altro == capo and g.citta_di(altro) > g.citta_di(io) + 1:
				return {"a": "rompi", "con": altro}
			if g.mese >= g.mesi_totali() - 4:
				for ci in g.citta:
					if ci.p == altro and ci.h[0] >= 0 and ci.g.size() <= 1:
						for u in g.pedine:
							if u.popolo == io and u.in_campo() and _passi(g, u.hex, g.hex_citta(ci)) <= u.m():
								return {"a": "rompi", "con": altro}
	if not _fatti.has(-11):
		_fatti[-11] = true
		var ho_alleato := false
		for k in g.alleanze:
			if io in k.split("|"):
				ho_alleato = true
		if not ho_alleato and g.popoli.size() >= 3:
			# Una proposta ogni quattro mesi, al popolo meno minaccioso che non sia in testa.
			var scelto := ""
			var meglio := INF
			for p in g.popoli:
				if p == io or p == capo or g.alleati(p, io) or "%s>%s" % [io, p] in g.proposte:
					continue
				if g.mese - int(_ultima_proposta.get(p, -99)) < 4:
					continue
				var pressione := 0.0
				for u in g.pedine:
					if u.popolo == p and u.in_campo():
						for ci in g.citta:
							if ci.p == io and ci.h[0] >= 0 and _passi(g, u.hex, g.hex_citta(ci)) <= 8:
								pressione += u.c()
								break
				if pressione < meglio:
					meglio = pressione
					scelto = p
			if scelto != "":
				_ultima_proposta[scelto] = g.mese
				return {"a": "proponi", "a2": scelto}
	return {"a": "fase"}

# --- Attacchi singoli e trasformazioni ---------------------------------------------

func _singoli(g: ZPartita) -> Dictionary:
	var io := g.popolo_di_mano()
	for u in g.pedine:
		if u.popolo == io and u.tipo == "donna" and not _fatti.has(6000 + u.id) and g.puo_trasformare(u) == "":
			_fatti[6000 + u.id] = true
			if float(_minaccia.get(u.hex, 0.0)) > 0.0 or _distanza_obiettivo(u.hex) < 14.0:
				return {"a": "trasforma", "u": u.id}
	var miglior := {}
	var mv := 0.8
	for u in g.pedine:
		if u.popolo != io or _fatti.has(1000 + u.id) or g.puo_attacco_singolo(u) != "":
			continue
		if int(_vicinanza.get(u.hex, 99)) > u.m() + 1:
			continue
		for b in g.pedine:
			if not g.attaccabile(b) or not g.nemici(b.popolo, io):
				continue
			if g.mappa.distanza(u.hex, b.hex) > u.m() + 1:
				continue
			var fa: int = g.valore(u) + g.bonus_maghi(u)
			var fd := g.forza_difesa([b])
			var pr := ZRegole.probabilita(fa - fd)
			var ev: float = (pr.DE * _valore(b) + pr.D * 0.4 * _valore(b) - pr.AE * _valore(u) - pr.A * 0.3 * _valore(u)) / 6.0
			if pr.AE > 0:
				ev -= 2.0
			if ev <= mv:
				continue
			var basi := g.basi_attacco_singolo(u, b)
			if basi.is_empty():
				continue
			# Dopo l'attacco il pezzo resta lì: meglio se non è un esagono pericoloso.
			var base: Vector2i = basi[0]
			var rb := INF
			for h in basi:
				var r := _rischio(g, u, h) - g.bonus_terreno_hex(h)
				if r < rb:
					rb = r
					base = h
			ev -= maxf(rb, 0.0) * 0.5
			if ev > mv:
				mv = ev
				miglior = {"a": "singolo", "u": u.id, "b": b.id, "h": [base.x, base.y]}
	if not miglior.is_empty():
		_fatti[1000 + int(miglior.u)] = true
		return miglior
	for u in g.pedine:
		if u.popolo == io and u.tipo == "signore" and io == "Draghi" and u.in_campo() and not u.mosso and not u.agito and not _fatti.has(2000 + u.id):
			_fatti[2000 + u.id] = true
			# Fiamme prima di muovere solo se non serve muovere per un attacco migliore.
			if not g.in_zona_nemica(u.hex, io):
				var t := _miglior_bersaglio_tiro(g, u)
				if not t.is_empty() and float(t.get("val", 0.0)) >= 3.0:
					t.erase("val")
					return t
	return {"a": "fase"}

# --- Movimento ------------------------------------------------------------------

func _movimento(g: ZPartita) -> Dictionary:
	var io := g.popolo_di_mano()
	# 1. Monaci che ricompaiono: vicino agli obiettivi ma al sicuro.
	for u in g.pedine:
		if u.popolo == io and u.viva and u.scomparso and u.mese_scomparsa < g.turno_globale and not _fatti.has(u.id):
			_fatti[u.id] = true
			var best := u.hex
			var bv := INF
			for h in g.destinazioni_ricomparsa(u):
				var v := _distanza_obiettivo(h) + _rischio(g, u, h) * 2.0
				if v < bv:
					bv = v
					best = h
			return {"a": "ricompari", "u": u.id, "h": [best.x, best.y]}
	# 2. Passaggi segreti verso una città in pericolo.
	if g.opzione("passaggi") and not g.passaggio_usato and not _difesa.is_empty() and not _fatti.has(-30):
		_fatti[-30] = true
		for cid in _difesa:
			var dest: Dictionary = g.citta[cid]
			for ci in g.citta:
				if ci.p == io and int(ci.id) != cid and ci.g.size() >= 3 and float(_minaccia.get(g.hex_citta(ci), 0.0)) <= 0.0:
					var forte := -1
					var fv := -1
					for id in ci.g:
						var w: ZPedina = g.pedine[id]
						if g.puo_passaggio(w) == "" and w.c() > fv:
							fv = w.c()
							forte = id
					if forte >= 0 and dest.g.size() < ZRegole.MAX_GUARNIGIONE:
						return {"a": "passaggio", "u": forte, "c": cid}
	return _movimento_ordinario(g)

func _movimento_ordinario(g: ZPartita) -> Dictionary:
	var io := g.popolo_di_mano()
	var candidati: Array[ZPedina] = []
	for u in g.pedine:
		if u.popolo != io or _fatti.has(u.id) or not u.viva or u.scomparso or u.scortato_da >= 0:
			continue
		if g.puo_muovere(u) != "":
			continue
		candidati.append(u)
	if candidati.is_empty():
		return {"a": "fase"}
	# Prima i difensori, poi dal fronte verso le retrovie; a parità i pezzi forti.
	candidati.sort_custom(func(a, b):
		var da: float = -100.0 if _difensori.has(a.id) else _distanza_obiettivo(a.hex) - a.c() * 0.1
		var db: float = -100.0 if _difensori.has(b.id) else _distanza_obiettivo(b.hex) - b.c() * 0.1
		return da < db)
	var u := candidati[0]
	_fatti[u.id] = true
	# Le guarnigioni restano: escono solo le eccedenze di una città tranquilla.
	if u.citta >= 0:
		var ci: Dictionary = g.citta[u.citta]
		var tranquilla := float(_minaccia.get(g.hex_citta(ci), 0.0)) <= 0.0
		if ci.g.size() <= int(par.guarnigione) or not tranquilla or u.tipo in ["mago", "illusionista"]:
			return _movimento(g)
		# Esce chi vale di più in campo, non i fanti.
		var minimo := 999
		for id in ci.g:
			minimo = mini(minimo, g.pedine[id].c())
		if u.c() <= minimo and ci.g.size() <= 3:
			return _movimento(g)
	# Il Signore Monaco lontano dal fronte e al sicuro sparisce per ricomparire più avanti.
	if io == "Monaci" and u.tipo == "signore" and u.in_campo() and not u.mosso and _distanza_obiettivo(u.hex) > u.m() + 2 and not g.in_zona_nemica(u.hex, io) and not _difensori.has(u.id):
		return {"a": "scompari", "u": u.id}
	var dest := _miglior_destinazione(g, u)
	if dest == u.hex:
		return _movimento(g)
	return {"a": "muovi", "u": u.id, "h": [dest.x, dest.y]}

func _miglior_destinazione(g: ZPartita, u: ZPedina) -> Vector2i:
	var rag := g.raggiungibili(u)
	var best := u.hex
	var bv := _punteggio(g, u, u.hex)
	for h in rag:
		var v := _punteggio(g, u, h)
		if v < bv:
			bv = v
			best = h
	return best

## Punteggio di un esagono di arrivo (più basso è meglio).
func _punteggio(g: ZPartita, u: ZPedina, h: Vector2i) -> float:
	var io := u.popolo
	var ci := g.citta_in(h)
	if not ci.is_empty():
		if g.nemici(ci.p, io):
			return -200.0   # città nemica sguarnita: si prende
		if ci.p == io:
			# Rinforzo di una città minacciata.
			if _difensori.get(u.id, -1) == int(ci.id) or (_difesa.has(int(ci.id)) and u.tipo != "signore"):
				return -150.0
			return 500.0
	if g.terreno(h) == ZMappa.T.GORGO:
		return 500.0
	# Difensore in viaggio: verso la città assegnata.
	if _difensori.has(u.id):
		var hc := g.hex_citta(g.citta[_difensori[u.id]])
		return float(_passi(g, h, hc)) * 2.0 + _rischio(g, u, h) * 0.5
	var tiratore := g.tipo_tiro(u) != "" and u.tipo != "signore" and g.puo_attaccare(u) != ""
	var s := _distanza_obiettivo(h)
	# Nemici adiacenti: questa mossa si combatte. Conviene se l'attacco
	# combinato (con chi è già lì intorno) ha buone probabilità.
	var adiacenti: Array[ZPedina] = []
	for v in g.mappa.vicino_geometrico_tutti(h):
		for w in g.pedine_in(v):
			if g.attaccabile(w) and g.nemici(w.popolo, io):
				adiacenti.append(w)
	if tiratore:
		var gitt := g.gittata(u)
		var vicino := int(_vicinanza.get(h, 11))
		s = absf(float(vicino) - maxf(2.0, gitt - 1.0)) * 1.5 + (8.0 if not adiacenti.is_empty() else 0.0)
		s += _rischio(g, u, h) * 1.2
	elif not adiacenti.is_empty() and g.puo_attaccare(u) == "":
		var meglio := -INF
		for b in adiacenti:
			var forza := float(g.valore(u) + g.bonus_maghi(u))
			for v in g.mappa.vicino_geometrico_tutti(b.hex):
				for w in g.pedine_in(v):
					if w != u and w.popolo == io and g.puo_attaccare(w) == "":
						forza += g.valore(w) + g.bonus_maghi(w)
			var diff := int(forza) - g.forza_difesa([b])
			var pr := ZRegole.probabilita(diff)
			var ev: float = (pr.DE * _valore(b) + pr.D * 0.4 * _valore(b) - pr.AE * _valore(u) * 1.5 - pr.A * 0.35 * _valore(u)) / 6.0
			meglio = maxf(meglio, ev)
		s = _distanza_obiettivo(h) * 0.3 - meglio * float(par.attacco) + _rischio(g, u, h) * 0.6 * float(par.rischio)
		if meglio < 0.0:
			s += 10.0
	else:
		s += _rischio(g, u, h) * float(par.rischio)
	# Restare uniti: un piccolo premio per i compagni vicini.
	s -= minf(_sostegno(g, u, h), 12.0) * float(par.unione)
	s -= g.bonus_terreno_hex(h) * 0.3
	if g.zl2() and g.ha_rete(h) and io != "Aracnidi":
		s += 6.0
	return s

# --- Lanci ------------------------------------------------------------------------

func _miglior_bersaglio_tiro(g: ZPartita, u: ZPedina) -> Dictionary:
	var best := {}
	var bv := 0.0
	for b in g.pedine:
		if not g.attaccabile(b) or not g.nemici(b.popolo, u.popolo):
			continue
		if g.mappa.distanza(u.hex, b.hex) > g.gittata(u):
			continue
		var v := g.valuta_tiro(u, b)
		if not v.ok:
			continue
		var val := 0.0
		if v.tipo == "visione":
			# Una visione che mette in fuga un nemico a contatto apre la strada.
			val = _valore(b) * (1.0 if b.m() >= 5 else 0.5) * (1.0 - v.distanza * 0.12)
			if g.in_zona_nemica(b.hex, b.popolo) or _sostegno(g, b, b.hex) > 0.0:
				val *= 1.3
		else:
			var media := 0.0
			for dado in range(1, 7):
				match v.tipo:
					"frecce": media += ZRegole.frecce(dado, v.distanza)
					"fiamme": media += ZRegole.vampe(dado, v.distanza)
					_: media += ZRegole.colpi_arcieri_cavallo(dado, v.distanza)
			media /= 6.0
			var mancano: int = int(v.servono) - b.colpi
			val = _valore(b) * clampf(media / maxf(1.0, mancano), 0.0, 1.0)
			# Finire un bersaglio già colpito.
			if b.colpi > 0:
				val += 3.0
		if val > bv:
			bv = val
			best = {"a": "tiro", "u": u.id, "b": b.id, "val": val}
	return best

func _lanci(g: ZPartita) -> Dictionary:
	var io := g.popolo_di_mano()
	for u in g.pedine:
		if u.popolo == io and u.tipo == "fante" and not _fatti.has(7000 + u.id) and g.puo_trasformare(u) == "" and g.in_zona_nemica(u.hex, io):
			_fatti[7000 + u.id] = true
			return {"a": "trasforma", "u": u.id}
	# Prima chi può solo tirare (arcieri, lanciafiamme), poi gli altri.
	var ordine: Array[ZPedina] = []
	for u in g.pedine:
		if u.popolo == io and not _fatti.has(3000 + u.id) and g.tipo_tiro(u) != "" and not u.agito and u.viva and not u.scomparso:
			ordine.append(u)
	ordine.sort_custom(func(a, b): return (0 if g.puo_attaccare(a) != "" else 1) < (0 if g.puo_attaccare(b) != "" else 1))
	for u in ordine:
		_fatti[3000 + u.id] = true
		var t := _miglior_bersaglio_tiro(g, u)
		if t.is_empty():
			continue
		# Maghi, Illusionisti e Draghi possono anche combattere: tirano se il
		# corpo a corpo non serve o se il lancio vale di più.
		if g.puo_attaccare(u) == "" and g.in_zona_nemica(u.hex, io):
			var conviene := false
			for b in g.pedine:
				if b.attivo() and g.nemici(b.popolo, io) and g.mappa.distanza(u.hex, b.hex) == 1:
					var att := _attaccanti_di(g, b)
					var val := g.valuta_attacco(att, [b.id])
					if val.ok and int(val.prob.DE) + int(val.prob.D) >= 4:
						conviene = true
			if conviene and float(t.val) < 6.0:
				continue
		t.erase("val")
		return t
	return {"a": "fase"}

# --- Combattimento ---------------------------------------------------------------

func _attaccanti_di(g: ZPartita, b: ZPedina) -> Array:
	var io := g.popolo_di_mano()
	var att: Array = []
	for v in g.mappa.vicino_geometrico_tutti(b.hex):
		for w in g.pedine_in(v):
			if w.popolo == io and g.puo_attaccare(w) == "" and w.id not in att:
				att.append(w.id)
	return att

func _combattimento(g: ZPartita) -> Dictionary:
	var io := g.popolo_di_mano()
	# Assedi: servono almeno tanti pezzi quanti la guarnigione e forza sufficiente.
	for ci in g.citta:
		if ci.h[0] < 0 or not g.nemici(ci.p, io) or _fatti.has(5000 + int(ci.id)):
			continue
		var att: Array = []
		var forza := 0
		for v in g.mappa.vicino_geometrico_tutti(g.hex_citta(ci)):
			for w in g.pedine_in(v):
				if w.popolo == io and g.puo_attaccare(w) == "":
					att.append(w.id)
					forza += g.valore(w) + g.bonus_maghi(w)
		var n: int = ci.g.size()
		if att.size() < maxi(1, n):
			continue
		# La guarnigione è coperta: si stima dal valore medio dei pezzi di quel popolo.
		var media := 4.0
		var tot := 0.0
		var cnt := 0
		for w in g.pedine:
			if w.popolo == ci.p and w.viva and w.tipo != "signore":
				tot += w.c()
				cnt += 1
		if cnt > 0:
			media = tot / cnt
		var pr := ZRegole.probabilita(forza - int(round(media * n)))
		var valore_att := 0.0
		for id in att:
			valore_att += _valore(g.pedine[id])
		var premio := 14.0 + media * n + (6.0 if g.mese >= g.mesi_totali() - 2 else 0.0)
		var ev: float = ((pr.D + pr.DE) * premio - pr.AE * valore_att - pr.A * 0.25 * valore_att) / 6.0
		if n == 0 or ev > 1.0:
			_fatti[5000 + int(ci.id)] = true
			return {"a": "assedio", "att": att, "c": ci.id}
	# Scontri: per ogni nemico si sceglie il gruppo d'attacco che conviene di più.
	# Si comincia dai pezzi più deboli o già colpiti, che è più facile eliminare.
	var miglior := {}
	var mv: float = par.soglia
	for b in g.pedine:
		if not g.attaccabile(b) or not g.nemici(b.popolo, io) or _fatti.has(4000 + b.id):
			continue
		var att := _attaccanti_di(g, b)
		if att.is_empty():
			continue
		# Si prova il gruppo intero e, se non serve tutto, il gruppo senza i più
		# preziosi (Signori), che restano liberi per un altro scontro.
		var gruppi := [att]
		var senza := att.filter(func(id): return g.pedine[id].tipo != "signore")
		if senza.size() > 0 and senza.size() < att.size():
			gruppi.append(senza)
		for gr in gruppi:
			var val := g.valuta_attacco(gr, [b.id])
			if not val.ok:
				continue
			var valore_att := 0.0
			for id in gr:
				valore_att += _valore(g.pedine[id])
			var pr: Dictionary = val.prob
			var valore_dif := 0.0
			for id in g.espandi_difensori([b.id]):
				valore_dif += _valore(g.pedine[id])
			var ev: float = (pr.DE * valore_dif + pr.D * 0.45 * valore_dif - pr.AE * valore_att - pr.A * 0.25 * valore_att) / 6.0
			# Pezzi nemici a contatto con le proprie città: priorità.
			for ci in g.citta:
				if ci.p == io and ci.h[0] >= 0 and g.mappa.distanza(g.hex_citta(ci), b.hex) <= 2:
					ev += 1.5
					break
			if gr.size() < att.size():
				ev += 0.4
			if ev > mv:
				mv = ev
				miglior = {"a": "attacco", "att": gr, "dif": [b.id]}
	if not miglior.is_empty():
		_fatti[4000 + int(miglior.dif[0])] = true
		return miglior
	return {"a": "fase"}

# --- Magia -----------------------------------------------------------------------

## Probabilità (su 6) che una magia di minimo `m` riesca spendendo `p` punti.
func _prob_magia(m: int, p: int) -> float:
	return clampf(7.0 - float(m - p), 0.0, 6.0) / 6.0

func _magia(g: ZPartita) -> Dictionary:
	var io := g.popolo_di_mano()
	if _fatti.has(-20):
		return {"a": "fase"}
	_fatti[-20] = true
	var prep: int = int(g.preparazione.get(io, 0))
	if prep < 2:
		return {"a": "fase"}
	var opzioni := []   # [valore atteso, magia, esagono]
	# Terremoto e Sonno: sull'esagono nemico più ricco.
	for b in g.pedine:
		if not b.attivo() or not g.nemici(b.popolo, io) or not g.entro_raggio_magia(io, b.hex):
			continue
		var v := 0.0
		for w in g.pedine_in(b.hex):
			if g.nemici(w.popolo, io):
				v += _valore(w)
		opzioni.append([v * _prob_magia(7, prep), "terremoto", b.hex])
		opzioni.append([v * 0.6 * _prob_magia(6, prep), "sonno", b.hex])
	# Voragine: una città nemica a portata vale molto.
	for ci in g.citta:
		if ci.h[0] >= 0 and g.nemici(ci.p, io):
			var hc := g.hex_citta(ci)
			if g.entro_raggio_magia(io, hc):
				var v := 14.0
				for id in ci.g:
					v += _valore(g.pedine[id])
				opzioni.append([v * _prob_magia(8, prep), "voragine", hc])
	# Seconda nascita: un Signore perso torna in una propria città.
	var persi := g.pedine.filter(func(u): return u.popolo == io and u.tipo == "signore" and not u.viva).size()
	if persi > 0:
		for ci in g.citta:
			if ci.p == io and ci.h[0] >= 0 and g.entro_raggio_magia(io, g.hex_citta(ci)):
				opzioni.append([10.0 * _prob_magia(8, prep), "rinascita", g.hex_citta(ci)])
				break
	# Coraggio: recupera i propri pezzi ridotti.
	var ridotte := g.pedine.filter(func(u): return u.popolo == io and u.viva and u.ridotta)
	if ridotte.size() > 0 and g.entro_raggio_magia(io, ridotte[0].hex):
		opzioni.append([float(ridotte.size()) * 3.0 * _prob_magia(6, prep), "coraggio", ridotte[0].hex])
	var migliore := [0.0, "", Vector2i.ZERO]
	for o in opzioni:
		if float(o[0]) > float(migliore[0]) and g.valuta_magia(o[1], o[2]) == "":
			migliore = o
	# Con pochi punti si lancia solo un colpo molto conveniente; altrimenti si accumula.
	var soglia := 12.0 if prep < ZRegole.MAX_PREPARAZIONE else 3.0
	if migliore[1] == "" or float(migliore[0]) < soglia:
		return {"a": "fase"}
	var h: Vector2i = migliore[2]
	return {"a": "magia", "s": migliore[1], "h": [h.x, h.y], "punti": prep}
