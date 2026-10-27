# Zargo's Lords

Versione digitale in Godot 4.7 del wargame fantasy *Zargo's Lords* (International Team), con il gioco base: Cavalieri, Draghi, Alati e Monaci.

Si gioca da 2 a 4 popoli. Ognuno può essere guidato da un giocatore allo stesso computer, dall'intelligenza artificiale oppure, online, da un giocatore remoto.

Pubblicazione: https://tannoiser2.github.io/Zargos-Lords/

## Cosa c'è

- **Regole complete del gioco base**, trascritte dal regolamento italiano e dalle ruote originali:
  - schieramento con città a distanza minima di 4 esagoni e mai sulla costa, guarnigioni coperte fino a 4 pezzi;
  - sequenza alleanze → movimento → tiri e scontri, con ordine di mossa fisso e calendario di 25 mesi;
  - movimento con boschi (2 punti), montagne (un'intera mossa per salire), gorghi magici (paralisi per tre mosse e inattaccabilità), ponti di nuvole e cuciture planetarie dei bordi;
  - zone d'influenza;
  - attacchi combinati, o di un solo pezzo contro più nemici;
  - ritirate in linea retta con eliminazione contro gli ostacoli e spinta dei pezzi amici;
  - poteri dei pezzi:
    - carica dei Signori Cavalieri (+3 frontale, +1 laterale);
    - bonus dei Maghi;
    - visioni di Maghi e Illusionisti;
    - frecce dei Fantarcieri in linea retta, con i colpi che si sommano;
    - fiamme di Draghi e Lanciafiamme (i Draghi ne sono immuni);
    - attacchi singoli di Alati, Falchi e Serpenti, con la carica travolgente del Serpente;
    - volo degli Alati;
    - sparizione dei Signori Monaci;
  - scorte dei fanti;
  - assedi;
  - alleanze libere e tradibili;
  - vittoria per numero di città.
- **Tabelle verificate sulle fotografie delle ruote** (`docs/original/wheels`): combattimento, frecce, fiamme, visioni, e il numero di frecce o vampe necessario per eliminare ogni pezzo, stampato sul retro delle ruote.
- **Mappa logica ricostruita esagono per esagono** dalla mappa del modulo Tabletop Simulator (`assets/board/mappa.png`), in `assets/data/board.json`:
  - reticolo 66 × 53;
  - pianure, boschi, montagne, 18 gorghi;
  - mare, ponti di nuvole e vuoto cosmico;
  - quattro continenti;
  - collegamenti dei bordi.
- **Interfaccia nello stile dei materiali originali**:
  - palette cuoio e avorio delle ruote;
  - titoli in un bastone condensato come il logo della scatola (Anton), testi in un geometrico alla Futura come le ruote (Jost);
  - calendario a 25 cerchi con i mesi barrati;
  - anteprima di ogni scontro come uno "spicchio" della ruota dei combattimenti, con l'esito per ciascuna faccia del dado.
- **Tavolo 3D**:
  - pedine di cartone esagonali con le illustrazioni originali, rigenerate in alta risoluzione da `tools/genera_pedine.py`;
  - evidenziazione dei movimenti e dei bersagli;
  - animazioni di frecce, fiamme e visioni;
  - telecamera orbitale.
- **Intelligenza artificiale**: diplomazia, attacchi singoli, movimento verso le città nemiche, tiri, assedi e scontri valutati sulle probabilità della ruota.
- **Partita online** tramite Firebase (autenticazione anonima e Realtime Database), con posti assegnati per popolo.
- **Salvataggio automatico** della partita locale dopo ogni azione.

## Struttura

| Percorso | Contenuto |
|---|---|
| `scripts/core/` | Modello delle regole, indipendente dalla grafica: `regole.gd` (tabelle e pezzi), `mappa.gd` (terreno e vicinanze), `partita.gd` (stato e azioni), `ia.gd` |
| `scripts/vista/` | Tavolo 3D, pedine, interfaccia, menu e tema grafico |
| `scripts/online/` | Client REST di Firebase |
| `tests/` | `test_regole.gd` (verifiche delle regole) e `simula_partita.gd` (partita completa fra IA) |
| `tools/genera_pedine.py` | Rigenera le facce delle pedine dalle scansioni in `docs/original/pedine` |
| `docs/original/` | Regolamenti, ruote, fogli delle pedine e illustrazioni originali (esclusi dal progetto Godot) |

## Comandi

- **Tasto sinistro**: seleziona; trascinando sposta il tavolo.
- **Tasto destro**: trascinando ruota la vista; un clic annulla la selezione.
- **Rotella**: zoom.
- **G**: reticolo degli esagoni.
- **Invio**: fase successiva.
- **Esc**: annulla.
- **Nella fase di combattimento**:
  - un clic sui propri pezzi li aggiunge al gruppo d'attacco;
  - un clic su un nemico apre l'anteprima dello scontro;
  - Maiusc+clic aggiunge altri nemici quando si attacca con un solo pezzo.

## Test

```
godot --headless --path . --script res://tests/test_regole.gd
GIOCATORI=4 godot --headless --path . --script res://tests/simula_partita.gd
```

La pipeline di GitHub Pages esegue i test prima di esportare la versione Web.

## Firebase

La configurazione è la stessa degli altri giochi della ludoteca. Le stanze sono sotto `zargos_lords/stanze/<codice>`; il frammento di regole è in `firebase.database.rules.json`.

Per lo sviluppo locale si copia `firebase_config.example.json` in `firebase_config.json`. Per Pages si usano i Secrets `FIREBASE_DATABASE_URL` e `FIREBASE_WEB_API_KEY`.

## Interpretazioni

Alcuni punti del regolamento sono ambigui. Le scelte fatte qui sono queste:

- L'esempio del regolamento (12 contro 5, dado 4) nel testo stampato dà D5, ma la ruota fotografata e la trascrizione italiana danno D3: fa fede la ruota.
- Una guarnigione assediata non può arretrare, quindi qualsiasi esito D la elimina e la città passa all'attaccante.
- Chi combatte dall'interno di una città non arretra.
- La carica del Cavaliere è "frontale" quando il nemico si trova sul prolungamento della linea di carica, "laterale" negli altri casi.
- Le ritirate sono scelte automaticamente nella direzione migliore per chi arretra; se un pezzo amico spinto non può arretrare, viene sacrificato al posto di chi si ritira solo quando vale meno.
- Le guarnigioni sono coperte: non esercitano zona d'influenza e i Maghi in città non danno il +2 ai pezzi fuori.
- Lo scambio degli ostaggi nelle alleanze non è ancora implementato.
