extends Node3D

const BOARD_SIZE := Vector2(16.0, 10.889)
const HEX_RADIUS := 0.245

var state := ZargosGameState.new()
var board_data := ZargosBoardData.new()
var camera: Camera3D
var camera_rig: Node3D
var camera_pitch: Node3D
var selected: CardboardUnit
var combat_group: Array[CardboardUnit] = []
var status_label: Label
var details_label: Label
var score_label: Label
var event_label: Label
var ai_button: CheckButton
var escort_button: Button
var special_button: Button
var deployment_button: Button
var grid_overlay: MeshInstance3D
var movement_overlay: MeshInstance3D
var rng := RandomNumberGenerator.new()
var orbiting := false
var panning := false
var orbit_yaw := 0.0
var orbit_pitch := -1.18
var camera_distance := 15.2
var ai_enabled := false
var ai_running := false
var human_faction: StringName = &"Cavalieri"
var faction_controllers: Dictionary = {}
var faction_controller_selectors: Dictionary = {}
var setup_layer: CanvasLayer
var reappearing_unit: CardboardUnit
var deployment_mode := false
var deployment_city: CardboardCity
var territory_owners: Dictionary = {}
var online: FirebaseOnline
var online_mode := false
var online_is_host := false
var online_host_faction: StringName = &""
var applying_remote_snapshot := false
var online_pending_action := ""
var online_player_count := 2
var online_human_index := 0
var firebase_url_input: LineEdit
var firebase_key_input: LineEdit
var room_code_input: LineEdit

func _ready() -> void:
	rng.randomize()
	online = FirebaseOnline.new()
	add_child(online)
	online.authenticated.connect(_on_online_authenticated)
	online.room_created.connect(_on_room_created)
	online.room_joined.connect(_on_room_joined)
	online.snapshot_received.connect(_apply_online_snapshot)
	online.online_error.connect(func(message: String): _show_event(message))
	_build_environment()
	_build_board()
	_build_hex_overlay()
	_build_movement_overlay()
	_build_camera()
	_build_lights()
	_build_ui()
	state.state_changed.connect(_refresh_ui)
	state.log_message.connect(_show_event)
	_refresh_ui()
	_build_setup_screen()

func _build_environment() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("160f0b")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e1b879")
	env.ambient_light_energy = 0.52
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)

func _build_board() -> void:
	var board := StaticBody3D.new()
	board.name = "Board"
	board.set_meta("is_board", true)
	add_child(board)

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(BOARD_SIZE.x, 0.22, BOARD_SIZE.y)
	var support_material := StandardMaterial3D.new()
	support_material.albedo_color = Color("6b4329")
	support_material.roughness = 0.78
	box.material = support_material
	mesh_instance.mesh = box
	board.add_child(mesh_instance)

	# BoxMesh ripartisce le coordinate UV fra le sei facce e sulla faccia
	# superiore mostrerebbe soltanto una porzione della scansione. La mappa
	# originale viene quindi posata integralmente su un piano dedicato.
	var map_face := MeshInstance3D.new()
	map_face.name = "OriginalMapFace"
	var map_plane := PlaneMesh.new()
	map_plane.size = BOARD_SIZE
	var map_material := StandardMaterial3D.new()
	map_material.albedo_texture = load("res://assets/board/zargo_board_original.jpg")
	map_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	map_material.roughness = 0.78
	map_plane.material = map_material
	map_face.mesh = map_plane
	map_face.position.y = 0.112
	board.add_child(map_face)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(BOARD_SIZE.x, 0.24, BOARD_SIZE.y)
	collision.shape = shape
	board.add_child(collision)

	var rim := MeshInstance3D.new()
	var rim_mesh := BoxMesh.new()
	rim_mesh.size = Vector3(BOARD_SIZE.x + 0.36, 0.16, BOARD_SIZE.y + 0.36)
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color("3b2013")
	rim_mat.metallic = 0.08
	rim_mat.roughness = 0.62
	rim_mesh.material = rim_mat
	rim.mesh = rim_mesh
	rim.position.y = -0.17
	add_child(rim)

func _build_hex_overlay() -> void:
	grid_overlay = MeshInstance3D.new()
	grid_overlay.name = "HexGridOverlay"
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.94, 0.72, 0.28, 0.42)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for column in range(ZargosRules.BOARD_COLUMNS):
		for row in range(ZargosRules.BOARD_ROWS):
			var center := hex_to_world(Vector2i(column, row)) + Vector3(0, 0.125, 0)
			for side in range(6):
				var a := deg_to_rad(60.0 * side)
				var b := deg_to_rad(60.0 * (side + 1))
				mesh.surface_add_vertex(center + Vector3(cos(a) * HEX_RADIUS, 0, sin(a) * HEX_RADIUS))
				mesh.surface_add_vertex(center + Vector3(cos(b) * HEX_RADIUS, 0, sin(b) * HEX_RADIUS))
	mesh.surface_end()
	grid_overlay.mesh = mesh
	grid_overlay.visible = false
	add_child(grid_overlay)

func _build_movement_overlay() -> void:
	movement_overlay = MeshInstance3D.new()
	movement_overlay.name = "MovementOverlay"
	add_child(movement_overlay)

func _show_reachable_hexes(unit: CardboardUnit) -> void:
	movement_overlay.mesh = null
	if state.phase != ZargosRules.Phase.MOVEMENT or unit.faction != state.active_faction() or unit.moved:
		return
	var flying := unit.ability == "Volo"
	var reachable := board_data.reachable_hexes(
		unit.hex,
		unit.movement,
		flying,
		func(hex: Vector2i): return _movement_blocked(hex, unit.faction, flying),
		func(hex: Vector2i): return _in_enemy_zone_of_influence(hex, unit.faction) and not flying
	)
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.95, 0.68, 0.16, 0.30)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for hex: Vector2i in reachable:
		if hex == unit.hex or (_unit_at(hex) and not _can_form_escort(unit, hex)):
			continue
		var center := hex_to_world(hex) + Vector3(0, 0.132, 0)
		for side in range(6):
			var a := deg_to_rad(60.0 * side)
			var b := deg_to_rad(60.0 * (side + 1))
			mesh.surface_add_vertex(center)
			mesh.surface_add_vertex(center + Vector3(cos(a) * HEX_RADIUS * 0.88, 0, sin(a) * HEX_RADIUS * 0.88))
			mesh.surface_add_vertex(center + Vector3(cos(b) * HEX_RADIUS * 0.88, 0, sin(b) * HEX_RADIUS * 0.88))
	mesh.surface_end()
	movement_overlay.mesh = mesh

func _build_camera() -> void:
	camera_rig = Node3D.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_pitch = Node3D.new()
	camera_rig.add_child(camera_pitch)
	camera = Camera3D.new()
	camera.fov = 48.0
	camera.near = 0.1
	camera.far = 80.0
	camera_pitch.add_child(camera)
	_update_camera()

func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -28, 0)
	sun.light_color = Color("ffd7a1")
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-5, 5, 4)
	fill.light_color = Color("8c9fd0")
	fill.light_energy = 2.0
	fill.omni_range = 18.0
	add_child(fill)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 18)
	panel.custom_minimum_size = Vector2(450, 164)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("23150fdd")
	style.border_color = Color("b98b42")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	panel.add_child(stack)
	var title := Label.new()
	title.text = "ZARGO'S LORDS"
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", Color("e4b656"))
	stack.add_child(title)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 18)
	stack.add_child(status_label)
	details_label = Label.new()
	details_label.text = "Seleziona una pedina attiva, poi un esagono di destinazione."
	details_label.add_theme_color_override("font_color", Color("dfd0b7"))
	stack.add_child(details_label)
	score_label = Label.new()
	score_label.add_theme_font_size_override("font_size", 14)
	score_label.add_theme_color_override("font_color", Color("cbb68f"))
	stack.add_child(score_label)
	var buttons := HFlowContainer.new()
	stack.add_child(buttons)
	var next := Button.new()
	next.text = "Fase successiva"
	next.pressed.connect(_on_next_phase)
	buttons.add_child(next)
	var battle := Button.new()
	battle.text = "Risolvi scontro"
	battle.pressed.connect(_on_resolve_battle)
	buttons.add_child(battle)
	escort_button = Button.new()
	escort_button.text = "Separa scorta"
	escort_button.visible = false
	escort_button.pressed.connect(_on_detach_escort)
	buttons.add_child(escort_button)
	special_button = Button.new()
	special_button.text = "Sparisci"
	special_button.visible = false
	special_button.pressed.connect(_on_monk_power)
	buttons.add_child(special_button)
	var reset_view := Button.new()
	reset_view.text = "Centra vista"
	reset_view.pressed.connect(_reset_camera)
	buttons.add_child(reset_view)
	var grid_button := CheckButton.new()
	grid_button.text = "Reticolo"
	grid_button.toggled.connect(func(enabled: bool):
		grid_overlay.visible = enabled
		_show_event("Reticolo di calibrazione %s." % ("visibile" if enabled else "nascosto"))
	)
	buttons.add_child(grid_button)
	ai_button = CheckButton.new()
	ai_button.text = "IA avversari"
	ai_button.toggled.connect(_on_ai_toggled)
	buttons.add_child(ai_button)
	deployment_button = Button.new()
	deployment_button.text = "Termina schieramento"
	deployment_button.visible = false
	deployment_button.pressed.connect(_finish_deployment)
	buttons.add_child(deployment_button)

	event_label = Label.new()
	event_label.position = Vector2(20, 194)
	event_label.size = Vector2(640, 32)
	event_label.add_theme_font_size_override("font_size", 16)
	event_label.add_theme_color_override("font_color", Color("f0c977"))
	layer.add_child(event_label)

	var help := Label.new()
	help.text = "Rotazione: tasto destro  •  Spostamento: tasto centrale  •  Zoom: rotella  •  Selezione: sinistro"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help.offset_top = -42
	help.offset_bottom = -12
	help.add_theme_color_override("font_color", Color("f3dfbd"))
	layer.add_child(help)

