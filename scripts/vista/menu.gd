class_name ZMenu
extends CanvasLayer
## Schermata iniziale: i Signori dei popoli con chi li guida, le opzioni
## dell'espansione e la partita online. Tutto deve stare nella finestra.

signal avvia(controllo: Dictionary, opzioni: Dictionary)
signal continua
signal crea_stanza(controllo: Dictionary, opzioni: Dictionary, url: String, chiave: String)
signal entra_stanza(codice: String, url: String, chiave: String)
signal regole
signal grafica_cambiata(grafica: String)

const SCELTE := ["Umano", "IA", "Escluso"]
const SCELTE_ONLINE := ["Io", "Remoto", "IA", "Escluso"]
const MAX_POPOLI := 4
const ESPANSIONE := ["Amazzoni", "Aracnidi"]

var radice: Control
var schede := {}          # popolo -> {"pannello", "img", "box", "gruppo"}
var scelta := {}          # popolo -> testo della scelta corrente
var box_online: PanelContainer
var campo_url: LineEdit
var campo_chiave: LineEdit
var campo_codice: LineEdit
var stato_label: Label
var online_attivo := false
var btn_continua: Button
var btn_nuova: Button
var opz_zl2: CheckButton
var opz := {}             # chiave -> CheckButton delle opzioni ZL2

func _ready() -> void:
	layer = 10
	radice = Control.new()
	radice.set_anchors_preset(Control.PRESET_FULL_RECT)
	radice.theme = ZTema.crea()
	add_child(radice)
	var fondo := ColorRect.new()
	fondo.color = ZTema.CUOIO_SCURO
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	radice.add_child(fondo)
	# A sinistra i quattro Signori del 1979 (illustrazione di Casolari) sotto il nome del gioco.
	var sinistra := VBoxContainer.new()
	sinistra.anchor_bottom = 1.0
	sinistra.anchor_right = 0.43
	sinistra.offset_left = 28
	sinistra.offset_top = 22
	sinistra.offset_bottom = -20
	sinistra.offset_right = -8
	sinistra.add_theme_constant_override("separation", 0)
	radice.add_child(sinistra)
	var logo := ZTema.etichetta("ZARGO'S LORDS", 56, ZTema.AVORIO, ZTema.titolo)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sinistra.add_child(logo)
	var motto := ZTema.etichetta("duelli magici per il potere mondiale", 16, ZTema.TERRA_ROSA, ZTema.testo_forte)
	motto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sinistra.add_child(motto)
	var illustrazione := TextureRect.new()
	illustrazione.texture = load("res://assets/ui/signori_insieme.png")
	illustrazione.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	illustrazione.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	illustrazione.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sinistra.add_child(illustrazione)
	# Colonna destra; lo scorrimento resta solo come riserva per finestre minuscole.
	var scroll := ScrollContainer.new()
	scroll.anchor_left = 0.43
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 20
	scroll.offset_right = -28
	scroll.offset_top = 24
	scroll.offset_bottom = -16
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	radice.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	scroll.add_child(v)
	var testa := HBoxContainer.new()
	var tit := ZTema.titoletto("Scegli i Signori in campo", 26, ZTema.AVORIO)
	tit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tit.tooltip_text = "Da due a quattro popoli. Venticinque mesi per conquistare più città degli altri."
	tit.mouse_filter = Control.MOUSE_FILTER_PASS
	testa.add_child(tit)
	testa.add_child(_riga_grafica())
	v.add_child(testa)
	# Gioco base sopra, espansione sotto, su due colonne.
	for gruppo in [ZRegole.POPOLI_ZL2.filter(func(x): return not x in ESPANSIONE), ESPANSIONE]:
		var griglia := GridContainer.new()
		griglia.columns = 2
		griglia.add_theme_constant_override("h_separation", 10)
		griglia.add_theme_constant_override("v_separation", 8)
		for p in gruppo:
			griglia.add_child(_scheda_popolo(p))
		if gruppo == ESPANSIONE:
			var t := ZTema.etichetta("ZARGO'S LORDS 2", 14, ZTema.OCRA, ZTema.titolo)
			v.add_child(t)
		v.add_child(griglia)
	v.add_child(_riga_opzioni())
	# Azioni principali.
	var azioni := HBoxContainer.new()
	azioni.add_theme_constant_override("separation", 10)
	btn_nuova = ZTema.pulsante_forte("NUOVA PARTITA", _nuova, 24)
	btn_nuova.custom_minimum_size = Vector2(230, 50)
	azioni.add_child(btn_nuova)
	btn_continua = ZTema.pulsante("Continua la salvata", func(): continua.emit(), 15)
	btn_continua.visible = FileAccess.file_exists("user://partita.json")
	azioni.add_child(btn_continua)
	azioni.add_child(ZTema.pulsante("Gioca online", _mostra_online, 15))
	azioni.add_child(ZTema.pulsante("Regole in breve", func(): regole.emit(), 15))
	v.add_child(azioni)
	stato_label = ZTema.etichetta("", 14, ZTema.OCRA, ZTema.testo_forte)
	stato_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(stato_label)
	v.add_child(_pannello_online())
	var crediti := ZTema.etichetta("Gioco originale: Zargo's Lords e Zargo's Lords 2, International Team. Versione digitale amatoriale.", 12, Color(ZTema.AVORIO, 0.45))
	crediti.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(crediti)
	for p in ZRegole.POPOLI_ZL2:
		var iniziale := "Escluso"
		if p == "Cavalieri":
			iniziale = "Umano"
		elif not p in ESPANSIONE:
			iniziale = "IA"
		_imposta(p, iniziale)
	_aggiorna_opzioni()

