class_name ZIA
extends RefCounted
## Avversario artificiale. Restituisce un'azione alla volta, così l'interfaccia
## può animare ogni passo; le azioni passano dalle stesse regole del giocatore.

var _turno_visto := -1
var _fatti := {}            # id pedina -> true, già considerata in questa fase
var _fase_vista := ""
var _campo := {}            # distanza (via terra) dall'obiettivo più vicino
var _tentativi := 0

func _reset_se_serve(g: ZPartita) -> void:
	if g.turno_globale != _turno_visto or g.fase != _fase_vista:
		_turno_visto = g.turno_globale
		_fase_vista = g.fase
		_fatti.clear()
		_tentativi = 0
		_campo.clear()

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
	match g.fase:
		ZPartita.FASE_SCHIERAMENTO:
			for u in g.pedine:
				if u.popolo == g.popolo_di_mano() and not u.schierata:
					return {"a": "auto_schieramento"}
			return {"a": "fine_schieramento"}
		ZPartita.FASE_ALLEANZE:
			return _alleanze(g)
		ZPartita.FASE_SINGOLI:
			return _singoli(g)
		ZPartita.FASE_MOVIMENTO:
			return _movimento(g)
		ZPartita.FASE_LANCI:
			return _lanci(g)
		ZPartita.FASE_COMBATTIMENTO:
			return _combattimento(g)
	return {}

# --- Diplomazia ----------------------------------------------------------------

func _capofila(g: ZPartita) -> String:
	var best := ""
	var n := -1
	for p in g.popoli:
		var c := g.citta_di(p) * 10 + g.pedine_di(p).size() / 5
		if c > n:
			n = c
			best = p
	return best

## Risposta di un popolo controllato dall'IA a una proposta d'alleanza.
static func accetta_alleanza(g: ZPartita, da: String, a: String) -> bool:
	for k in g.alleanze:
		if a in k:
			return false
	return g.citta_di(da) <= g.citta_di(a) + 1

func _alleanze(g: ZPartita) -> Dictionary:
	var io := g.popolo_di_mano()
	var capo := _capofila(g)
	if not _fatti.has(-10):
		_fatti[-10] = true
		for k in g.alleanze:
			var parti := k.split("|")
			var altro := parti[0] if parti[1] == io else parti[1]
			if io in parti and altro == capo and g.citta_di(altro) > g.citta_di(io) + 2:
				return {"a": "rompi", "con": altro}
	if not _fatti.has(-11):
		_fatti[-11] = true
		var ho_alleato := false
		for k in g.alleanze:
			if io in k:
				ho_alleato = true
		if not ho_alleato and g.popoli.size() >= 3:
			for p in g.popoli:
				if p != io and p != capo and not g.alleati(p, io) and "%s>%s" % [io, p] not in g.proposte:
					return {"a": "proponi", "a2": p}
	return {"a": "fase"}

# --- Movimento ------------------------------------------------------------------

func _valore(u: ZPedina) -> float:
	var v := float(u.c())
	if u.tipo == "signore":
		v += 4.0
	if u.tipo in ["mago", "illusionista", "fantarcere", "lanciafiamme"]:
		v += 2.0
	return v

func _calcola_campo(g: ZPartita, io: String) -> void:
	var sorgenti := {}
	for ci in g.citta:
		if ci.h[0] >= 0 and g.nemici(ci.p, io):
			# Le città sguarnite sono il bersaglio più appetibile.
			sorgenti[g.hex_citta(ci)] = 0 if ci.g.is_empty() else 2
	for u in g.pedine:
		if u.in_campo() and g.nemici(u.popolo, io):
			if not sorgenti.has(u.hex):
				sorgenti[u.hex] = 4
	var coda: Array[Vector2i] = []
	for h in sorgenti:
		_campo[h] = sorgenti[h]
		coda.append(h)
	coda.sort_custom(func(a, b): return _campo[a] < _campo[b])
	var i := 0
	while i < coda.size():
		var h := coda[i]
		i += 1
		for v in g.mappa.vicini_terra(h):
			var costo := 2 if g.mappa.terreno(v) in [ZMappa.T.BOSCO, ZMappa.T.MONTAGNA] else 1
			var nd: int = _campo[h] + costo
			if not _campo.has(v) or nd < _campo[v]:
				_campo[v] = nd
				coda.append(v)

func _distanza_obiettivo(h: Vector2i) -> float:
	return float(_campo.get(h, 200))

