extends SceneTree
## Partita completa fra quattro IA, eseguita senza grafica: verifica che il
## motore regga 25 mesi senza errori e che lo stato sopravviva alla serializzazione.

func _init() -> void:
	var inizio := Time.get_ticks_msec()
	var giocatori := int(OS.get_environment("GIOCATORI")) if OS.get_environment("GIOCATORI") != "" else 4
	var g := ZPartita.new()
	var scelti: Array = ZRegole.POPOLI.slice(0, giocatori)
	var ctrl := {}
	for p in scelti:
		ctrl[p] = "ia"
	g.nuova(scelti, ctrl, 12345)
	var ia := ZIA.new()
	var azioni := 0
	var rifiuti := 0
	var combattimenti := 0
	while g.fase != ZPartita.FASE_FINITA and azioni < 40000:
		var az := ia.prossima_azione(g)
		var r := g.esegui(az)
		azioni += 1
		if azioni % 100 == 0:
			print("%d %s mese %d %s t=%d" % [azioni, g.fase, g.mese, g.popolo_di_mano(), Time.get_ticks_msec() - inizio])
		if not r.ok:
			rifiuti += 1
			ia.scarta(az)
			if az.get("a") == "fase":
				push_error("Fase rifiutata: " + r.errore)
				break
		else:
			for e in r.eventi:
				if e.t == "combattimento":
					combattimenti += 1
		# Ogni tanto lo stato viene salvato e ricaricato, come avviene online.
		if azioni % 97 == 0:
			var copia := ZPartita.new()
			copia.da_dict(JSON.parse_string(JSON.stringify(g.a_dict())))
			g = copia
	print("Fase finale: %s, mese %d, azioni %d (rifiutate %d), combattimenti %d, %.1fs" % [g.fase, g.mese, azioni, rifiuti, combattimenti, (Time.get_ticks_msec() - inizio) / 1000.0])
	for p in g.popoli:
		print("  %s: %d città, %d pezzi" % [p, g.citta_di(p), g.pedine_di(p).size()])
	print("Vincitori: ", g.vincitori)
	for riga in g.registro.slice(g.registro.size() - 12):
		print("  · ", riga)
	quit(0 if g.fase == ZPartita.FASE_FINITA else 1)
