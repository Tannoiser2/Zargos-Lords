class_name ZRegole
extends RefCounted
## Dati e tabelle del gioco base, trascritti dalle ruote originali
## (fotografie in docs/original/wheels) e dal regolamento italiano.

const POPOLI: Array[String] = ["Cavalieri", "Draghi", "Alati", "Monaci"]
## Ordine di mossa con l'espansione Zargo's Lords 2 (regola C).
const POPOLI_ZL2: Array[String] = ["Cavalieri", "Draghi", "Alati", "Monaci", "Amazzoni", "Aracnidi"]
const CITTA_ZL2 := 6
const MESI_LAMPO := 10
const MESI := 25
const CITTA_PER_POPOLO := 4
const MAX_GUARNIGIONE := 4
const DISTANZA_MIN_CITTA := 4

## Fasce della differenza di combattimento (finestra della ruota calendario).
const FASCE := [
	Vector2i(-5, -2), Vector2i(-1, 0), Vector2i(1, 3), Vector2i(4, 7),
	Vector2i(8, 11), Vector2i(12, 15), Vector2i(16, 20), Vector2i(21, 100),
]

## Ruota dei combattimenti: una riga per faccia del dado, una colonna per fascia
## (dall'anello interno, -5/-2, a quello esterno, 21/100).
const TABELLA_COMBATTIMENTO := [
	["AE", "A5", "A3", "A1", "D1", "D1", "D3", "D5"],
	["A5", "A3", "A1", "D1", "D1", "D3", "D5", "DE"],
	["A3", "A1", "D1", "D1", "D3", "D5", "DE", "DE"],
	["A1", "A1", "D1", "D3", "D5", "DE", "DE", "DE"],
	["A1", "D1", "D3", "D5", "DE", "DE", "DE", "DE"],
	["D1", "D3", "D5", "DE", "DE", "DE", "DE", "DE"],
]

## Ruota delle frecce: frecce a segno per dado (riga) e distanza 1-8 (colonna).
const TABELLA_FRECCE := [
	[1, 1, 1, 0, 0, 0, 0, 0],
	[2, 1, 1, 1, 0, 0, 0, 0],
	[2, 2, 1, 1, 1, 0, 0, 0],
	[2, 2, 2, 1, 1, 1, 0, 0],
	[3, 2, 2, 2, 1, 1, 1, 0],
	[3, 3, 2, 2, 2, 1, 1, 1],
]

## Ruota del fuoco: vampe a segno per dado e distanza 1-5.
const TABELLA_FIAMME := [
	[1, 1, 0, 0, 0],
	[2, 1, 1, 0, 0],
	[2, 2, 1, 1, 0],
	[3, 2, 2, 1, 1],
	[3, 3, 2, 2, 1],
	[4, 3, 3, 2, 2],
]

## Ruota delle visioni: la fuga vale "MAX meno" questo valore, dove MAX è il
## fattore di movimento del bersaglio. Riga = dado, colonna = distanza 1-5.
const TABELLA_VISIONI := [
	[2, 3, 4, 5, 6],
	[1, 2, 3, 4, 5],
	[0, 1, 2, 3, 4],
	[0, 0, 1, 2, 3],
	[0, 0, 0, 1, 2],
	[0, 0, 0, 0, 1],
]