func _scheda_popolo(p: String) -> Control:
	var c := PanelContainer.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	c.add_child(h)
	var img := TextureRect.new()
	img.texture = ZTema.ritratto_signore(p)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.custom_minimum_size = Vector2(96, 120)
	img.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(img)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.custom_minimum_size = Vector2(230, 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var nome := ZTema.titoletto(p, 21, ZRegole.COLORI[p].darkened(0.5))
	nome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(nome)
	var box := GridContainer.new()
	box.add_theme_constant_override("h_separation", 4)
	box.add_theme_constant_override("v_separation", 4)
	col.add_child(box)
	h.add_child(col)
	schede[p] = {"pannello": c, "img": img, "box": box}
	_crea_pulsanti(p)
	return c

func _crea_pulsanti(p: String) -> void:
	var box: GridContainer = schede[p].box
	for f in box.get_children():
		f.queue_free()
	box.columns = 2 if online_attivo else 3
	var gruppo := ButtonGroup.new()
	schede[p].gruppo = gruppo
	for s in (SCELTE_ONLINE if online_attivo else SCELTE):
		var b := ZTema.pulsante(s, Callable(), 14)
		b.toggle_mode = true
		b.button_group = gruppo
		b.custom_minimum_size = Vector2(0, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_scegli.bind(p, s))
		box.add_child(b)

func _scegli(p: String, s: String) -> void:
	var prima: String = scelta.get(p, "Escluso")
	if s != "Escluso" and prima == "Escluso" and _in_campo().size() >= MAX_POPOLI:
		stato("Al massimo quattro popoli: escludine prima un altro.")
		_imposta(p, prima)
		return
	stato("")
	_imposta(p, s)
	if p in ESPANSIONE and s != "Escluso" and not opz_zl2.button_pressed:
		opz_zl2.button_pressed = true
	_aggiorna_opzioni()

func _imposta(p: String, s: String) -> void:
	scelta[p] = s
	var box: GridContainer = schede[p].box
	for b in box.get_children():
		if b is Button and not b.is_queued_for_deletion():
			b.set_pressed_no_signal(b.text == s)
	var fuori := s == "Escluso"
	var pannello: PanelContainer = schede[p].pannello
	var bordo: Color = ZRegole.COLORI[p].darkened(0.3)
	pannello.add_theme_stylebox_override("panel", ZTema.riquadro(
		ZTema.GRIGIO if fuori else ZTema.AVORIO, Color(bordo, 0.5) if fuori else bordo, 3, 8, 8))
	(schede[p].img as TextureRect).modulate = Color(1, 1, 1, 0.35) if fuori else Color.WHITE

func _in_campo() -> Array:
	var out := []
	for p in ZRegole.POPOLI_ZL2:
		if scelta.get(p, "Escluso") != "Escluso":
			out.append(p)
	return out

var _gruppo_grafica: ButtonGroup
func _riga_grafica() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(ZTema.etichetta("Pedine:", 15, ZTema.AVORIO, ZTema.testo_forte))
	_gruppo_grafica = ButtonGroup.new()
	for g in [["originale", "Originali 1979"], ["nuova", "Nuova grafica"], ["3d", "Miniature 3D"]]:
		var b := ZTema.pulsante(g[1], func(): _scegli_grafica(g[0]), 14)
		b.toggle_mode = true
		b.button_group = _gruppo_grafica
		b.set_pressed_no_signal(ZTema.grafica == g[0])
		h.add_child(b)
	return h

func _scegli_grafica(g: String) -> void:
	ZTema.grafica = g
	grafica_cambiata.emit(g)
	for p in schede:
		(schede[p].img as TextureRect).texture = ZTema.ritratto_signore(p)

func _riga_opzioni() -> Control:
	var c := PanelContainer.new()
	c.add_theme_stylebox_override("panel", ZTema.riquadro(Color(ZTema.AVORIO, 0.1), Color(ZTema.TERRA_ROSA, 0.5), 1, 6, 8))
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 14)
	c.add_child(h)
	opz_zl2 = _interruttore("Regole di Zargo's Lords 2", "Sei città per popolo, pile di due pezzi, pezzi ridotti invece che eliminati contro gli ostacoli, frecce in ogni direzione.")
	opz_zl2.toggled.connect(func(_on): _aggiorna_opzioni())
	h.add_child(opz_zl2)
	for k in [["iniziativa", "Iniziativa", "Ogni mese l'ordine dei popoli si sorteggia; ogni fase (potere, movimento, combattimento) la giocano tutti prima di passare alla successiva."], ["magia", "Magia", "I Signori accumulano punti di preparazione e lanciano incantesimi."], ["passaggi", "Passaggi segreti", "Una volta per mossa un pezzo in guarnigione passa a un'altra città del suo popolo."], ["lampo", "Guerra lampo", "Le città conquistate vengono rase e danno punti: vince chi ne fa di più."]]:
		var b := _interruttore(k[1], k[2])
		opz[k[0]] = b
		h.add_child(b)
	return c

