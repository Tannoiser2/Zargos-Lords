class_name ZMenu
extends CanvasLayer
## Schermata iniziale: scelta dei popoli e di chi li guida, partita online.

signal avvia(controllo: Dictionary)
signal continua
signal crea_stanza(controllo: Dictionary, url: String, chiave: String)
signal entra_stanza(codice: String, url: String, chiave: String)
signal regole

const SCELTE := ["Giocatore", "IA", "Escluso"]
const SCELTE_ONLINE := ["Io", "Giocatore remoto", "IA", "Escluso"]

var radice: Control
var selettori := {}
var box_online: VBoxContainer
var campo_url: LineEdit
var campo_chiave: LineEdit
var campo_codice: LineEdit
var stato_online: Label
var online_attivo := false
var btn_continua: Button
var btn_nuova: Button

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
	# Copertina originale a sinistra, incorniciata come la scatola.
	var cornice := PanelContainer.new()
	cornice.anchor_bottom = 1.0
	cornice.anchor_right = 0.42
	cornice.offset_left = 40
	cornice.offset_top = 40
	cornice.offset_bottom = -40
	cornice.offset_right = -10
	cornice.add_theme_stylebox_override("panel", ZTema.riquadro(ZTema.TERRA_ROSA, ZTema.INCHIOSTRO, 3, 4, 0))
	radice.add_child(cornice)
	var copertina := TextureRect.new()
	copertina.texture = load("res://assets/ui/copertina.jpg")
	copertina.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	copertina.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	copertina.clip_contents = true
	cornice.add_child(copertina)
	# Colonna destra.
	var scroll := ScrollContainer.new()
	scroll.anchor_left = 0.42
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 30
	scroll.offset_right = -40
	scroll.offset_top = 36
	scroll.offset_bottom = -30
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	radice.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 14)
	scroll.add_child(v)
	var logo := ZTema.etichetta("ZARGO'S\nLORDS", 92, ZTema.AVORIO, ZTema.titolo)
	logo.add_theme_constant_override("line_spacing", -34)
	v.add_child(logo)
	v.add_child(ZTema.etichetta("duelli magici per il potere mondiale", 20, ZTema.TERRA_ROSA, ZTema.testo_forte))
	var intro := ZTema.etichetta("Venticinque mesi, quattro popoli, un solo vincitore: chi controllerà più città alla fine dell'Anno di Zargo.", 16, Color(ZTema.AVORIO, 0.8))
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(intro)
	var griglia := GridContainer.new()
	griglia.columns = 2
	griglia.add_theme_constant_override("h_separation", 12)
	griglia.add_theme_constant_override("v_separation", 12)
	for p in ZRegole.POPOLI:
		griglia.add_child(_scheda_popolo(p))
	v.add_child(griglia)
	var nota := ZTema.etichetta("Con due popoli ciascuno riceve due continenti; con tre o quattro si stringono (e si tradiscono) alleanze.", 13, Color(ZTema.AVORIO, 0.6))
	nota.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(nota)
	var azioni := HBoxContainer.new()
	azioni.add_theme_constant_override("separation", 12)
	btn_nuova = ZTema.pulsante_forte("NUOVA PARTITA", _nuova, 26)
	btn_nuova.custom_minimum_size = Vector2(250, 56)
	azioni.add_child(btn_nuova)
	btn_continua = ZTema.pulsante("Continua la partita salvata", func(): continua.emit(), 16)
	btn_continua.visible = FileAccess.file_exists("user://partita.json")
	azioni.add_child(btn_continua)
	v.add_child(azioni)
	var riga2 := HBoxContainer.new()
	riga2.add_child(ZTema.pulsante("Gioca online", _mostra_online, 15))
	riga2.add_child(ZTema.pulsante("Regole in breve", func(): regole.emit(), 15))
	v.add_child(riga2)
	box_online = VBoxContainer.new()
	box_online.visible = false
	v.add_child(box_online)
	var pannello := PanelContainer.new()
	pannello.add_theme_stylebox_override("panel", ZTema.riquadro(ZTema.AVORIO, ZTema.CUOIO, 2, 8, 14))
	box_online.add_child(pannello)
	var vo := VBoxContainer.new()
	pannello.add_child(vo)
	vo.add_child(ZTema.titoletto("Partita online", 20))
	var spiega := ZTema.etichetta("Chi crea la stanza sceglie sopra i popoli: «Io», «Giocatore remoto» o «IA». Gli altri giocatori entrano con il codice e ricevono il primo popolo remoto libero.", 13)
	spiega.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vo.add_child(spiega)
	campo_url = LineEdit.new()
	campo_url.placeholder_text = "Database URL Firebase (https://…firebaseio.com)"
	campo_chiave = LineEdit.new()
	campo_chiave.placeholder_text = "Web API key"
	campo_chiave.secret = true
	vo.add_child(campo_url)
	vo.add_child(campo_chiave)
	var cfg := _config_firebase()
	if not cfg.is_empty():
		campo_url.text = cfg.get("database_url", "")
		campo_chiave.text = cfg.get("api_key", "")
		campo_url.visible = false
		campo_chiave.visible = false
	var ho := HBoxContainer.new()
	ho.add_child(ZTema.pulsante("Crea stanza", func(): crea_stanza.emit(_controllo(), campo_url.text, campo_chiave.text)))
	campo_codice = LineEdit.new()
	campo_codice.placeholder_text = "Codice stanza"
	campo_codice.custom_minimum_size = Vector2(150, 0)
	ho.add_child(campo_codice)
	ho.add_child(ZTema.pulsante("Entra", func(): entra_stanza.emit(campo_codice.text, campo_url.text, campo_chiave.text)))
	vo.add_child(ho)
	stato_online = ZTema.etichetta("", 14, ZTema.CUOIO, ZTema.testo_forte)
	stato_online.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vo.add_child(stato_online)
	var crediti := ZTema.etichetta("Gioco originale: Zargo's Lords, International Team. Versione digitale amatoriale.", 12, Color(ZTema.AVORIO, 0.45))
	v.add_child(crediti)

