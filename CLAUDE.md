# Tivu

App macOS per la barra dei menu (Swift/SwiftUI, macOS 14+): il telecomando di una TV LG con webOS o Android / Google TV. Stesso schema di
GGuidotz/nod e GGuidotz/whats-going-on.

- Compilazione: `./build.sh` (swiftc diretto, niente progetto Xcode). Firma con l'identità locale di Nod
  (~/.nod-signing) se c'è, altrimenti ad hoc: serve perché macOS ricordi il permesso Accessibilità dei tasti volume.
  Prova sul Mac: `./build.sh --install`.
- `Sources/Core` non importa SwiftUI né AppKit: solo Foundation, socket, Network e Security (TVClient, AndroidTVClient,
  TVDiscovery, WakeOnLAN). Il modello parla con `TVController`: LG (TVClient) o Android (AndroidTVClient).
- Il cavo HDMI non porta comandi su macOS (niente HDMI-CEC, e le TV ignorano DDC): tutto passa dalla rete di casa con
  il protocollo SSAP di webOS (WebSocket sulla porta 3000, abbinamento con richiesta sulla TV e chiave salvata).
- TV Android / Google TV: protocollo Android TV Remote v2 (protobuf su TLS). Porta 6467 abbinamento: la TV mostra un
  codice esadecimale di 6 caratteri, Tivu manda SHA-256(modulo+esponente del Mac, della TV, codice senza il primo
  byte); porta 6466 telecomando. Identità = certificato autofirmato creato con /usr/bin/openssl in Application
  Support/Tivu e caricato solo in memoria (da macOS 15). Niente "imposta volume" (si va a passi con i tasti) né elenco ingressi
  (tasti HDMI 1-4). `remote_start.started` dice se la TV è accesa o in standby. Il nome viene dal servizio Cast
  (porta 8008). Provato su una TV Google reale; scansione porte 6466 e 6467.
- Privacy: il repo è pubblico. Mai indirizzi di rete, indirizzi fisici, chiavi o modelli reali in codice, commenti,
  README, CHANGELOG o report di diagnostica. Solo esempi inventati (192.168.1.20, 42XX650V). La TV abbinata sta in
  UserDefaults, sul Mac.
- Testi: chiave = frase italiana, `L("…")`; ogni chiave nuova va in `Localization/en.lproj/Localizable.strings`.
  Controllo: `python3 -I tools/check-strings.py` (legge anche i commenti: negli esempi usa chiavi vere).
- Versione: `VERSION` + sezione `## <versione> · <data>` in cima a `CHANGELOG.md` (build.sh la richiede) e in
  `CHANGELOG.en.md`.
- Design: Human Interface Guidelines di Apple; minimal. Liquid Glass sui controlli che galleggiano, sempre dietro
  `if #available(macOS 26, *)` (`Sources/App/Style.swift`); lo stato scelto mai solo con il colore.
- Interfaccia e messaggi in italiano, niente emoji.
- Avvio AppKit (`Sources/App/Main.swift`), non `App` di SwiftUI: la voce nella barra è un NSStatusItem, le
  impostazioni una finestra nostra.
- Leggerezza: nessuna lettura periodica dei dati. La TV avvisa da sola (sottoscrizioni a volume e app in primo piano);
  una richiesta ogni 25 s tiene vivo il collegamento. A TV spenta si riprova solo su un evento (pannello, tasto volume,
  risveglio, cambio di schermo o di uscita audio) e, con l'audio in HDMI, una volta al minuto.
- Ricerca della TV: SSDP, e se non risponde nessuno (il firewall di macOS scarta le risposte per le app non firmate da
  Apple) una scansione delle porte 3000 e 3001 nella rete locale, solo reti private fino a 1022 indirizzi.
- Tasti volume: filtro eventi solo per i tasti multimediali (`Sources/App/MediaKeys.swift`), con permesso Accessibilità.
  Vanno alla TV solo se è collegata e, nella scelta predefinita, se l'uscita audio del Mac è HDMI o DisplayPort.
- Le impostazioni dell'immagine della TV non sono esposte da SSAP su webOS 1.x: si raggiungono con il telecomando del
  pannello (tasti inviati sul socket del puntatore). Non promettere preset immagine senza averli provati su una TV.
- Icona: `Resources/Icon/Tivu.icon` (strati da `python3 -I tools/render-icon.py --layers …`), compilata da actool in
  build.sh e controllata da `tools/icon-check`; `AppIcon-1024.png` è il ripiego classico.