func _interruttore(testo: String, aiuto: String) -> CheckButton:
	var b := CheckButton.new()
	b.text = testo
	b.tooltip_text = aiuto
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, ZTema.AVORIO if k.begins_with("font_h") or k == "font_color" else ZTema.OCRA)
	b.add_theme_color_override("font_disabled_color", Color(ZTema.AVORIO, 0.35))
	return b

func _aggiorna_opzioni() -> void:
	var serve := false
	for p in ESPANSIONE:
		if scelta.get(p, "Escluso") != "Escluso":
			serve = true
	if serve:
		opz_zl2.button_pressed = true
	opz_zl2.disabled = serve
	for k in opz:
		var b: CheckButton = opz[k]
		b.disabled = not opz_zl2.button_pressed
		if b.disabled:
			b.button_pressed = false

func _opzioni() -> Dictionary:
	var out := {"zl2": opz_zl2.button_pressed}
	for k in opz:
		out[k] = (opz[k] as CheckButton).button_pressed
	return out

func _pannello_online() -> Control:
	box_online = PanelContainer.new()
	box_online.visible = false
	box_online.add_theme_stylebox_override("panel", ZTema.riquadro(ZTema.AVORIO, ZTema.CUOIO, 2, 8, 10))
	var vo := VBoxContainer.new()
	vo.add_theme_constant_override("separation", 6)
	box_online.add_child(vo)
	var spiega := ZTema.etichetta("Chi crea la stanza assegna i popoli: «Io», «Remoto» o «IA». Gli altri entrano con il codice e occupano il primo popolo remoto libero.", 13)
	spiega.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vo.add_child(spiega)
	campo_url = LineEdit.new()
	campo_url.placeholder_text = "Database URL Firebase (https://…firebaseio.com)"
	campo_chiave = LineEdit.new()
	campo_chiave.placeholder_text = "Web API key"
	campo_chiave.secret = true
	var hc := HBoxContainer.new()
	campo_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	campo_chiave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hc.add_child(campo_url)
	hc.add_child(campo_chiave)
	vo.add_child(hc)
	var cfg := _config_firebase()
	if not cfg.is_empty():
		campo_url.text = cfg.get("database_url", "")
		campo_chiave.text = cfg.get("api_key", "")
		hc.visible = false
	var ho := HBoxContainer.new()
	ho.add_child(ZTema.pulsante("Crea stanza", _crea, 15))
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(16, 0)
	ho.add_child(sep)
	campo_codice = LineEdit.new()
	campo_codice.placeholder_text = "Codice stanza"
	campo_codice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ho.add_child(campo_codice)
	ho.add_child(ZTema.pulsante("Entra", func(): entra_stanza.emit(campo_codice.text, campo_url.text, campo_chiave.text), 15))
	vo.add_child(ho)
	return box_online

func _mostra_online() -> void:
	online_attivo = not box_online.visible
	box_online.visible = online_attivo
	for p in schede:
		var s: String = scelta[p]
		if online_attivo and s == "Umano":
			s = "Io" if p == _primo_umano() else "Remoto"
		elif not online_attivo and s in ["Io", "Remoto"]:
			s = "Umano"
		_crea_pulsanti(p)
		_imposta(p, s)

func _primo_umano() -> String:
	for p in ZRegole.POPOLI_ZL2:
		if scelta.get(p, "") in ["Umano", "Io"]:
			return p
	return ""

func _config_firebase() -> Dictionary:
	if not FileAccess.file_exists("res://firebase_config.json"):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://firebase_config.json"))
	return d if d is Dictionary else {}

func _controllo() -> Dictionary:
	var out := {}
	for p in ZRegole.POPOLI_ZL2:
		match String(scelta.get(p, "Escluso")):
			"Umano", "Io": out[p] = "umano"
			"Remoto": out[p] = "remoto"
			"IA": out[p] = "ia"
	return out

func _nuova() -> void:
	var c := _controllo()
	if c.size() < 2:
		stato("Servono almeno due popoli in gioco.")
		return
	avvia.emit(c, _opzioni())

func _crea() -> void:
	crea_stanza.emit(_controllo(), _opzioni(), campo_url.text, campo_chiave.text)

func stato(testo: String) -> void:
	stato_label.text = testo