func _movimento(g: ZPartita) -> Dictionary:
	var io := g.popolo_di_mano()
	if _campo.is_empty():
		_calcola_campo(g, io)
	# 1. Monaci che ricompaiono.
	for u in g.pedine:
		if u.popolo == io and u.viva and u.scomparso and u.mese_scomparsa < g.turno_globale and not _fatti.has(u.id):
			_fatti[u.id] = true
			var best := u.hex
			var bv := INF
			for h in g.destinazioni_ricomparsa(u):
				var v := _distanza_obiettivo(h) + _pericolo(g, u, h) * 1.5
				if v < bv:
					bv = v
					best = h
			return {"a": "ricompari", "u": u.id, "h": [best.x, best.y]}
	return _movimento_ordinario(g)

func _singoli(g: ZPartita) -> Dictionary:
	var io := g.popolo_di_mano()
	# Attacchi singoli di Alati, Falchi e Serpenti.
	if true:
		var miglior := {}
		var mv := 0.6
		for u in g.pedine:
			if u.popolo != io or _fatti.has(1000 + u.id) or g.puo_attacco_singolo(u) != "":
				continue
			for b in g.pedine:
				if not g.attaccabile(b) or not g.nemici(b.popolo, io):
					continue
				if g.mappa.distanza(u.hex, b.hex) > u.m() + 1:
					continue
				var basi := g.basi_attacco_singolo(u, b)
				if basi.is_empty():
					continue
				var fa: int = u.c() + g.bonus_maghi(u)
				var fd := b.c() + g.bonus_maghi(b) + g.bonus_terreno(b)
				var pr := ZRegole.probabilita(fa - fd)
				var ev: float = (pr.DE * _valore(b) + pr.D * 0.4 * _valore(b) - pr.AE * _valore(u) - pr.A * 0.3 * _valore(u)) / 6.0
				if pr.AE > 0:
					ev -= 2.0
				if ev > mv:
					mv = ev
					var base: Vector2i = basi[0]
					for h in basi:
						if g.bonus_terreno_hex(h) > g.bonus_terreno_hex(base):
							base = h
					miglior = {"a": "singolo", "u": u.id, "b": b.id, "h": [base.x, base.y]}
		if not miglior.is_empty():
			_fatti[1000 + int(miglior.u)] = true
			return miglior
	# Draghi che fiammeggiano prima di muovere.
	for u in g.pedine:
		if u.popolo == io and u.tipo == "signore" and io == "Draghi" and u.in_campo() and not u.mosso and not u.agito and not _fatti.has(2000 + u.id):
			_fatti[2000 + u.id] = true
			var t := _miglior_bersaglio_tiro(g, u)
			if not t.is_empty():
				return t
	return {"a": "fase"}

func _movimento_ordinario(g: ZPartita) -> Dictionary:
	var io := g.popolo_di_mano()
	# Movimento ordinario, dai pezzi più vicini al fronte.
	var candidati: Array[ZPedina] = []
	for u in g.pedine:
		if u.popolo != io or _fatti.has(u.id) or not u.viva or u.scomparso or u.scortato_da >= 0:
			continue
		if g.puo_muovere(u) != "":
			continue
		candidati.append(u)
	if candidati.is_empty():
		return {"a": "fase"}
	candidati.sort_custom(func(a, b): return _distanza_obiettivo(a.hex) < _distanza_obiettivo(b.hex))
	var u := candidati[0]
	_fatti[u.id] = true
	# Le guarnigioni restano in città, salvo eccedenze quando il nemico è lontano.
	if u.citta >= 0:
		var ci: Dictionary = g.citta[u.citta]
		if ci.g.size() <= 2 or _distanza_obiettivo(u.hex) < 6:
			return _movimento(g)
	# Il Signore Monaco lontano dal fronte preferisce sparire.
	if io == "Monaci" and u.tipo == "signore" and u.in_campo() and _distanza_obiettivo(u.hex) > u.m() + 2 and not g.in_zona_nemica(u.hex, io):
		return {"a": "scompari", "u": u.id}
	var dest := _miglior_destinazione(g, u)
	if dest == u.hex:
		return _movimento(g)
	return {"a": "muovi", "u": u.id, "h": [dest.x, dest.y]}

func _pericolo(g: ZPartita, u: ZPedina, h: Vector2i) -> float:
	var nemico := 0.0
	var amico := float(u.c() + g.bonus_terreno_hex(h))
	for v in g.mappa.vicino_geometrico_tutti(h):
		for w in g.pedine_in(v):
			if g.nemici(w.popolo, u.popolo):
				nemico += w.c()
			elif w.popolo == u.popolo and w != u:
				amico += w.c() * 0.5
	return maxf(0.0, nemico - amico)

