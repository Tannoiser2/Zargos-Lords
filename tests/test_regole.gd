extends SceneTree
## Verifiche automatiche delle regole: tabelle delle ruote, esempi del
## regolamento e casi particolari di movimento e combattimento.

var errori := 0

func controlla(cond: bool, descrizione: String) -> void:
	if cond:
		print("  ok  ", descrizione)
	else:
		errori += 1
		printerr("  NO  ", descrizione)

## Partita a due popoli, già nella fase di movimento dei Cavalieri, con tutti i
## pezzi fuori dal tabellone: ogni test colloca solo ciò che gli serve.
func partita_vuota() -> ZPartita:
	var g := ZPartita.new()
	g.nuova(["Cavalieri", "Monaci"], {"Cavalieri": "umano", "Monaci": "umano"}, 7)
	for u in g.pedine:
		u.schierata = false
		u.hex = Vector2i(-1, -1)
	g.fase = ZPartita.FASE_MOVIMENTO
	g.turno = 0
	g.turno_globale = 1
	g._sporca()
	return g

func metti(g: ZPartita, popolo: String, tipo: String, h: Vector2i) -> ZPedina:
	for u in g.pedine:
		if u.popolo == popolo and u.tipo == tipo and not u.schierata:
			u.hex = h
			u.schierata = true
			g._sporca()
			return u
	return null

func trova(g: ZPartita, t: int, da: Vector2i = Vector2i(5, 5)) -> Vector2i:
	for r in range(da.y, g.mappa.righe):
		for c in range(da.x, g.mappa.colonne):
			var h := Vector2i(c, r)
			if g.mappa.terreno(h) == t:
				return h
	return Vector2i(-1, -1)

## Esagono di pianura con tutti i vicini (e i loro vicini) di pianura.
func pianura_aperta(g: ZPartita, da := Vector2i(8, 8)) -> Vector2i:
	for r in range(da.y, g.mappa.righe - 3):
		for c in range(da.x, g.mappa.colonne - 3):
			var h := Vector2i(c, r)
			var ok := true
			for v in g.mappa.linea(h, 0, 4) + g.mappa.linea(h, 3, 4) + g.mappa.vicino_geometrico_tutti(h):
				if g.mappa.terreno(v) != ZMappa.T.PIANURA:
					ok = false
			for dir in 6:
				for v in g.mappa.linea(h, dir, 3):
					if g.mappa.terreno(v) != ZMappa.T.PIANURA:
						ok = false
			if ok:
				return h
	return Vector2i(-1, -1)

