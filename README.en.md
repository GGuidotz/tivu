# Tivu

Your LG or Android TV's remote, in the Mac menu bar. [Italiano](README.md)

Plug a Mac into a TV over HDMI and the volume keys stop working: macOS disables them on HDMI, and the cable carries no
commands. Tivu talks to the TV over your home network and gives you back volume, inputs and power, without hunting for
the remote.

## What it does

- **Volume**: slider and mute in the panel, scroll over the icon, and the keyboard volume keys control the TV when the
  Mac's audio goes out over HDMI. If speakers are connected to the TV (optical, ARC), it drives those.
- **HDMI inputs**: one click to switch.
- **Power**: off from the panel, on over the network if the TV allows it.
- **Fold-away remote**: arrows, OK, Back, Home and the quick menu, to reach the picture settings.
- **Light**: it doesn't keep polling the TV; the TV reports when something changes.

Works with LG webOS TVs and with Android or Google TVs on the same network as the Mac. The first time, an LG TV asks
you to accept the connection with its remote; an Android TV shows a 6-character code to type in Settings › TV. Everything stays between the Mac and the TV: no external services.

## Install

```
brew install --cask gguidotz/tap/tivu
```

Update: `brew update && brew upgrade --cask tivu`.

From source (needs the Xcode command line tools):

```
git clone https://github.com/GGuidotz/tivu.git
cd tivu
./build.sh --install
```

## Permissions

- **Local network**: to find the TV and talk to it.
- **Accessibility** (optional): to receive the keyboard volume keys. Tivu only sees those.

## Limits

- Picture settings (brightness, modes) live in the TV: Tivu doesn't change them directly, it takes you there with the
  remote. Settings › TV lists the tweaks that matter when a computer is plugged into the TV.
- Power on over the network depends on the TV and the router; if it doesn't start, the first press is the remote's.

On Android the volume moves in steps (the protocol has no "set volume") and inputs are the HDMI 1-4 keys: the TV
doesn't say which ones are connected. Tivu uses Google's remote protocol, the same as the Google TV phone app.

Independent project, not affiliated with LG or Google. MIT licence.
