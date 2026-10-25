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
var setup_layer: CanvasLayer
var reappearing_unit: CardboardUnit

func _ready() -> void:
	rng.randomize()
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
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/board/zargo_board_original.jpg")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.roughness = 0.78
	box.material = material
	mesh_instance.mesh = box
	board.add_child(mesh_instance)

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
	ai_button = CheckButton.new()
	ai_button.text = "IA avversari"
	ai_button.toggled.connect(_on_ai_toggled)
	buttons.add_child(ai_button)

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
	var shade := ColorRect.new()
	shade.color = Color("120b08f2")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	setup_layer.add_child(shade)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(470, 420)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-235, -210)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("2b190f")
	style.border_color = Color("c49342")
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	setup_layer.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 16)
	panel.add_child(stack)
	var title := Label.new()
	title.text = "ZARGO'S LORDS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color("e5b75b"))
	stack.add_child(title)
	var intro := Label.new()
	intro.text = "PREPARAZIONE DELLA GUERRA DEI SIGNORI"
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.add_theme_color_override("font_color", Color("d9c5a0"))
	stack.add_child(intro)
	var player_label := Label.new()
	player_label.text = "Popoli in gioco"
	stack.add_child(player_label)
	var player_count := OptionButton.new()
	player_count.add_item("2 popoli — due continenti ciascuno", 2)
	player_count.add_item("3 popoli", 3)
	player_count.add_item("4 popoli", 4)
	player_count.select(2)
	stack.add_child(player_count)
	var faction_label := Label.new()
	faction_label.text = "Il tuo popolo"
	stack.add_child(faction_label)
	var faction_choice := OptionButton.new()
	for faction in ZargosRules.FACTIONS:
		faction_choice.add_item(String(faction))
	stack.add_child(faction_choice)
	var note := Label.new()
	note.text = "Gli altri popoli saranno controllati dall'IA.\nLo schieramento libero completo verrà aggiunto nel prossimo passaggio."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color("bfae91"))
	stack.add_child(note)
	var start := Button.new()
	start.text = "INIZIA LA PARTITA"
	start.custom_minimum_size.y = 52
	start.add_theme_font_size_override("font_size", 19)
	start.pressed.connect(func(): _start_new_game(player_count.get_selected_id(), faction_choice.selected))
	stack.add_child(start)

func _start_new_game(player_count: int, human_index: int) -> void:
	human_faction = ZargosRules.FACTIONS[human_index]
	var active: Array[StringName] = [human_faction]
	var cursor := (human_index + 1) % ZargosRules.FACTIONS.size()
	while active.size() < player_count:
		var candidate: StringName = ZargosRules.FACTIONS[cursor]
		if candidate not in active:
			active.append(candidate)
		cursor = (cursor + 1) % ZargosRules.FACTIONS.size()
	state.configure(active)
	var owners := _territory_owners(active)
	_spawn_armies(owners)
	_spawn_cities(owners)
	ai_button.button_pressed = true
	setup_layer.queue_free()
	_show_event("La Guerra dei Signori ha inizio. Tu controlli i %s." % human_faction)
	_refresh_ui()

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
		_handle_city_click(collider)
	elif collider.has_meta("is_board"):
		if reappearing_unit:
			_try_reappear(world_to_hex(hit.position))
		elif selected:
			_try_move_selected(world_to_hex(hit.position))

func _select_unit(unit: CardboardUnit) -> void:
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
	_detach_escort(selected)
	selected.hex = destination
	selected.position = hex_to_world(destination) + Vector3(0, 0.18, 0)
	selected.moved = true
	if occupant:
		_form_escort(selected, occupant)
	movement_overlay.mesh = null
	var terrain_name: String = String(ZargosRules.Terrain.keys()[board_data.terrain_at(destination)]).capitalize()
	_show_event("%s spostato • costo %d/%d • terreno %s%s." % [selected.unit_type, movement_cost, selected.movement, terrain_name, " • scorta formata" if occupant else ""])

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
	var destinations := _hex_neighbors(guard.hex).filter(func(hex: Vector2i): return _is_on_board(hex) and not _unit_at(hex) and ZargosRules.terrain_cost(board_data.terrain_at(hex)) >= 0)
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
		for neighbor in ZargosBoardData.neighbors(current):
			if not ZargosBoardData.is_on_board(neighbor):
				continue
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

func _movement_blocked(hex: Vector2i, moving_faction: StringName, flying: bool) -> bool:
	var unit := _unit_at(hex)
	if not unit:
		return false
	# Amici e alleati possono essere attraversati; gli Alati sorvolano anche i nemici.
	return unit.faction != moving_faction and not flying

func _in_enemy_zone_of_influence(hex: Vector2i, moving_faction: StringName) -> bool:
	for neighbor in _hex_neighbors(hex):
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
	var distance := ZargosRules.hex_distance(selected.hex, city.hex)
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

func _release_garrison(city: CardboardCity) -> void:
	if city.faction != state.active_faction():
		_show_event("Puoi gestire solo le città del popolo attivo.")
		return
	var unit := city.release_first()
	if not unit:
		_show_event("La città non contiene una guarnigione.")
		return
	var destinations := _hex_neighbors(city.hex).filter(func(hex: Vector2i): return _is_on_board(hex) and not _unit_at(hex))
	if destinations.is_empty():
		city.add_to_garrison(unit)
		_show_event("Nessun esagono libero per far uscire la guarnigione.")
		return
	unit.hex = destinations[0]
	unit.position = hex_to_world(unit.hex) + Vector3(0, 0.18, 0)
	unit.moved = true
	_show_event("%s esce dalla guarnigione." % unit.unit_type)

