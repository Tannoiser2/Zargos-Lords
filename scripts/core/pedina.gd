class_name ZPedina
extends RefCounted
## Stato di una singola pedina. Tutti i campi sono serializzabili per il
## salvataggio e la sincronizzazione online.

var id := 0
var popolo := ""
var tipo := ""
var hex := Vector2i(-1, -1)
var viva := true
var schierata := false
var citta := -1          # id della città che la ospita in guarnigione
var scorta := -1         # id del pezzo scortato (se questo è il fante di scorta)
var scortato_da := -1    # id del fante che lo scorta
var mosso := false       # ha già usato il movimento in questa mossa
var residuo := 0         # punti movimento rimasti dopo un attacco singolo vinto
var agito := false       # ha già combattuto, tirato o lanciato
var singolo := false     # ha compiuto un attacco singolo
var scorta_cambiata := false
var paralisi := 0        # mosse ancora da trascorrere ferma in un gorgo
var scomparso := false
var mese_scomparsa := -1
var colpi := 0           # frecce o vampe accumulate nella mossa avversaria
var carica_dir := -1     # direzione della carica (Cavalieri) o della corsa (Serpente)
var ingaggiata := false  # attaccata in questo turno: la sua zona d'influenza cessa
# --- Zargo's Lords 2 ---
var ridotta := false     # girata a faccia in giù: ferma, senza zona d'influenza
var origine := ""        # tipo originale di una Pantera trasformata
var trasformata := -1    # turno globale dell'ultima trasformazione
var catturata := false   # presa nella rete di un Reziario in questo scontro
var spada := -1          # turno globale in cui vale "Spada di luce"
var muta := -1           # fino a questo turno globale non può fare magie

func _dati() -> Dictionary:
	return ZRegole.PEZZI["Magia"][tipo] if tipo == "megadrago" else ZRegole.PEZZI[popolo][tipo]

func c() -> int:
	return int(_dati()["c"])

func m() -> int:
	return int(_dati()["m"])

func nome() -> String:
	return String(_dati()["nome"])

func vola() -> bool:
	return ZRegole.vola(popolo, tipo) and scortato_da < 0

func in_campo() -> bool:
	return viva and schierata and citta < 0 and not scomparso

## Pezzo in campo e attivo (non ridotto).
func attivo() -> bool:
	return in_campo() and not ridotta

func pantera() -> bool:
	return tipo in ["pantera", "pantera0"]

func a_dict() -> Dictionary:
	return {
		"id": id, "p": popolo, "t": tipo, "h": [hex.x, hex.y], "v": viva, "s": schierata,
		"ci": citta, "sc": scorta, "sd": scortato_da, "mo": mosso, "re": residuo, "ag": agito,
		"si": singolo, "scc": scorta_cambiata, "pa": paralisi, "sp": scomparso, "ms": mese_scomparsa,
		"co": colpi, "cd": carica_dir, "in": ingaggiata,
		"ri": ridotta, "or": origine, "tr": trasformata, "ca": catturata, "sl": spada, "mu": muta,
	}

static func da_dict(d: Dictionary) -> ZPedina:
	var p := ZPedina.new()
	p.id = int(d.id)
	p.popolo = String(d.p)
	p.tipo = String(d.t)
	p.hex = Vector2i(int(d.h[0]), int(d.h[1]))
	p.viva = bool(d.v)
	p.schierata = bool(d.s)
	p.citta = int(d.ci)
	p.scorta = int(d.sc)
	p.scortato_da = int(d.sd)
	p.mosso = bool(d.mo)
	p.residuo = int(d.re)
	p.agito = bool(d.ag)
	p.singolo = bool(d.si)
	p.scorta_cambiata = bool(d.scc)
	p.paralisi = int(d.pa)
	p.scomparso = bool(d.sp)
	p.mese_scomparsa = int(d.ms)
	p.colpi = int(d.co)
	p.carica_dir = int(d.cd)
	p.ingaggiata = bool(d["in"])
	p.ridotta = bool(d.get("ri", false))
	p.origine = String(d.get("or", ""))
	p.trasformata = int(d.get("tr", -1))
	p.catturata = bool(d.get("ca", false))
	p.spada = int(d.get("sl", -1))
	p.muta = int(d.get("mu", -1))
	return p
