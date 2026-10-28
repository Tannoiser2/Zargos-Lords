extends SceneTree
## Torneo fra la IA attuale (ZIA) e quella di riferimento (tests/ia/ia_base.gd):
## a ogni partita la nuova guida metà dei popoli, a rotazione dei posti.
## Uso: PARTITE=8 GIOCATORI=4 godot --headless --script res://tests/torneo_ia.gd

func _init() -> void:
	var Base = load("res://tests/ia/ia_base.gd")
	var partite := int(OS.get_environment("PARTITE")) if OS.get_environment("PARTITE") != "" else 6
	var giocatori := int(OS.get_environment("GIOCATORI")) if OS.get_environment("GIOCATORI") != "" else 4
	var zl2 := OS.get_environment("ZL2") != ""
	var seme0 := int(OS.get_environment("SEME")) if OS.get_environment("SEME") != "" else 500
	var tot := {"nuova": 0.0, "base": 0.0, "vittorie_nuova": 0, "vittorie_base": 0, "pareggi": 0}
	for k in partite:
		var g := ZPartita.new()
		var lista: Array = ZRegole.POPOLI_ZL2.duplicate() if zl2 else ZRegole.POPOLI.duplicate()
		var scelti: Array = lista.slice(lista.size() - giocatori) if zl2 else lista.slice(0, giocatori)
		var ctrl := {}
		for p in scelti:
			ctrl[p] = "ia"
		g.nuova(scelti, ctrl, seme0 + k, {"zl2": zl2, "magia": zl2, "passaggi": zl2})
		var chi := {}
		var nuovi := {}
		for i in scelti.size():
			var nuova := (i + k) % 2 == 0
			chi[scelti[i]] = ZIA.new() if nuova else Base.new()
			nuovi[scelti[i]] = nuova
		var n := 0
		var t0 := Time.get_ticks_msec()
		while g.fase != ZPartita.FASE_FINITA and n < 60000:
			n += 1
			var p := g.popolo_di_mano()
			var ia = chi[p]
			var az: Dictionary = ia.prossima_azione(g)
			var r := g.esegui(az)
			if not r.ok:
				ia.scarta(az)
			for pr in g.proposte.duplicate():
				var parti: PackedStringArray = pr.split(">")
				var risposta: bool = ZIA.accetta_alleanza(g, parti[0], parti[1]) if nuovi[parti[1]] else Base.accetta_alleanza(g, parti[0], parti[1])
				g.esegui({"a": "rispondi", "da": parti[0], "a2": parti[1], "si": risposta})
		var righe := []
		var sn := 0.0
		var sb := 0.0
		for p in scelti:
			var c := g.citta_di(p)
			righe.append("%s%s %d/%d" % [p, "*" if nuovi[p] else "", c, g.pedine_di(p).size()])
			if nuovi[p]: sn += c
			else: sb += c
		tot.nuova += sn
		tot.base += sb
		if sn > sb: tot.vittorie_nuova += 1
		elif sb > sn: tot.vittorie_base += 1
		else: tot.pareggi += 1
		var vinc_nuova := false
		for v in g.vincitori:
			if nuovi[v]: vinc_nuova = true
		print("partita %d mese %d (%.0fs): %s  vincitori %s%s" % [k, g.mese, (Time.get_ticks_msec() - t0) / 1000.0, ", ".join(righe), g.vincitori, " [nuova]" if vinc_nuova else ""])
	print("TOTALE città: nuova %.0f, base %.0f; partite vinte nuova %d, base %d, pari %d" % [tot.nuova, tot.base, tot.vittorie_nuova, tot.vittorie_base, tot.pareggi])
	quit()