## Valori stampati sulle pedine: combattimento a sinistra, movimento a destra.
## "q" è il numero di pedine presenti sui fogli originali.
const PEZZI := {
	"Cavalieri": {
		"signore": {"nome": "Signore Cavaliere", "c": 10, "m": 7, "q": 9},
		"mago": {"nome": "Mago", "c": 2, "m": 5, "q": 3},
		"fantarcere": {"nome": "Fantarcere", "c": 2, "m": 5, "q": 8},
		"fante": {"nome": "Fante", "c": 5, "m": 4, "q": 28},
	},
	"Draghi": {
		"signore": {"nome": "Signore Drago", "c": 6, "m": 5, "q": 8},
		"serpente": {"nome": "Serpente", "c": 10, "m": 10, "q": 8},
		"lanciafiamme": {"nome": "Lanciafiamme", "c": 2, "m": 5, "q": 10},
		"fante": {"nome": "Fante", "c": 3, "m": 5, "q": 28},
	},
	"Alati": {
		"signore": {"nome": "Signore Alato", "c": 8, "m": 15, "q": 7},
		"falco": {"nome": "Falco", "c": 5, "m": 12, "q": 12},
		"fantarcere": {"nome": "Fantarcere", "c": 2, "m": 4, "q": 10},
		"fante": {"nome": "Fante", "c": 4, "m": 5, "q": 24},
	},
	"Monaci": {
		"signore": {"nome": "Signore Monaco", "c": 7, "m": 10, "q": 8},
		"illusionista": {"nome": "Monaco Illusionista", "c": 2, "m": 6, "q": 6},
		"cavaliere": {"nome": "Monaco Cavaliere", "c": 5, "m": 9, "q": 12},
		"fante": {"nome": "Fante", "c": 4, "m": 5, "q": 24},
	},
	# Zargo's Lords 2. Quantità contate sui fogli originali.
	"Amazzoni": {
		"signore": {"nome": "Signora Amazzone", "c": 7, "m": 7, "q": 7},
		"donna": {"nome": "Donna-Pantera", "c": 1, "m": 5, "q": 6},
		"arciere": {"nome": "Arciera a cavallo", "c": 3, "m": 10, "q": 12},
		"fante": {"nome": "Fante", "c": 3, "m": 6, "q": 30},
		"pantera": {"nome": "Pantera", "c": 12, "m": 10, "q": 0},
		"pantera0": {"nome": "Pantera", "c": 12, "m": 0, "q": 0},
	},
	"Aracnidi": {
		"signore": {"nome": "Signore Aracnide", "c": 5, "m": 10, "q": 8},
		"ragno": {"nome": "Ragno gigante", "c": 8, "m": 12, "q": 5},
		"reziario": {"nome": "Reziario", "c": 2, "m": 6, "q": 10},
		"fante": {"nome": "Fante", "c": 4, "m": 5, "q": 35},
	},
	# Creature evocate dalla magia nera.
	"Magia": {
		"megadrago": {"nome": "Mega drago", "c": 15, "m": 0, "q": 0},
	},
}

## Tabella "frecce arcieri a cavallo" (Amazzoni) e dardi degli Aracnidi:
## colpi per dado (riga) e distanza 1-5 (colonna).
const TABELLA_ARCIERI_CAVALLO := [
	[1, 1, 0, 0, 0],
	[2, 1, 1, 0, 0],
	[2, 2, 1, 0, 0],
	[2, 2, 1, 1, 0],
	[3, 2, 2, 1, 0],
	[3, 3, 2, 1, 1],
]

## Tabella delle reti dei Reziari: "" nulla, "C" catturato, "E" eliminato.
const TABELLA_RETI := ["", "", "", "C", "C", "E"]

## Magia (regola opzionale 2 di Zargo's Lords 2): punteggio minimo.
const MAGIE := {
	"frana": {"nome": "Grande frana", "scuola": "bianca", "min": 4, "testo": "Annulla l'effetto delle montagne su movimento e combattimento per questa mossa. Ogni punto in più: un esagono di varco in più."},
	"ponte": {"nome": "Ponte di pensiero", "scuola": "bianca", "min": 5, "testo": "Crea per questa mossa un ponte di nuvole fra due coste (al massimo 3 esagoni di mare). Ogni punto in più: un ponte in più."},
	"coraggio": {"nome": "Coraggio illuminato", "scuola": "bianca", "min": 6, "testo": "Recupera un'unità ridotta. Ogni punto in più: un'unità in più."},
	"spada": {"nome": "Spada di luce", "scuola": "bianca", "min": 7, "testo": "Raddoppia il valore delle proprie unità in un esagono per questa mossa. Ogni punto in più: un esagono di raggio in più."},
	"rinascita": {"nome": "Seconda nascita", "scuola": "bianca", "min": 8, "testo": "Un signore perso rinasce in una propria città. Ogni punto in più: un signore in più."},
	"odalische": {"nome": "Odalische infami", "scuola": "nera", "min": 3, "testo": "Un signore nemico non può fare magie nel suo prossimo turno. Ogni punto in più: un signore in più."},
	"megadrago": {"nome": "Mega drago", "scuola": "nera", "min": 5, "testo": "Crea in un esagono un drago di valore 15 che combatte in questa mossa. Ogni punto in più: un drago in più."},
	"sonno": {"nome": "Sonno oscuro", "scuola": "nera", "min": 6, "testo": "Riduce le unità nemiche in un esagono. Ogni punto in più: un esagono di raggio in più."},
	"terremoto": {"nome": "Terremoto", "scuola": "nera", "min": 7, "testo": "Elimina le unità nemiche in un esagono. Ogni punto in più: un esagono di raggio in più."},
	"voragine": {"nome": "Voragine di fiamme", "scuola": "nera", "min": 8, "testo": "Sprofonda una città nemica con i suoi occupanti (metà dei punti vittoria). Ogni punto in più: una città in più."},
}
const MAX_PREPARAZIONE := 4
const RAGGIO_MAGIA := 10