func _miglior_destinazione(g: ZPartita, u: ZPedina) -> Vector2i:
	var rag := g.raggiungibili(u)
	var tiratore := g.tipo_tiro(u) != "" and u.tipo != "signore"
	var best := u.hex
	var bv := _punteggio(g, u, u.hex, tiratore)
	for h in rag:
		var v := _punteggio(g, u, h, tiratore)
		if v < bv:
			bv = v
			best = h
	return best

func _punteggio(g: ZPartita, u: ZPedina, h: Vector2i, tiratore: bool) -> float:
	var d := _distanza_obiettivo(h)
	var ci := g.citta_in(h)
	if not ci.is_empty() and g.nemici(ci.p, u.popolo):
		return -100.0
	var s := d
	if tiratore:
		# Arcieri, maghi e lanciafiamme restano a qualche esagono dal nemico.
		var nemico_vicino := 99
		for v in g.mappa.vicino_geometrico_tutti(h):
			for w in g.pedine_in(v):
				if g.nemici(w.popolo, u.popolo):
					nemico_vicino = 1
		s = absf(d - 4.0) + (6.0 if nemico_vicino == 1 else 0.0)
	s += _pericolo(g, u, h) * 0.9
	s -= g.bonus_terreno_hex(h) * 0.4
	if g.mappa.terreno(h) == ZMappa.T.GORGO:
		s += 30.0
	return s

# --- Combattimento ---------------------------------------------------------------

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
			val = _valore(b) * (1.0 if b.m() >= 5 else 0.5) * (1.0 - v.distanza * 0.12)
		else:
			var media := 0.0
			for dado in range(1, 7):
				media += ZRegole.frecce(dado, v.distanza) if v.tipo == "frecce" else ZRegole.vampe(dado, v.distanza)
			media /= 6.0
			var mancano: int = int(v.servono) - b.colpi
			val = _valore(b) * clampf(media / maxf(1.0, mancano), 0.0, 1.0)
			if b.colpi > 0:
				val += 2.0
		if val > bv:
			bv = val
			best = {"a": "tiro", "u": u.id, "b": b.id}
	return best

func _lanci(g: ZPartita) -> Dictionary:
	var io := g.popolo_di_mano()
	for u in g.pedine:
		if u.popolo == io and not _fatti.has(3000 + u.id) and g.tipo_tiro(u) != "" and not u.agito and u.viva and not u.scomparso:
			_fatti[3000 + u.id] = true
			# Maghi, Illusionisti e Drago possono anche combattere: tirano solo
			# se non hanno un nemico adiacente da attaccare.
			if g.puo_attaccare(u) == "" and g.in_zona_nemica(u.hex, io):
				continue
			var t := _miglior_bersaglio_tiro(g, u)
			if not t.is_empty():
				return t
	return {"a": "fase"}

func _combattimento(g: ZPartita) -> Dictionary:
	var io := g.popolo_di_mano()
	# Assedi.
	for ci in g.citta:
		if ci.h[0] < 0 or not g.nemici(ci.p, io) or _fatti.has(5000 + int(ci.id)):
			continue
		var att: Array = []
		var forza := 0
		for v in g.mappa.vicino_geometrico_tutti(g.hex_citta(ci)):
			for w in g.pedine_in(v):
				if w.popolo == io and g.puo_attaccare(w) == "":
					att.append(w.id)
					forza += w.c() + g.bonus_maghi(w)
		var n: int = ci.g.size()
		if att.size() >= maxi(1, n) and forza >= n * 5 + 3:
			_fatti[5000 + int(ci.id)] = true
			return {"a": "assedio", "att": att, "c": ci.id}
	# Scontri: si cerca il nemico per cui l'attacco combinato conviene di più.
	var miglior := {}
	var mv := 0.3
	for b in g.pedine:
		if not g.attaccabile(b) or not g.nemici(b.popolo, io) or _fatti.has(4000 + b.id):
			continue
		var att: Array = []
		var valore_att := 0.0
		for v in g.mappa.vicino_geometrico_tutti(b.hex):
			for w in g.pedine_in(v):
				if w.popolo == io and g.puo_attaccare(w) == "":
					att.append(w.id)
					valore_att += _valore(w)
		if att.is_empty():
			continue
		var val := g.valuta_attacco(att, [b.id])
		if not val.ok:
			continue
		var pr: Dictionary = val.prob
		var ev: float = (pr.DE * _valore(b) + pr.D * 0.35 * _valore(b) - pr.AE * valore_att - pr.A * 0.25 * valore_att) / 6.0
		if ev > mv:
			mv = ev
			miglior = {"a": "attacco", "att": att, "dif": [b.id]}
	if not miglior.is_empty():
		_fatti[4000 + int(miglior.dif[0])] = true
		return miglior
	return {"a": "fase"}
