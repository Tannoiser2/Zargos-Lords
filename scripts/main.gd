extends Node
## Regia del gioco: collega il modello delle regole (ZPartita), il tavolo 3D,
## l'interfaccia, l'intelligenza artificiale e la partita online.

const SALVATAGGIO := "user://partita.json"

var partita: ZPartita
var tavolo: ZTavolo
var hud: ZHud
var menu: ZMenu
var ia := ZIA.new()
var online: FirebaseOnline
var in_online := false
var sono_host := false
var posti := {}             # popolo -> uid | "ia"
var _attesa_pubblicazione := false
var impostazioni := ConfigFile.new()
const FILE_IMPOSTAZIONI := "user://impostazioni.cfg"

var sel_id := -1            # pedina selezionata
var citta_sel := -1         # città selezionata
var gruppo: Array[int] = [] # attaccanti scelti nella fase di combattimento
var difensori: Array[int] = []
var citta_bersaglio := -1
var ia_in_corso := false
var magia_scelta := ""      # incantesimo scelto nella fase della magia
var magia_punti := 0        # punti di preparazione da spendere
var magia_h1 := Vector2i(-1, -1)   # prima costa del Ponte di pensiero
var passaggio_id := -1      # pezzo in guarnigione che cerca un passaggio segreto
var _ultimo_turno_visto := -1

func _ready() -> void:
	impostazioni.load(FILE_IMPOSTAZIONI)
	ZTema.grafica = impostazioni.get_value("gioco", "grafica", "nuova")
	ZTavolo.rilievi = impostazioni.get_value("gioco", "rilievi", "si") == "si"
	tavolo = ZTavolo.new()
	add_child(tavolo)
	tavolo.esagono_cliccato.connect(_clic)
	tavolo.esagono_destro.connect(func(_h): _deseleziona())
	tavolo.esagono_sopra.connect(_sopra)
	hud = ZHud.new()
	add_child(hud)
	hud.fase_premuta.connect(_premi_fase)
	hud.menu_premuto.connect(_menu_partita)
	hud.opzione_premuta.connect(_cambia_opzione)
	hud.regole_premute.connect(_mostra_regole)
	hud.griglia_premuta.connect(func(): tavolo.mostra_griglia(not tavolo.griglia_visibile()))
	hud.radice.visible = false
	online = FirebaseOnline.new()
	add_child(online)
	online.online_error.connect(func(m): _messaggio_online(m))
	online.snapshot_received.connect(_ricevi_stato)
	online.stanza_letta.connect(func(d): if d.get("posti") is Dictionary: posti = d.posti)
	_apri_menu()

# ---------------------------------------------------------------------------
# Menu e avvio
# ---------------------------------------------------------------------------

func _apri_menu() -> void:
	if menu:
		menu.queue_free()
	menu = ZMenu.new()
	add_child(menu)
	menu.avvia.connect(_nuova_partita)
	menu.continua.connect(_carica)
	menu.regole.connect(_mostra_regole_menu)
	menu.crea_stanza.connect(_crea_stanza)
	menu.entra_stanza.connect(_entra_stanza)
	menu.grafica_cambiata.connect(func(g): _imposta("grafica", g))
	hud.radice.visible = false

func _nuova_partita(controllo: Dictionary, opzioni := {}) -> void:
	in_online = false
	partita = ZPartita.new()
	partita.nuova(controllo.keys(), controllo, 0, opzioni)
	_avvia_vista()

func _carica() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(SALVATAGGIO))
	if not d is Dictionary:
		return
	in_online = false
	partita = ZPartita.new()
	partita.da_dict(d)
	_avvia_vista()

func _avvia_vista() -> void:
	if menu:
		menu.queue_free()
		menu = null
	ia = ZIA.new()
	for s in tavolo.segnalini.values():
		s.queue_free()
	for s in tavolo.citta.values():
		s.queue_free()
	tavolo.segnalini.clear()
	tavolo.citta.clear()
	hud.radice.visible = true
	_deseleziona()
	tavolo.usa_mappa(impostazioni.get_value("gioco", "mappa", "nuova"))
	_aggiorna_opzioni()
	tavolo.sincronizza(partita, 0.0)
	_inquadra_popolo(partita.popolo_di_mano())
	_aggiorna()

func _salva() -> void:
	if in_online or partita == null:
		return
	var f := FileAccess.open(SALVATAGGIO, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(partita.a_dict()))

func _imposta(chiave: String, valore: String) -> void:
	impostazioni.set_value("gioco", chiave, valore)
	impostazioni.save(FILE_IMPOSTAZIONI)
	if chiave == "mappa":
		tavolo.usa_mappa(valore)
	if chiave == "grafica":
		ZTema.grafica = valore
		if partita and menu == null:
			# Le pedine si ricostruiscono con le nuove facce o miniature.
			for x in tavolo.segnalini.values():
				x.queue_free()
			for x in tavolo.citta.values():
				x.queue_free()
			tavolo.segnalini.clear()
			tavolo.citta.clear()
			tavolo.sincronizza(partita, 0.0)
			_aggiorna()

func _menu_partita() -> void:
	hud.apri_finestra("Torna al menu principale?", "La partita è salvata dopo ogni azione: la ritrovi con «Continua la salvata»." if not in_online else "Lasci la stanza online.", [
		["Resta", Callable()],
		["Torna al menu", func():
			if in_online:
				online.stop_polling()
			_apri_menu()],
	], 440)

## Pulsanti della barra in alto: grafica delle pedine, ruota o riquadro, mappa.
func _cambia_opzione(k: String) -> void:
	match k:
		"grafica":
			_imposta("grafica", {"originale": "nuova", "nuova": "3d", "3d": "originale"}[ZTema.grafica])
		"rilievi":
			ZTavolo.rilievi = not ZTavolo.rilievi
			impostazioni.set_value("gioco", "rilievi", "si" if ZTavolo.rilievi else "no")
			impostazioni.save(FILE_IMPOSTAZIONI)
			if partita:
				tavolo.sincronizza(partita, 0.2)
		"risoluzione":
			_imposta("risoluzione", "riquadro" if impostazioni.get_value("gioco", "risoluzione", "ruota") == "ruota" else "ruota")
		"mappa":
			_imposta("mappa", "nuova" if impostazioni.get_value("gioco", "mappa", "nuova") == "originale" else "originale")
	_aggiorna_opzioni()

func _aggiorna_opzioni() -> void:
	hud.aggiorna_opzioni(ZTema.grafica, impostazioni.get_value("gioco", "risoluzione", "ruota"), impostazioni.get_value("gioco", "mappa", "nuova"))

# ---------------------------------------------------------------------------
# Chi controlla cosa
# ---------------------------------------------------------------------------

func _mio(p: String) -> bool:
	if partita == null or p == "":
		return false
	if in_online:
		return posti.get(p, "") == online.uid
	return partita.controllo.get(p, "") == "umano"

func _ia_locale(p: String) -> bool:
	if partita.controllo.get(p, "") != "ia":
		return false
	return not in_online or sono_host

func _posso_agire() -> bool:
	return partita != null and not ia_in_corso and not presentando and _mio(partita.popolo_di_mano()) and partita.fase != ZPartita.FASE_FINITA

func _process(_delta: float) -> void:
	if partita == null or menu != null:
		return
	if partita.fase == ZPartita.FASE_FINITA:
		return
	if not ia_in_corso and _ia_locale(partita.popolo_di_mano()) and not hud.finestra_aperta():
		_turno_ia()

func _turno_ia() -> void:
	ia_in_corso = true
	_deseleziona()
	_aggiorna()
	var giro := partita.turno_globale
	while partita.fase != ZPartita.FASE_FINITA and _ia_locale(partita.popolo_di_mano()):
		if hud.finestra_aperta():
			await get_tree().create_timer(0.3).timeout
			continue
		var az := ia.prossima_azione(partita)
		var r := _applica(az)
		if not r.ok:
			ia.scarta(az)
			continue
		if presentando:
			await presentazione_finita
		var pausa := 0.12
		for e in r.eventi:
			if e.t in ["combattimento", "tiro"]:
				pausa = 0.4
			elif e.t == "conquista":
				pausa = maxf(pausa, 1.0)
			elif e.t == "turno":
				pausa = maxf(pausa, 0.6)
		if partita.fase == ZPartita.FASE_SCHIERAMENTO:
			pausa = 0.05
		await get_tree().create_timer(pausa).timeout
		if partita.turno_globale != giro and not _ia_locale(partita.popolo_di_mano()):
			break
	ia_in_corso = false
	_aggiorna()

# ---------------------------------------------------------------------------
# Esecuzione delle azioni ed effetti
# ---------------------------------------------------------------------------

func _applica(az: Dictionary) -> Dictionary:
	var r := partita.esegui(az)
	if not r.ok:
		if not ia_in_corso:
			_avviso(r.errore)
		return r
	# Proposte d'alleanza dirette a un popolo guidato dall'IA: risponde subito.
	for k in partita.proposte.duplicate():
		var parti: PackedStringArray = k.split(">")
		if _ia_locale(parti[1]):
			partita.esegui({"a": "rispondi", "da": parti[0], "a2": parti[1], "si": ZIA.accetta_alleanza(partita, parti[0], parti[1])})
	_coda.append_array(r.eventi)
	if not presentando:
		_presenta_coda()
	_controlla_proposte()
	_aggiorna()
	_salva()
	if in_online:
		_pubblica()
	return r

# --- Messa in scena degli eventi ---------------------------------------------------
# Lo stato della partita è già aggiornato quando arrivano gli eventi: il tavolo
# resta fermo finché ogni scontro non è stato mostrato, poi si allinea.

var _coda: Array = []
var presentando := false
signal presentazione_finita

func _presenta_coda() -> void:
	presentando = true
	_aggiorna()
	while not _coda.is_empty():
		var e: Dictionary = _coda.pop_front()
		match e.t:
			"combattimento":
				await _presenta_scontro(e)
			"tiro":
				await _presenta_tiro(e)
			"magia":
				_effetto(e)
				var mm: Dictionary = ZRegole.MAGIE[e.s]
				hud.mostra_carta(load("res://assets/ui/magie/%s.png" % e.s), ("%s RIUSCITA" if e.ok else "%s FALLITA") % String(mm.nome).to_upper(), "%s: dado %d + %d punti = %d (serve %d)." % [ZRegole.Gli(e.p), e.dado, e.punti, e.totale, mm.min])
				await get_tree().create_timer(2.4).timeout
				hud.nascondi_banner()
			"scompare":
				await tavolo.svanisci(int(e.u))
				tavolo.sincronizza(partita, 0.0)
			"ricompare":
				await tavolo.ricompari(int(e.u), Vector2i(int(e.a[0]), int(e.a[1])))
			"muovi", "ritira":
				tavolo.sposta(int(e.u), Vector2i(int(e.a[0]), int(e.a[1])), 0.3 if e.t == "muovi" else 0.4)
				if e.t == "ritira":
					await get_tree().create_timer(0.25).timeout
			"elimina":
				tavolo.elimina(int(e.u))
				await get_tree().create_timer(0.2).timeout
			_:
				_effetto(e)
	tavolo.pulisci_scontro()
	hud.nascondi_banner()
	tavolo.sincronizza(partita)
	presentando = false
	_aggiorna()
	presentazione_finita.emit()