const DESCRIZIONI := {
	"Cavalieri/signore": "Carica: se l'intero movimento è in linea retta vale +3 nell'urto frontale, +1 in quello laterale.",
	"Cavalieri/mago": "+2 a tutti i pezzi del suo popolo adiacenti. Una visione per mossa entro 5 esagoni.",
	"Cavalieri/fantarcere": "In attacco non combatte: nella fase di combattimento tira frecce in linea retta entro 8 esagoni (anche dopo aver mosso).",
	"Draghi/signore": "Lancia fiamme entro 5 esagoni, prima o dopo aver mosso, in alternativa al combattimento.",
	"Draghi/serpente": "Attacco singolo: carica in linea retta travolgendo i nemici sulla sua strada.",
	"Draghi/lanciafiamme": "In attacco non combatte: nella fase di combattimento lancia fiamme su un nemico entro 5 esagoni (anche dopo aver mosso). Se attaccato si difende normalmente.",
	"Alati/signore": "Vola sopra nemici, boschi e montagne. Attacco singolo.",
	"Alati/falco": "Vola come gli Alati. Attacco singolo.",
	"Alati/fantarcere": "In attacco non combatte: nella fase di combattimento tira frecce in linea retta entro 8 esagoni (anche dopo aver mosso).",
	"Monaci/signore": "Può sparire e ricomparire alla mossa successiva entro il suo movimento.",
	"Monaci/illusionista": "Una visione per mossa entro 5 esagoni, come un mago, senza bonus ai vicini.",
	"Monaci/cavaliere": "Nessun potere speciale (niente carica).",
	"Amazzoni/signore": "Manto magico: durante il movimento attraversa esagoni occupati o controllati dal nemico; alla fine è soggetta alle zone d'influenza.",
	"Amazzoni/donna": "All'inizio della propria mossa può trasformarsi in Pantera (12/10).",
	"Amazzoni/arciere": "In alternativa al combattimento tira frecce entro 5 esagoni (tabella degli arcieri a cavallo).",
	"Amazzoni/fante": "Dopo il movimento, due fanti per mossa possono tentare di trasformarsi in Pantera (12/0): riesce con un dado pari.",
	"Amazzoni/pantera": "Attacca normalmente o singolarmente. Torna umana all'inizio della prossima mossa amazzone.",
	"Amazzoni/pantera0": "Attacca normalmente o singolarmente, ma non si muove. Torna fante all'inizio della prossima mossa amazzone.",
	"Aracnidi/signore": "In alternativa al combattimento lancia frecce avvelenate entro 5 esagoni: basta una freccia in meno per eliminare.",
	"Aracnidi/ragno": "Durante il movimento lascia fino a tre reti negli esagoni attraversati: per i nemici che arretrano sono un ostacolo.",
	"Aracnidi/reziario": "Prima dell'esito di uno scontro tenta di imprigionare il nemico: 4-5 catturato (se deve arretrare è eliminato), 6 eliminato.",
	"Magia/megadrago": "Evocato dalla magia nera: combatte in questa mossa e poi svanisce.",
}

## Frecce e vampe necessarie per eliminare ciascun pezzo (testo sul retro
## delle ruote). 0 = immune.
const FRECCE_NECESSARIE := {
	"Cavalieri": {"signore": 6, "mago": 6, "fantarcere": 3, "fante": 3},
	"Draghi": {"signore": 6, "serpente": 5, "lanciafiamme": 3, "fante": 3},
	"Alati": {"signore": 6, "falco": 5, "fantarcere": 3, "fante": 3},
	"Monaci": {"signore": 6, "illusionista": 6, "cavaliere": 5, "fante": 3},
	"Amazzoni": {"signore": 6, "donna": 3, "arciere": 5, "fante": 3, "pantera": 5, "pantera0": 5},
	"Aracnidi": {"signore": 6, "ragno": 5, "reziario": 3, "fante": 3},
	"Magia": {"megadrago": 99},
}
const VAMPE_NECESSARIE := {
	"Cavalieri": {"signore": 5, "mago": 5, "fantarcere": 3, "fante": 3},
	"Draghi": {"signore": 0, "serpente": 0, "lanciafiamme": 0, "fante": 3},
	"Alati": {"signore": 5, "falco": 3, "fantarcere": 3, "fante": 3},
	"Monaci": {"signore": 5, "illusionista": 5, "cavaliere": 3, "fante": 3},
	"Amazzoni": {"signore": 5, "donna": 5, "arciere": 5, "fante": 3, "pantera": 5, "pantera0": 5},
	"Aracnidi": {"signore": 5, "ragno": 5, "reziario": 3, "fante": 3},
	"Magia": {"megadrago": 99},
}

