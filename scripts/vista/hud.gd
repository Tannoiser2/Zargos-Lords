class_name ZHud
extends CanvasLayer
## Interfaccia di gioco: barra del calendario, pannello laterale, comandi.

signal fase_premuta
signal menu_premuto
signal opzione_premuta(chiave: String)
signal regole_premute
signal griglia_premuta
signal vista_ruotata(gradi: float)

const LARGHEZZA_PANNELLO := 360

var radice: Control
var calendario: ZWidget.Calendario
var box_ritratto_turno: HBoxContainer
var _ritratto_turno := ""

func imposta_ritratto_turno(p: String) -> void:
	var k := p + ZTema.grafica
	if k == _ritratto_turno:
		return
	_ritratto_turno = k
	for c in box_ritratto_turno.get_children():
		c.queue_free()
	if p != "":
		box_ritratto_turno.add_child(ZTema.ritratto(p, 44, true))
var lbl_turno: Label
var lbl_fase: Label
var lbl_mese: Label
var box_popoli: VBoxContainer
var box_selezione: VBoxContainer
var cronaca: RichTextLabel
var suggerimento: Label
var btn_fase: Button
var vassoio: PanelContainer
var box_vassoio: HBoxContainer
var popup: PanelContainer
var popup_dado: ZWidget.Dado
var popup_titolo: Label
var popup_testo: Label
var popup_spicchio: ZWidget.Spicchio
var _timer_popup: SceneTreeTimer
var finestra: PanelContainer
var box_finestra: VBoxContainer
var velo: ColorRect
var attesa: Label
var banner: PanelContainer
var box_banner: HBoxContainer
var box_scontro: PanelContainer
var scroll_selezione: ScrollContainer
var pannello_ruota: PanelContainer
var ruota: ZRuota
var ruota_titolo: Label
var ruota_testo: Label

func _ready() -> void:
	layer = 5
	radice = Control.new()
	radice.set_anchors_preset(Control.PRESET_FULL_RECT)
	radice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radice.theme = ZTema.crea()
	add_child(radice)
	_barra_alta()
	_pannello_laterale()
	_barra_bassa()
	_popup()
	_banner()
	_pannello_ruota()
	_finestra()

func _barra_alta() -> void:
	var barra := PanelContainer.new()
	barra.set_anchors_preset(Control.PRESET_TOP_WIDE)
	barra.offset_bottom = 58
	barra.add_theme_stylebox_override("panel", ZTema.riquadro(ZTema.CUOIO, ZTema.CUOIO_SCURO, 0, 0, 14))
	radice.add_child(barra)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	barra.add_child(h)
	var cal_box := VBoxContainer.new()
	cal_box.add_theme_constant_override("separation", 0)
	cal_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl_mese = ZTema.etichetta("IL CALENDARIO · MESE 1 DI 25", 11, Color(ZTema.AVORIO, 0.7), ZTema.testo_forte)
	cal_box.add_child(lbl_mese)
	calendario = ZWidget.Calendario.new()
	cal_box.add_child(calendario)
	h.add_child(cal_box)
	var turno_box := HBoxContainer.new()
	turno_box.add_theme_constant_override("separation", 10)
	box_ritratto_turno = HBoxContainer.new()
	box_ritratto_turno.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	turno_box.add_child(box_ritratto_turno)
	var tb := VBoxContainer.new()
	tb.add_theme_constant_override("separation", -2)
	tb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl_turno = ZTema.etichetta("", 20, ZTema.AVORIO, ZTema.titolo)
	lbl_turno.clip_text = true
	lbl_turno.custom_minimum_size = Vector2(150, 0)
	turno_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_fase = ZTema.etichetta("", 12, Color(ZTema.AVORIO, 0.75), ZTema.testo_forte)
	lbl_fase.clip_text = true
	tb.add_child(lbl_turno)
	tb.add_child(lbl_fase)
	turno_box.add_child(tb)
	h.add_child(turno_box)
	# Scelte grafiche, sempre a portata di mano.
	var opz := HBoxContainer.new()
	opz.add_theme_constant_override("separation", 3)
	for k in ["grafica", "rilievi", "risoluzione", "mappa"]:
		var b := ZTema.pulsante("", func(): opzione_premuta.emit(k), 11)
		b.custom_minimum_size = Vector2(0, 34)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pulsanti_opzioni[k] = b
		opz.add_child(b)
	h.add_child(opz)
	var icone := HBoxContainer.new()
	icone.add_theme_constant_override("separation", 6)
	icone.add_child(ZWidget.Icona.new("griglia", "Reticolo degli esagoni (G)", func(): griglia_premuta.emit()))
	icone.add_child(ZWidget.Icona.new("aiuto", "Regole in breve", func(): regole_premute.emit()))
	icone.add_child(ZWidget.Icona.new("casa", "Torna al menu principale (la partita è salvata)", func(): menu_premuto.emit()))
	h.add_child(icone)