func _testi_tiro(e: Dictionary) -> Array:
	var u := partita.pedine[int(e.u)]
	var b := partita.pedine[int(e.b)]
	if e.tipo == "visione":
		return ["VISIONE: FUGA DI %d" % e.fuga if e.fuga > 0 else "VISIONE SENZA EFFETTO", "%s su %s a %d esagoni." % [u.nome(), b.nome(), e.distanza]]
	var nome: String = {"frecce": "FRECCE", "cavallo": "FRECCE", "dardi": "DARDI"}.get(e.tipo, "VAMPE")
	var titolo := ("%s: BERSAGLIO ELIMINATO" % nome) if e.eliminato else ("%d %s A SEGNO" % [e.colpi, nome])
	var testo := "%s su %s a %d esagoni: %d su %d necessarie." % [u.nome(), b.nome(), e.distanza, e.totale, e.servono]
	if int(e.get("dm", e.dado)) != int(e.dado):
		testo += " Dado %d, modificato a %d." % [e.dado, e.dm]
	return [titolo, testo]

## Frecce, fiamme e visioni: l'animazione sul tavolo, poi (se scelta) la ruota
## originale dei tiri o la metà delle visioni della ruota dei combattimenti.
func _presenta_tiro(e: Dictionary) -> void:
	var u := partita.pedine[int(e.u)]
	var b := partita.pedine[int(e.b)]
	var tabella: String = {"frecce": "frecce", "fiamme": "fiamme", "visione": "visione"}.get(e.tipo, "")
	var con_ruota: bool = tabella != "" and impostazioni.get_value("gioco", "risoluzione", "ruota") == "ruota"
	var verbi := {"frecce": "TIRANO FRECCE", "cavallo": "TIRANO FRECCE", "dardi": "LANCIANO DARDI", "fiamme": "LANCIANO FIAMME", "visione": "LANCIANO UNA VISIONE"}
	var sotto := "distanza %d" % int(e.distanza)
	var bers := "fuga fino a %d" % b.m() if e.tipo == "visione" else "colpi %d/%d" % [int(e.totale) - int(e.colpi), int(e.servono)]
	hud.mostra_banner(u.popolo, [ZTema.texture_pedina(u.popolo, u.tipo)], 0, b.popolo, [ZTema.texture_pedina(b.popolo, b.tipo)], 0, verbi.get(e.tipo, "TIRANO"), sotto, bers)
	_inquadra_azione([u.hex, b.hex], con_ruota)
	await get_tree().create_timer(0.5).timeout
	await tavolo.lancia(u.hex, b.hex, e.tipo, u.id, b.id)
	var tt := _testi_tiro(e)
	if con_ruota:
		await hud.mostra_ruota(int(e.get("dm", e.dado)), int(e.distanza) - 1, tt[0], tt[1], "", tabella, func(): hud.esito_banner(tt[0], tt[1]))
	else:
		hud.mostra_dado(int(e.dado), tt[0], tt[1])
		hud.esito_banner(tt[0], tt[1])
		await get_tree().create_timer(1.4).timeout
	hud.nascondi_banner()

## Scontro ben visibile: frecce sul tavolo, fascia con i due schieramenti,
## poi la ruota originale (o il riquadro, a scelta) con l'esito.
func _presenta_scontro(e: Dictionary) -> void:
	var ha: Array[Vector2i] = []
	for x in e.get("ha", []):
		ha.append(Vector2i(int(x[0]), int(x[1])))
	var hd: Array[Vector2i] = []
	for x in e.get("hd", []):
		hd.append(Vector2i(int(x[0]), int(x[1])))
	var pa: String = e.get("pa", partita.pedine[int(e.att[0])].popolo)
	var pd: String = e.get("pd", "")
	var citta := e.has("citta")
	var coinvolge_umano := _umano_locale(pa) or _umano_locale(pd)
	tavolo.mostra_scontro(ha, hd, ZRegole.COLORI.get(pa, ZTema.OCRA), Color(0.95, 0.15, 0.1))
	var con_ruota: bool = int(e.dado) > 0 and impostazioni.get_value("gioco", "risoluzione", "ruota") == "ruota"
	_inquadra_azione(ha + hd, con_ruota)
	var t_att: Array = []
	for id in e.att:
		var u := partita.pedine[int(id)]
		t_att.append(ZTema.texture_pedina(u.popolo, u.tipo))
	var t_dif: Array = []
	if citta:
		t_dif.append(ZTema.texture_pedina(pd, "citta"))
	else:
		for id in e.dif:
			var u := partita.pedine[int(id)]
			t_dif.append(ZTema.texture_pedina(u.popolo, u.tipo))
	var verbo := "ASSEDIANO" if citta else ("ATTACCO SINGOLO" if e.get("singolo", false) else "ATTACCANO")
	hud.mostra_banner(pa, t_att, int(e.fa), pd, t_dif, int(e.fd) if not citta or int(e.dado) > 0 else -1, verbo)
	var titolo := _frase_esito(e.esito, citta).to_upper()
	var testo := "%d contro %d: differenza %+d, dado %d." % [e.fa, e.fd, e.diff, e.dado]
	# Chi doveva arretrare ma non aveva via di fuga viene eliminato.
	var morti := 0
	for x in _coda:
		if x.t == "elimina" and (int(x.u) in e.dif.map(func(v): return int(v)) or int(x.u) in e.att.map(func(v): return int(v))):
			morti += 1
	if morti > 0 and not e.esito.ends_with("E") and not citta:
		testo += " Senza via di fuga: %d %s." % [morti, "pezzo eliminato" if morti == 1 else "pezzi eliminati"]
		titolo = "%s: NESSUNA VIA DI FUGA" % ("DIFENSORE ELIMINATO" if e.esito.begins_with("D") else "ATTACCANTI ELIMINATI")
	if int(e.dado) == 0:
		titolo = "ASSEDIANTI TROPPO DEBOLI"
		testo = "La guarnigione vale %d: con %d gli assedianti sono eliminati." % [e.fd, e.fa]
	await get_tree().create_timer(0.9 if coinvolge_umano else 0.5).timeout
	if con_ruota:
		var fascia := ZRegole.fascia(int(e.diff))
		await hud.mostra_ruota(int(e.dado), fascia, titolo, testo, "", "combattimento", func(): hud.esito_banner(titolo, testo))
	else:
		hud.mostra_dado(int(e.dado), titolo, testo, int(e.diff) if int(e.dado) > 0 else -999)
		hud.esito_banner(titolo, testo)
		await get_tree().create_timer(1.6 if coinvolge_umano else 0.9).timeout
	tavolo.pulisci_scontro()
	hud.nascondi_banner()

## Porta la telecamera sui pezzi coinvolti in uno scontro o in un tiro, abbastanza
## vicina da riconoscerli. Con la ruota (che sale in basso a destra) l'azione
## viene spostata in alto a sinistra perché resti visibile.
func _inquadra_azione(esagoni: Array, con_ruota: bool) -> void:
	if esagoni.is_empty():
		return
	var centro := Vector3.ZERO
	for h: Vector2i in esagoni:
		centro += tavolo.mondo(h)
	centro /= esagoni.size()
	var ampiezza := 0.0
	for h: Vector2i in esagoni:
		ampiezza = maxf(ampiezza, centro.distance_to(tavolo.mondo(h)))
	var dist := clampf(2.0 + ampiezza * 2.4, 2.2, 5.0)
	var punto := centro
	if con_ruota:
		var destra := tavolo.camera.global_transform.basis.x
		destra.y = 0
		destra = destra.normalized()
		var avanti := Vector3(destra.z, 0, -destra.x)
		punto += destra * dist * 0.2 - avanti * dist * 0.1
	tavolo.inquadra(punto, dist)

func _umano_locale(p: String) -> bool:
	if p == "" or partita == null:
		return false
	return _mio(p) or (not in_online and partita.controllo.get(p, "") == "umano")

func _frase_esito(e: String, citta := false) -> String:
	if e == "AE":
		return "Attaccanti eliminati"
	if e == "DE":
		return "Guarnigione eliminata: città conquistata" if citta else "Difensore eliminato"
	if e.begins_with("A"):
		return "Gli attaccanti arretrano di %s" % e.right(1)
	if e.begins_with("D"):
		return "La guarnigione non può arretrare: città conquistata" if citta else "Il difensore arretra di %s" % e.right(1)
	return e