const COLORI := {
	"Cavalieri": Color("8aa3bd"),
	"Draghi": Color("6f8f37"),
	"Alati": Color("9a68b0"),
	"Monaci": Color("d9a52a"),
	"Amazzoni": Color("c4463c"),
	"Aracnidi": Color("7a9a58"),
	"Magia": Color("e0b030"),
}

static func valori(popolo: String, tipo: String) -> Dictionary:
	return PEZZI[popolo][tipo]

static func nome_pezzo(popolo: String, tipo: String) -> String:
	return PEZZI[popolo][tipo]["nome"]

static func vola(popolo: String, tipo: String) -> bool:
	return popolo == "Alati" and tipo in ["signore", "falco"]

static func attacco_singolo(popolo: String, tipo: String) -> bool:
	return vola(popolo, tipo) or (popolo == "Draghi" and tipo == "serpente") or (popolo == "Amazzoni" and tipo in ["pantera", "pantera0"])

static func signore(tipo: String) -> bool:
	return tipo == "signore"

static func arciere(tipo: String) -> bool:
	return tipo == "fantarcere"

static func fiamme(popolo: String, tipo: String) -> bool:
	return popolo == "Draghi" and tipo in ["signore", "lanciafiamme"]

static func visioni(popolo: String, tipo: String) -> bool:
	return (popolo == "Cavalieri" and tipo == "mago") or (popolo == "Monaci" and tipo == "illusionista")

static func fascia(differenza: int) -> int:
	for i in FASCE.size():
		if differenza >= FASCE[i].x and differenza <= FASCE[i].y:
			return i
	return -1 if differenza < FASCE[0].x else FASCE.size() - 1

static func esito_combattimento(differenza: int, dado: int) -> String:
	var f := fascia(differenza)
	if f < 0:
		return ""
	return TABELLA_COMBATTIMENTO[clampi(dado, 1, 6) - 1][f]

static func frecce(dado: int, distanza: int) -> int:
	if distanza < 1 or distanza > 8:
		return 0
	return TABELLA_FRECCE[clampi(dado, 1, 6) - 1][distanza - 1]

static func vampe(dado: int, distanza: int) -> int:
	if distanza < 1 or distanza > 5:
		return 0
	return TABELLA_FIAMME[clampi(dado, 1, 6) - 1][distanza - 1]

static func fuga_visione(dado: int, distanza: int, movimento: int) -> int:
	if distanza < 1 or distanza > 5:
		return 0
	return maxi(0, movimento - TABELLA_VISIONI[clampi(dado, 1, 6) - 1][distanza - 1])

## Probabilità (su 6) di ciascun tipo di esito per una data differenza:
## usata dall'interfaccia e dall'IA per stimare un attacco.
static func probabilita(differenza: int) -> Dictionary:
	var out := {"AE": 0, "A": 0, "D": 0, "DE": 0}
	var f := fascia(differenza)
	if f < 0:
		out["AE"] = 6
		return out
	for dado in range(1, 7):
		var e: String = TABELLA_COMBATTIMENTO[dado - 1][f]
		if e == "AE" or e == "DE":
			out[e] += 1
		else:
			out[e.left(1)] += 1
	return out

## Articoli: "i Cavalieri", "gli Alati", "le Amazzoni".
static func gli(p: String) -> String:
	if p == "Amazzoni":
		return "le " + p
	return ("gli " if p in ["Alati", "Aracnidi"] else "i ") + p

static func degli(p: String) -> String:
	if p == "Amazzoni":
		return "delle " + p
	return ("degli " if p in ["Alati", "Aracnidi"] else "dei ") + p

static func agli(p: String) -> String:
	if p == "Amazzoni":
		return "alle " + p
	return ("agli " if p in ["Alati", "Aracnidi"] else "ai ") + p

static func Gli(p: String) -> String:
	return gli(p).capitalize().split(" ")[0] + " " + p


static func colpi_arcieri_cavallo(dado: int, distanza: int) -> int:
	if distanza < 1 or distanza > 5:
		return 0
	return TABELLA_ARCIERI_CAVALLO[clampi(dado, 1, 6) - 1][distanza - 1]