var pulsanti_opzioni := {}

## Testi dei pulsanti delle scelte grafiche nella barra in alto.
func aggiorna_opzioni(grafica: String, risoluzione: String, mappa: String) -> void:
	if pulsanti_opzioni.is_empty():
		return
	var b: Button = pulsanti_opzioni.grafica
	b.text = "Pedine: " + {"originale": "1979", "nuova": "nuove", "3d": "3D"}.get(grafica, grafica)
	b.tooltip_text = "Cambia la grafica delle pedine: originali 1979, nuove, miniature 3D"
	b = pulsanti_opzioni.rilievi
	b.text = "Rilievi: " + ("sì" if ZTavolo.rilievi else "no")
	b.tooltip_text = "Montagne, boschi, gorghi e ponti di nuvole in 3D sul tavolo"
	b = pulsanti_opzioni.risoluzione
	b.text = "Scontri: " + ("ruota" if risoluzione == "ruota" else "riquadro")
	b.tooltip_text = "Risolvi scontri e tiri con la ruota originale o con il riquadro"
	b = pulsanti_opzioni.mappa
	b.text = "Mappa: " + ("1979" if mappa == "originale" else "nuova")
	b.tooltip_text = "Mappa nuova (Tabletop Simulator) o tabellone originale del 1979"

func _pannello_laterale() -> void:
	var p := PanelContainer.new()
	p.anchor_left = 1.0
	p.anchor_right = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = -LARGHEZZA_PANNELLO - 12
	p.offset_right = -12
	p.offset_top = 70
	p.offset_bottom = -12
	p.add_theme_stylebox_override("panel", ZTema.riquadro(ZTema.AVORIO, ZTema.CUOIO_SCURO, 3, 8, 14))
	radice.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(ZTema.titoletto("I popoli di Zargo", 18))
	box_popoli = VBoxContainer.new()
	box_popoli.add_theme_constant_override("separation", 4)
	v.add_child(box_popoli)
	v.add_child(HSeparator.new())
	# Scheda dello scontro in corso: chi attacca e chi difende.
	box_scontro = PanelContainer.new()
	box_scontro.add_theme_stylebox_override("panel", ZTema.riquadro(ZTema.CUOIO_SCURO, ZTema.OCRA, 2, 8, 10))
	box_scontro.visible = false
	v.add_child(box_scontro)
	var scroll_sel := ScrollContainer.new()
	scroll_selezione = scroll_sel
	scroll_sel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_sel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_sel.size_flags_stretch_ratio = 1.4
	box_selezione = VBoxContainer.new()
	box_selezione.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_sel.add_child(box_selezione)
	v.add_child(scroll_sel)
	v.add_child(HSeparator.new())
	v.add_child(ZTema.titoletto("Cronaca", 16))
	cronaca = RichTextLabel.new()
	cronaca.bbcode_enabled = true
	cronaca.scroll_following = true
	cronaca.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cronaca.size_flags_stretch_ratio = 0.7
	cronaca.add_theme_font_size_override("normal_font_size", 13)
	cronaca.add_theme_font_size_override("bold_font_size", 13)
	cronaca.add_theme_color_override("default_color", Color(ZTema.INCHIOSTRO, 0.85))
	v.add_child(cronaca)