func _build_setup_screen() -> void:
	setup_layer = CanvasLayer.new()
	setup_layer.layer = 20
	add_child(setup_layer)
	var background := TextureRect.new()
	background.texture = load("res://zargos-illustration.jpg")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.modulate = Color(0.58, 0.45, 0.38, 1.0)
	setup_layer.add_child(background)
	var shade := ColorRect.new()
	shade.color = Color("100907b8")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	setup_layer.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 38)
	margin.add_theme_constant_override("margin_right", 38)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	setup_layer.add_child(margin)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("28160ee8")
	style.border_color = Color("d0a459")
	style.set_border_width_all(4)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	margin.add_child(panel)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)
	panel.add_child(columns)
	var brand := VBoxContainer.new()
	brand.custom_minimum_size.x = 330
	brand.add_theme_constant_override("separation", 8)
	columns.add_child(brand)
	var title := Label.new()
	title.text = "ZARGO'S LORDS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color("e7c174"))
	brand.add_child(title)
	var intro := Label.new()
	intro.text = "DUELLI MAGICI PER IL POTERE MONDIALE"
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.add_theme_font_size_override("font_size", 13)
	intro.add_theme_color_override("font_color", Color("cab58d"))
	brand.add_child(intro)
	var cover := TextureRect.new()
	cover.texture = load("res://zargos.jpg")
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cover.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	brand.add_child(cover)
	var edition := Label.new()
	edition.text = "INTERNATIONAL TEAM • EDIZIONE DIGITALE"
	edition.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	edition.add_theme_color_override("font_color", Color("b99d71"))
	brand.add_child(edition)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 11)
	scroll.add_child(stack)
	var setup_title := Label.new()
	setup_title.text = "CONSIGLIO DI GUERRA"
	setup_title.add_theme_font_size_override("font_size", 26)
	setup_title.add_theme_color_override("font_color", Color("f0d49b"))
	stack.add_child(setup_title)
	var instructions := Label.new()
	instructions.text = "Scegli chi guiderà ogni popolo. Con quattro IA puoi assistere alla guerra come osservatore."
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions.add_theme_color_override("font_color", Color("d6c6aa"))
	stack.add_child(instructions)
	var faction_grid := GridContainer.new()
	faction_grid.columns = 2
	faction_grid.add_theme_constant_override("h_separation", 10)
	faction_grid.add_theme_constant_override("v_separation", 10)
	stack.add_child(faction_grid)
	faction_controller_selectors.clear()
	for index in range(ZargosRules.FACTIONS.size()):
		faction_grid.add_child(_build_faction_card(ZargosRules.FACTIONS[index], index))

	var expansion := PanelContainer.new()
	var expansion_style := StyleBoxFlat.new()
	expansion_style.bg_color = Color("4a241fbb")
	expansion_style.border_color = Color("b45d4e")
	expansion_style.set_border_width_all(2)
	expansion_style.set_corner_radius_all(8)
	expansion_style.set_content_margin_all(10)
	expansion.add_theme_stylebox_override("panel", expansion_style)
	stack.add_child(expansion)
	var expansion_row := HBoxContainer.new()
	expansion_row.add_theme_constant_override("separation", 12)
	expansion.add_child(expansion_row)
	var expansion_cover := TextureRect.new()
	expansion_cover.texture = load("res://zargos2_copertina.jpg")
	expansion_cover.custom_minimum_size = Vector2(88, 100)
	expansion_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	expansion_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	expansion_row.add_child(expansion_cover)
	var expansion_copy := VBoxContainer.new()
	expansion_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	expansion_row.add_child(expansion_copy)
	var expansion_title := Label.new()
	expansion_title.text = "ZARGO'S LORDS 2 • ESPANSIONE"
	expansion_title.add_theme_color_override("font_color", Color("f0b096"))
	expansion_title.add_theme_font_size_override("font_size", 17)
	expansion_copy.add_child(expansion_title)
	var expansion_text := Label.new()
	expansion_text.text = "Amazzoni e Arachnidi • nuove arti magiche e nuove armate"
	expansion_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	expansion_text.add_theme_color_override("font_color", Color("d2b5a7"))
	expansion_copy.add_child(expansion_text)
	var expansion_toggle := CheckButton.new()
	expansion_toggle.text = "In preparazione — materiale acquisito"
	expansion_toggle.disabled = true
	expansion_copy.add_child(expansion_toggle)

	var online_toggle := CheckButton.new()
	online_toggle.text = "GIOCO ONLINE • Firebase"
	online_toggle.add_theme_font_size_override("font_size", 17)
	stack.add_child(online_toggle)
	var online_box := VBoxContainer.new()
	online_box.visible = false
	online_box.add_theme_constant_override("separation", 7)
	stack.add_child(online_box)
	online_toggle.toggled.connect(func(enabled: bool): online_box.visible = enabled)
	firebase_url_input = LineEdit.new()
	firebase_url_input.placeholder_text = "Realtime Database URL (https://…firebasedatabase.app)"
	online_box.add_child(firebase_url_input)
	firebase_key_input = LineEdit.new()
	firebase_key_input.placeholder_text = "Firebase Web API key"
	online_box.add_child(firebase_key_input)
	_load_firebase_defaults()
	room_code_input = LineEdit.new()
	room_code_input.placeholder_text = "Codice stanza (vuoto = generato automaticamente)"
	room_code_input.max_length = 8
	online_box.add_child(room_code_input)
	var online_buttons := HBoxContainer.new()
	online_box.add_child(online_buttons)
	var host := Button.new()
	host.text = "Crea stanza"
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.pressed.connect(func(): _begin_online_from_menu("create"))
	online_buttons.add_child(host)
	var join := Button.new()
	join.text = "Entra nella stanza"
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join.pressed.connect(func(): _begin_online_from_menu("join"))
	online_buttons.add_child(join)
	var start := Button.new()
	start.text = "INIZIA LA GUERRA"
	start.custom_minimum_size.y = 52
	start.add_theme_font_size_override("font_size", 20)
	start.pressed.connect(_start_menu_game)
	stack.add_child(start)

