# Tivu

Il telecomando della tua TV LG, nella barra dei menu del Mac. [English](README.en.md)

Colleghi il Mac alla TV con il cavo HDMI e i tasti volume smettono di funzionare: su HDMI macOS li disattiva, e il cavo
non porta comandi. Tivu parla con la TV sulla rete di casa e ti ridà il volume, gli ingressi e l'accensione, senza
cercare il telecomando.

## Cosa fa

- **Volume**: cursore e muto nel pannello, rotella sopra l'icona, e i tasti volume della tastiera che comandano la TV
  quando l'audio del Mac esce in HDMI. Se alla TV sono collegate delle casse (ottico, ARC), regola quelle.
- **Ingressi HDMI**: un clic per passare da uno all'altro.
- **Accendi e spegni**: spegnimento dal pannello, accensione dalla rete se la TV lo permette.
- **Telecomando a scomparsa**: frecce, OK, Indietro, Home e menu rapido, per arrivare alle impostazioni dell'immagine.
- **Leggero**: non interroga la TV di continuo; è lei ad avvisare quando qualcosa cambia.

Funziona con le TV LG con webOS, sulla stessa rete del Mac. La prima volta la TV chiede di accettare il collegamento
con il telecomando. Tutto resta tra il Mac e la TV: nessun servizio esterno.

## Installazione

```
brew install --cask gguidotz/tap/tivu
```

Aggiornamento: `brew update && brew upgrade --cask tivu`.

Dai sorgenti (servono gli strumenti a riga di comando di Xcode):

```
git clone https://github.com/GGuidotz/tivu.git
cd tivu
./build.sh --install
```

## Permessi

- **Rete locale**: per trovare la TV e parlarle.
- **Accessibilità** (facoltativo): per ricevere i tasti volume della tastiera. Tivu vede solo quelli.

## Limiti

- Le impostazioni dell'immagine (luminosità, modalità) stanno nella TV: Tivu non le cambia direttamente, ti ci porta
  con il telecomando. In Impostazioni › TV trovi i ritocchi che contano quando alla TV è collegato un computer.
- L'accensione dalla rete dipende dalla TV e dal router; se non parte, il primo tasto resta quello del telecomando.

Progetto indipendente, non affiliato a LG. Licenza MIT.