func _barra_bassa() -> void:
	var box := PanelContainer.new()
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.anchor_right = 1.0
	box.offset_left = 12
	box.offset_right = -LARGHEZZA_PANNELLO - 24
	box.offset_top = -64
	box.offset_bottom = -12
	box.add_theme_stylebox_override("panel", ZTema.riquadro(Color(ZTema.AVORIO, 0.94), ZTema.CUOIO_SCURO, 2, 8, 12))
	radice.add_child(box)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	box.add_child(h)
	suggerimento = ZTema.etichetta("", 15, ZTema.INCHIOSTRO)
	suggerimento.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	suggerimento.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	suggerimento.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(suggerimento)
	attesa = ZTema.etichetta("", 14, ZTema.CUOIO, ZTema.testo_forte)
	h.add_child(attesa)
	btn_fase = ZTema.pulsante_forte("FINE MOVIMENTO  ›", func(): fase_premuta.emit(), 20)
	btn_fase.custom_minimum_size = Vector2(250, 0)
	h.add_child(btn_fase)
	# Vassoio delle pedine da schierare, sopra la barra.
	vassoio = PanelContainer.new()
	vassoio.anchor_top = 1.0
	vassoio.anchor_bottom = 1.0
	vassoio.offset_left = 12
	vassoio.offset_top = -170
	vassoio.offset_bottom = -74
	vassoio.add_theme_stylebox_override("panel", ZTema.riquadro(Color(ZTema.CUOIO, 0.95), ZTema.CUOIO_SCURO, 2, 8, 10))
	radice.add_child(vassoio)
	box_vassoio = HBoxContainer.new()
	box_vassoio.add_theme_constant_override("separation", 6)
	vassoio.add_child(box_vassoio)
	vassoio.visible = false

func _popup() -> void:
	popup = PanelContainer.new()
	popup.anchor_left = 1.0
	popup.anchor_right = 1.0
	popup.anchor_top = 1.0
	popup.anchor_bottom = 1.0
	popup.offset_right = -LARGHEZZA_PANNELLO - 24
	popup.offset_bottom = -70
	popup.offset_left = popup.offset_right - 470
	popup.offset_top = popup.offset_bottom - 90
	popup.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	popup.grow_vertical = Control.GROW_DIRECTION_BEGIN
	popup.add_theme_stylebox_override("panel", ZTema.riquadro(ZTema.CUOIO, ZTema.CUOIO_SCURO, 3, 12, 16))
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	radice.add_child(popup)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	popup.add_child(h)
	popup_dado = ZWidget.Dado.new(72)
	popup_dado.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(popup_dado)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	popup_titolo = ZTema.etichetta("", 26, ZTema.AVORIO, ZTema.titolo)
	popup_testo = ZTema.etichetta("", 14, Color(ZTema.AVORIO, 0.9))
	popup_testo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	popup_testo.custom_minimum_size = Vector2(320, 0)
	popup_spicchio = ZWidget.Spicchio.new()
	v.add_child(popup_titolo)
	v.add_child(popup_testo)
	v.add_child(popup_spicchio)
	h.add_child(v)
	popup.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			popup.visible = false)
	popup.visible = false

func mostra_dado(dado: int, titolo: String, testo: String, differenza := -999) -> void:
	popup.visible = true
	popup_dado.visible = dado > 0
	popup_dado.imposta(dado)
	popup_titolo.text = titolo
	popup_testo.text = testo
	popup_spicchio.visible = differenza > -999
	if differenza > -999:
		popup_spicchio.imposta(differenza, dado)
	popup.modulate.a = 0.0
	var tw := popup.create_tween()
	tw.tween_property(popup, "modulate:a", 1.0, 0.15)
	var t := get_tree().create_timer(3.2)
	_timer_popup = t
	t.timeout.connect(func():
		if _timer_popup == t:
			var tw2 := popup.create_tween()
			tw2.tween_property(popup, "modulate:a", 0.0, 0.3)
			tw2.tween_callback(func(): popup.visible = false))

# --- Scontro: chi combatte contro chi ------------------------------------------------

func _banner() -> void:
	banner = PanelContainer.new()
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.offset_top = 70
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.add_theme_stylebox_override("panel", ZTema.riquadro(Color(ZTema.CUOIO_SCURO, 0.96), ZTema.OCRA, 2, 10, 12))
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radice.add_child(banner)
	box_banner = HBoxContainer.new()
	box_banner.add_theme_constant_override("separation", 14)
	box_banner.alignment = BoxContainer.ALIGNMENT_CENTER
	banner.add_child(box_banner)
	banner.visible = false

func _schieramento_banner(popolo: String, pezzi: Array, didascalia: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var titolo := ZTema.etichetta(popolo.to_upper(), 22, ZRegole.COLORI.get(popolo, ZTema.AVORIO).lightened(0.25), ZTema.titolo)
	titolo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(titolo)
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 2)
	h.alignment = FlowContainer.ALIGNMENT_CENTER
	for t in pezzi.slice(0, 6):
		var img := TextureRect.new()
		img.texture = t
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.custom_minimum_size = Vector2(46, 46)
		h.add_child(img)
	v.add_child(h)
	var d := ZTema.etichetta(didascalia, 13, Color(ZTema.AVORIO, 0.8), ZTema.testo_forte)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(d)
	return v