func _effetto(e: Dictionary) -> void:
	match e.t:
		"combattimento_vecchio":
			var dif_hex: Vector2i = partita.pedine[int(e.dif[0])].hex if not e.has("citta") else partita.hex_citta(partita.citta[int(e.citta)])
			tavolo.lampo(dif_hex, Color(1, 0.4, 0.3))
			var att: ZPedina = partita.pedine[int(e.att[0])]
			var titolo := _frase_esito(e.esito, e.has("citta")).to_upper()
			var testo := "%s: attacco %d contro difesa %d, differenza %+d." % ["Assedio " + ZRegole.degli(att.popolo) if e.has("citta") else ("Attacco singolo " if e.get("singolo", false) else "Scontro: ") + ZRegole.gli(att.popolo), e.fa, e.fd, e.diff]
			if int(e.dado) == 0:
				titolo = "ASSEDIANTI TROPPO DEBOLI"
				testo = "La guarnigione vale %d: con %d gli assedianti sono eliminati." % [e.fd, e.fa]
			hud.mostra_dado(int(e.dado), titolo, testo, int(e.diff) if int(e.dado) > 0 else -999)
		"tiro":
			var u := partita.pedine[int(e.u)]
			var b := partita.pedine[int(e.b)]
			tavolo.lancia(u.hex, b.hex, e.tipo, u.id, b.id)
			var tt := _testi_tiro(e)
			hud.mostra_dado(int(e.dado), tt[0], tt[1])
		"conquista":
			var h := Vector2i(int(e.h[0]), int(e.h[1])) if e.has("h") else partita.hex_citta(partita.citta[int(e.c)])
			tavolo.lampo(h, ZTema.OCRA)
			if e.get("rasa", false):
				hud.mostra_dado(0, "CITTÀ RASA AL SUOLO", "%s distruggono una città %s." % [ZRegole.Gli(e.p), ZRegole.degli(e.da)])
			else:
				hud.mostra_dado(0, "CITTÀ CONQUISTATA", "%s strappano una città %s." % [ZRegole.Gli(e.p), ZRegole.degli(e.da)])
		"magia":
			var m: Dictionary = ZRegole.MAGIE[e.s]
			tavolo.lampo(Vector2i(int(e.h[0]), int(e.h[1])), Color(0.7, 0.5, 1.0) if m.scuola == "nera" else Color(1, 1, 0.8))
			hud.mostra_dado(int(e.dado), ("%s RIUSCITA" if e.ok else "%s FALLITA") % String(m.nome).to_upper(), "%s: dado %d + %d punti di preparazione = %d (serve %d)." % [ZRegole.Gli(e.p), e.dado, e.punti, e.totale, m.min])
		"trasforma":
			var w := partita.pedine[int(e.u)]
			tavolo.lampo(w.hex, Color(0.95, 0.6, 0.2))
			if e.has("dado"):
				hud.mostra_dado(int(e.dado), "TRASFORMAZIONE RIUSCITA" if e.ok else "TRASFORMAZIONE FALLITA", "Il fante amazzone diventa Pantera con un numero pari." if e.ok else "Serviva un numero pari.")
		"rete":
			var w := partita.pedine[int(e.u)]
			tavolo.lampo(w.hex, Color(0.9, 0.9, 0.85))
			var esiti := {"": "LA RETE MANCA IL BERSAGLIO", "C": "NEMICO CATTURATO NELLA RETE", "E": "NEMICO STRANGOLATO NELLA RETE"}
			hud.mostra_dado(int(e.dado), esiti.get(e.esito, "RETE"), "Il Reziario lancia la rete prima dello scontro: 4-5 cattura (se deve arretrare è eliminato), 6 elimina.")
		"ridotta":
			tavolo.lampo(partita.pedine[int(e.u)].hex, Color(0.6, 0.6, 0.6))
		"recupero":
			tavolo.lampo(partita.pedine[int(e.u)].hex, Color(0.5, 1.0, 0.5))
		"evoca":
			tavolo.lampo(partita.pedine[int(e.u)].hex, Color(1.0, 0.3, 0.1))
			tavolo.sincronizza(partita)
		"passaggio":
			tavolo.lampo(Vector2i(int(e.a[0]), int(e.a[1])), Color(0.85, 0.75, 0.5))
		"reti", "ponti":
			tavolo.sincronizza(partita)
		"assedio_respinto":
			hud.mostra_dado(0, "GUARNIGIONE DI %d PEZZI" % e.n, "Per attaccare la città servono almeno altrettanti assedianti.")
		"gorgo":
			tavolo.lampo(partita.pedine[int(e.u)].hex, Color(0.8, 0.3, 1.0))
		"scompare", "ricompare":
			tavolo.lampo(partita.pedine[int(e.u)].hex, Color(0.95, 0.8, 0.3))
		"turno":
			_deseleziona(false)
			if _mio(e.p):
				_inquadra_popolo(e.p)
				var titoli := ["FASE DEL POTERE", "FASE DI MOVIMENTO", "FASE DI COMBATTIMENTO"]
				if e.has("blocco"):
					hud.mostra_dado(0, "%s %s" % [titoli[int(e.blocco)], ZRegole.degli(e.p).to_upper()], "Mese %d dell'Anno di Zargo, ordine d'iniziativa: %s. Tocca a te." % [int(e.mese), ", ".join(partita.ordine)])
				else:
					hud.mostra_dado(0, "MOSSA %s" % ZRegole.degli(e.p).to_upper(), "Mese %d dell'Anno di Zargo. Tocca a te." % int(e.mese))
		"fine":
			_fine_partita()

func _inquadra_popolo(p: String) -> void:
	var lista: Array[Vector2i] = []
	for u in partita.pedine:
		if u.popolo == p and u.viva and u.schierata:
			lista.append(u.hex)
	if lista.is_empty():
		for i in partita.continenti_di(p):
			lista.append_array(partita.mappa.esagoni_continente(i))
	tavolo.inquadra_esagoni(lista)

func _fine_partita() -> void:
	var righe := ""
	var ordine := partita.popoli.duplicate()
	ordine.sort_custom(func(a, b): return partita.citta_di(a) > partita.citta_di(b))
	for p in ordine:
		righe += "%s  [b]%s[/b]: %d città, %d pezzi\n" % [ZTema.bb_ritratto(p, 40), p, partita.citta_di(p), partita.pedine_di(p).size()]
	var titolo := "Vincono %s" % " e ".join(partita.vincitori.map(func(p): return ZRegole.gli(p)))
	hud.apri_finestra(titolo, "L'Anno di Zargo è giunto al termine.\n\n" + righe, [["Guarda il tavolo", Callable()], ["Nuova partita", _apri_menu]])

func _avviso(testo: String) -> void:
	hud.suggerimento.text = testo
	hud.suggerimento.add_theme_color_override("font_color", ZTema.ROSSO)
	var t := get_tree().create_timer(2.5)
	t.timeout.connect(func():
		hud.suggerimento.remove_theme_color_override("font_color")
		_aggiorna_suggerimento())

# ---------------------------------------------------------------------------
# Input sul tavolo
# ---------------------------------------------------------------------------

func _unhandled_key_input(ev: InputEvent) -> void:
	if not ev is InputEventKey or not ev.pressed or partita == null or menu != null:
		return
	match (ev as InputEventKey).keycode:
		KEY_ESCAPE:
			_deseleziona()
		KEY_G:
			tavolo.mostra_griglia(not tavolo.griglia_visibile())
		KEY_ENTER, KEY_KP_ENTER:
			_premi_fase()

func _deseleziona(aggiorna := true) -> void:
	sel_id = -1
	citta_sel = -1
	gruppo.clear()
	difensori.clear()
	citta_bersaglio = -1
	magia_h1 = Vector2i(-1, -1)
	magia_scelta = ""
	passaggio_id = -1
	if aggiorna and partita:
		_aggiorna()

func _sopra(h: Vector2i) -> void:
	if partita == null or h.x < 0:
		return
	var t: String = ZMappa.NOMI_TERRENO[partita.terreno(h)]
	var u := partita.pedina_in(h)
	var info: String = t
	var bonus := partita.bonus_terreno_hex(h)
	if bonus > 0:
		info += " (+%d in difesa)" % bonus
	if partita.terreno(h) == ZMappa.T.BOSCO:
		info += " · costa 2 punti"
	if partita.ha_rete(h):
		info += " · rete di ragno"
	var ci := partita.citta_in(h)
	if not ci.is_empty():
		info += " · città %s, guarnigione di %d pezzi" % [ZRegole.degli(ci.p), ci.g.size()]
	if u:
		info += " · %s %s (%d/%d)" % [u.nome(), ZRegole.degli(u.popolo), u.c(), u.m()]
	var cont := partita.mappa.continente(h)
	if cont >= 0:
		info += " · continente " + partita.mappa.nomi_continenti[cont]
	hud.attesa.text = info if not ia_in_corso else hud.attesa.text

func _clic(h: Vector2i, shift: bool) -> void:
	if partita == null or hud.finestra_aperta():
		return
	var u := partita.pedina_in(h)
	var ci := partita.citta_in(h)
	var p := partita.popolo_di_mano()
	if not _posso_agire():
		# Fuori turno si possono soltanto ispezionare i pezzi.
		sel_id = u.id if u else -1
		citta_sel = int(ci.id) if not ci.is_empty() and u == null else -1
		_aggiorna()
		return
	match partita.fase:
		ZPartita.FASE_SCHIERAMENTO:
			_clic_schieramento(h, u, ci)
		ZPartita.FASE_ALLEANZE:
			sel_id = u.id if u else -1
			citta_sel = int(ci.id) if not ci.is_empty() and u == null else -1
			_aggiorna()
		ZPartita.FASE_MAGIA:
			_clic_magia(h, u, ci)
		ZPartita.FASE_SINGOLI, ZPartita.FASE_MOVIMENTO:
			_clic_movimento(h, u, ci, shift)
		ZPartita.FASE_LANCI:
			_clic_lanci(h, u, ci)
		ZPartita.FASE_COMBATTIMENTO:
			_clic_combattimento(h, u, ci, shift)

## Fase dei lanci: si sceglie un tiratore, poi il bersaglio.
func _clic_lanci(h: Vector2i, u: ZPedina, ci: Dictionary) -> void:
	var p := partita.popolo_di_mano()
	if u and u.popolo == p:
		sel_id = u.id
		citta_sel = -1
		_aggiorna()
		return
	if u and partita.nemici(u.popolo, p) and sel_id >= 0:
		var s := partita.pedine[sel_id]
		if partita.tipo_tiro(s) == "":
			_avviso("%s non lancia frecce, fiamme o visioni." % s.nome())
			return
		var v := partita.valuta_tiro(s, u)
		if v.ok:
			_applica({"a": "tiro", "u": s.id, "b": u.id})
			sel_id = -1
			_aggiorna()
		else:
			_avviso("%s: %s" % [s.nome(), v.errore])
		return
	sel_id = u.id if u else -1
	citta_sel = int(ci.id) if not ci.is_empty() and u == null else -1
	_aggiorna()

func _clic_schieramento(h: Vector2i, u: ZPedina, ci: Dictionary) -> void:
	var p := partita.popolo_di_mano()
	if citta_sel >= 0 and partita.citta[citta_sel].p == p and (partita.citta[citta_sel].h[0] < 0 or ci.is_empty()):
		if ci.is_empty() and u == null:
			if _applica({"a": "piazza_citta", "c": citta_sel, "h": [h.x, h.y]}).ok:
				citta_sel = _prossima_citta_da_piazzare()
				_aggiorna()
			return
	if sel_id >= 0 and partita.pedine[sel_id].popolo == p and u == null:
		if _applica({"a": "piazza", "u": sel_id, "h": [h.x, h.y]}).ok:
			var tipo := partita.pedine[sel_id].tipo
			sel_id = _prossima_da_schierare(tipo)
			_aggiorna()
		return
	if u and u.popolo == p:
		sel_id = u.id
		citta_sel = -1
	elif not ci.is_empty() and ci.p == p:
		citta_sel = int(ci.id)
		sel_id = -1
	_aggiorna()

func _prossima_da_schierare(tipo: String) -> int:
	for u in partita.pedine:
		if u.popolo == partita.popolo_di_mano() and not u.schierata and u.tipo == tipo:
			return u.id
	for u in partita.pedine:
		if u.popolo == partita.popolo_di_mano() and not u.schierata:
			return u.id
	return -1

func _prossima_citta_da_piazzare() -> int:
	for ci in partita.citta:
		if ci.p == partita.popolo_di_mano() and ci.h[0] < 0:
			return int(ci.id)
	return -1