func _resolve_siege(attacker: CardboardUnit, city: CardboardCity) -> void:
	if attacker.faction != state.active_faction() or attacker.acted:
		_show_event("L'attaccante non può agire ora.")
		return
	if ZargosRules.hex_distance(attacker.hex, city.hex) != 1:
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

func _resolve_group_siege(city: CardboardCity) -> void:
	var attackers := combat_group.duplicate()
	if attackers.size() < city.garrison.size():
		_show_event("La guarnigione contiene %d pedine: occorrono almeno altrettanti assedianti." % city.garrison.size())
		return
	for attacker in attackers:
		if attacker.acted or ZargosRules.hex_distance(attacker.hex, city.hex) != 1:
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

func _city_threat_proxy(city: CardboardCity) -> CardboardUnit:
	# Unità temporanea non inserita nell'albero: serve solo come origine geometrica della fuga.
	var proxy := CardboardUnit.new()
	proxy.hex = city.hex
	return proxy

func _on_next_phase() -> void:
	var old_faction := state.active_faction()
	state.advance_phase()
	if state.phase == ZargosRules.Phase.ALLIANCES or state.active_faction() != old_faction:
		for child in get_children():
			if child is CardboardUnit:
				child.reset_turn()
	reappearing_unit = null
	_select_unit(null)

func _on_resolve_battle() -> void:
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
	var distance := ZargosRules.hex_distance(attacker.hex, defender.hex)
	if distance > 1 and attacker.ability in ["Tiro", "Fiamme", "Visione"]:
		_resolve_ranged_attack(attacker, defender, distance)
		return
	if distance != 1:
		_show_event("Il combattimento normale richiede un nemico adiacente.")
		return
	attacker.acted = true
	var die := rng.randi_range(1, 6)
	var attacker_strength := _effective_combat(attacker)
	var defender_strength := _effective_combat(defender) + board_data.defense_bonus_at(defender.hex)
	var result := ZargosRules.resolve_combat(attacker_strength, defender_strength, die)
	_show_event("Dado %d • %s %d contro %s %d: %s [%s]" % [die, attacker.unit_type, attacker_strength, defender.unit_type, defender_strength, result.text, result.result])
	match result.result:
		"DE": _eliminate_unit(defender, attacker)
		"AE": _eliminate_unit(attacker, defender)
		"IMPOSSIBILE": return
		_:
			var retreating := defender if result.retreat > 0 else attacker
			var threat := attacker if result.retreat > 0 else defender
			_retreat_unit(retreating, threat, absi(result.retreat))

func _resolve_group_attack(defender: CardboardUnit) -> void:
	if defender.faction == state.active_faction():
		_show_event("Il bersaglio deve appartenere a un popolo nemico.")
		return
	if combat_group.is_empty():
		return
	for attacker in combat_group:
		if not is_instance_valid(attacker) or attacker.acted or ZargosRules.hex_distance(attacker.hex, defender.hex) != 1:
			_show_event("Tutti gli attaccanti devono essere disponibili e adiacenti allo stesso difensore.")
			return
	var attackers := combat_group.duplicate()
	var attack_strength := _group_base_strength()
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

func _resolve_ranged_attack(attacker: CardboardUnit, defender: CardboardUnit, distance: int) -> void:
	var die := rng.randi_range(1, 6)
	attacker.acted = true
	match attacker.ability:
		"Tiro":
			if distance > 8:
				_show_event("Bersaglio oltre la gittata massima degli arcieri.")
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
	for neighbor in _hex_neighbors(unit.hex):
		var supporter := _unit_at(neighbor)
		if supporter and supporter.faction == unit.faction and supporter.unit_type == &"Mago":
			strength += 2
	return strength

func _retreat_unit(unit: CardboardUnit, threat: CardboardUnit, distance: int) -> void:
	var current := unit.hex
	for step in range(distance):
		var options := _hex_neighbors(current)
		options = options.filter(func(hex: Vector2i): return _is_on_board(hex) and not _unit_at(hex))
		options.sort_custom(func(a: Vector2i, b: Vector2i): return ZargosRules.hex_distance(a, threat.hex) > ZargosRules.hex_distance(b, threat.hex))
		if options.is_empty() or ZargosRules.hex_distance(options[0], threat.hex) <= ZargosRules.hex_distance(current, threat.hex):
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

func _is_on_board(hex: Vector2i) -> bool:
	return hex.x >= 0 and hex.y >= 0 and hex.x < ZargosRules.BOARD_COLUMNS and hex.y < ZargosRules.BOARD_ROWS

func _find_adjacent_enemy(unit: CardboardUnit) -> CardboardUnit:
	for child in get_children():
		if child is CardboardUnit and child.faction != unit.faction and ZargosRules.hex_distance(child.hex, unit.hex) == 1:
			return child
	return null

func _refresh_ui() -> void:
	status_label.text = state.summary()
	score_label.text = "Città: " + state.city_score()
	if state.game_over:
		_show_event("Fine della partita • Vincitori: %s" % ", ".join(state.winners()))
	elif ai_enabled and state.active_faction() != human_faction and not ai_running:
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
	ai_enabled = enabled
	_show_event("Avversari IA %s." % ("attivati" if enabled else "disattivati"))
	_refresh_ui()

func _run_ai_turn() -> void:
	if ai_running or not ai_enabled or state.game_over or state.active_faction() == human_faction:
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
			unit.hex = destination
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
				nearest = mini(nearest, ZargosRules.hex_distance(candidate, target_hex))
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
		var distance := ZargosRules.hex_distance(unit.hex, enemy.hex)
		if distance <= max_range and distance < best_distance:
			best = enemy
			best_distance = distance
	return best

