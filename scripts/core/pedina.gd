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

func c() -> int:
	return int(ZRegole.PEZZI[popolo][tipo]["c"])

func m() -> int:
	return int(ZRegole.PEZZI[popolo][tipo]["m"])

func nome() -> String:
	return ZRegole.nome_pezzo(popolo, tipo)

func vola() -> bool:
	return ZRegole.vola(popolo, tipo) and scortato_da < 0

func in_campo() -> bool:
	return viva and schierata and citta < 0 and not scomparso

func a_dict() -> Dictionary:
	return {
		"id": id, "p": popolo, "t": tipo, "h": [hex.x, hex.y], "v": viva, "s": schierata,
		"ci": citta, "sc": scorta, "sd": scortato_da, "mo": mosso, "re": residuo, "ag": agito,
		"si": singolo, "scc": scorta_cambiata, "pa": paralisi, "sp": scomparso, "ms": mese_scomparsa,
		"co": colpi, "cd": carica_dir, "in": ingaggiata,
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
	return p