## Fase della magia: dopo aver scelto l'incantesimo si clicca il bersaglio
## (due coste per il Ponte di pensiero).
func _clic_magia(h: Vector2i, u: ZPedina, ci: Dictionary) -> void:
	if magia_scelta == "" or partita.magia_fatta:
		sel_id = u.id if u else -1
		citta_sel = int(ci.id) if not ci.is_empty() and u == null else -1
		_aggiorna()
		return
	if magia_scelta == "ponte" and magia_h1.x < 0:
		if partita.mappa.terra(h) and partita.mappa.costa(h) and partita.entro_raggio_magia(partita.popolo_di_mano(), h):
			magia_h1 = h
			_aggiorna()
		else:
			_avviso("Scegli una costa entro 10 esagoni da un tuo incantatore (Signore, Mago o Illusionista).")
		return
	var az := {"a": "magia", "s": magia_scelta, "h": [h.x, h.y], "punti": magia_punti}
	if magia_scelta == "ponte":
		az = {"a": "magia", "s": "ponte", "h": [magia_h1.x, magia_h1.y], "h2": [h.x, h.y], "punti": magia_punti}
	var e := partita.valuta_magia(String(az.s), Vector2i(int(az.h[0]), int(az.h[1])), az.get("h2", null))
	if e != "":
		_avviso(e)
		if magia_scelta == "ponte":
			magia_h1 = Vector2i(-1, -1)
			_aggiorna()
		return
	_applica(az)
	magia_scelta = ""
	magia_punti = 0
	magia_h1 = Vector2i(-1, -1)
	_aggiorna()

func _clic_movimento(h: Vector2i, u: ZPedina, ci: Dictionary, shift := false) -> void:
	var p := partita.popolo_di_mano()
	if passaggio_id >= 0:
		var w := partita.pedine[passaggio_id]
		passaggio_id = -1
		if not ci.is_empty() and ci.p == p and int(ci.id) != w.citta:
			_applica({"a": "passaggio", "u": w.id, "c": int(ci.id)})
			sel_id = -1
			citta_sel = int(ci.id)
		_aggiorna()
		return
	var s: ZPedina = partita.pedine[sel_id] if sel_id >= 0 else null
	if s and s.popolo == p:
		# Monaco scomparso: ricompare nell'esagono scelto.
		if s.scomparso:
			if h in partita.destinazioni_ricomparsa(s):
				_applica({"a": "ricompari", "u": s.id, "h": [h.x, h.y]})
			return
		# Attacco singolo o fiamme del Drago su un nemico.
		if u and partita.nemici(u.popolo, p):
			var basi := partita.basi_attacco_singolo(s, u)
			if not basi.is_empty():
				_applica({"a": "singolo", "u": s.id, "b": u.id, "h": _base_migliore(basi)})
				return
			if partita.tipo_tiro(s) == "fiamme" and partita.valuta_tiro(s, u).ok:
				_applica({"a": "tiro", "u": s.id, "b": u.id})
				return
		var rag := partita.raggiungibili(s)
		if rag.has(h) and (u == null or (u.popolo == p and shift)) and partita.puo_muovere(s) == "":
			_applica({"a": "muovi", "u": s.id, "h": [h.x, h.y]})
			if partita.pedine[s.id].residuo <= 0:
				sel_id = -1
				if partita.pedine[s.id].citta >= 0:
					citta_sel = -1
			_aggiorna()
			return
	if u:
		sel_id = u.id
		citta_sel = -1
	elif not ci.is_empty():
		citta_sel = int(ci.id)
		sel_id = -1
	else:
		sel_id = -1
		citta_sel = -1
	_aggiorna()

func _base_migliore(basi: Array[Vector2i]) -> Array:
	var b := basi[0]
	for h in basi:
		if partita.bonus_terreno_hex(h) > partita.bonus_terreno_hex(b):
			b = h
	return [b.x, b.y]

func _clic_combattimento(h: Vector2i, u: ZPedina, ci: Dictionary, shift: bool) -> void:
	var p := partita.popolo_di_mano()
	if u and u.popolo == p:
		# Selezione degli attaccanti: un clic aggiunge o toglie dal gruppo.
		var perche := partita.puo_attaccare(u)
		if perche != "" and u.id not in gruppo:
			_avviso("%s: %s" % [u.nome(), perche])
			return
		if u.id in gruppo:
			gruppo.erase(u.id)
			if sel_id == u.id:
				sel_id = gruppo[-1] if not gruppo.is_empty() else -1
		else:
			gruppo.append(u.id)
			sel_id = u.id
		_aggiorna()
		return
	if u and partita.nemici(u.popolo, p):
		citta_bersaglio = -1
		if false:
			var s := partita.pedine[gruppo[0]]
			var tipo := partita.tipo_tiro(s)
			var solo_tiro := tipo != "" and partita.puo_attaccare(s) != "" and not s.agito
			if tipo != "" and partita.valuta_tiro(s, u).ok and (tipo == "frecce" or s.tipo == "lanciafiamme"):
				_applica({"a": "tiro", "u": s.id, "b": u.id})
				gruppo.clear()
				sel_id = -1
				_aggiorna()
				return
			if solo_tiro:
				# Fantarcieri e Lanciafiamme non combattono in attacco: si spiega
				# perché il tiro non è possibile invece di aprire uno scontro.
				var v := partita.valuta_tiro(s, u)
				_avviso("%s: %s" % [s.nome(), v.errore])
				return
		if shift and gruppo.size() == 1:
			if u.id in difensori:
				difensori.erase(u.id)
			else:
				difensori.append(u.id)
		else:
			difensori = [u.id]
		if gruppo.is_empty():
			gruppo = _attaccanti_adiacenti(u.hex)
		_aggiorna()
		return
	if not ci.is_empty() and partita.nemici(ci.p, p):
		difensori.clear()
		citta_bersaglio = int(ci.id)
		if gruppo.is_empty():
			gruppo = _attaccanti_adiacenti(h)
		_aggiorna()
		return
	if not ci.is_empty():
		citta_sel = int(ci.id)
		sel_id = -1
	_aggiorna()

func _attaccanti_adiacenti(h: Vector2i) -> Array[int]:
	var out: Array[int] = []
	for v in partita.mappa.vicino_geometrico_tutti(h):
		for w in partita.pedine_in(v):
			if w.popolo == partita.popolo_di_mano() and partita.puo_attaccare(w) == "":
				out.append(w.id)
		var ci := partita.citta_in(v)
		if not ci.is_empty() and ci.p == partita.popolo_di_mano():
			for id in ci.g:
				if partita.puo_attaccare(partita.pedine[id]) == "":
					out.append(id)
	return out

func _premi_fase() -> void:
	if not _posso_agire() or hud.finestra_aperta():
		return
	if partita.fase == ZPartita.FASE_SCHIERAMENTO:
		var mancano := 0
		for u in partita.pedine:
			if u.popolo == partita.popolo_di_mano() and not u.schierata:
				mancano += 1
		if mancano > 0:
			hud.apri_finestra("Confermare lo schieramento?", "Restano %d pezzi da schierare: verranno collocati automaticamente." % mancano, [["Annulla", Callable()], ["Conferma", func(): _fase_confermata()]], 460)
			return
	_fase_confermata()

func _fase_confermata() -> void:
	_deseleziona(false)
	_applica({"a": "fase"})

# ---------------------------------------------------------------------------
# Alleanze
# ---------------------------------------------------------------------------

var _proposte_mostrate := {}

func _controlla_proposte() -> void:
	for k in partita.proposte:
		var parti: PackedStringArray = k.split(">")
		if _mio(parti[1]) and not _proposte_mostrate.has(k):
			_proposte_mostrate[k] = true
			var da := parti[0]
			var a := parti[1]
			hud.apri_finestra("Proposta d'alleanza", ZTema.bb_ritratto(da, 56) + "  " + ZTema.bb_ritratto(a, 56) + "\n\n%s propongono un'alleanza %s.\n\nGli alleati non si attaccano e possono attraversare le rispettive linee. L'alleanza però non è mai vincolante: chiunque può tradirla prima della propria mossa." % [ZRegole.Gli(da), ZRegole.agli(a)], [
				["Rifiuta", func(): _applica({"a": "rispondi", "da": da, "a2": a, "si": false})],
				["Accetta", func(): _applica({"a": "rispondi", "da": da, "a2": a, "si": true})],
			], 480)
			return

# ---------------------------------------------------------------------------
# Interfaccia
# ---------------------------------------------------------------------------

func _aggiorna() -> void:
	if partita == null:
		return
	var p := partita.popolo_di_mano()
	hud.calendario.imposta(partita.mese)
	hud.lbl_mese.text = "IL CALENDARIO · MESE %d DI 25" % partita.mese
	hud.imposta_ritratto_turno(p)
	var chi := ""
	if partita.fase != ZPartita.FASE_FINITA:
		chi = "tocca a te" if _mio(p) else ("intelligenza artificiale" if partita.controllo.get(p) == "ia" else "giocatore remoto" if in_online else "")
	match partita.fase:
		ZPartita.FASE_SCHIERAMENTO:
			hud.lbl_turno.text = "SCHIERAMENTO %s" % ZRegole.degli(p).to_upper()
			hud.lbl_fase.text = "PREPARAZIONE · " + chi.to_upper()
		ZPartita.FASE_FINITA:
			hud.lbl_turno.text = "FINE DELL'ANNO DI ZARGO"
			hud.lbl_fase.text = ""
		_:
			hud.lbl_turno.text = "MOSSA %s" % ZRegole.degli(p).to_upper()
			if partita.alternato():
				hud.lbl_turno.text = "%s %s" % [["POTERE", "MOVIMENTO", "COMBATTIMENTO"][clampi(partita.blocco, 0, 2)], ZRegole.degli(p).to_upper()]
			var nomi := {"alleanze": "ALLEANZE", "magia": "MAGIA", "singoli": "ATTACCHI SINGOLI", "movimento": "MOVIMENTO", "lanci": "LANCI", "combattimento": "CORPO A CORPO"}
			var ordine := ["alleanze", "magia", "singoli", "movimento", "lanci", "combattimento"]
			if not partita.opzione("magia"):
				ordine.erase("magia")
			hud.lbl_fase.text = "%d · %s · %s" % [ordine.find(partita.fase) + 1, nomi.get(partita.fase, ""), chi.to_upper()]
	match partita.fase:
		ZPartita.FASE_SCHIERAMENTO: hud.btn_fase.text = "CONFERMA SCHIERAMENTO"
		ZPartita.FASE_ALLEANZE: hud.btn_fase.text = "AVANTI  ›"
		ZPartita.FASE_MAGIA: hud.btn_fase.text = "AGLI ATTACCHI SINGOLI  ›"
		ZPartita.FASE_SINGOLI: hud.btn_fase.text = "AL MOVIMENTO  ›"
		ZPartita.FASE_MOVIMENTO: hud.btn_fase.text = "AI LANCI  ›"
		ZPartita.FASE_LANCI: hud.btn_fase.text = "AL CORPO A CORPO  ›"
		ZPartita.FASE_COMBATTIMENTO: hud.btn_fase.text = "FINE DELLA MOSSA  ›"
		_: hud.btn_fase.text = "PARTITA FINITA"
	hud.btn_fase.disabled = not _posso_agire()
	hud.attesa.text = ("%s pensano…" % ZRegole.Gli(p)) if ia_in_corso else ""
	# Durante la messa in scena cronaca e conteggi restano quelli di prima:
	# l'esito si scopre con la ruota, non leggendolo in anticipo.
	if not presentando:
		_aggiorna_popoli()
	_aggiorna_selezione()
	_aggiorna_vassoio()
	_aggiorna_evidenziazioni()
	_aggiorna_suggerimento()
	if not presentando:
		hud.scrivi_cronaca(partita.registro.slice(maxi(0, partita.registro.size() - 80)))

