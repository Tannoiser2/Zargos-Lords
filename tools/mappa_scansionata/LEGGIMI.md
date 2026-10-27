# Ricostruzione della mappa originale dalle 18 scansioni A4 (300 dpi)

1. `pdfimages -j "Mappa scansionata.pdf" p` estrae le pagine `p-000.jpg … p-017.jpg`.
2. `1_registra.py`: posizione approssimata di ogni scansione sulla foto intera ingrandita (SIFT).
3. `2_allinea.py`: allineamento fine fra scansioni sovrapposte (minimi quadrati sulle corrispondenze, residuo mediano < 1 px).
4. `3_mosaico.py`: fusione con pesi sfumati verso i bordi → mosaico 11191 × 7616.
5. `tools/mappa_originale/render_orig.py` con `FONTE=mosaico.png W=6144 H=4124` riporta il mosaico sul reticolo di gioco.
6. `5_affina_griglia.py` (due passate) corregge gli scarti residui confrontando gli esagoni stampati con il reticolo.
