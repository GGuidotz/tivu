// Il pannello: una frase che dice come sta la TV, il volume, gli ingressi HDMI e, a scomparsa, un telecomando
// essenziale. Minimal: ciò che non serve adesso non si vede. Il fondo è il vetro del popover (macOS 26); i tasti sono
// capsule di Sguardo (riempimento neutro, l'accento solo per ciò che è acceso o scelto). Lo stato scelto non è mai
// detto solo dal colore: c'è sempre un segno di spunta o un testo.

import SwiftUI

struct PanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if prefs.hasTV, model.tvState == .pairing, prefs.tvBrand == .android {
                PairingCode(model: model)
            }
            if !prefs.hasTV {
                Button { close(); model.showSettings(.tv) } label: {
                    Text(L("Abbina una TV…")).frame(maxWidth: .infinity)
                }
                .buttonStyle(SGCapsuleButtonStyle(.primary, size: .large))
            } else if model.isOn {
                volume
                if !model.hdmiInputs.isEmpty { inputs }
                if prefs.showRemote { RemotePad(model: model) }
            }
            footer
        }
        .padding(16)
        .frame(width: 300)
        .animation(SG.Motion.snappy, value: prefs.showRemote)
        .animation(SG.Motion.snappy, value: model.tvState)
        .animation(SG.Motion.snappy, value: model.tvAwake)
        .sguardoAccent(default: .tivu)
        .id(prefs.language)
    }

    // MARK: - Pezzi

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.tvTitle)
                    .font(SG.Font.bodyEmphasis)
                    .foregroundStyle(SG.Ink.primary)
                    .lineLimit(1)
                Text(model.summary)
                    .font(SG.Font.field)
                    .foregroundStyle(SG.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if prefs.hasTV {
                switch model.tvState {
                case .connected where model.tvAwake:
                    RoundIconButton(symbol: "power", label: L("Spegni la TV")) { model.turnOff() }
                case .connected, .disconnected:
                    RoundIconButton(symbol: "power", label: L("Accendi la TV"), prominent: true) { model.turnOn() }
                default:
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private var volume: some View {
        HStack(spacing: 10) {
            RoundIconButton(symbol: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                            label: model.muted ? L("Riattiva l'audio") : L("Muto"),
                            selected: model.muted) { model.toggleMute() }
            Slider(value: Binding(get: { Double(model.volume) }, set: { model.setVolume(Int($0.rounded())) }),
                   in: 0...100)
                .accessibilityLabel(L("Volume della TV"))
                .accessibilityValue("\(model.volume)")
            Text("\(model.volume)")
                .font(SG.Font.value)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 30, alignment: .trailing)
                .foregroundStyle(model.muted ? SG.Ink.secondary : SG.Ink.primary)
                .accessibilityHidden(true)
        }
    }

    private var inputs: some View {
        HStack(spacing: 6) {
            ForEach(model.hdmiInputs) { input in
                let selected = model.currentInput == input
                Button { model.switchInput(input) } label: {
                    HStack(spacing: 4) {
                        if selected {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                        }
                        Text(input.title)
                            .font(selected ? SG.Font.label : SG.Font.field)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(PanelKeyStyle(shape: Capsule(), selected: selected))
                .accessibilityLabel(input.title)
                .help(input.label)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if prefs.hasTV, model.isOn {
                Button { prefs.showRemote.toggle() } label: {
                    Label(prefs.showRemote ? L("Nascondi il telecomando") : L("Telecomando"),
                          systemImage: prefs.showRemote ? "chevron.up" : "dpad")
                        .font(SG.Font.field)
                }
                .buttonStyle(.plain)
                .foregroundStyle(SG.Ink.secondary)
            }
            Spacer()
            Button { close(); model.showSettings(nil) } label: {
                Image(systemName: "gearshape").font(SG.Font.body)
            }
            .buttonStyle(.plain)
            .foregroundStyle(SG.Ink.secondary)
            .keyboardShortcut(",", modifiers: .command)
            .help(L("Impostazioni…"))
            .accessibilityLabel(L("Impostazioni…"))
        }
    }
}

/// Il riempimento di un tasto del pannello: neutro (Sguardo); scelto = velo e filo dell'accento; principale = accento
/// pieno con testo bianco. Niente vetro: il pannello è già il vetro del popover.
struct PanelKeyStyle<S: InsettableShape>: ButtonStyle {
    var shape: S
    var selected = false
    var prominent = false
    @Environment(\.sgAccent) private var accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? SG.Ink.onAccent : SG.Ink.primary)
            .background(shape.fill(prominent ? accent.base : SG.Fill.neutralButton))
            .overlay(shape.fill(selected ? accent.selectedWash : .clear))
            .overlay(shape.strokeBorder(accent.base, lineWidth: selected ? 1.5 : 0))
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .opacity(isEnabled ? 1 : SG.Motion.disabledOpacity)
            .animation(SG.Motion.snappy, value: configuration.isPressed)
            .animation(SG.Motion.snappy, value: selected)
    }
}

/// Un tasto rotondo con un simbolo.
struct RoundIconButton: View {
    var symbol: String
    var label: String
    var selected = false
    var prominent = false
    var size: CGFloat = 32
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .medium))
                .frame(width: size, height: size)
        }
        .buttonStyle(PanelKeyStyle(shape: Circle(), selected: selected, prominent: prominent))
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Il telecomando essenziale: frecce e OK al centro, intorno Indietro, Home, menu rapido ed Esci. È il modo per
/// arrivare dal Mac alle impostazioni dell'immagine della TV, che dalla rete non si possono cambiare direttamente.
/// Con il pannello aperto valgono anche le frecce e Invio della tastiera.
private struct RemotePad: View {
    var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                key(.back, "arrow.uturn.backward", L("Indietro"))
                key(.up, "chevron.up", L("Su"))
                key(.home, "house", L("Home"))
            }
            GridRow {
                key(.left, "chevron.left", L("Sinistra"))
                key(.enter, "circle.fill", L("OK"))
                key(.right, "chevron.right", L("Destra"))
            }
            GridRow {
                key(.menu, "slider.horizontal.3", L("Menu rapido della TV"))
                key(.down, "chevron.down", L("Giù"))
                key(.exit, "xmark", L("Esci"))
            }
        }
        .frame(maxWidth: .infinity)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.upArrow) { model.press(.up); return .handled }
        .onKeyPress(.downArrow) { model.press(.down); return .handled }
        .onKeyPress(.leftArrow) { model.press(.left); return .handled }
        .onKeyPress(.rightArrow) { model.press(.right); return .handled }
        .onKeyPress(.return) { model.press(.enter); return .handled }
        .onKeyPress(.delete) { model.press(.back); return .handled }
    }

    private func key(_ button: TVButton, _ symbol: String, _ label: String) -> some View {
        Button { model.press(button) } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 64, height: 36)
        }
        .buttonStyle(PanelKeyStyle(shape: Capsule()))
        .help(label)
        .accessibilityLabel(label)
    }
}