func _aggiorna_popoli() -> void:
	for c in hud.box_popoli.get_children():
		c.queue_free()
	var elenco: Array = partita.ordine if partita.alternato() else partita.popoli
	for p: String in elenco:
		var attivo := p == partita.popolo_di_mano()
		var riga := HBoxContainer.new()
		riga.add_theme_constant_override("separation", 8)
		# Ritratto del Signore, con il colore del popolo sotto.
		riga.add_child(ZTema.ritratto(p, 40, attivo))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sopra := HBoxContainer.new()
		sopra.add_child(ZTema.etichetta(p, 16, ZTema.INCHIOSTRO, ZTema.testo_forte if attivo else ZTema.testo))
		var ctrl: String = partita.controllo.get(p, "")
		var etichetta := "IA" if ctrl == "ia" else ("tu" if _mio(p) else ("remoto" if in_online else "giocatore"))
		var et := ZTema.etichetta(etichetta, 12, Color(ZTema.INCHIOSTRO, 0.55))
		et.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sopra.add_child(et)
		var testo_p := "%d città · %d pezzi" % [partita.citta_di(p), partita.pedine_di(p).size()]
		if partita.opzione("lampo"):
			testo_p = "%s punti · %d città" % [ZPartita.numero(partita.punteggio(p)), partita.citta_di(p)]
		sopra.add_child(ZTema.etichetta(testo_p, 13, ZTema.INCHIOSTRO, ZTema.testo_forte if attivo else ZTema.testo))
		v.add_child(sopra)
		var note: PackedStringArray = []
		var alleati: PackedStringArray = []
		for q in partita.popoli:
			if q != p and partita.alleati(p, q):
				alleati.append(q)
		if not alleati.is_empty():
			note.append("[color=#5a7a2a]alleati: %s[/color]" % ", ".join(alleati))
		if partita.opzione("magia"):
			note.append("[color=#6a3fa0]magia %d[/color]" % int(partita.preparazione.get(p, 0)))
		if not note.is_empty():
			var rt := RichTextLabel.new()
			rt.bbcode_enabled = true
			rt.fit_content = true
			rt.scroll_active = false
			rt.add_theme_font_size_override("normal_font_size", 12)
			rt.add_theme_font_override("normal_font", ZTema.testo_forte)
			rt.text = " · ".join(note)
			v.add_child(rt)
		riga.add_child(v)
		hud.box_popoli.add_child(riga)

func _scheda_pedina(u: ZPedina) -> Control:
	var h := HBoxContainer.new()
	var img := TextureRect.new()
	img.texture = ZTema.texture_pedina(u.popolo, u.tipo)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.custom_minimum_size = Vector2(84, 84)
	h.add_child(img)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(ZTema.titoletto(u.nome(), 20, ZRegole.COLORI[u.popolo].darkened(0.5)))
	var valori := ZTema.etichetta("%s · combattimento %d · movimento %d" % [u.popolo, partita.valore(u), u.m()], 13, ZTema.INCHIOSTRO, ZTema.testo_forte)
	valori.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(valori)
	var d: String = ZRegole.DESCRIZIONI.get("%s/%s" % [u.popolo, u.tipo], "")
	if d != "":
		var l := ZTema.etichetta(d, 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	var tipo_t := partita.tipo_tiro(u)
	if tipo_t != "" and u.popolo == partita.popolo_di_mano() and _posso_agire() and not u.agito:
		var guida := ""
		var possibile := partita.fase == ZPartita.FASE_LANCI or (partita.fase == ZPartita.FASE_SINGOLI and u.popolo == "Draghi" and u.tipo == "signore" and not u.mosso)
		if possibile:
			var n := 0
			for b in partita.pedine:
				if partita.attaccabile(b) and partita.nemici(b.popolo, u.popolo) and partita.mappa.distanza(u.hex, b.hex) <= partita.gittata(u) and partita.valuta_tiro(u, b).ok:
					n += 1
			guida = ("Bersagli a tiro: %d (in arancione). Clicca un nemico per %s." % [n, {"frecce": "tirare", "cavallo": "tirare", "dardi": "lanciare i dardi", "fiamme": "lanciare le fiamme", "visione": "lanciare la visione"}.get(tipo_t, "tirare")]) if n > 0 else "Nessun bersaglio valido a tiro da qui (gittata %d%s)." % [partita.gittata(u), ", in linea retta e senza ostacoli" if tipo_t == "frecce" and not partita.zl2() else ""]
		elif partita.fase == ZPartita.FASE_MOVIMENTO:
			guida = "Lancerà nella fase dei lanci, subito dopo il movimento."
		if guida != "":
			var lg := ZTema.etichetta(guida, 12, ZTema.VERDE.darkened(0.3), ZTema.testo_forte)
			lg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(lg)
	var stato: PackedStringArray = []
	if u.citta >= 0:
		stato.append("in guarnigione")
	if u.scortato_da >= 0:
		stato.append("sotto scorta")
	if u.scorta >= 0:
		stato.append("scorta " + partita.pedine[u.scorta].nome())
	if u.paralisi > 0:
		stato.append("paralizzato nel gorgo (%d)" % u.paralisi)
	if u.scomparso:
		stato.append("scomparso")
	if u.ridotta:
		stato.append("ridotto: fermo, senza zona d'influenza, si recupera a fine mossa")
	if u.catturata:
		stato.append("preso nella rete")
	if u.spada >= partita.turno_globale:
		stato.append("Spada di luce: valore doppio")
	if u.muta >= partita.turno_globale:
		stato.append("stregato dalle Odalische: niente magie")
	if u.pantera() and u.origine != "":
		stato.append("trasformata (tornerà %s)" % ("Donna-Pantera" if u.origine == "donna" else "fante"))
	if u.popolo == partita.popolo_di_mano() and partita.fase in [ZPartita.FASE_SINGOLI, ZPartita.FASE_MOVIMENTO, ZPartita.FASE_LANCI, ZPartita.FASE_COMBATTIMENTO]:
		if u.mosso:
			stato.append("ha mosso")
		if u.agito:
			stato.append("ha combattuto")
		if u.residuo > 0:
			stato.append("movimento residuo %d" % u.residuo)
	if u.colpi > 0:
		stato.append("colpi subiti %d" % u.colpi)
	var bonus := partita.bonus_maghi(u) + partita.bonus_terreno(u)
	if bonus > 0:
		stato.append("+%d in difesa" % bonus)
	if not stato.is_empty():
		var st := ZTema.etichetta(" · ".join(stato), 12, ZTema.CUOIO, ZTema.testo_forte)
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(st)
	h.add_child(v)
	return h

func _aggiorna_selezione() -> void:
	hud.pulisci_selezione()
	var box := hud.box_selezione
	var p := partita.popolo_di_mano()
	var mio := _posso_agire()
	# Diplomazia.
	if partita.fase == ZPartita.FASE_ALLEANZE and mio:
		box.add_child(ZTema.titoletto("Diplomazia", 18))
		var spiega := ZTema.etichetta("Prima di muovere puoi proporre alleanze o tradire quelle in corso.", 13)
		spiega.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(spiega)
		for q in partita.popoli:
			if q == p:
				continue
			var riga := HBoxContainer.new()
			riga.add_child(ZTema.ritratto(q, 40))
			var l := ZTema.etichetta(q, 15, ZTema.INCHIOSTRO, ZTema.testo_forte)
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			riga.add_child(l)
			if partita.alleati(p, q):
				riga.add_child(ZTema.pulsante("Tradisci", func(): _applica({"a": "rompi", "con": q}), 13))
			elif "%s>%s" % [p, q] in partita.proposte:
				riga.add_child(ZTema.etichetta("in attesa…", 13, ZTema.CUOIO))
			else:
				riga.add_child(ZTema.pulsante("Proponi alleanza", func(): _applica({"a": "proponi", "a2": q}), 13))
			box.add_child(riga)
		box.add_child(HSeparator.new())
	if partita.fase == ZPartita.FASE_MAGIA and mio:
		_pannello_magia(box)
		if sel_id < 0 and citta_sel < 0:
			return
		box.add_child(HSeparator.new())
	# Anteprima dello scontro.
	if partita.fase == ZPartita.FASE_COMBATTIMENTO and mio and (not difensori.is_empty() or citta_bersaglio >= 0):
		_pannello_scontro(box)
		return
	if partita.fase == ZPartita.FASE_COMBATTIMENTO and mio and gruppo.size() > 1:
		box.add_child(ZTema.titoletto("Gruppo d'attacco", 18))
		for id in gruppo:
			box.add_child(ZTema.etichetta("• %s (%d)" % [partita.pedine[id].nome(), partita.pedine[id].c()], 14))
		box.add_child(ZTema.etichetta("Ora clicca il nemico da attaccare.", 13, ZTema.CUOIO))
		return
	if sel_id >= 0:
		var u := partita.pedine[sel_id]
		box.add_child(_scheda_pedina(u))
		if mio and u.popolo == p:
			var azioni := HBoxContainer.new()
			if partita.fase == ZPartita.FASE_MOVIMENTO:
				if u.popolo == "Monaci" and u.tipo == "signore" and not u.scomparso and not u.mosso:
					azioni.add_child(ZTema.pulsante("Scompari", func(): _applica({"a": "scompari", "u": u.id}); sel_id = -1; _aggiorna(), 14))
				if (u.scorta >= 0 or u.scortato_da >= 0) and not u.scorta_cambiata:
					azioni.add_child(ZTema.pulsante("Togli la scorta", func(): _applica({"a": "togli_scorta", "u": u.id}), 14))
			if partita.zl2() and u.popolo == "Amazzoni" and partita.puo_trasformare(u) == "":
				if u.tipo == "donna":
					azioni.add_child(ZTema.pulsante("Trasformati in Pantera", func(): _applica({"a": "trasforma", "u": u.id}), 14))
				else:
					azioni.add_child(ZTema.pulsante("Tenta la trasformazione (pari)", func(): _applica({"a": "trasforma", "u": u.id}), 14))
			if partita.fase == ZPartita.FASE_MOVIMENTO and u.citta >= 0 and partita.puo_passaggio(u) == "":
				azioni.add_child(ZTema.pulsante("Passaggio segreto", func(): passaggio_id = u.id; _aggiorna(), 14))
			if azioni.get_child_count() > 0:
				box.add_child(azioni)
			if passaggio_id == u.id:
				var lp := ZTema.etichetta("Clicca un'altra tua città (in giallo) per trasferirvi il pezzo.", 13, ZTema.VERDE.darkened(0.3), ZTema.testo_forte)
				lp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				box.add_child(lp)
		if u.scorta >= 0:
			box.add_child(ZTema.etichetta("Scorta:", 12, ZTema.CUOIO, ZTema.testo_forte))
			box.add_child(_scheda_pedina(partita.pedine[u.scorta]))
	elif citta_sel >= 0:
		var ci: Dictionary = partita.citta[citta_sel]
		var tc := HBoxContainer.new()
		tc.add_child(ZTema.ritratto(ci.p, 40))
		var lc := ZTema.titoletto("Città %s" % ZRegole.degli(ci.p), 20, ZRegole.COLORI[ci.p].darkened(0.5))
		lc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tc.add_child(lc)
		box.add_child(tc)
		if ci.orig != ci.p:
			box.add_child(ZTema.etichetta("Conquistata %s" % ZRegole.agli(ci.orig), 13, ZTema.CUOIO))
		if _mio(ci.p) or (not in_online and partita.controllo.get(ci.p) == "umano" and ci.p == p):
			var gl := ZTema.etichetta("Guarnigione (%d/4) — scegli un pezzo per farlo uscire:" % ci.g.size(), 13, ZTema.INCHIOSTRO, ZTema.testo_forte)
			gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(gl)
			for id in ci.g:
				var w := partita.pedine[id]
				var b := ZTema.pulsante("%s  (%d/%d)" % [w.nome(), w.c(), w.m()], func(): sel_id = w.id; _aggiorna(), 14)
				b.icon = ZTema.texture_pedina(w.popolo, w.tipo)
				b.add_theme_constant_override("icon_max_width", 36)
				b.custom_minimum_size = Vector2(0, 44)
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				box.add_child(b)
		else:
			box.add_child(ZTema.etichetta("Guarnigione di %d pezzi coperti." % ci.g.size(), 14))
	elif partita.fase != ZPartita.FASE_SCHIERAMENTO:
		_legenda(box)
	elif partita.fase == ZPartita.FASE_SCHIERAMENTO and mio:
		var t := ZTema.etichetta("Scegli una città o un pezzo dal vassoio in basso e clicca un esagono dei tuoi continenti. Le città non vanno sulla costa e devono distare almeno 4 esagoni; ogni città accoglie fino a 4 pezzi coperti.", 14)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(t)
		box.add_child(ZTema.pulsante("Schieramento automatico", func(): _applica({"a": "auto_schieramento"}), 15))

## Fase della magia: punti di preparazione, scelta dell'incantesimo e dei punti da spendere.
func _pannello_magia(box: VBoxContainer) -> void:
	var p := partita.popolo_di_mano()
	var prep := int(partita.preparazione.get(p, 0))
	box.add_child(ZTema.titoletto("Magia", 18))
	if partita.magia_fatta:
		box.add_child(ZTema.etichetta("Hai già fatto la tua magia in questa mossa.", 13, ZTema.CUOIO))
		return
	var info := ZTema.etichetta("Preparazione: %d punti (si accumula un punto per mossa senza magie, massimo %d). Il dado più i punti spesi deve raggiungere il minimo dell'incantesimo; il bersaglio dev'essere entro %d esagoni da un tuo incantatore (Signore, Mago o Illusionista)." % [prep, ZRegole.MAX_PREPARAZIONE, ZRegole.RAGGIO_MAGIA], 13)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info)
	magia_punti = clampi(magia_punti, 0, prep)
	var rp := HBoxContainer.new()
	rp.add_child(ZTema.etichetta("Punti da spendere:", 14, ZTema.INCHIOSTRO, ZTema.testo_forte))
	var meno := ZTema.pulsante("−", func(): magia_punti = maxi(0, magia_punti - 1); _aggiorna(), 15)
	meno.disabled = magia_punti <= 0
	rp.add_child(meno)
	rp.add_child(ZTema.etichetta(str(magia_punti), 18, Color("6a3fa0"), ZTema.titolo))
	var piu := ZTema.pulsante("+", func(): magia_punti = mini(prep, magia_punti + 1); _aggiorna(), 15)
	piu.disabled = magia_punti >= prep
	rp.add_child(piu)
	box.add_child(rp)
	if magia_scelta != "":
		# Carta scelta in grande, con il pulsante per tornare alle altre.
		var m: Dictionary = ZRegole.MAGIE[magia_scelta]
		var carta := _carta_magia(magia_scelta, Vector2(320, 320), true)
		box.add_child(carta)
		box.add_child(ZTema.pulsante("‹ Scegli un'altra magia", func(): magia_scelta = ""; magia_h1 = Vector2i(-1, -1); _aggiorna(), 13))
	else:
		for scuola in ["bianca", "nera"]:
			box.add_child(ZTema.etichetta("Magia " + scuola, 12, ZTema.CUOIO, ZTema.testo_forte))
			var g := GridContainer.new()
			g.columns = 3
			g.add_theme_constant_override("h_separation", 4)
			g.add_theme_constant_override("v_separation", 4)
			for k in ZRegole.MAGIE:
				if ZRegole.MAGIE[k].scuola == scuola:
					g.add_child(_carta_magia(k, Vector2(104, 104), false))
			box.add_child(g)
	if magia_scelta != "":
		var m: Dictionary = ZRegole.MAGIE[magia_scelta]
		var probabilita := clampi(7 - (int(m.min) - magia_punti), 0, 6)
		var d := ZTema.etichetta("Con %d punti di preparazione riesce con %d su 6." % [magia_punti, probabilita], 13)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(d)
		var guida := {"frana": "Clicca un esagono di montagna.", "ponte": "Clicca la prima costa." if magia_h1.x < 0 else "Ora clicca la seconda costa (2-4 esagoni più in là).", "coraggio": "Clicca vicino alle tue unità ridotte.", "spada": "Clicca l'esagono dei tuoi pezzi.", "rinascita": "Clicca una tua città.", "odalische": "Clicca un Signore nemico.", "megadrago": "Clicca un esagono di terra libero.", "sonno": "Clicca l'esagono dei nemici.", "terremoto": "Clicca l'esagono dei nemici.", "voragine": "Clicca una città nemica."}
		box.add_child(ZTema.etichetta(guida.get(magia_scelta, ""), 13, ZTema.VERDE.darkened(0.3), ZTema.testo_forte))

