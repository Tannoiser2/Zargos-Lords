extends SceneTree
## Partita completa fra quattro IA, eseguita senza grafica: verifica che il
## motore regga 25 mesi senza errori e che lo stato sopravviva alla serializzazione.

func _init() -> void:
	var inizio := Time.get_ticks_msec()
	var giocatori := int(OS.get_environment("GIOCATORI")) if OS.get_environment("GIOCATORI") != "" else 4
	var g := ZPartita.new()
	var lista: Array = ZRegole.POPOLI_ZL2.duplicate() if OS.get_environment("ZL2") != "" else ZRegole.POPOLI.duplicate()
	var scelti: Array = lista.slice(lista.size() - giocatori) if OS.get_environment("ZL2") != "" else lista.slice(0, giocatori)
	var opz := {"zl2": OS.get_environment("ZL2") != "", "magia": OS.get_environment("MAGIA") != "", "passaggi": true, "lampo": OS.get_environment("LAMPO") != ""}
	var ctrl := {}
	for p in scelti:
		ctrl[p] = "ia"
	g.nuova(scelti, ctrl, int(OS.get_environment("SEME")) if OS.get_environment("SEME") != "" else 12345, opz)
	var ia := ZIA.new()
	var azioni := 0
	var rifiuti := 0
	var combattimenti := 0
	var pile_illegali := 0
	var speciali := {}
	while g.fase != ZPartita.FASE_FINITA and azioni < 40000:
		var az := ia.prossima_azione(g)
		var r := g.esegui(az)
		azioni += 1
		if azioni % 100 == 0:
			print("%d %s mese %d %s t=%d" % [azioni, g.fase, g.mese, g.popolo_di_mano(), Time.get_ticks_msec() - inizio])
		if not r.ok:
			rifiuti += 1
			if OS.get_environment("DEBUG") != "":
				print("RIFIUTO ", az, " -> ", r.errore)
			ia.scarta(az)
			if az.get("a") == "fase":
				push_error("Fase rifiutata: " + r.errore)
				break
		else:
			for e in r.eventi:
				if e.t == "combattimento":
					combattimenti += 1
				if e.t in ["magia", "trasforma", "rete", "reti", "ridotta", "recupero"]:
					speciali[e.t] = speciali.get(e.t, 0) + 1
					if e.t == "magia":
						speciali[e.s + ("_ok" if e.ok else "_ko")] = speciali.get(e.s + ("_ok" if e.ok else "_ko"), 0) + 1
		var errore_pila := controlla_pile(g)
		if errore_pila != "":
			push_error("Pila illegale dopo %s: %s" % [str(az), errore_pila])
			pile_illegali += 1
			if pile_illegali > 5:
				break
		# Ogni tanto lo stato viene salvato e ricaricato, come avviene online.
		if azioni % 97 == 0:
			var copia := ZPartita.new()
			copia.da_dict(JSON.parse_string(JSON.stringify(g.a_dict())))
			g = copia
	print("Fase finale: %s, mese %d, azioni %d (rifiutate %d), combattimenti %d, %.1fs" % [g.fase, g.mese, azioni, rifiuti, combattimenti, (Time.get_ticks_msec() - inizio) / 1000.0])
	for p in g.popoli:
		print("  %s: %d città, %d pezzi, punteggio %s" % [p, g.citta_di(p), g.pedine_di(p).size(), str(g.punteggio(p))])
	print("Vincitori: ", g.vincitori, " preparazione ", g.preparazione, " opzioni ", g.opzioni)
	for riga in g.registro.slice(g.registro.size() - 12):
		print("  · ", riga)
	print("Pile illegali: %d" % pile_illegali)
	print("Eventi speciali: ", speciali)
	quit(0 if g.fase == ZPartita.FASE_FINITA and pile_illegali == 0 else 1)

## Un esagono può contenere un solo pezzo, salvo un fante con lo scortato;
## nessun pezzo in campo sta su una città.
func controlla_pile(g: ZPartita) -> String:
	var per_hex := {}
	for u in g.pedine:
		if u.in_campo():
			if not per_hex.has(u.hex):
				per_hex[u.hex] = []
			per_hex[u.hex].append(u)
	for h in per_hex:
		var l: Array = per_hex[h]
		if not g.citta_in(h).is_empty():
			return "pezzo in campo sulla città %s" % str(h)
		if l.size() > 2:
			return "%d pezzi in %s: %s" % [l.size(), str(h), str(l.map(func(x): return "%d %s %s rid=%s" % [x.id, x.popolo, x.tipo, x.ridotta]))]
		if l.size() == 2:
			var a: ZPedina = l[0]
			var b: ZPedina = l[1]
			if not (a.scorta == b.id or b.scorta == a.id) and not (g.zl2() and a.popolo == b.popolo):
				return "due pezzi senza scorta in %s: %s %s / %s %s" % [str(h), a.popolo, a.tipo, b.popolo, b.tipo]
	return ""