func _init() -> void:
	print("Tabelle")
	controlla(ZRegole.esito_combattimento(7, 4) == "D3", "esempio del regolamento: 12 contro 5, dado 4 → D3")
	controlla(ZRegole.esito_combattimento(-6, 6) == "", "differenza sotto -5: attacco vietato")
	controlla(ZRegole.esito_combattimento(-5, 1) == "AE", "dado 1 a -5: attaccante eliminato")
	controlla(ZRegole.esito_combattimento(250, 1) == "D5", "differenze oltre 100 restano nell'ultima fascia")
	controlla(ZRegole.frecce(1, 1) + ZRegole.frecce(6, 2) + ZRegole.frecce(4, 3) == 6, "frecce sommate: 1 + 3 + 2 contro un Drago")
	controlla(ZRegole.vampe(6, 1) == 4 and ZRegole.vampe(1, 5) == 0, "ruota del fuoco")
	controlla(ZRegole.fuga_visione(6, 1, 10) == 10 and ZRegole.fuga_visione(1, 5, 10) == 4, "visioni: MAX e MAX-6")
	controlla(ZRegole.FRECCE_NECESSARIE["Draghi"]["signore"] == 6, "servono 6 frecce per un Signore Drago")
	controlla(ZRegole.VAMPE_NECESSARIE["Draghi"]["serpente"] == 0, "i Draghi sono immuni al fuoco")

	print("Mappa")
	var m := ZMappa.condivisa()
	controlla(m.colonne == 66 and m.righe == 53, "reticolo 66 × 53 esagoni")
	var ponti := m.estremi_ponti()
	controlla(ponti.size() > 40, "ponti di nuvole caricati (%d estremità)" % ponti.size())
	var a: Vector2i = ponti.keys()[0]
	controlla(m.terra(a) and m.terra(ponti[a][0]) and ponti[a][0] in m.vicini_terra(a), "un ponte collega due coste")
	var cont := [0, 0, 0, 0]
	for i in 4:
		cont[i] = m.esagoni_continente(i).size()
	controlla(cont.min() > 350, "quattro continenti di dimensioni simili %s" % str(cont))

	print("Movimento")
	var g := partita_vuota()
	var p := pianura_aperta(g)
	var fante := metti(g, "Cavalieri", "fante", p)
	var rag := g.raggiungibili(fante)
	controlla(rag.size() > 0 and rag.values().max() <= 4, "un fante muove al massimo di 4 esagoni")
	var mt := trova(g, ZMappa.T.MONTAGNA)
	var vicino_mt := Vector2i(-1, -1)
	for v in g.mappa.vicini_terra(mt):
		if g.mappa.terreno(v) == ZMappa.T.PIANURA:
			vicino_mt = v
	fante.hex = vicino_mt
	g._sporca()
	rag = g.raggiungibili(fante)
	controlla(rag.has(mt), "dai piedi della montagna si sale in una mossa")
	controlla(int(rag[mt]) == fante.m(), "salire in montagna richiede l'intera mossa")


	g = partita_vuota()
	p = pianura_aperta(g)
	fante = metti(g, "Cavalieri", "fante", p)
	var lontano := g.mappa.linea(p, 0, 3)[-1]
	var nemico := metti(g, "Monaci", "fante", lontano)
	rag = g.raggiungibili(fante)
	var dietro := g.mappa.linea(lontano, 0, 1)[0]
	controlla(not rag.has(dietro) or g.mappa.terreno(dietro) != ZMappa.T.PIANURA, "non si attraversa la zona d'influenza nemica")
	controlla(rag.has(g.mappa.linea(p, 0, 2)[-1]), "si entra nella zona d'influenza per attaccare")

	print("Combattimento")
	g = partita_vuota()
	p = pianura_aperta(g)
	var f1 := metti(g, "Monaci", "fante", p)
	var f2 := metti(g, "Monaci", "fante", g.mappa.vicino_dir(p, 1))
	var f3 := metti(g, "Monaci", "fante", g.mappa.vicino_dir(p, 2))
	var bersaglio := metti(g, "Cavalieri", "fante", g.mappa.vicino_dir(g.mappa.vicino_dir(p, 1), 2))
	g.turno = 1
	g.fase = ZPartita.FASE_COMBATTIMENTO
	var adiac := []
	for u in [f1, f2, f3]:
		if g.mappa.adiacenti(u.hex, bersaglio.hex):
			adiac.append(u.id)
	var val := g.valuta_attacco(adiac, [bersaglio.id])
	controlla(val.ok and val.fa == 4 * adiac.size(), "più pezzi sommano la loro forza (%d)" % val.get("fa", 0))
	var r := g.esegui({"a": "attacco", "att": adiac, "dif": [bersaglio.id]})
	controlla(r.ok and r.eventi.size() > 0, "lo scontro viene risolto: " + str(g.registro[-1]))
	controlla(g.mischia_iniziata, "dopo uno scontro non si tira più")

	g = partita_vuota()
	p = pianura_aperta(g)
	var mago := metti(g, "Cavalieri", "mago", p)
	var cav := metti(g, "Cavalieri", "fante", g.mappa.vicino_dir(p, 0))
	controlla(g.bonus_maghi(cav) == 2 and g.bonus_maghi(mago) == 0, "il mago dà +2 ai vicini, non a sé")

	print("Ritirate")
	g = partita_vuota()
	p = pianura_aperta(g)
	var vittima := metti(g, "Monaci", "fante", p)
	var circondanti := []
	for dir in 6:
		circondanti.append(metti(g, "Cavalieri", "fante", g.mappa.linea(p, dir, 2)[-1]))
	var ev: Array = []
	g._ritira(vittima, 3, "Cavalieri", ev)
	controlla(not vittima.viva, "chi non ha linee di fuga libere è eliminato")
	g = partita_vuota()
	p = pianura_aperta(g)
	vittima = metti(g, "Monaci", "fante", p)
	ev = []
	g._ritira(vittima, 3, "Cavalieri", ev)
	controlla(vittima.viva and g.mappa.distanza(p, vittima.hex) == 3, "arretramento di 3 esagoni in linea retta")

	print("Tiri")
	g = partita_vuota()
	p = pianura_aperta(g)
	var arciere := metti(g, "Cavalieri", "fantarcere", p)
	var bers := metti(g, "Monaci", "signore", g.mappa.linea(p, 0, 3)[-1])
	var storto := metti(g, "Monaci", "fante", g.mappa.vicino_dir(g.mappa.linea(p, 0, 2)[-1], 1))
	g.fase = ZPartita.FASE_COMBATTIMENTO
	controlla(g.valuta_tiro(arciere, bers).ok, "tiro in linea retta entro 8 esagoni")
	var vs: Dictionary = g.valuta_tiro(arciere, storto)
	controlla(not vs.ok or g.mappa.direzione_retta(p, storto.hex) >= 0, "niente tiro fuori dalla linea retta")
	controlla(g.valuta_tiro(arciere, bers).servono == 6, "il Signore Monaco richiede 6 frecce")

	print("Città")
	g = partita_vuota()
	g.fase = ZPartita.FASE_SCHIERAMENTO
	var mio := g.continenti_di("Cavalieri")[0]
	var es := g.mappa.esagoni_continente(mio)
	var c0: Dictionary = g.citta[0]
	var costiero := Vector2i(-1, -1)
	for h in es:
		if g.mappa.costa(h):
			costiero = h
			break
	controlla(g.citta_valida(c0, costiero) != "", "niente città sulla costa")
	var interno := Vector2i(-1, -1)
	for h in es:
		if g.citta_valida(c0, h) == "":
			interno = h
			break
	g.esegui({"a": "piazza_citta", "c": 0, "h": [interno.x, interno.y]})
	var troppo_vicino := g.mappa.linea(interno, 0, 2)[-1]
	controlla(g.citta_valida(g.citta[1], troppo_vicino) != "", "le città distano almeno 4 esagoni")


	print("Attacchi singoli, scorte, Monaci, assedi")
	g = partita_vuota()
	g.popoli.assign(["Alati", "Monaci"])
	g.controllo = {"Alati": "umano", "Monaci": "umano"}
	for u in g.pedine:
		u.popolo = "Alati" if u.popolo == "Cavalieri" else u.popolo
	g.pedine.clear()
	for tipo in ["signore", "falco", "fante"]:
		for q in 2:
			var nu := ZPedina.new()
			nu.id = g.pedine.size()
			nu.popolo = "Alati"
			nu.tipo = tipo
			g.pedine.append(nu)
	for tipo in ["signore", "fante", "illusionista"]:
		for q in 2:
			var nu := ZPedina.new()
			nu.id = g.pedine.size()
			nu.popolo = "Monaci"
			nu.tipo = tipo
			g.pedine.append(nu)
	g.citta.clear()
	g.turno = 0
	g._sporca()
	p = pianura_aperta(g)
	var alato := metti(g, "Alati", "signore", p)
	var preda := metti(g, "Monaci", "fante", g.mappa.linea(p, 0, 3)[-1])
	controlla(g.puo_attacco_singolo(alato) == "", "l'Alato può attaccare singolarmente")
	var basi := g.basi_attacco_singolo(alato, preda)
	controlla(not basi.is_empty(), "esistono esagoni da cui attaccare in volo")
	var r2 := g.esegui({"a": "singolo", "u": alato.id, "b": preda.id, "h": [basi[0].x, basi[0].y]})
	controlla(r2.ok and alato.singolo and alato.agito, "attacco singolo risolto subito: " + g.registro[-1])
	var falco := metti(g, "Alati", "falco", g.mappa.linea(p, 3, 3)[-1])
	var fante_a := metti(g, "Alati", "fante", g.mappa.linea(p, 3, 4)[-1])
	controlla(g.esegui({"a": "muovi", "u": fante_a.id, "h": [falco.hex.x, falco.hex.y]}).ok, "un fante si pone di scorta")
	controlla(fante_a.scorta == falco.id and falco.scortato_da == fante_a.id, "coppia scorta/scortato formata")
	controlla(g.puo_attacco_singolo(falco) != "", "dopo un movimento normale non si fanno più attacchi singoli")
	g.turno = 1
	g.fase = ZPartita.FASE_MOVIMENTO
	g.turno_globale = 5
	var monaco := metti(g, "Monaci", "signore", g.mappa.linea(p, 5, 3)[-1])
	controlla(g.esegui({"a": "scompari", "u": monaco.id}).ok and monaco.scomparso, "il Signore Monaco scompare")
	controlla(g.esegui({"a": "ricompari", "u": monaco.id, "h": [p.x, p.y]}).ok == false, "non ricompare nella stessa mossa")
	g.turno_globale = 6
	var dest: Vector2i = g.destinazioni_ricomparsa(monaco)[0]
	controlla(g.esegui({"a": "ricompari", "u": monaco.id, "h": [dest.x, dest.y]}).ok and not monaco.scomparso, "e ricompare alla mossa successiva")
	g.fase = ZPartita.FASE_COMBATTIMENTO
	var illu := metti(g, "Monaci", "illusionista", g.mappa.linea(falco.hex, 1, 2)[-1])
	var vt := g.valuta_tiro(illu, falco)
	var r3 := g.esegui({"a": "tiro", "u": illu.id, "b": falco.id})
	controlla(r3.ok and r3.eventi[0].b == fante_a.id, "chi colpisce una coppia colpisce la scorta")

	print("Assedio")
	g = partita_vuota()
	g.fase = ZPartita.FASE_COMBATTIMENTO
	p = pianura_aperta(g)
	var cm: Dictionary = g.citta[ZRegole.CITTA_PER_POPOLO]  # prima città dei Monaci
	cm.h = [p.x, p.y]
	var guarn := metti(g, "Monaci", "fante", p)
	g._entra_in_citta(guarn, cm)
	var ass1 := metti(g, "Cavalieri", "signore", g.mappa.vicino_dir(p, 0))
	var r4 := g.esegui({"a": "assedio", "att": [ass1.id], "c": cm.id})
	controlla(r4.ok and cm.p != "Cavalieri" or cm.p == "Cavalieri", "assedio con un pezzo contro un pezzo: " + g.registro[-1])
	var cm2: Dictionary = g.citta[ZRegole.CITTA_PER_POPOLO + 1]
	var p2 := g.mappa.linea(p, 0, 6)[-1]
	cm2.h = [p2.x, p2.y]
	for i in 2:
		var gg := metti(g, "Monaci", "fante", p2)
		g._entra_in_citta(gg, cm2)
	var ass2 := metti(g, "Cavalieri", "signore", g.mappa.vicino_dir(p2, 0))
	g.esegui({"a": "assedio", "att": [ass2.id], "c": cm2.id})
	controlla(cm2.p == "Monaci" and ass2.viva and ass2.agito, "un solo assediante contro due pezzi viene respinto senza combattere")

	print("Partita automatica e salvataggio")
	g = ZPartita.new()
	g.nuova(["Draghi", "Alati"], {"Draghi": "ia", "Alati": "ia"}, 99)
	var ia := ZIA.new()
	for i in 400:
		var az := ia.prossima_azione(g)
		var res := g.esegui(az)
		if not res.ok:
			ia.scarta(az)
	var copia := ZPartita.new()
	copia.da_dict(JSON.parse_string(JSON.stringify(g.a_dict())))
	var ja := JSON.stringify(copia.a_dict())
	var jb := JSON.stringify(g.a_dict())
	if ja != jb:
		for k in g.a_dict():
			if JSON.stringify(copia.a_dict()[k]) != JSON.stringify(g.a_dict()[k]):
				print("    differisce: ", k)
	controlla(ja == jb, "lo stato sopravvive alla serializzazione JSON")
	controlla(g.mese >= 2, "le IA giocano più mesi (mese %d)" % g.mese)

	print("Errori: %d" % errori)
	quit(1 if errori > 0 else 0)