## Scheda dello scontro nel pannello a destra, con le pedine dei due schieramenti.
func mostra_banner(pa: String, att: Array, forza_a: int, pd: String, dif: Array, forza_d: int, tipo := "ATTACCANO", testo_a := "", testo_d := "") -> void:
	for c in box_scontro.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var intest := ZTema.etichetta(tipo, 12, ZTema.OCRA, ZTema.testo_forte)
	intest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(intest)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var sa := _schieramento_banner(pa, att, testo_a if testo_a != "" else "attacco %d" % forza_a)
	sa.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sa)
	var vs := ZTema.etichetta("VS", 30, ZTema.OCRA, ZTema.titolo)
	vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(vs)
	var sd := _schieramento_banner(pd, dif, testo_d if testo_d != "" else (("difesa %d" % forza_d) if forza_d >= 0 else "guarnigione coperta"))
	sd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sd)
	v.add_child(h)
	_box_esito = VBoxContainer.new()
	_box_esito.add_theme_constant_override("separation", 0)
	v.add_child(_box_esito)
	box_scontro.add_child(v)
	box_scontro.visible = true
	scroll_selezione.visible = false

var _box_esito: VBoxContainer

## Carta di una magia con il suo esito, nel riquadro degli scontri.
func mostra_carta(tex: Texture2D, titolo: String, testo: String) -> void:
	for c in box_scontro.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var img := TextureRect.new()
	img.texture = tex
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.custom_minimum_size = Vector2(0, 230)
	v.add_child(img)
	_box_esito = VBoxContainer.new()
	v.add_child(_box_esito)
	box_scontro.add_child(v)
	box_scontro.visible = true
	scroll_selezione.visible = false
	esito_banner(titolo, testo)

## Esito scritto sotto la scheda dello scontro, nello stesso stile.
func esito_banner(titolo: String, testo: String) -> void:
	if _box_esito == null or not is_instance_valid(_box_esito):
		return
	for c in _box_esito.get_children():
		c.queue_free()
	var sep := ColorRect.new()
	sep.color = Color(ZTema.OCRA, 0.45)
	sep.custom_minimum_size = Vector2(0, 2)
	_box_esito.add_child(sep)
	var spazio := Control.new()
	spazio.custom_minimum_size = Vector2(0, 4)
	_box_esito.add_child(spazio)
	var t := ZTema.etichetta(titolo, 21, ZTema.AVORIO, ZTema.titolo)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box_esito.add_child(t)
	var d := ZTema.etichetta(testo, 13, Color(ZTema.AVORIO, 0.85))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box_esito.add_child(d)

func nascondi_banner() -> void:
	box_scontro.visible = false
	scroll_selezione.visible = true

# --- La ruota originale -------------------------------------------------------------

func _pannello_ruota() -> void:
	pannello_ruota = PanelContainer.new()
	pannello_ruota.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	pannello_ruota.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radice.add_child(pannello_ruota)
	# Dietro la barra di stato: la ruota ne esce come da sotto il tavolo.
	radice.move_child(pannello_ruota, 0)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	h.alignment = BoxContainer.ALIGNMENT_END
	pannello_ruota.add_child(h)
	var didascalia := PanelContainer.new()
	didascalia.add_theme_stylebox_override("panel", ZTema.riquadro(ZTema.CUOIO_SCURO, ZTema.OCRA, 2, 6, 12))
	didascalia.size_flags_vertical = Control.SIZE_SHRINK_END
	didascalia.custom_minimum_size = Vector2(250, 0)
	var vd := VBoxContainer.new()
	vd.add_theme_constant_override("separation", 2)
	ruota_titolo = ZTema.etichetta("", 22, ZTema.AVORIO, ZTema.titolo)
	ruota_titolo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ruota_testo = ZTema.etichetta("", 13, Color(ZTema.AVORIO, 0.85))
	ruota_testo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vd.add_child(ruota_titolo)
	vd.add_child(ruota_testo)
	didascalia.add_child(vd)
	didascalia.visible = false   # l'esito si legge nella scheda dello scontro a destra
	h.add_child(didascalia)
	ruota = ZRuota.new()
	ruota.size_flags_vertical = Control.SIZE_SHRINK_END
	h.add_child(ruota)
	pannello_ruota.visible = false

