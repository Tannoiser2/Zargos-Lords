# Zargo's Lords

Progetto per la realizzazione di una versione digitale in Godot del wargame fantasy vintage *Zargo's Lords*.

## Stato del progetto

Il repository contiene per ora il materiale di riferimento del gioco base:

- regolamento italiano in formato Word;
- scansione della mappa;
- fogli delle pedine dei quattro popoli originali;
- tabelle, copertine e illustrazioni di riferimento.

È disponibile un primo prototipo Godot 4.7 con:

- tabellone tridimensionale con spessore e scansione della mappa originale;
- camera orbitale con rotazione, ingrandimento e spostamento;
- pedine esagonali tridimensionali di tipo cartoncino;
- quattro popoli con valori base di movimento e combattimento;
- selezione e movimento sul reticolo della scansione originale;
- evidenziazione delle destinazioni raggiungibili e zone d'influenza nemiche;
- preparazione della partita con scelta di 2, 3 o 4 popoli e del popolo umano;
- assegnazione di due continenti per popolo nelle partite a due;
- sequenza Alleanze, Movimento e Combattimento;
- ordine di turno Cavalieri, Draghi, Alati e Monaci;
- calendario di 25 mesi;
- tabelle originali complete per combattimento, frecce, fiamme e visioni;
- risoluzione di eliminazioni e arretramenti, inclusa la fuga bloccata;
- attacchi normali combinati con più pedine e ritirata dell'intero gruppo;
- formazione e separazione delle scorte, arretramento congiunto e fuga dello scortato se il fante viene eliminato;
- sparizione dei Signori Monaci e ricomparsa nella mossa successiva con vincoli di mare e gorghi;
- carica rettilinea dei Signori Cavalieri con bonus frontale e laterale;
- linea di tiro rettilinea dei Fantarcieri con blocchi di terreno, città e boschi;
- frecce, fiamme e visioni selezionando direttamente il bersaglio;
- accumulo dei colpi a distanza sullo stesso bersaglio nel turno;
- città tridimensionali, conquista e conteggio per fazione;
- guarnigioni nascoste fino a quattro unità e uscita dalla città;
- assedio con più attaccanti, numero minimo richiesto, forza combinata della guarnigione e risultati speciali per le città;
- percorso esagonale con costi di boschi, montagne, mari, ponti e gorghi;
- reticolo 36 × 24 calibrato sui centri degli esagoni stampati della scansione originale;
- maschera completa di mare, laghi e spazi centrali esterni non transitabili;
- orientamento corretto delle annotazioni di boschi, montagne e gorghi magici sui quattro continenti;
- reticolo di calibrazione attivabile e lettura di coordinate e terreno facendo clic sulla mappa;
- bonus difensivi del terreno applicati al combattimento;
- determinazione del vincitore in base alle città controllate al 25º mese;
- modalità solitaria con popolo umano selezionabile e avversari controllati dall'IA;
- test automatici delle regole e degli esempi del manuale.

La verifica manuale finale delle coste e dei ponti di nuvole, lo schieramento libero completo e il multiplayer Firebase verranno aggiunti nelle fasi successive.

## Avvio

Aprire `project.godot` con Godot 4.7 e avviare la scena principale.

La prima versione Web è pubblicata tramite GitHub Pages all'indirizzo:

https://tannoiser2.github.io/Zargos-Lords/

## Controlli

- tasto destro e trascinamento: ruota il tabellone;
- tasto centrale e trascinamento: sposta la visuale;
- rotella: ingrandisce o allontana;
- tasto sinistro: seleziona una pedina o una destinazione;
- Reticolo: mostra o nasconde la griglia calibrata; facendo clic su un esagono libero vengono mostrate coordinate e terreno;
- in combattimento, selezionare l'attaccante e poi una pedina nemica adiacente;
- Esc: annulla la selezione.

## Edizione di riferimento

La prima implementazione sarà basata sul gioco originale con Cavalieri, Draghi, Alati e Monaci. Il materiale relativo a *Zargo's Lords 2* e alla nuova edizione non fa parte di questo primo caricamento.

## Nota sui materiali

I file presenti sono conservati come sorgenti di lavoro. Prima della pubblicazione di una build distribuibile, ogni elemento grafico verrà verificato, ripulito e convertito in asset adatti all'uso digitale.