## Carta di una magia (illustrazione con nome, punti minimi ed effetto).
## Piccola è un pulsante che la sceglie.
func _carta_magia(k: String, dim: Vector2, grande: bool) -> Control:
	var tex: Texture2D = load("res://assets/ui/magie/%s.png" % k)
	var m: Dictionary = ZRegole.MAGIE[k]
	if grande:
		var img := TextureRect.new()
		img.texture = tex
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.custom_minimum_size = dim
		return img
	var b := TextureButton.new()
	b.texture_normal = tex
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.custom_minimum_size = dim
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "%s (%d+): %s" % [m.nome, m.min, m.testo]
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func(): magia_scelta = k; magia_h1 = Vector2i(-1, -1); _aggiorna())
	return b

func _legenda(box: VBoxContainer) -> void:
	box.add_child(ZTema.titoletto("Il terreno", 16))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 0)
	for riga in [
		["Pianura", "1 punto"],
		["Bosco", "2 punti · +1 difesa · niente frecce"],
		["Montagna", "tutta la mossa · +3 difesa"],
		["Gorgo", "paralizza per 3 mosse"],
		["Ponte", "da costa a costa"],
	]:
		g.add_child(ZTema.etichetta(riga[0], 12, ZTema.INCHIOSTRO, ZTema.testo_forte))
		g.add_child(ZTema.etichetta(riga[1], 12))
	box.add_child(g)
	box.add_child(ZTema.etichetta("Mouse su un esagono per i dettagli.", 11, Color(ZTema.INCHIOSTRO, 0.55)))

func _pannello_scontro(box: VBoxContainer) -> void:
	box.add_child(ZTema.titoletto("Scontro", 20))
	var att := gruppo.duplicate()
	if citta_bersaglio >= 0:
		var ci: Dictionary = partita.citta[citta_bersaglio]
		var intro := ZTema.etichetta("Assedio alla città %s: guarnigione di %d pezzi coperti." % [ZRegole.degli(ci.p), ci.g.size()], 14)
		intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(intro)
		var forza := 0
		for id in att:
			box.add_child(ZTema.etichetta("• %s (%d)" % [partita.pedine[id].nome(), partita.pedine[id].c()], 14))
			forza += partita.pedine[id].c() + partita.bonus_maghi(partita.pedine[id])
		var regola := ZTema.etichetta("Forza degli assedianti: %d. Servono almeno %d pezzi; se la guarnigione supera di oltre 5 la vostra forza, gli assedianti sono eliminati." % [forza, ci.g.size()], 13, ZTema.CUOIO)
		regola.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(regola)
		var v := partita.valuta_assedio(att, citta_bersaglio)
		var b := ZTema.pulsante_forte("ASSEDIA", func():
			_applica({"a": "assedio", "att": att, "c": citta_bersaglio})
			_deseleziona(), 20)
		b.disabled = not v.ok
		if not v.ok:
			var err := ZTema.etichetta(v.errore, 13, ZTema.ROSSO, ZTema.testo_forte)
			err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(err)
		box.add_child(b)
		box.add_child(ZTema.pulsante("Annulla", _deseleziona, 14))
		return
	var esclusi: Array = []
	if att.size() > 1:
		for id in att.duplicate():
			var w := partita.pedine[id]
			if ZRegole.arciere(w.tipo) or w.tipo == "lanciafiamme":
				att.erase(id)
				esclusi.append(w.nome())
	if not esclusi.is_empty():
		var nota := ZTema.etichetta("Esclusi dallo scontro (in attacco possono solo tirare): " + ", ".join(esclusi), 12, ZTema.CUOIO, ZTema.testo_forte)
		nota.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(nota)
	var val := partita.valuta_attacco(att, difensori)
	var col_a := HBoxContainer.new()
	var va := VBoxContainer.new()
	va.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	va.add_child(ZTema.etichetta("ATTACCO", 12, ZTema.CUOIO, ZTema.testo_forte))
	for id in att:
		var w := partita.pedine[id]
		var extra := partita.bonus_maghi(w) + (partita.bonus_carica(w, partita.pedine[difensori[0]]) if not difensori.is_empty() else 0)
		va.add_child(ZTema.etichetta("%s %d%s" % [w.nome(), w.c(), (" +%d" % extra) if extra > 0 else ""], 13))
	var vd := VBoxContainer.new()
	vd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vd.add_child(ZTema.etichetta("DIFESA", 12, ZTema.CUOIO, ZTema.testo_forte))
	for id in difensori:
		var w := partita.pedine[id]
		var extra := partita.bonus_maghi(w) + partita.bonus_terreno(w)
		vd.add_child(ZTema.etichetta("%s %d%s" % [w.nome(), w.c(), (" +%d" % extra) if extra > 0 else ""], 13))
	col_a.add_child(va)
	col_a.add_child(vd)
	box.add_child(col_a)
	if val.has("fa"):
		box.add_child(ZTema.etichetta("%d contro %d · differenza %+d" % [val.fa, val.fd, val.diff], 18, ZTema.INCHIOSTRO, ZTema.titolo))
	if val.ok:
		var sp := ZWidget.Spicchio.new()
		sp.imposta(val.diff)
		box.add_child(sp)
		var spiega := ZTema.etichetta("Esito per ogni faccia del dado (D = il difensore arretra, A = l'attaccante arretra, E = eliminato).", 11, Color(ZTema.INCHIOSTRO, 0.6))
		spiega.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(spiega)
	else:
		var e := ZTema.etichetta(val.errore, 13, ZTema.ROSSO, ZTema.testo_forte)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(e)
	var bott := HBoxContainer.new()
	var b := ZTema.pulsante_forte("TIRA IL DADO", func():
		_applica({"a": "attacco", "att": att, "dif": difensori.duplicate()})
		_deseleziona(), 20)
	b.disabled = not val.ok
	bott.add_child(b)
	box.add_child(bott)
	var tip := ZTema.etichetta("Clic sui tuoi pezzi per aggiungerli o toglierli; Maiusc+clic per attaccare più nemici con un solo pezzo.", 11, Color(ZTema.INCHIOSTRO, 0.6))
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(tip)
	box.add_child(ZTema.pulsante("Annulla", _deseleziona, 14))

