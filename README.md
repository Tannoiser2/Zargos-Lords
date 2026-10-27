# Zargo's Lords

Versione digitale in Godot 4.7 del wargame fantasy *Zargo's Lords* (International Team), con il gioco base (Cavalieri, Draghi, Alati e Monaci) e l'espansione *Zargo's Lords 2* (Amazzoni e Aracnidi, magia, passaggi segreti, guerra lampo).

Si gioca da 2 a 4 popoli, scelti fra sei. Ognuno può essere guidato da un giocatore allo stesso computer, dall'intelligenza artificiale oppure, online, da un giocatore remoto.

Pubblicazione: https://tannoiser2.github.io/Zargos-Lords/

## Cosa c'è

- **Regole complete del gioco base**, trascritte dal regolamento italiano e dalle ruote originali:
  - schieramento con città a distanza minima di 4 esagoni e mai sulla costa, guarnigioni coperte fino a 4 pezzi;
  - mossa divisa in fasi: alleanze → attacchi singoli (Alati, Falchi, Serpenti, e fiamme del Drago prima di muovere) → movimento → lanci (frecce, fiamme, visioni) → corpo a corpo; le fasi senza azioni possibili vengono saltate; ordine di mossa fisso e calendario di 25 mesi;
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
- **Zargo's Lords 2** (pedine da `docs/original/pedine/zargos2-*.jpg`):
  - Amazzoni: Signora con il manto magico (ignora blocchi e zone d'influenza), Donne-Pantera che diventano Pantere (12/10), arcieri a cavallo con una propria tabella, fanti che si trasformano in Pantere con un numero pari (al massimo due tentativi per mossa);
  - Aracnidi: ragni che lasciano fino a tre reti sul percorso (chi ci entra si ferma), Reziari che lanciano la rete prima dello scontro (4-5 cattura, 6 elimina), dardi del Signore;
  - sei città per popolo, pile di due pezzi dello stesso popolo, pezzi ridotti invece che eliminati contro gli ostacoli e recuperati a fine mossa (sul tavolo diventano grigi, pedina e miniatura), frecce in ogni direzione con +1 contro le pile;
  - magia minore: Frecce incantate (portata 8 per i Fantarcieri e 5 per le Arciere a cavallo accanto a un incantatore, altrimenti 2), Pioggia di fiamme dei Signori Draghi (Lanciafiamme a 5 accanto a un Signore), visioni e dardi a 5;
  - incantatori: Signori, Maghi e Monaci Illusionisti lanciano la magia e possono essere colpiti dalle Odalische infami;
  - regole opzionali: iniziativa (ordine dei popoli sorteggiato ogni mese, ogni fase giocata da tutti prima della successiva: potere, movimento, combattimento), passaggi segreti fra le proprie città, magia (fase propria, punti di preparazione fino a 4, dieci incantesimi entro 10 esagoni da un Signore), guerra lampo (città rase al suolo e punti vittoria).
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
  - ogni popolo è rappresentato dal ritratto del suo Signore (pannello, diplomazia, città, barra in alto, finestre);
  - anteprima di ogni scontro come uno "spicchio" della ruota dei combattimenti, con l'esito per ciascuna faccia del dado.
- **Tavolo 3D**:
  - pedine di cartone esagonali con le illustrazioni originali, rigenerate in alta risoluzione da `tools/genera_pedine.py`;
  - evidenziazione dei movimenti e dei bersagli;
  - animazioni di frecce, fiamme e visioni;
  - telecamera orbitale.
- **Animazioni dei lanci**: il tiratore si volta verso il bersaglio, poi partono raffiche di frecce in arco, sciami di braci per le fiamme o anelli spettrali per le visioni; il bersaglio sussulta. I Signori Monaci svaniscono e ricompaiono in una nuvola di fumo dorato.
- **Intelligenza artificiale**: diplomazia, attacchi singoli, movimento verso le città nemiche, tiri, assedi e scontri valutati sulle probabilità della ruota.
- **Partita online** tramite Firebase (autenticazione anonima e Realtime Database), con posti assegnati per popolo.
- **Salvataggio automatico** della partita locale dopo ogni azione.

## Menu iniziale

Accanto al disegno di ogni Signore (popoli del gioco base sopra, dell espansione sotto, su due colonne) si sceglie chi guida il popolo: *Umano*, *IA* o *Escluso* (online: *Io*, *Remoto*, *IA*, *Escluso*). Al massimo quattro popoli in campo. Sotto si attivano le regole di Zargo's Lords 2 e le opzioni magia, passaggi segreti e guerra lampo. I disegni dei Signori sono ritagliati da `tools/genera_signori.py`.

## Grafica delle pedine

Si sceglie nel menu iniziale (in alto a destra) o dal menu in partita; anche i ritratti dei Signori nel menu cambiano di conseguenza.

- **Originali 1979**: le scansioni dei fogli di pedine (`assets/units`).
- **Nuova grafica**: le nuove illustrazioni in `docs/nuova_grafica`, riportate su esagoni a punta in alto con il bordo del colore del popolo da `tools/genera_pedine_nuove.py` (`assets/units_nuove`).
- **Miniature 3D**: 25 modelli generati con Meshy (image-to-3D, topologia leggera da 8000 triangoli, texture ridotte a 1024 px) a partire dalle nuove illustrazioni, in piedi su basi con i soli valori (`assets/units_basi`, da `tools/genera_basi.py`; modelli in `assets/modelli/<popolo>/<tipo>.glb`). Anche le sei città hanno la loro miniatura. Nel pannello laterale e nel vassoio si vede il rendering della miniatura; il segnalino di sparizione resta una pedina piatta, i pezzi ridotti diventano miniature grigie; la Pantera nata da un fante usa la stessa miniatura della Pantera, il Mega drago quella del Signore Drago ingrandita. Con le miniature anche il terreno è in rilievo: montagne, boschi, gorghi e ponti di nuvole sono modelli Meshy (`assets/modelli/terreno`) ricavati da illustrazioni nello stile della mappa originale di Riboldi; i pezzi su montagne, boschi e gorghi poggiano sopra il rilievo, gli esagoni con una città restano piatti. Gli ID dei task Meshy sono in `docs/nuova_grafica/meshy_task.txt`.

Nel gioco base ogni esagono ospita un solo pezzo (salvo il fante di scorta). Due pezzi nello stesso esagono (pila di Zargo's Lords 2, che ammette al massimo due pedine per esagono, o fante di scorta) sono mostrati affiancati e rimpiccioliti dentro l'esagono.

## Opzioni (barra in alto durante la partita)

- **Scontri e tiri**: *ruota originale* oppure *riquadro*. Con la ruota, il disco fotografato dalla scatola gira sotto il cartoncino del calendario, si ferma sul dado ed evidenzia la fascia del risultato: la ruota dei combattimenti per gli scontri e, sull'altra metà, per le visioni; la ruota dei tiri per frecce e fiamme. Vale per tutti gli scontri e i tiri, anche fra IA. Arciere a cavallo e dardi degli Aracnidi, che hanno tabelle di Zargo's Lords 2 non stampate sulle ruote, usano il riquadro. Le texture sono generate da `tools/genera_ruota.py`.
- **Mappa**: *nuova* (modulo Tabletop Simulator) oppure *originale* (tabellone 1979). La mappa originale è riallineata esagono per esagono sul reticolo della nuova (`tools/mappa_originale/`); ora è ricostruita dalle 18 scansioni A4 del tabellone (`tools/mappa_scansionata`) e riallineata a mano sul reticolo, a 4096 × 2749 pixel come la mappa nuova.

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
- Fantarcieri e Lanciafiamme in attacco possono solo tirare; Maghi, Illusionisti e Signori Draghi scelgono fra lancio e corpo a corpo (chi lancia non combatte più in quella mossa).
- Il segnalino di sparizione dei Monaci non blocca l'esagono.
- Lo scambio degli ostaggi nelle alleanze non è ancora implementato.
- ZL2: la Voragine di fiamme dà mezza città (o metà dei punti in guerra lampo); il Mega drago combatte solo nella mossa in cui è evocato; le Pantere tornano Donne o fanti all'inizio della mossa successiva delle Amazzoni.
