# What's new

## 0.1.1 · 2026-11-17
Better protection for the TV key and the connection.

### Improvements
- **TV key kept safe.** The pairing key now lives in the Mac's Keychain instead of the preferences. A key you already saved is moved over automatically.
- **Encrypted connection.** When the TV allows it, Tivu talks to it over an encrypted link; if the TV's certificate changes, Tivu tells you and asks you to pair again, without sending anything. Older TVs keep working as before.
- **Tighter signing.** The app is signed with the hardened runtime, which stops other programs from injecting code into it.

## 0.1.0 · 2026-11-11
The first version: your LG TV remote in the menu bar.

### New features
- **Volume from the Mac.** Slider and mute in the panel, scroll over the menu bar icon, and the keyboard volume keys control the TV when audio goes out over HDMI.
- **HDMI inputs.** Switch inputs with one click; the current one has a checkmark.
- **Power on and off.** Turn the TV off from the panel and back on over the network, if the TV allows it.
- **Fold-away remote.** Arrows, OK, Back, Home and the quick menu: reach the picture settings without hunting for the remote.
- **Guided pairing.** Tivu finds the TV on your home network; accept once with the remote and you're done.
- **Picture tips.** In Settings › TV, the four tweaks that matter when a computer is plugged into the TV.