func _aggiorna_vassoio() -> void:
	for c in hud.box_vassoio.get_children():
		c.queue_free()
	var p := partita.popolo_di_mano()
	hud.vassoio.visible = partita.fase == ZPartita.FASE_SCHIERAMENTO and _posso_agire()
	if not hud.vassoio.visible:
		return
	var da_piazzare := 0
	for ci in partita.citta:
		if ci.p == p and ci.h[0] < 0:
			da_piazzare += 1
	hud.box_vassoio.add_child(_voce_vassoio(p, "citta", da_piazzare, "Città", func(): citta_sel = _prossima_citta_da_piazzare(); sel_id = -1; _aggiorna()))
	for tipo in ZRegole.PEZZI[p]:
		var n := 0
		for u in partita.pedine:
			if u.popolo == p and u.tipo == tipo and not u.schierata:
				n += 1
		var t: String = tipo
		hud.box_vassoio.add_child(_voce_vassoio(p, tipo, n, ZRegole.nome_pezzo(p, tipo), func(): sel_id = _prossima_da_schierare(t); citta_sel = -1; _aggiorna()))

func _voce_vassoio(p: String, tipo: String, n: int, nome: String, azione: Callable) -> Control:
	var b := Button.new()
	b.icon = ZTema.texture_pedina(p, tipo)
	b.add_theme_constant_override("icon_max_width", 54)
	b.custom_minimum_size = Vector2(150, 76)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.text = "%s\n× %d" % [nome, n]
	b.add_theme_font_size_override("font_size", 12)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = n == 0
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(azione)
	var attivo: bool = (tipo == "citta" and citta_sel >= 0 and partita.citta[citta_sel].h[0] < 0) or (sel_id >= 0 and partita.pedine[sel_id].tipo == tipo and not partita.pedine[sel_id].schierata)
	if attivo:
		b.add_theme_stylebox_override("normal", ZTema.riquadro(Color("fff3cf"), ZTema.OCRA, 3, 4, 8))
	return b

func _aggiorna_evidenziazioni() -> void:
	tavolo.pulisci_evidenziazioni(["varchi"])
	tavolo.seleziona_pedine([])
	for s in tavolo.citta.values():
		s.seleziona(false)
	if partita.fase == ZPartita.FASE_FINITA:
		return
	var p := partita.popolo_di_mano()
	var mio := _posso_agire()
	if sel_id >= 0:
		tavolo.seleziona_pedine([sel_id])
	if citta_sel >= 0 and tavolo.citta.has(citta_sel):
		tavolo.citta[citta_sel].seleziona(true)
	if not mio:
		return
	if passaggio_id >= 0:
		var mete: Array = []
		for ci in partita.citta:
			if ci.p == p and ci.h[0] >= 0 and int(ci.id) != partita.pedine[passaggio_id].citta and ci.g.size() < ZRegole.MAX_GUARNIGIONE:
				mete.append(partita.hex_citta(ci))
		tavolo.evidenzia("basi", mete, Color(0.95, 0.8, 0.3, 0.6))
		return
	match partita.fase:
		ZPartita.FASE_MAGIA:
			var signori: Array = []
			for u in partita.signori_magici(p):
				signori.append(u.hex)
			tavolo.evidenzia("gruppo", signori, Color(0.65, 0.45, 1.0, 0.45))
			if magia_scelta != "" and not partita.magia_fatta:
				var bersagli: Array = []
				var visti := {}
				for u in partita.signori_magici(p):
					for v in partita._esagoni_entro(u.hex, ZRegole.RAGGIO_MAGIA):
						if visti.has(v):
							continue
						visti[v] = true
						var ok := false
						if magia_scelta == "ponte":
							if magia_h1.x < 0:
								ok = partita.mappa.terra(v) and partita.mappa.costa(v)
							else:
								ok = partita.valuta_magia("ponte", magia_h1, [v.x, v.y]) == ""
						elif magia_scelta in ["sonno", "terremoto", "spada", "coraggio"]:
							ok = partita.valuta_magia(magia_scelta, v) == "" and not partita.pedine_in(v).is_empty()
						else:
							ok = partita.valuta_magia(magia_scelta, v) == ""
						if ok:
							bersagli.append(v)
				tavolo.evidenzia("bersagli", bersagli, Color(0.6, 0.35, 0.95, 0.45))
				if magia_h1.x >= 0:
					tavolo.evidenzia("basi", [magia_h1], Color(0.7, 0.9, 1.0, 0.7))
		ZPartita.FASE_SCHIERAMENTO:
			var zone: Array = []
			var colori := {}
			for i in partita.continenti_di(p):
				for h in partita.mappa.esagoni_continente(i):
					if citta_sel >= 0 and partita.citta[citta_sel].h[0] < 0:
						if partita.citta_valida(partita.citta[citta_sel], h) == "":
							zone.append(h)
							colori[h] = Color(0.95, 0.75, 0.3, 0.45)
					elif sel_id >= 0 and partita.pedina_in(h) == null:
						zone.append(h)
						colori[h] = Color(1, 0.95, 0.75, 0.2)
			tavolo.evidenzia("schieramento", zone, colori)
		ZPartita.FASE_SINGOLI, ZPartita.FASE_MOVIMENTO:
			if sel_id < 0:
				# Suggerisce i pezzi che possono agire in questa fase.
				var liberi: Array = []
				for u in partita.pedine:
					if u.popolo != p or not u.in_campo() or u.scortato_da >= 0:
						continue
					if partita.fase == ZPartita.FASE_MOVIMENTO and partita.puo_muovere(u) == "":
						liberi.append(u.hex)
					elif partita.fase == ZPartita.FASE_SINGOLI and (partita.puo_attacco_singolo(u) == "" or partita.puo_muovere(u) == "" or (u.popolo == "Draghi" and u.tipo == "signore" and not u.agito) or (partita.zl2() and partita.puo_trasformare(u) == "")):
						liberi.append(u.hex)
				tavolo.evidenzia("gruppo", liberi, Color(1, 0.95, 0.75, 0.3))
				return
			var s := partita.pedine[sel_id]
			if s.popolo != p:
				return
			if s.scomparso:
				tavolo.evidenzia("raggio", partita.destinazioni_ricomparsa(s), Color(0.85, 0.6, 1.0, 0.45))
				return
			if partita.puo_muovere(s) == "":
				var rag := partita.raggiungibili(s)
				tavolo.evidenzia("raggio", rag.keys(), Color(1.0, 0.97, 0.85, 0.42))
			var bersagli: Array = []
			if partita.puo_attacco_singolo(s) == "" or partita.tipo_tiro(s) == "fiamme":
				for b in partita.pedine:
					if partita.attaccabile(b) and partita.nemici(b.popolo, p) and partita.mappa.distanza(s.hex, b.hex) <= s.m() + 1:
						if not partita.basi_attacco_singolo(s, b).is_empty() or (partita.tipo_tiro(s) == "fiamme" and partita.valuta_tiro(s, b).ok):
							bersagli.append(b.hex)
			tavolo.evidenzia("bersagli", bersagli, Color(0.85, 0.15, 0.1, 0.55))
		ZPartita.FASE_LANCI:
			var tiratori: Array = []
			for u in partita.pedine:
				if u.popolo == p and u.viva and not u.scomparso and partita.tipo_tiro(u) != "" and not u.agito and u.scortato_da < 0:
					tiratori.append(u.hex)
			tavolo.evidenzia("gruppo", tiratori, Color(1, 0.95, 0.75, 0.3))
			if sel_id >= 0:
				var s := partita.pedine[sel_id]
				if s.popolo == p and partita.tipo_tiro(s) != "":
					var bersagli: Array = []
					for b in partita.pedine:
						if partita.attaccabile(b) and partita.nemici(b.popolo, p) and partita.mappa.distanza(s.hex, b.hex) <= partita.gittata(s) and partita.valuta_tiro(s, b).ok:
							bersagli.append(b.hex)
					tavolo.evidenzia("bersagli", bersagli, Color(0.95, 0.5, 0.1, 0.55))
		ZPartita.FASE_COMBATTIMENTO:
			var g_hex: Array = []
			for id in gruppo:
				g_hex.append(partita.pedine[id].hex)
			tavolo.seleziona_pedine(gruppo)
			var bersagli: Array = []
			var colori := {}
			for u in partita.pedine:
				if partita.attaccabile(u) and partita.nemici(u.popolo, p) and not colori.has(u.hex):
					for v in partita.mappa.vicino_geometrico_tutti(u.hex):
						var w := partita.pedina_in(v)
						if w and w.popolo == p and partita.puo_attaccare(w) == "":
							bersagli.append(u.hex)
							colori[u.hex] = Color(0.85, 0.15, 0.1, 0.45)
							break
			for id in difensori:
				if tavolo.segnalini.has(id):
					tavolo.segnalini[id].seleziona(true, ZTema.ROSSO)
				var h := partita.pedine[id].hex
				if not colori.has(h):
					bersagli.append(h)
				colori[h] = Color(0.9, 0.05, 0.05, 0.75)
			tavolo.evidenzia("bersagli", bersagli, colori)
			if citta_bersaglio >= 0:
				tavolo.evidenzia("basi", [partita.hex_citta(partita.citta[citta_bersaglio])], Color(0.9, 0.05, 0.05, 0.7))
			var pronti: Array = []
			for u in partita.pedine:
				if u.popolo == p and u.in_campo() and partita.puo_attaccare(u) == "" and partita.in_zona_nemica(u.hex, p):
					pronti.append(u.hex)
			tavolo.evidenzia("gruppo", pronti, Color(1, 0.85, 0.4, 0.18))