func _build_faction_card(faction: StringName, index: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(292, 128)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_style := StyleBoxFlat.new()
	var color: Color = ZargosRules.FACTION_COLORS[faction]
	card_style.bg_color = Color(color.r * 0.23, color.g * 0.23, color.b * 0.23, 0.94)
	card_style.border_color = color.lightened(0.12)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(8)
	card_style.set_content_margin_all(9)
	card.add_theme_stylebox_override("panel", card_style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var portrait := TextureRect.new()
	portrait.texture = CardboardUnit.COUNTER_TEXTURES[faction][&"Signore"]
	portrait.custom_minimum_size = Vector2(88, 88)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(portrait)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	var name_label := Label.new()
	name_label.text = String(faction).to_upper()
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", color.lightened(0.2))
	copy.add_child(name_label)
	var role := Label.new()
	role.text = ["Acciaio e visioni", "Fiamme e serpenti", "Ali e archi", "Illusione e sparizione"][index]
	role.add_theme_font_size_override("font_size", 12)
	role.add_theme_color_override("font_color", Color("d8c7aa"))
	copy.add_child(role)
	var selector := OptionButton.new()
	selector.add_item("Umano")
	selector.add_item("IA")
	selector.add_item("Esclusa")
	selector.select(0 if index == 0 else 1)
	copy.add_child(selector)
	faction_controller_selectors[faction] = selector
	return card

func _begin_online_from_menu(action: String) -> void:
	var active_count := 0
	var human_index := -1
	for index in range(ZargosRules.FACTIONS.size()):
		var selector: OptionButton = faction_controller_selectors[ZargosRules.FACTIONS[index]]
		if selector.selected != 2:
			active_count += 1
		if selector.selected == 0 and human_index < 0:
			human_index = index
	if active_count < 2 or human_index < 0:
		_show_event("Per il gioco online scegli almeno due popoli e almeno un giocatore Umano.")
		return
	_begin_online(action, active_count, human_index)

func _load_firebase_defaults() -> void:
	if not FileAccess.file_exists("res://firebase_config.json"):
		return
	var file := FileAccess.open("res://firebase_config.json", FileAccess.READ)
	if not file:
		return
	var config: Variant = JSON.parse_string(file.get_as_text())
	if config is Dictionary:
		firebase_url_input.text = String(config.get("database_url", ""))
		firebase_key_input.text = String(config.get("api_key", ""))

func _start_new_game(player_count: int, human_index: int) -> void:
	human_faction = ZargosRules.FACTIONS[human_index]
	var active: Array[StringName] = [human_faction]
	var cursor := (human_index + 1) % ZargosRules.FACTIONS.size()
	while active.size() < player_count:
		var candidate: StringName = ZargosRules.FACTIONS[cursor]
		if candidate not in active:
			active.append(candidate)
		cursor = (cursor + 1) % ZargosRules.FACTIONS.size()
	faction_controllers.clear()
	for faction in ZargosRules.FACTIONS:
		faction_controllers[faction] = "human" if faction == human_faction else ("ai" if faction in active else "off")
	_launch_game(active)

func _start_menu_game() -> void:
	var active: Array[StringName] = []
	var humans: Array[StringName] = []
	faction_controllers.clear()
	for faction in ZargosRules.FACTIONS:
		var selector: OptionButton = faction_controller_selectors[faction]
		var controller: String = ["human", "ai", "off"][selector.selected]
		faction_controllers[faction] = controller
		if controller != "off":
			active.append(faction)
		if controller == "human":
			humans.append(faction)
	if active.size() < 2:
		_show_event("Attiva almeno due popoli per iniziare la Guerra dei Signori.")
		return
	human_faction = humans[0] if not humans.is_empty() else &""
	_launch_game(active)

func _launch_game(active: Array[StringName]) -> void:
	state.configure(active)
	territory_owners = _territory_owners(active)
	_spawn_armies(territory_owners)
	_spawn_cities(territory_owners)
	var has_humans := faction_controllers.values().has("human")
	deployment_mode = has_humans
	ai_enabled = true
	ai_button.button_pressed = false
	ai_button.disabled = has_humans
	deployment_button.visible = has_humans
	setup_layer.queue_free()
	if has_humans:
		_show_event("Schieramento: seleziona le pedine e le città dei popoli umani.")
		details_label.text = "SCHIERAMENTO • Disponi le forze umane, poi premi Termina schieramento."
	else:
		ai_button.button_pressed = true
		_show_event("Modalità osservatore: quattro popoli IA combattono per Zargo.")
		details_label.text = "MODALITÀ OSSERVATORE • Tutti i popoli sono guidati dall’IA."
	_refresh_ui()

func _controller_for(faction: StringName) -> String:
	if online_mode:
		return "human" if faction == human_faction else "remote"
	return String(faction_controllers.get(faction, "ai"))

func _is_human_controller(faction: StringName) -> bool:
	return _controller_for(faction) == "human"

func _begin_online(action: String, player_count: int, human_index: int) -> void:
	if not online.configure(firebase_url_input.text, firebase_key_input.text):
		return
	online_pending_action = action
	online_player_count = player_count
	online_human_index = human_index
	_show_event("Connessione a Firebase…")
	online.authenticate_anonymously()

func _on_online_authenticated() -> void:
	var requested_code := FirebaseOnline.normalize_room_code(room_code_input.text)
	if online_pending_action == "create":
		online_mode = true
		online_is_host = true
		_start_new_game(online_player_count, online_human_index)
		online_host_faction = human_faction
		var code := requested_code if not requested_code.is_empty() else FirebaseOnline.generate_room_code()
		online.create_room(code, _make_online_snapshot())
	elif online_pending_action == "join":
		if requested_code.length() < 4:
			_show_event("Inserisci un codice stanza di almeno 4 caratteri.")
			return
		online.join_room(requested_code)

func _on_room_created(code: String, _data: Dictionary) -> void:
	online_pending_action = ""
	online.start_polling()
	_show_event("Stanza %s creata. Comunica questo codice agli altri giocatori." % code)

func _on_room_joined(code: String, data: Dictionary) -> void:
	online_pending_action = ""
	online_mode = true
	online_is_host = false
	if data.get("state") is Dictionary:
		var remote_state: Dictionary = data.state
		var requested_faction := String(ZargosRules.FACTIONS[online_human_index])
		var remote_factions: Array = remote_state.get("factions", [])
		var host_faction := String(remote_state.get("host_faction", ""))
		online_host_faction = StringName(host_faction)
		if requested_faction in remote_factions and requested_faction != host_faction:
			human_faction = StringName(requested_faction)
		else:
			for candidate in remote_factions:
				if String(candidate) != host_faction:
					human_faction = StringName(String(candidate))
					break
		_apply_online_snapshot(data.state)
	if is_instance_valid(setup_layer):
		setup_layer.queue_free()
	ai_enabled = false
	ai_button.button_pressed = false
	ai_button.disabled = true
	online.start_polling()
	_show_event("Collegato alla stanza %s come %s." % [code, human_faction])

func _territory_owners(active: Array[StringName]) -> Dictionary:
	var territories := ZargosRules.FACTIONS
	var owners := {}
	if active.size() == 2:
		owners[territories[0]] = active[0]
		owners[territories[2]] = active[0]
		owners[territories[1]] = active[1]
		owners[territories[3]] = active[1]
	else:
		for index in range(active.size()):
			owners[territories[index]] = active[index]
	return owners

func _spawn_armies(territory_owners: Dictionary) -> void:
	var homes := {
		&"Cavalieri": Vector2i(9, 6), &"Draghi": Vector2i(27, 6),
		&"Alati": Vector2i(9, 17), &"Monaci": Vector2i(27, 17)
	}
	for territory: StringName in territory_owners:
		var faction: StringName = territory_owners[territory]
		var base: Vector2i = homes[territory]
		var index := 0
		for unit_type in ZargosRules.UNIT_TYPES[faction].keys():
			var offset := Vector2i(index % 2, index / 2)
			_spawn_unit(faction, unit_type, base + offset)
			index += 1

func _spawn_cities(territory_owners: Dictionary) -> void:
	var locations := {
		&"Cavalieri": [Vector2i(6, 4), Vector2i(9, 4), Vector2i(12, 5), Vector2i(6, 8), Vector2i(10, 9), Vector2i(13, 8)],
		&"Draghi": [Vector2i(23, 4), Vector2i(27, 4), Vector2i(31, 5), Vector2i(23, 8), Vector2i(28, 8), Vector2i(31, 8)],
		&"Alati": [Vector2i(5, 16), Vector2i(8, 20), Vector2i(11, 20), Vector2i(6, 21), Vector2i(10, 16), Vector2i(14, 18)],
		&"Monaci": [Vector2i(22, 21), Vector2i(26, 21), Vector2i(31, 20), Vector2i(23, 16), Vector2i(27, 15), Vector2i(31, 17)],
	}
	for territory: StringName in territory_owners:
		var faction: StringName = territory_owners[territory]
		for city_hex in locations[territory]:
			var city := CardboardCity.new()
			add_child(city)
			city.setup(faction, city_hex)
			city.position = hex_to_world(city_hex) + Vector3(0, 0.19, 0)
			state.register_city(faction)

func _spawn_unit(faction: StringName, unit_type: StringName, hex: Vector2i) -> void:
	var unit := CardboardUnit.new()
	add_child(unit)
	unit.setup(faction, unit_type, hex)
	unit.position = hex_to_world(hex) + Vector3(0, 0.18, 0)

func _make_online_snapshot() -> Dictionary:
	var units: Array[CardboardUnit] = []
	var cities: Array[CardboardCity] = []
	for child in get_children():
		if child is CardboardUnit:
			units.append(child)
		elif child is CardboardCity:
			cities.append(child)
	var unit_ids := {}
	for index in range(units.size()):
		unit_ids[units[index]] = index
	var unit_data: Array[Dictionary] = []
	for unit in units:
		unit_data.append({
			"faction": String(unit.faction), "type": String(unit.unit_type),
			"x": unit.hex.x, "y": unit.hex.y, "moved": unit.moved, "acted": unit.acted,
			"hits": unit.ranged_hits, "visible": unit.visible, "vanished": unit.vanished,
			"vanished_month": unit.vanished_month, "vanish_x": unit.vanish_origin.x, "vanish_y": unit.vanish_origin.y,
			"facing": unit.facing_direction, "charge": unit.charge_ready, "charge_direction": unit.charge_direction,
			"guard_target": unit_ids.get(unit.guard_target, -1), "guard_unit": unit_ids.get(unit.guard_unit, -1),
		})
	var city_data: Array[Dictionary] = []
	for city in cities:
		var garrison_ids: Array[int] = []
		for unit in city.garrison:
			if unit_ids.has(unit):
				garrison_ids.append(unit_ids[unit])
		city_data.append({"faction": String(city.faction), "x": city.hex.x, "y": city.hex.y, "garrison": garrison_ids})
	var owners := {}
	for continent in territory_owners:
		owners[String(continent)] = String(territory_owners[continent])
	var scores := {}
	for faction in ZargosRules.FACTIONS:
		scores[String(faction)] = int(state.cities.get(faction, 0))
	return {
		"month": state.month, "active_index": state.active_faction_index, "phase": state.phase,
		"game_over": state.game_over, "factions": Array(state.factions).map(func(value): return String(value)),
		"host_faction": String(online_host_faction),
		"scores": scores, "territory_owners": owners, "deployment": deployment_mode,
		"units": unit_data, "cities": city_data,
	}

func _apply_online_snapshot(snapshot: Dictionary) -> void:
	if applying_remote_snapshot or not snapshot.has("factions"):
		return
	applying_remote_snapshot = true
	_clear_deployment_selection()
	for child in get_children():
		if child is CardboardUnit or child is CardboardCity:
			remove_child(child)
			child.queue_free()
	var factions: Array[StringName] = []
	for faction in snapshot.get("factions", []):
		factions.append(StringName(String(faction)))
	state.configure(factions)
	state.month = int(snapshot.get("month", 1))
	state.active_faction_index = clampi(int(snapshot.get("active_index", 0)), 0, maxi(0, factions.size() - 1))
	state.phase = int(snapshot.get("phase", ZargosRules.Phase.ALLIANCES)) as ZargosRules.Phase
	state.game_over = bool(snapshot.get("game_over", false))
	for faction in ZargosRules.FACTIONS:
		state.cities[faction] = int(snapshot.get("scores", {}).get(String(faction), 0))
	territory_owners.clear()
	for continent in snapshot.get("territory_owners", {}):
		territory_owners[StringName(continent)] = StringName(snapshot.territory_owners[continent])
	deployment_mode = bool(snapshot.get("deployment", false))
	deployment_button.visible = deployment_mode and (not online_mode or online_is_host)
	var units: Array[CardboardUnit] = []
	for data in snapshot.get("units", []):
		var unit := CardboardUnit.new()
		add_child(unit)
		unit.setup(StringName(data.get("faction", "")), StringName(data.get("type", "")), Vector2i(int(data.get("x", 0)), int(data.get("y", 0))))
		unit.moved = bool(data.get("moved", false))
		unit.acted = bool(data.get("acted", false))
		unit.ranged_hits = int(data.get("hits", 0))
		unit.vanished = bool(data.get("vanished", false))
		unit.vanished_month = int(data.get("vanished_month", 0))
		unit.vanish_origin = Vector2i(int(data.get("vanish_x", 0)), int(data.get("vanish_y", 0)))
		unit.facing_direction = int(data.get("facing", -1))
		unit.charge_ready = bool(data.get("charge", false))
		unit.charge_direction = int(data.get("charge_direction", -1))
		unit.visible = bool(data.get("visible", true))
		unit.collision_layer = 1 if unit.visible else 0
		unit.collision_mask = 1 if unit.visible else 0
		unit.position = hex_to_world(unit.hex) + Vector3(0, 0.18, 0)
		units.append(unit)
	var unit_records: Array = snapshot.get("units", [])
	for index in range(mini(units.size(), unit_records.size())):
		var target_index := int(unit_records[index].get("guard_target", -1))
		var guard_index := int(unit_records[index].get("guard_unit", -1))
		units[index].guard_target = units[target_index] if target_index >= 0 and target_index < units.size() else null
		units[index].guard_unit = units[guard_index] if guard_index >= 0 and guard_index < units.size() else null
	for data in snapshot.get("cities", []):
		var city := CardboardCity.new()
		add_child(city)
		city.setup(StringName(data.get("faction", "")), Vector2i(int(data.get("x", 0)), int(data.get("y", 0))))
		city.position = hex_to_world(city.hex) + Vector3(0, 0.19, 0)
		for unit_index in data.get("garrison", []):
			var index := int(unit_index)
			if index >= 0 and index < units.size():
				city.garrison.append(units[index])
	state.state_changed.emit()
	applying_remote_snapshot = false

func _schedule_online_publish(delay := 0.0) -> void:
	if not online_mode or applying_remote_snapshot or online.room_code.is_empty():
		return
	if delay <= 0.0:
		online.publish_snapshot(_make_online_snapshot())
	else:
		get_tree().create_timer(delay).timeout.connect(func():
			if online_mode and not applying_remote_snapshot:
				online.publish_snapshot(_make_online_snapshot())
		, CONNECT_ONE_SHOT)

func hex_to_world(hex: Vector2i) -> Vector3:
	var row_height := HEX_RADIUS * sqrt(3.0)
	var x := (hex.x - (ZargosRules.BOARD_COLUMNS - 1) * 0.5) * HEX_RADIUS * 1.5
	var z := (hex.y - (ZargosRules.BOARD_ROWS - 1) * 0.5) * row_height
	if hex.x & 1:
		z += row_height * 0.5
	return Vector3(x, 0.0, z)

func world_to_hex(point: Vector3) -> Vector2i:
	var row_height := HEX_RADIUS * sqrt(3.0)
	var column := int(round(point.x / (HEX_RADIUS * 1.5) + (ZargosRules.BOARD_COLUMNS - 1) * 0.5))
	var z_offset := row_height * 0.5 if column & 1 else 0.0
	var row := int(round((point.z - z_offset) / row_height + (ZargosRules.BOARD_ROWS - 1) * 0.5))
	return Vector2i(clampi(column, 0, ZargosRules.BOARD_COLUMNS - 1), clampi(row, 0, ZargosRules.BOARD_ROWS - 1))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			orbiting = event.pressed
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_distance = maxf(4.0, camera_distance - 0.9)
			_update_camera()
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_distance = minf(24.0, camera_distance + 0.9)
			_update_camera()
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_pick_at(event.position)
	elif event is InputEventMouseMotion:
		if orbiting:
			orbit_yaw -= event.relative.x * 0.008
			orbit_pitch = clampf(orbit_pitch - event.relative.y * 0.008, -1.45, -0.28)
			_update_camera()
		elif panning:
			var factor := camera_distance * 0.0018
			camera_rig.position += camera_rig.global_basis.x * -event.relative.x * factor
			camera_rig.position += Vector3(camera_rig.global_basis.z.x, 0, camera_rig.global_basis.z.z).normalized() * -event.relative.y * factor
	if event.is_action_pressed("cancel_action"):
		reappearing_unit = null
		_select_unit(null)

func _pick_at(screen_position: Vector2) -> void:
	var origin := camera.project_ray_origin(screen_position)
	var end := origin + camera.project_ray_normal(screen_position) * 100.0
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider: Object = hit.collider
	if collider is CardboardUnit:
		if deployment_mode:
			_select_deployment_unit(collider)
			return
		if online_mode and state.active_faction() != human_faction:
			_show_event("Attendi la mossa dei %s." % state.active_faction())
			return
		if state.phase == ZargosRules.Phase.COMBAT and collider.faction == state.active_faction():
			_toggle_combat_attacker(collider)
		elif selected and collider != selected and state.phase == ZargosRules.Phase.COMBAT:
			if combat_group.size() > 1:
				_resolve_group_attack(collider)
			else:
				_resolve_attack(selected, collider)
		else:
			_select_unit(collider)
	elif collider is CardboardCity:
		if deployment_mode:
			_select_deployment_city(collider)
			return
		if online_mode and state.active_faction() != human_faction:
			_show_event("Attendi la mossa dei %s." % state.active_faction())
			return
		_handle_city_click(collider)
	elif collider.has_meta("is_board"):
		var clicked_hex := world_to_hex(hit.position)
		if deployment_mode:
			_try_deployment_move(clicked_hex)
		elif reappearing_unit:
			_try_reappear(clicked_hex)
		elif selected:
			_try_move_selected(clicked_hex)
		else:
			var terrain_name := _terrain_name(board_data.terrain_at(clicked_hex))
			details_label.text = "Esagono %d,%d • %s" % [clicked_hex.x, clicked_hex.y, terrain_name]
			_show_event("Coordinate mappa: %d,%d • Terreno: %s" % [clicked_hex.x, clicked_hex.y, terrain_name])

func _terrain_name(terrain_type: ZargosRules.Terrain) -> String:
	match terrain_type:
		ZargosRules.Terrain.FOREST: return "Bosco"
		ZargosRules.Terrain.MOUNTAIN: return "Montagna"
		ZargosRules.Terrain.SEA: return "Mare"
		ZargosRules.Terrain.CLOUD_BRIDGE: return "Ponte di nuvole"
		ZargosRules.Terrain.MAGIC_VORTEX: return "Gorgo magico"
		ZargosRules.Terrain.CITY: return "Città"
		ZargosRules.Terrain.VOID: return "Fuori mappa"
		_: return "Pianura"

func _select_unit(unit: CardboardUnit) -> void:
	if online_mode and unit and unit.faction != human_faction:
		_show_event("In questa sessione controlli soltanto i %s." % human_faction)
		return
	_clear_combat_group()
	if selected:
		selected.set_selected(false)
	selected = unit
	if not selected:
		movement_overlay.mesh = null
		escort_button.visible = false
		_update_special_button()
		details_label.text = "Nessuna pedina selezionata."
		return
	selected.set_selected(true)
	escort_button.visible = selected.guard_target != null or selected.guard_unit != null
	_update_special_button()
	_show_reachable_hexes(selected)
	details_label.text = "%s • %s • Movimento %d • Combattimento %d%s" % [selected.faction, selected.unit_type, selected.movement, selected.combat, " • " + selected.ability if selected.ability else ""]

func _select_deployment_unit(unit: CardboardUnit) -> void:
	if not _is_human_controller(unit.faction):
		_show_event("Questa fazione è controllata dall’IA e usa lo schieramento automatico.")
		return
	_clear_deployment_selection()
	selected = unit
	selected.set_selected(true)
	details_label.text = "SCHIERAMENTO • %s • %s • scegli un esagono libero sui tuoi continenti" % [unit.faction, unit.unit_type]

func _select_deployment_city(city: CardboardCity) -> void:
	if not _is_human_controller(city.faction):
		_show_event("Questa fazione è controllata dall’IA e usa lo schieramento automatico.")
		return
	_clear_deployment_selection()
	deployment_city = city
	city.set_selected(true)
	details_label.text = "SCHIERAMENTO • Città dei %s • scegli un esagono libero sui tuoi continenti" % city.faction

func _clear_deployment_selection() -> void:
	if selected:
		selected.set_selected(false)
	selected = null
	if deployment_city:
		deployment_city.set_selected(false)
	deployment_city = null
	movement_overlay.mesh = null

func _try_deployment_move(destination: Vector2i) -> void:
	if not selected and not deployment_city:
		var continent := board_data.continent_at(destination)
		_show_event("Esagono %d,%d • continente %s • %s" % [destination.x, destination.y, continent, _terrain_name(board_data.terrain_at(destination))])
		return
	if not board_data.is_deployment_hex(destination):
		_show_event("Questo esagono non è disponibile per lo schieramento.")
		return
	var continent := board_data.continent_at(destination)
	var deploying_faction: StringName = selected.faction if selected else deployment_city.faction
	if territory_owners.get(continent, &"") != deploying_faction:
		_show_event("L'esagono appartiene al continente dei %s." % territory_owners.get(continent, continent))
		return
	var occupying_unit := _unit_at(destination)
	var occupying_city := _city_at(destination)
	if selected:
		if (occupying_unit and occupying_unit != selected) or occupying_city:
			_show_event("L'esagono è già occupato.")
			return
		selected.hex = destination
		selected.position = hex_to_world(destination) + Vector3(0, 0.18, 0)
		_show_event("%s schierato sul continente %s, esagono %d,%d." % [selected.unit_type, continent, destination.x, destination.y])
	else:
		if occupying_unit or (occupying_city and occupying_city != deployment_city):
			_show_event("L'esagono è già occupato.")
			return
		deployment_city.hex = destination
		deployment_city.position = hex_to_world(destination) + Vector3(0, 0.19, 0)
		_show_event("Città schierata sul continente %s, esagono %d,%d." % [continent, destination.x, destination.y])
	_schedule_online_publish()

func _finish_deployment() -> void:
	if not deployment_mode:
		return
	_clear_deployment_selection()
	deployment_mode = false
	deployment_button.visible = false
	ai_button.disabled = false
	ai_button.button_pressed = not online_mode
	if online_mode:
		ai_button.disabled = true
	_show_event("Schieramento completato. La Guerra dei Signori ha inizio.")
	details_label.text = "Seleziona una pedina attiva, poi un esagono di destinazione."
	_refresh_ui()
	_schedule_online_publish()

func _toggle_combat_attacker(unit: CardboardUnit) -> void:
	if unit.acted:
		_show_event("Questa pedina ha già combattuto nel turno corrente.")
		return
	if unit in combat_group:
		combat_group.erase(unit)
		unit.set_selected(false)
	else:
		combat_group.append(unit)
		unit.set_selected(true)
	selected = combat_group.back() if not combat_group.is_empty() else null
	movement_overlay.mesh = null
	details_label.text = "Attacco combinato: %d pedine • forza base %d • seleziona il difensore" % [combat_group.size(), _group_base_strength()]

func _clear_combat_group() -> void:
	for unit in combat_group:
		if is_instance_valid(unit):
			unit.set_selected(false)
	combat_group.clear()

func _group_base_strength() -> int:
	var total := 0
	for unit in combat_group:
		total += _effective_combat(unit)
	return total

func _try_move_selected(destination: Vector2i) -> void:
	if state.phase != ZargosRules.Phase.MOVEMENT:
		_show_event("Le pedine si muovono soltanto durante la fase Movimento.")
		return
	if selected.faction != state.active_faction():
		_show_event("È il turno dei %s." % state.active_faction())
		return
	if selected.moved:
		_show_event("Questa pedina ha già mosso nel turno corrente.")
		return
	if (selected.guard_target or selected.guard_unit) and selected.escort_changed:
		_show_event("Una scorta non può essere formata e separata nella stessa mossa.")
		return
	var flying := selected.ability == "Volo"
	var movement_cost := board_data.find_movement_cost(
		selected.hex,
		destination,
		selected.movement,
		flying,
		func(hex: Vector2i): return _movement_blocked(hex, selected.faction, flying),
		func(hex: Vector2i): return _in_enemy_zone_of_influence(hex, selected.faction) and not flying
	)
	if movement_cost < 0:
		_show_event("Destinazione non raggiungibile con il movimento e il terreno disponibili.")
		return
	var occupant := _unit_at(destination)
	if occupant and not _can_form_escort(selected, destination):
		_show_event("L'esagono è già occupato.")
		return
	if occupant and (selected.guard_target or selected.guard_unit):
		_show_event("Non puoi separare una scorta e formarne un'altra nella stessa mossa.")
		return
	var origin := selected.hex
	_detach_escort(selected)
	selected.hex = destination
	selected.position = hex_to_world(destination) + Vector3(0, 0.18, 0)
	selected.moved = true
	_register_facing_and_charge(selected, origin, destination)
	if occupant:
		_form_escort(selected, occupant)
	movement_overlay.mesh = null
	var terrain_name: String = String(ZargosRules.Terrain.keys()[board_data.terrain_at(destination)]).capitalize()
	var movement_note := " • scorta formata" if occupant else ""
	if selected.charge_ready:
		movement_note += " • carica rettilinea pronta"
	_show_event("%s spostato • costo %d/%d • terreno %s%s." % [selected.unit_type, movement_cost, selected.movement, terrain_name, movement_note])
	_schedule_online_publish()

func _unit_at(hex: Vector2i) -> CardboardUnit:
	var units := _units_at(hex)
	if units.is_empty():
		return null
	# La fanteria di scorta è impilata sopra e subisce per prima ogni attacco.
	for unit in units:
		if unit.guard_target:
			return unit
	return units[0]

func _units_at(hex: Vector2i) -> Array[CardboardUnit]:
	var result: Array[CardboardUnit] = []
	for child in get_children():
		if child is CardboardUnit and child.visible and child.hex == hex:
			result.append(child)
	return result

func _can_form_escort(unit: CardboardUnit, destination: Vector2i) -> bool:
	var units := _units_at(destination)
	if units.size() != 1:
		return false
	var other := units[0]
	if other.faction != unit.faction or other.guard_unit or other.guard_target:
		return false
	return (unit.unit_type == &"Fante") != (other.unit_type == &"Fante")

func _form_escort(a: CardboardUnit, b: CardboardUnit) -> void:
	var guard := a if a.unit_type == &"Fante" else b
	var protected := b if guard == a else a
	guard.guard_target = protected
	protected.guard_unit = guard
	guard.escort_changed = true
	protected.escort_changed = true
	guard.position = hex_to_world(guard.hex) + Vector3(0, 0.24, 0)
	protected.position = hex_to_world(protected.hex) + Vector3(0, 0.17, 0)
	_show_event("%s forma una scorta per %s." % [guard.unit_type, protected.unit_type])

func _detach_escort(unit: CardboardUnit) -> void:
	if unit.guard_target:
		unit.escort_changed = true
		unit.guard_target.escort_changed = true
		unit.guard_target.guard_unit = null
		unit.guard_target.position = hex_to_world(unit.guard_target.hex) + Vector3(0, 0.18, 0)
		unit.guard_target = null
	if unit.guard_unit:
		unit.escort_changed = true
		unit.guard_unit.escort_changed = true
		unit.guard_unit.guard_target = null
		unit.guard_unit.position = hex_to_world(unit.guard_unit.hex) + Vector3(0, 0.18, 0)
		unit.guard_unit = null

func _on_detach_escort() -> void:
	if not selected or state.phase != ZargosRules.Phase.MOVEMENT:
		_show_event("Le scorte si separano durante la fase Movimento.")
		return
	var guard := selected if selected.guard_target else selected.guard_unit
	if not guard or guard.faction != state.active_faction():
		_show_event("Puoi separare soltanto una tua scorta attiva.")
		return
	if guard.escort_changed:
		_show_event("La scorta è stata formata in questa mossa e non può essere già separata.")
		return
	var protected := guard.guard_target
	var destinations := _map_neighbors(guard.hex).filter(func(hex: Vector2i): return not _unit_at(hex) and ZargosRules.terrain_cost(board_data.terrain_at(hex)) >= 0)
	if destinations.is_empty():
		_show_event("Non c'è un esagono libero in cui separare la scorta.")
		return
	var destination: Vector2i = destinations[0]
	_detach_escort(guard)
	guard.escort_changed = true
	protected.escort_changed = true
	guard.hex = destination
	guard.position = hex_to_world(destination) + Vector3(0, 0.18, 0)
	_select_unit(guard)
	_show_event("Scorta separata senza consumare il movimento della pedina.")

func _update_special_button() -> void:
	if not special_button:
		return
	var can_vanish := selected and selected.faction == &"Monaci" and selected.unit_type == &"Signore" and state.phase == ZargosRules.Phase.MOVEMENT and selected.faction == state.active_faction() and not selected.moved
	var can_return := _next_vanished_monk() != null and state.phase == ZargosRules.Phase.MOVEMENT
	special_button.visible = can_vanish or can_return
	special_button.text = "Sparisci" if can_vanish else "Ricompari"

func _next_vanished_monk() -> CardboardUnit:
	for child in get_children():
		if child is CardboardUnit and child.vanished and child.faction == state.active_faction() and state.month > child.vanished_month:
			return child
	return null

func _on_monk_power() -> void:
	if selected and selected.faction == &"Monaci" and selected.unit_type == &"Signore" and not selected.vanished:
		if selected.guard_unit:
			_show_event("Un Monaco sotto scorta non può usare i propri poteri.")
			return
		selected.vanished = true
		selected.vanished_month = state.month
		selected.vanish_origin = selected.hex
		selected.moved = true
		selected.visible = false
		selected.collision_layer = 0
		selected.collision_mask = 0
		_show_event("Il Monaco scompare. Potrà ricomparire nella prossima mossa dei Monaci.")
		selected = null
		movement_overlay.mesh = null
		_update_special_button()
		_schedule_online_publish()
		return
	reappearing_unit = _next_vanished_monk()
	if not reappearing_unit:
		_show_event("Nessun Monaco può ricomparire in questo momento.")
		return
	_show_vanish_destinations(reappearing_unit)
	details_label.text = "Ricomparsa del Monaco: scegli un esagono evidenziato."
	_show_event("Il Monaco può ricomparire entro %d esagoni, senza attraversare mari o gorghi." % reappearing_unit.movement)

func _vanish_destinations(unit: CardboardUnit) -> Dictionary:
	var frontier: Array[Vector2i] = [unit.vanish_origin]
	var costs := {unit.vanish_origin: 0}
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		for neighbor in board_data.planetary_neighbors(current):
			var terrain_type := board_data.terrain_at(neighbor)
			if terrain_type in [ZargosRules.Terrain.SEA, ZargosRules.Terrain.VOID, ZargosRules.Terrain.MAGIC_VORTEX]:
				continue
			var cost: int = costs[current] + 1
			if cost > unit.movement:
				continue
			if not costs.has(neighbor) or cost < costs[neighbor]:
				costs[neighbor] = cost
				frontier.append(neighbor)
	return costs

func _show_vanish_destinations(unit: CardboardUnit) -> void:
	var destinations := _vanish_destinations(unit)
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.58, 0.34, 0.92, 0.36)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for hex: Vector2i in destinations:
		if _unit_at(hex):
			continue
		var center := hex_to_world(hex) + Vector3(0, 0.132, 0)
		for side in range(6):
			var a := deg_to_rad(60.0 * side)
			var b := deg_to_rad(60.0 * (side + 1))
			mesh.surface_add_vertex(center)
			mesh.surface_add_vertex(center + Vector3(cos(a) * HEX_RADIUS * 0.88, 0, sin(a) * HEX_RADIUS * 0.88))
			mesh.surface_add_vertex(center + Vector3(cos(b) * HEX_RADIUS * 0.88, 0, sin(b) * HEX_RADIUS * 0.88))
	mesh.surface_end()
	movement_overlay.mesh = mesh

func _try_reappear(destination: Vector2i) -> void:
	if not reappearing_unit or not _vanish_destinations(reappearing_unit).has(destination) or _unit_at(destination):
		_show_event("Il Monaco non può ricomparire in quell'esagono.")
		return
	var unit := reappearing_unit
	reappearing_unit = null
	unit.hex = destination
	unit.position = hex_to_world(destination) + Vector3(0, 0.18, 0)
	unit.visible = true
	unit.collision_layer = 1
	unit.collision_mask = 1
	unit.vanished = false
	unit.moved = false
	unit.acted = false
	_select_unit(unit)
	_show_event("Il Monaco ricompare e può muovere e combattere normalmente.")
	_schedule_online_publish()

func _movement_blocked(hex: Vector2i, moving_faction: StringName, flying: bool) -> bool:
	var unit := _unit_at(hex)
	if not unit:
		return false
	# Amici e alleati possono essere attraversati; gli Alati sorvolano anche i nemici.
	return unit.faction != moving_faction and not flying

func _register_facing_and_charge(unit: CardboardUnit, origin: Vector2i, destination: Vector2i) -> void:
	unit.charge_ready = false
	unit.charge_direction = -1
	var direction := _straight_direction(origin, destination)
	if direction < 0:
		return
	unit.facing_direction = direction
	if unit.faction == &"Cavalieri" and unit.unit_type == &"Signore" and _straight_path_is_clear(origin, destination, direction, unit.faction):
		unit.charge_ready = true
		unit.charge_direction = direction

func _straight_direction(origin: Vector2i, destination: Vector2i) -> int:
	var distance := ZargosRules.hex_distance(origin, destination)
	if distance <= 0:
		return -1
	var neighbors := _hex_neighbors(origin)
	for direction in range(neighbors.size()):
		var current := origin
		var aligned := true
		for step in range(distance):
			var next_options := _hex_neighbors(current)
			# La stessa direzione geometrica viene ritrovata scegliendo il vicino
			# che continua ad avvicinarsi alla destinazione sulla medesima linea.
			var next := next_options[direction]
			if ZargosRules.hex_distance(next, destination) != distance - step - 1:
				aligned = false
				break
			current = next
		if aligned and current == destination:
			return direction
	return -1

func _straight_path_is_clear(origin: Vector2i, destination: Vector2i, direction: int, faction: StringName) -> bool:
	var current := origin
	while current != destination:
		current = _hex_neighbors(current)[direction]
		if current != destination and _movement_blocked(current, faction, false):
			return false
		var terrain_type := board_data.terrain_at(current)
		if terrain_type in [ZargosRules.Terrain.SEA, ZargosRules.Terrain.VOID, ZargosRules.Terrain.MOUNTAIN]:
			return false
	return true

func _in_enemy_zone_of_influence(hex: Vector2i, moving_faction: StringName) -> bool:
	for neighbor in _map_neighbors(hex):
		var unit := _unit_at(neighbor)
		if unit and unit.faction != moving_faction:
			return true
	return false

func _handle_city_click(city: CardboardCity) -> void:
	if state.phase == ZargosRules.Phase.COMBAT and selected and city.faction != selected.faction:
		if combat_group.size() > 1:
			_resolve_group_siege(city)
		else:
			_resolve_siege(selected, city)
		return
	if state.phase != ZargosRules.Phase.MOVEMENT:
		_show_event("Le città si gestiscono durante Movimento o Combattimento.")
		return
	if not selected:
		_release_garrison(city)
		return
	_try_enter_city(city)

func _try_enter_city(city: CardboardCity) -> void:
	if not selected:
		return
	if selected.faction != state.active_faction() or selected.moved:
		_show_event("La pedina selezionata non può muovere ora.")
		return
	var distance := _map_distance(selected.hex, city.hex)
	if distance > selected.movement:
		_show_event("La città è oltre il movimento massimo della pedina.")
		return
	if _unit_at(city.hex) and _unit_at(city.hex) != selected:
		_show_event("La città è già occupata da una pedina.")
		return
	var old_owner := city.faction
	if old_owner != selected.faction and not city.garrison.is_empty():
		_show_event("La città è difesa: devi assediarla durante il Combattimento.")
		return
	selected.hex = city.hex
	selected.moved = true
	if old_owner != selected.faction:
		selected.position = hex_to_world(city.hex) + Vector3(0, 0.34, 0)
		city.change_owner(selected.faction)
		state.capture_city(old_owner, selected.faction)
		_show_event("I %s conquistano una città dei %s." % [selected.faction, old_owner])
	else:
		if city.add_to_garrison(selected):
			_show_event("%s entra nella guarnigione (%d/4)." % [selected.unit_type, city.garrison.size()])
			_select_unit(null)
		else:
			selected.position = hex_to_world(city.hex) + Vector3(0, 0.34, 0)
			_show_event("Guarnigione completa: la pedina resta sopra la città.")
	_schedule_online_publish()

func _release_garrison(city: CardboardCity) -> void:
	if city.faction != state.active_faction():
		_show_event("Puoi gestire solo le città del popolo attivo.")
		return
	var unit := city.release_first()
	if not unit:
		_show_event("La città non contiene una guarnigione.")
		return
	var destinations := _map_neighbors(city.hex).filter(func(hex: Vector2i): return not _unit_at(hex))
	if destinations.is_empty():
		city.add_to_garrison(unit)
		_show_event("Nessun esagono libero per far uscire la guarnigione.")
		return
	unit.hex = destinations[0]
	unit.position = hex_to_world(unit.hex) + Vector3(0, 0.18, 0)
	unit.moved = true
	_show_event("%s esce dalla guarnigione." % unit.unit_type)
	_schedule_online_publish()

func _resolve_siege(attacker: CardboardUnit, city: CardboardCity) -> void:
	if attacker.faction != state.active_faction() or attacker.acted:
		_show_event("L'attaccante non può agire ora.")
		return
	if _map_distance(attacker.hex, city.hex) != 1:
		_show_event("Per assediare una città bisogna essere adiacenti.")
		return
	if city.garrison.is_empty():
		var old_owner := city.faction
		city.change_owner(attacker.faction)
		state.capture_city(old_owner, attacker.faction)
		_show_event("Città indifesa conquistata dai %s." % attacker.faction)
		return
	if city.garrison.size() > 1:
		_show_event("Servono almeno %d assedianti per affrontare questa guarnigione." % city.garrison.size())
		return
	attacker.acted = true
	var defense := city.garrison_strength()
	var die := rng.randi_range(1, 6)
	var attack_strength := _effective_combat(attacker)
	var result := ZargosRules.resolve_combat(attack_strength, defense, die)
	var code: String = result.result
	if code in ["D1", "D3"]:
		code = "A1"
	_show_event("Assedio • dado %d • %d contro guarnigione %d: %s" % [die, attack_strength, defense, code])
	if code in ["D5", "DE"]:
		for defeated in city.clear_garrison():
			_eliminate_unit(defeated)
		var old_owner := city.faction
		city.change_owner(attacker.faction)
		state.capture_city(old_owner, attacker.faction)
		_show_event(event_label.text + " • città conquistata")
	elif code == "AE":
		_eliminate_unit(attacker)
	elif code.begins_with("A"):
		_retreat_unit(attacker, _city_threat_proxy(city), int(code.right(1)))
	_schedule_online_publish(0.4)

func _resolve_group_siege(city: CardboardCity) -> void:
	var attackers := combat_group.duplicate()
	if attackers.size() < city.garrison.size():
		_show_event("La guarnigione contiene %d pedine: occorrono almeno altrettanti assedianti." % city.garrison.size())
		return
	for attacker in attackers:
		if attacker.acted or _map_distance(attacker.hex, city.hex) != 1:
			_show_event("Tutti gli assedianti devono essere disponibili e adiacenti alla città.")
			return
	if city.garrison.is_empty():
		var old_owner := city.faction
		city.change_owner(attackers[0].faction)
		state.capture_city(old_owner, attackers[0].faction)
		_clear_combat_group()
		selected = null
		_show_event("Città indifesa conquistata dai %s." % attackers[0].faction)
		return
	var attack_strength := _group_base_strength()
	var defense := city.garrison_strength()
	var die := rng.randi_range(1, 6)
	var result := ZargosRules.resolve_combat(attack_strength, defense, die)
	for attacker in attackers:
		attacker.acted = true
	var code: String = result.result
	if code in ["D1", "D3"]:
		code = "A1"
	_show_event("Assedio combinato (%d) • dado %d • %d contro %d: %s" % [attackers.size(), die, attack_strength, defense, code])
	_clear_combat_group()
	selected = null
	if code in ["D5", "DE"]:
		for defeated in city.clear_garrison():
			_eliminate_unit(defeated)
		var old_owner := city.faction
		city.change_owner(attackers[0].faction)
		state.capture_city(old_owner, attackers[0].faction)
		_show_event(event_label.text + " • città conquistata")
	elif code == "AE" or code == "IMPOSSIBILE":
		for attacker in attackers:
			_eliminate_unit(attacker)
	else:
		for attacker in attackers:
			_retreat_unit(attacker, _city_threat_proxy(city), int(code.right(1)))
	_schedule_online_publish(0.4)

func _city_threat_proxy(city: CardboardCity) -> CardboardUnit:
	# Unità temporanea non inserita nell'albero: serve solo come origine geometrica della fuga.
	var proxy := CardboardUnit.new()
	proxy.hex = city.hex
	return proxy

func _on_next_phase() -> void:
	if deployment_mode:
		_show_event("Termina prima lo schieramento iniziale.")
		return
	if _controller_for(state.active_faction()) != "human":
		_show_event("Attendi la mossa dei %s." % state.active_faction())
		return
	var old_faction := state.active_faction()
	state.advance_phase()
	if state.phase == ZargosRules.Phase.ALLIANCES or state.active_faction() != old_faction:
		for child in get_children():
			if child is CardboardUnit:
				child.reset_turn()
	reappearing_unit = null
	_select_unit(null)
	_schedule_online_publish()

func _on_resolve_battle() -> void:
	if deployment_mode:
		_show_event("Il combattimento inizia dopo lo schieramento.")
		return
	if state.phase != ZargosRules.Phase.COMBAT or not selected:
		_show_event("Seleziona un attaccante durante la fase Combattimento.")
		return
	var target := _find_adjacent_enemy(selected)
	if not target:
		_show_event("Nessun nemico adiacente alla pedina selezionata.")
		return
	_resolve_attack(selected, target)

func _resolve_attack(attacker: CardboardUnit, defender: CardboardUnit) -> void:
	if attacker.faction != state.active_faction():
		_show_event("È il turno dei %s." % state.active_faction())
		return
	if attacker.faction == defender.faction:
		_show_event("Non puoi attaccare una pedina del tuo popolo.")
		return
	if attacker.acted:
		_show_event("Questa pedina ha già agito nella fase di combattimento.")
		return
	var distance := _map_distance(attacker.hex, defender.hex)
	if distance > 1 and attacker.ability in ["Tiro", "Fiamme", "Visione"]:
		_resolve_ranged_attack(attacker, defender, distance)
		return
	if distance != 1:
		_show_event("Il combattimento normale richiede un nemico adiacente.")
		return
	attacker.acted = true
	var die := rng.randi_range(1, 6)
	var charge_bonus := _charge_bonus(attacker, defender)
	var attacker_strength := _effective_combat(attacker) + charge_bonus
	var defender_strength := _effective_combat(defender) + board_data.defense_bonus_at(defender.hex)
	var result := ZargosRules.resolve_combat(attacker_strength, defender_strength, die)
	_show_event("Dado %d • %s %d%s contro %s %d: %s [%s]" % [die, attacker.unit_type, attacker_strength, " (carica +%d)" % charge_bonus if charge_bonus else "", defender.unit_type, defender_strength, result.text, result.result])
	match result.result:
		"DE": _eliminate_unit(defender, attacker)
		"AE": _eliminate_unit(attacker, defender)
		"IMPOSSIBILE": return
		_:
			var retreating := defender if result.retreat > 0 else attacker
			var threat := attacker if result.retreat > 0 else defender
			_retreat_unit(retreating, threat, absi(result.retreat))
	_schedule_online_publish(0.4)

func _resolve_group_attack(defender: CardboardUnit) -> void:
	if defender.faction == state.active_faction():
		_show_event("Il bersaglio deve appartenere a un popolo nemico.")
		return
	if combat_group.is_empty():
		return
	for attacker in combat_group:
		if not is_instance_valid(attacker) or attacker.acted or _map_distance(attacker.hex, defender.hex) != 1:
			_show_event("Tutti gli attaccanti devono essere disponibili e adiacenti allo stesso difensore.")
			return
	var attackers := combat_group.duplicate()
	var attack_strength := _group_attack_strength(defender)
	var defense_strength := _effective_combat(defender) + board_data.defense_bonus_at(defender.hex)
	var die := rng.randi_range(1, 6)
	var result := ZargosRules.resolve_combat(attack_strength, defense_strength, die)
	for attacker in attackers:
		attacker.acted = true
	_show_event("Attacco combinato (%d pedine) • dado %d • %d contro %d: %s [%s]" % [attackers.size(), die, attack_strength, defense_strength, result.text, result.result])
	_clear_combat_group()
	selected = null
	match result.result:
		"DE": _eliminate_unit(defender, attackers[0])
		"AE":
			for attacker in attackers:
				_eliminate_unit(attacker, defender)
		"IMPOSSIBILE":
			for attacker in attackers:
				attacker.acted = false
		_:
			if result.retreat > 0:
				_retreat_unit(defender, attackers[0], absi(result.retreat))
			else:
				for attacker in attackers:
					_retreat_unit(attacker, defender, absi(result.retreat))
	_schedule_online_publish(0.4)

func _resolve_ranged_attack(attacker: CardboardUnit, defender: CardboardUnit, distance: int) -> void:
	var die := rng.randi_range(1, 6)
	attacker.acted = true
	match attacker.ability:
		"Tiro":
			if distance > 8:
				_show_event("Bersaglio oltre la gittata massima degli arcieri.")
				attacker.acted = false
				return
			var line_result := _arrow_line_result(attacker, defender)
			if not line_result.clear:
				_show_event(line_result.message)
				attacker.acted = false
				return
			_apply_ranged_hits(attacker, defender, die, ZargosRules.arrow_hits(die, distance), "Frecce")
		"Fiamme":
			if distance > 5:
				_show_event("Bersaglio oltre la gittata massima delle fiamme.")
				attacker.acted = false
				return
			var in_forest := board_data.terrain_at(defender.hex) == ZargosRules.Terrain.FOREST
			_apply_ranged_hits(attacker, defender, die, ZargosRules.fire_hits(die, distance, in_forest), "Fiamme")
		"Visione":
			if distance > 5:
				_show_event("Bersaglio oltre la gittata massima della visione.")
				attacker.acted = false
				return
			var retreat := ZargosRules.vision_retreat(die, distance, defender.movement)
			_show_event("Visione • dado %d • distanza %d: %s arretra di %d" % [die, distance, defender.unit_type, retreat])
			if retreat > 0:
				_retreat_unit(defender, attacker, retreat)
	_schedule_online_publish(0.4)

func _arrow_line_result(attacker: CardboardUnit, defender: CardboardUnit) -> Dictionary:
	if board_data.terrain_at(attacker.hex) == ZargosRules.Terrain.FOREST:
		return {"clear": false, "message": "I Fantarcieri non possono tirare dall'interno di un bosco."}
	if board_data.terrain_at(defender.hex) == ZargosRules.Terrain.FOREST:
		return {"clear": false, "message": "I Fantarcieri non possono colpire un bersaglio dentro un bosco."}
	var direction := _straight_direction(attacker.hex, defender.hex)
	if direction < 0:
		return {"clear": false, "message": "Il tiro degli arcieri deve seguire una linea esagonale retta."}
	var current := attacker.hex
	while current != defender.hex:
		current = _hex_neighbors(current)[direction]
		if current == defender.hex:
			break
		var terrain_type := board_data.terrain_at(current)
		if terrain_type in [ZargosRules.Terrain.FOREST, ZargosRules.Terrain.MOUNTAIN, ZargosRules.Terrain.MAGIC_VORTEX]:
			return {"clear": false, "message": "La linea di tiro è bloccata dal terreno."}
		if _city_at(current):
			return {"clear": false, "message": "Una città blocca la linea di tiro."}
	return {"clear": true, "message": ""}

func _city_at(hex: Vector2i) -> CardboardCity:
	for child in get_children():
		if child is CardboardCity and child.hex == hex:
			return child
	return null

func _apply_ranged_hits(attacker: CardboardUnit, defender: CardboardUnit, die: int, hits: int, attack_name: String) -> void:
	defender.ranged_hits += hits
	var required := maxi(1, defender.combat)
	_show_event("%s • dado %d: %d colpi su %s (%d/%d)" % [attack_name, die, hits, defender.unit_type, defender.ranged_hits, required])
	if defender.ranged_hits >= required:
		_show_event(event_label.text + " • bersaglio eliminato")
		_eliminate_unit(defender, attacker)

func _effective_combat(unit: CardboardUnit) -> int:
	var strength := unit.combat
	if unit.faction != &"Cavalieri":
		return strength
	for neighbor in _map_neighbors(unit.hex):
		var supporter := _unit_at(neighbor)
		if supporter and supporter.faction == unit.faction and supporter.unit_type == &"Mago":
			strength += 2
	return strength

func _group_attack_strength(defender: CardboardUnit) -> int:
	var total := 0
	for attacker in combat_group:
		total += _effective_combat(attacker) + _charge_bonus(attacker, defender)
	return total

func _charge_bonus(attacker: CardboardUnit, defender: CardboardUnit) -> int:
	if not attacker.charge_ready or attacker.faction != &"Cavalieri" or attacker.unit_type != &"Signore":
		return 0
	if _map_distance(attacker.hex, defender.hex) != 1:
		return 0
	var impact_direction := _straight_direction(attacker.hex, defender.hex)
	if impact_direction != attacker.charge_direction:
		return 0
	var frontal := defender.facing_direction == (attacker.charge_direction + 3) % 6
	return 3 if frontal else 1

func _retreat_unit(unit: CardboardUnit, threat: CardboardUnit, distance: int) -> void:
	var current := unit.hex
	for step in range(distance):
		var options := _map_neighbors(current)
		options = options.filter(func(hex: Vector2i): return not _unit_at(hex))
		options.sort_custom(func(a: Vector2i, b: Vector2i): return _map_distance(a, threat.hex) > _map_distance(b, threat.hex))
		if options.is_empty() or _map_distance(options[0], threat.hex) <= _map_distance(current, threat.hex):
			_show_event(event_label.text + " • Fuga bloccata: pedina eliminata")
			_eliminate_unit(unit, threat)
			return
		current = options[0]
	unit.hex = current
	var tween := create_tween()
	tween.tween_property(unit, "position", hex_to_world(current) + Vector3(0, 0.18, 0), 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if unit.guard_target:
		unit.guard_target.hex = current
		tween.parallel().tween_property(unit.guard_target, "position", hex_to_world(current) + Vector3(0, 0.17, 0), 0.28)
		tween.parallel().tween_property(unit, "position", hex_to_world(current) + Vector3(0, 0.24, 0), 0.28)

func _eliminate_unit(unit: CardboardUnit, threat: CardboardUnit = null) -> void:
	if selected == unit:
		selected = null
	var unguarded := unit.guard_target
	_detach_escort(unit)
	if unguarded and is_instance_valid(unguarded) and threat and is_instance_valid(threat):
		_show_event(event_label.text + " • scorta eliminata: lo scortato fugge")
		_retreat_unit(unguarded, threat, unguarded.movement)
	var tween := create_tween()
	tween.tween_property(unit, "scale", Vector3.ZERO, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(unit.queue_free)

func _hex_neighbors(hex: Vector2i) -> Array[Vector2i]:
	var offsets_even: Array[Vector2i] = [Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1)]
	var offsets_odd: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	var output: Array[Vector2i] = []
	for offset in (offsets_odd if hex.x & 1 else offsets_even):
		output.append(hex + offset)
	return output

func _map_neighbors(hex: Vector2i) -> Array[Vector2i]:
	return board_data.planetary_neighbors(hex)

func _map_distance(a: Vector2i, b: Vector2i) -> int:
	return board_data.planetary_distance(a, b)

func _is_on_board(hex: Vector2i) -> bool:
	return hex.x >= 0 and hex.y >= 0 and hex.x < ZargosRules.BOARD_COLUMNS and hex.y < ZargosRules.BOARD_ROWS

func _find_adjacent_enemy(unit: CardboardUnit) -> CardboardUnit:
	for child in get_children():
		if child is CardboardUnit and child.faction != unit.faction and _map_distance(child.hex, unit.hex) == 1:
			return child
	return null

func _refresh_ui() -> void:
	status_label.text = state.summary()
	score_label.text = "Città: " + state.city_score()
	if online_mode and not online.room_code.is_empty():
		score_label.text += "  •  Online %s" % online.room_code
	if state.game_over:
		_show_event("Fine della partita • Vincitori: %s" % ", ".join(state.winners()))
	elif not deployment_mode and ai_enabled and _controller_for(state.active_faction()) == "ai" and not ai_running:
		call_deferred("_run_ai_turn")
	_update_special_button()

func _show_event(message: String) -> void:
	event_label.text = message

func _reset_camera() -> void:
	camera_rig.position = Vector3.ZERO
	orbit_yaw = 0.0
	orbit_pitch = -1.18
	camera_distance = 15.2
	_update_camera()

func _update_camera() -> void:
	camera_rig.rotation.y = orbit_yaw
	camera_pitch.rotation.x = orbit_pitch
	camera.position = Vector3(0, 0, camera_distance)

func _on_ai_toggled(enabled: bool) -> void:
	if deployment_mode:
		ai_enabled = false
		return
	ai_enabled = enabled
	_show_event("Avversari IA %s." % ("attivati" if enabled else "disattivati"))
	_refresh_ui()

func _run_ai_turn() -> void:
	if deployment_mode or ai_running or not ai_enabled or state.game_over or _controller_for(state.active_faction()) != "ai":
		return
	ai_running = true
	var faction := state.active_faction()
	_show_event("I %s stanno pianificando la mossa…" % faction)
	await get_tree().create_timer(0.35).timeout
	if state.phase == ZargosRules.Phase.ALLIANCES:
		state.advance_phase()
	for unit in _units_for_faction(faction):
		var destination := _best_ai_destination(unit)
		if destination != unit.hex:
			var origin := unit.hex
			unit.hex = destination
			_register_facing_and_charge(unit, origin, destination)
			var tween := create_tween()
			tween.tween_property(unit, "position", hex_to_world(destination) + Vector3(0, 0.18, 0), 0.18)
			unit.moved = true
			await tween.finished
	state.advance_phase()
	for unit in _units_for_faction(faction):
		if not is_instance_valid(unit) or unit.acted:
			continue
		var target := _best_ai_target(unit)
		if target:
			_resolve_attack(unit, target)
			await get_tree().create_timer(0.18).timeout
	state.advance_phase()
	ai_running = false
	_show_event("Turno dei %s completato." % faction)
	_refresh_ui()

func _units_for_faction(faction: StringName) -> Array[CardboardUnit]:
	var result: Array[CardboardUnit] = []
	for child in get_children():
		if child is CardboardUnit and child.visible and child.faction == faction and not child.guard_unit:
			result.append(child)
	return result

func _enemy_units(faction: StringName) -> Array[CardboardUnit]:
	var result: Array[CardboardUnit] = []
	for child in get_children():
		if child is CardboardUnit and child.visible and child.faction != faction and not child.guard_unit:
			result.append(child)
	return result

func _best_ai_destination(unit: CardboardUnit) -> Vector2i:
	var targets: Array[Vector2i] = []
	for enemy in _enemy_units(unit.faction):
		targets.append(enemy.hex)
	for child in get_children():
		if child is CardboardCity and child.faction != unit.faction:
			targets.append(child.hex)
	if targets.is_empty():
		return unit.hex
	var best_hex := unit.hex
	var best_distance := 9999
	var flying := unit.ability == "Volo"
	for column in range(ZargosRules.BOARD_COLUMNS):
		for row in range(ZargosRules.BOARD_ROWS):
			var candidate := Vector2i(column, row)
			if candidate != unit.hex and _unit_at(candidate):
				continue
			var cost := board_data.find_movement_cost(
				unit.hex,
				candidate,
				unit.movement,
				flying,
				func(hex: Vector2i): return _movement_blocked(hex, unit.faction, flying),
				func(hex: Vector2i): return _in_enemy_zone_of_influence(hex, unit.faction) and not flying
			)
			if cost < 0:
				continue
			var nearest := 9999
			for target_hex in targets:
				nearest = mini(nearest, _map_distance(candidate, target_hex))
			if nearest < best_distance:
				best_distance = nearest
				best_hex = candidate
	return best_hex

func _best_ai_target(unit: CardboardUnit) -> CardboardUnit:
	var max_range := 1
	if unit.ability == "Tiro": max_range = 8
	elif unit.ability in ["Fiamme", "Visione"]: max_range = 5
	var best: CardboardUnit = null
	var best_distance := 9999
	for enemy in _enemy_units(unit.faction):
		var distance := _map_distance(unit.hex, enemy.hex)
		if unit.ability == "Tiro" and not _arrow_line_result(unit, enemy).clear:
			continue
		if distance <= max_range and distance < best_distance:
			best = enemy
			best_distance = distance
	return best

