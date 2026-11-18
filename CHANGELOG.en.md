# What's new

## 0.2.0 · 2026-11-18
Tivu now also talks to Android and Google TVs, and better protects the TV key and the connection.

### New features
- **Android and Google TVs.** Tivu finds them on your home network next to LG TVs. Pairing happens once: the TV shows a 6-character code, which you type in Settings › TV.
- **Volume, inputs and remote.** Volume and mute from the keyboard keys, HDMI 1 to 4, arrows, OK, Back, Home and menu, as with LG TVs. On Android the volume moves in steps, and inputs are the HDMI 1-4 keys: the TV doesn't say which ones are connected.
- **Standby.** If the Android TV is on standby, the panel says so and the power button wakes it.

### Improvements
- **TV key kept safe.** The pairing key now lives in the Mac's Keychain instead of the preferences. A key you already saved is moved over automatically.
- **Encrypted connection.** When an LG TV allows it, Tivu talks to it over an encrypted link; if the TV's certificate changes, Tivu tells you and asks you to pair again, without sending anything. Older TVs keep working as before.
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