func _aggiorna_suggerimento() -> void:
	var p := partita.popolo_di_mano()
	var t := ""
	if partita.fase == ZPartita.FASE_FINITA:
		t = "La partita è finita."
	elif ia_in_corso or not _mio(p):
		t = "Muovono %s. Puoi esplorare il tavolo e ispezionare i pezzi." % ZRegole.gli(p)
	else:
		match partita.fase:
			ZPartita.FASE_SCHIERAMENTO:
				t = "Schiera città, guarnigioni e armate sui tuoi continenti, poi conferma."
			ZPartita.FASE_ALLEANZE:
				t = "Proponi o tradisci alleanze nel pannello a destra, poi passa al movimento."
			ZPartita.FASE_MAGIA:
				t = "Magia: scegli un incantesimo e i punti di preparazione da spendere, poi clicca il bersaglio entro 10 esagoni da un tuo incantatore (Signore, Mago o Illusionista) (in viola). Oppure passa oltre e accumula un punto."
			ZPartita.FASE_SINGOLI:
				t = "Attacchi singoli, prima di ogni altro movimento: seleziona un Alato, un Falco, un Serpente o una Pantera e clicca un nemico in rosso. Il Signore Drago può fiammeggiare prima di muovere; le Donne-Pantera si trasformano ora."
			ZPartita.FASE_MOVIMENTO:
				t = "Seleziona un pezzo e clicca un esagono evidenziato; Maiusc+clic con un fante su un pezzo amico per fargli da scorta."
				if sel_id >= 0 and partita.pedine[sel_id].scomparso:
					t = "Scegli dove far ricomparire il Signore Monaco."
			ZPartita.FASE_LANCI:
				t = "Lanci: seleziona un tiratore evidenziato (Fantarcieri, Lanciafiamme, Draghi, Maghi, Illusionisti) e clicca un bersaglio arancione. Maghi, Illusionisti e Draghi che lanciano non combattono più."
			ZPartita.FASE_COMBATTIMENTO:
				t = "Corpo a corpo: scegli gli attaccanti adiacenti e clicca il nemico o la città da attaccare."
	hud.suggerimento.text = t

# ---------------------------------------------------------------------------
# Regole in breve
# ---------------------------------------------------------------------------

const REGOLE := """[b]Scopo.[/b] L'Anno di Zargo dura 25 mesi: vince chi, alla fine, controlla più città, proprie o conquistate. Il numero di pezzi superstiti non conta.

[b]La mossa.[/b] Ogni mese muovono, nell'ordine, Cavalieri, Draghi, Alati e Monaci. Ciascuno: 1) propone o tradisce alleanze (con 3-4 popoli); 2) attacchi singoli di Alati, Falchi e Serpenti, prima di ogni altro movimento (il Signore Drago può anche fiammeggiare prima di muovere); 3) muove gli altri pezzi; 4) lanci: frecce, fiamme e visioni; 5) combattimenti corpo a corpo. Le fasi in cui non c'è nulla da fare vengono saltate.

[b]Movimento.[/b] Il mare si attraversa solo sui ponti di nuvole. Un bosco costa 2 punti. Una montagna richiede un'intera mossa per salire. Un gorgo magico ferma e paralizza per tre mosse (e rende inattaccabili). Gli esagoni adiacenti a un nemico sono la sua zona d'influenza: ci si entra solo per attaccarlo.

[b]Scontri.[/b] Si sommano i valori degli attaccanti adiacenti e si sottrae la difesa (+1 in bosco, +3 in montagna, +2 per ogni Mago vicino). Sotto -5 non si può attaccare. Il dado decide: A/D con un numero = l'attaccante o il difensore arretra in linea retta di tanti esagoni; E = eliminato. Chi arretra contro mare, boschi, monti, città o zone d'influenza nemiche è eliminato.

[b]Poteri.[/b] Signori Cavalieri: carica in linea retta (+3 frontale, +1 laterale). Maghi e Illusionisti: visioni entro 5 esagoni, che mettono in fuga. Fantarcieri: frecce in linea retta entro 8. Draghi e Lanciafiamme: fiamme entro 5 (i Draghi ne sono immuni). Alati, Falchi e Serpenti: attacchi singoli prima di ogni altro movimento; gli Alati volano sopra nemici, boschi e montagne. Signori Monaci: spariscono e ricompaiono la mossa successiva.

[b]Città e scorte.[/b] Una città ospita fino a 4 pezzi coperti. Per assediarla servono almeno tanti pezzi quanti ne contiene la guarnigione; la guarnigione non può arretrare, quindi ogni esito favorevole all'attaccante conquista la città. Un fante può fare da scorta a un altro pezzo, subendo al suo posto gli attacchi.

[b]Zargo's Lords 2.[/b] Con Amazzoni o Aracnidi in campo (o attivando l'opzione nel menu) ogni popolo ha 6 città e si possono impilare due pezzi dello stesso popolo. Chi arretra contro un ostacolo viene ridotto (girato, fermo e senza zona d'influenza) invece che eliminato: a fine mossa si recupera con 4+ se un proprio Signore è vicino. Le frecce partono in ogni direzione, +1 contro le pile. Amazzoni: arcieri a cavallo, Donne-Pantera che si trasformano all'inizio della mossa, fanti che diventano Pantere con un numero pari, Signora con il manto magico. Aracnidi: ragni che lasciano reti sul percorso, Reziari che lanciano la rete prima dello scontro, dardi del Signore. Con l'espansione i tiri arrivano a 2 esagoni, a 8 (frecce) o 5 (arciere a cavallo, lanciafiamme) se il tiratore è accanto a un incantatore: Signori, Maghi e Illusionisti. Regole opzionali: iniziativa (ordine sorteggiato ogni mese e fasi giocate a turno da tutti), passaggi segreti fra le proprie città, magia (punti di preparazione e dieci incantesimi bianchi e neri), guerra lampo a punti.

[b]Comandi.[/b] Tasto sinistro: seleziona e trascina il tavolo. Tasto destro: ruota la vista (clic: annulla la selezione). Rotella: zoom. G: reticolo. Invio: fase successiva."""

func _mostra_regole() -> void:
	hud.apri_finestra("Regole in breve", REGOLE, [["Chiudi", Callable()]], 720, 470)

func _mostra_regole_menu() -> void:
	hud.radice.visible = true
	hud.apri_finestra("Regole in breve", REGOLE, [["Chiudi", func(): hud.radice.visible = partita != null and menu == null]], 720, 470)
	hud.layer = 11

# ---------------------------------------------------------------------------
# Partita online
# ---------------------------------------------------------------------------

func _messaggio_online(m: String) -> void:
	if menu:
		menu.stato(m)
	else:
		_avviso(m)

func _connetti(url: String, chiave: String, poi: Callable) -> void:
	if not online.configure(url, chiave):
		return
	if menu:
		menu.stato("Collegamento a Firebase…")
	online.authenticated.connect(poi, CONNECT_ONE_SHOT)
	online.authenticate_anonymously()

func _crea_stanza(controllo: Dictionary, opzioni: Dictionary, url: String, chiave: String) -> void:
	if controllo.size() < 2:
		menu.stato("Servono almeno due popoli in gioco.")
		return
	_connetti(url, chiave, func():
		var ctrl := {}
		posti.clear()
		for p in controllo:
			match controllo[p]:
				"umano":
					ctrl[p] = "umano"
					posti[p] = online.uid
				"remoto":
					ctrl[p] = "umano"
					posti[p] = "libero"
				"ia":
					ctrl[p] = "ia"
					posti[p] = "ia"
		partita = ZPartita.new()
		partita.nuova(ctrl.keys(), ctrl, 0, opzioni)
		var codice := FirebaseOnline.generate_room_code()
		online.room_created.connect(func(c, _d):
			in_online = true
			sono_host = true
			online.start_polling()
			_avvia_vista()
			hud.apri_finestra("Stanza %s" % c, "Comunica agli altri giocatori il codice [b]%s[/b]: entrando dal menu «Gioca online» occuperanno i popoli remoti liberi." % c, [["Iniziamo", Callable()]], 460)
		, CONNECT_ONE_SHOT)
		online.create_room(codice, partita.a_dict(), {"posti": posti, "host": online.uid}))

func _entra_stanza(codice: String, url: String, chiave: String) -> void:
	_connetti(url, chiave, func():
		online.room_joined.connect(func(c, d):
			var p_posti: Dictionary = d.get("posti", {})
			var scelto := ""
			for p in ZRegole.POPOLI_ZL2:
				if p_posti.get(p) == online.uid:
					scelto = p
			if scelto == "":
				for p in ZRegole.POPOLI_ZL2:
					if p_posti.get(p) == "libero":
						scelto = p
						break
			if scelto == "":
				menu.stato("Nessun posto libero nella stanza %s." % c)
				return
			posti = p_posti
			posti[scelto] = online.uid
			online.scrivi("posti/" + scelto, online.uid)
			partita = ZPartita.new()
			partita.da_dict(d.state)
			in_online = true
			sono_host = d.get("host", "") == online.uid
			online.start_polling()
			_avvia_vista()
			hud.mostra_dado(0, "SEI %s" % ZRegole.gli(scelto).to_upper(), "Collegato alla stanza %s." % c)
		, CONNECT_ONE_SHOT)
		online.join_room(codice))

func _pubblica() -> void:
	online.publish_snapshot(partita.a_dict())

func _ricevi_stato(stato: Dictionary) -> void:
	if partita == null or ia_in_corso or presentando:
		return
	var prima := partita.a_dict()
	partita.da_dict(stato)
	_controlla_proposte()
	tavolo.sincronizza(partita)
	if int(prima.tg) != partita.turno_globale and _mio(partita.popolo_di_mano()):
		_inquadra_popolo(partita.popolo_di_mano())
		hud.mostra_dado(0, "TOCCA A TE", "Mossa %s, mese %d." % [ZRegole.degli(partita.popolo_di_mano()), partita.mese])
	_aggiorna()