## La ruota sale da sotto la barra di stato, accanto a "fine mossa", gira fino
## al dado, evidenzia l'esito e poi ridiscende. Si attende con `await`.
func mostra_ruota(dado: int, fascia: int, titolo: String, testo: String, intro: String, tabella := "combattimento", al_risultato: Callable = Callable()) -> void:
	ruota.usa(tabella)
	var vp := radice.size
	ruota.scala = clampf((vp.y - 330.0) / (1024.0 * 0.53), 0.42, 0.55)
	ruota._ridimensiona()
	ruota.rotazione = ruota.angolo_per_dado(randi_range(1, 6)) - 200.0
	ruota.fascia_evidenziata = -1
	ruota.queue_redraw()
	ruota_titolo.text = "IL DADO RUOTA…"
	ruota_testo.text = intro
	pannello_ruota.visible = true
	pannello_ruota.reset_size()
	var dim := pannello_ruota.get_combined_minimum_size()
	pannello_ruota.size = dim
	var destra := vp.x - LARGHEZZA_PANNELLO - 24.0
	var alto_barra := vp.y - 64.0
	var su := alto_barra - dim.y + 6.0
	var giu := vp.y + 4.0
	pannello_ruota.position = Vector2(destra - dim.x, giu)
	var tw := create_tween()
	tw.tween_property(pannello_ruota, "position:y", su, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished
	ruota.gira(dado, fascia, 1.7)
	await ruota.finita
	if al_risultato.is_valid():
		al_risultato.call()
	ruota_titolo.text = titolo
	ruota_testo.text = testo
	await get_tree().create_timer(2.0).timeout
	var tw2 := create_tween()
	tw2.tween_property(pannello_ruota, "position:y", giu, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tw2.finished
	pannello_ruota.visible = false

func _finestra() -> void:
	velo = ColorRect.new()
	velo.color = Color(0.08, 0.04, 0.02, 0.55)
	velo.set_anchors_preset(Control.PRESET_FULL_RECT)
	velo.visible = false
	radice.add_child(velo)
	finestra = PanelContainer.new()
	finestra.set_anchors_preset(Control.PRESET_CENTER)
	finestra.grow_horizontal = Control.GROW_DIRECTION_BOTH
	finestra.grow_vertical = Control.GROW_DIRECTION_BOTH
	finestra.add_theme_stylebox_override("panel", ZTema.riquadro(ZTema.AVORIO, ZTema.CUOIO, 4, 10, 22))
	finestra.visible = false
	radice.add_child(finestra)
	box_finestra = VBoxContainer.new()
	box_finestra.add_theme_constant_override("separation", 12)
	finestra.add_child(box_finestra)

## Finestra modale con titolo, testo (BBCode) e pulsanti [testo, Callable].
func apri_finestra(titolo: String, testo: String, pulsanti: Array, larghezza := 520, altezza := 0) -> void:
	for c in box_finestra.get_children():
		c.queue_free()
	box_finestra.add_child(ZTema.titoletto(titolo, 30))
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = altezza == 0
	rt.custom_minimum_size = Vector2(larghezza, altezza)
	rt.text = testo
	rt.add_theme_font_size_override("normal_font_size", 16)
	rt.add_theme_font_size_override("bold_font_size", 16)
	box_finestra.add_child(rt)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_END
	for i in pulsanti.size():
		var cb: Callable = pulsanti[i][1]
		var azione := func():
			chiudi_finestra()
			if cb.is_valid():
				cb.call()
		var ultimo := i == pulsanti.size() - 1
		var b := ZTema.pulsante_forte(pulsanti[i][0], azione, 18) if ultimo else ZTema.pulsante(pulsanti[i][0], azione, 16)
		h.add_child(b)
	box_finestra.add_child(h)
	velo.visible = true
	finestra.visible = true
	finestra.reset_size()
	finestra.position = (radice.size - finestra.size) * 0.5

func chiudi_finestra() -> void:
	velo.visible = false
	finestra.visible = false

func finestra_aperta() -> bool:
	return finestra.visible

func scrivi_cronaca(righe: Array) -> void:
	var testo := ""
	for r in righe:
		var s := String(r)
		if s.begins_with("—"):
			testo += "\n[b][color=#5b3422]%s[/color][/b]\n" % s
		elif s.begins_with("Muovono"):
			testo += "[b]%s[/b]\n" % s
		else:
			testo += "• %s\n" % s
	cronaca.text = testo

func pulisci_selezione() -> void:
	for c in box_selezione.get_children():
		c.queue_free()