func _scheda_popolo(p: String) -> Control:
	var c := PanelContainer.new()
	c.custom_minimum_size = Vector2(250, 0)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.add_theme_stylebox_override("panel", ZTema.riquadro(ZTema.AVORIO, ZRegole.COLORI[p].darkened(0.3), 3, 8, 10))
	var h := HBoxContainer.new()
	c.add_child(h)
	var img := TextureRect.new()
	img.texture = ZTema.texture_pedina(p, "signore")
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.custom_minimum_size = Vector2(76, 76)
	h.add_child(img)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(ZTema.titoletto(p, 24, ZRegole.COLORI[p].darkened(0.45)))
	var sel := OptionButton.new()
	for s in SCELTE:
		sel.add_item(s)
	sel.selected = 0 if p == "Cavalieri" else 1
	sel.focus_mode = Control.FOCUS_NONE
	v.add_child(sel)
	h.add_child(v)
	selettori[p] = sel
	return c

func _mostra_online() -> void:
	online_attivo = not box_online.visible
	box_online.visible = online_attivo
	for p in selettori:
		var sel: OptionButton = selettori[p]
		var prima := sel.selected
		sel.clear()
		for s in (SCELTE_ONLINE if online_attivo else SCELTE):
			sel.add_item(s)
		if online_attivo:
			sel.selected = [0, 2, 3][prima] if prima < 3 else 2
		else:
			sel.selected = [0, 0, 1, 2][prima] if prima < 4 else 1

func _config_firebase() -> Dictionary:
	if not FileAccess.file_exists("res://firebase_config.json"):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://firebase_config.json"))
	return d if d is Dictionary else {}

func _controllo() -> Dictionary:
	var out := {}
	for p in selettori:
		var testo: String = selettori[p].get_item_text(selettori[p].selected)
		match testo:
			"Giocatore", "Io": out[p] = "umano"
			"Giocatore remoto": out[p] = "remoto"
			"IA": out[p] = "ia"
	return out

func _nuova() -> void:
	var c := _controllo()
	if c.size() < 2:
		stato("Servono almeno due popoli in gioco.")
		return
	avvia.emit(c)

func stato(testo: String) -> void:
	stato_online.text = testo
	if not box_online.visible:
		box_online.visible = true
