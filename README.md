# Zargo's Lords

Progetto per la realizzazione di una versione digitale in Godot del wargame fantasy vintage *Zargo's Lords*.

## Stato del progetto

Il repository contiene per ora il materiale di riferimento del gioco base:

- regolamento italiano in formato Word;
- scansione della mappa;
- fogli delle pedine dei quattro popoli originali;
- tabelle, copertine e illustrazioni di riferimento.

È disponibile un primo prototipo Godot 4.7 con:

- tabellone tridimensionale con spessore e texture della mappa;
- camera orbitale con rotazione, ingrandimento e spostamento;
- pedine esagonali tridimensionali di tipo cartoncino;
- quattro popoli con valori base di movimento e combattimento;
- selezione e movimento su una griglia esagonale logica;
- sequenza Alleanze, Movimento e Combattimento;
- ordine di turno Cavalieri, Draghi, Alati e Monaci;
- calendario di 25 mesi;
- primo risolutore di combattimento e test automatici delle regole.

La trascrizione completa delle tabelle rotanti, i terreni definitivi, gli schieramenti, gli avversari IA e il multiplayer Firebase verranno aggiunti nelle fasi successive.

## Avvio

Aprire `project.godot` con Godot 4.7 e avviare la scena principale.

## Controlli

- tasto destro e trascinamento: ruota il tabellone;
- tasto centrale e trascinamento: sposta la visuale;
- rotella: ingrandisce o allontana;
- tasto sinistro: seleziona una pedina o una destinazione;
- Esc: annulla la selezione.

## Edizione di riferimento

La prima implementazione sarà basata sul gioco originale con Cavalieri, Draghi, Alati e Monaci. Il materiale relativo a *Zargo's Lords 2* e alla nuova edizione non fa parte di questo primo caricamento.

## Nota sui materiali

I file presenti sono conservati come sorgenti di lavoro. Prima della pubblicazione di una build distribuibile, ogni elemento grafico verrà verificato, ripulito e convertito in asset adatti all'uso digitale.
