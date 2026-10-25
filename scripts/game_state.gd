class_name ZargosGameState
extends RefCounted

signal state_changed
signal log_message(message: String)

var month := 1
var active_faction_index := 0
var phase := ZargosRules.Phase.ALLIANCES
var game_over := false
var cities := {&"Cavalieri": 6, &"Draghi": 6, &"Alati": 6, &"Monaci": 6}

func active_faction() -> StringName:
	return ZargosRules.FACTIONS[active_faction_index]

func phase_name() -> String:
	return ["Alleanze", "Movimento", "Combattimento"][phase]

func advance_phase() -> void:
	if game_over:
		return
	if phase < ZargosRules.Phase.COMBAT:
		phase += 1
	else:
		phase = ZargosRules.Phase.ALLIANCES
		active_faction_index += 1
		if active_faction_index >= ZargosRules.FACTIONS.size():
			active_faction_index = 0
			month += 1
			if month > ZargosRules.MONTH_LIMIT:
				month = ZargosRules.MONTH_LIMIT
				game_over = true
				log_message.emit("L'Anno di Zargo è terminato. Vince chi controlla più città.")
	state_changed.emit()

func summary() -> String:
	if game_over:
		return "Fine della partita • 25° mese"
	return "Mese %d/25  •  %s  •  %s" % [month, active_faction(), phase_name()]

