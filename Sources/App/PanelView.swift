// Il pannello: una frase che dice come sta la TV, il volume, gli ingressi HDMI e, a scomparsa, un telecomando
// essenziale. Minimal: ciò che non serve adesso non si vede. Il fondo è il vetro del popover (macOS 26); i tasti sono
// di vetro trasparente. Lo stato scelto non è mai detto solo dal colore: c'è sempre un segno di spunta o un testo.

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
                Button(L("Abbina una TV…")) { close(); model.showSettings(.tv) }
                    .glassProminentButton()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            } else if model.isOn {
                volume
                if !model.hdmiInputs.isEmpty { inputs }
                if prefs.showRemote { RemotePad(model: model) }
            }
            footer
        }
        .padding(16)
        .frame(width: 300)
        .animation(.easeInOut(duration: 0.18), value: prefs.showRemote)
        .animation(.easeInOut(duration: 0.18), value: model.tvState)
        .animation(.easeInOut(duration: 0.18), value: model.tvAwake)
        .id(prefs.language)
    }

    // MARK: - Pezzi

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.tvTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(model.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if prefs.hasTV {
                switch model.tvState {
                case .connected where model.tvAwake:
                    GlassIconButton(symbol: "power", label: L("Spegni la TV")) { model.turnOff() }
                case .connected, .disconnected:
                    GlassIconButton(symbol: "power", label: L("Accendi la TV"), tint: .accentColor) { model.turnOn() }
                default:
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private var volume: some View {
        HStack(spacing: 10) {
            GlassIconButton(symbol: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                            label: model.muted ? L("Riattiva l'audio") : L("Muto"),
                            tint: model.muted ? .accentColor : nil) { model.toggleMute() }
            Slider(value: Binding(get: { Double(model.volume) }, set: { model.setVolume(Int($0.rounded())) }),
                   in: 0...100)
                .accessibilityLabel(L("Volume della TV"))
                .accessibilityValue("\(model.volume)")
            Text("\(model.volume)")
                .font(.body.weight(.medium))
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)
                .foregroundStyle(model.muted ? .secondary : .primary)
                .accessibilityHidden(true)
        }
    }

    private var inputs: some View {
        GlassGroup(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(model.hdmiInputs) { input in
                    let selected = model.currentInput == input
                    Button { model.switchInput(input) } label: {
                        HStack(spacing: 4) {
                            if selected {
                                Image(systemName: "checkmark").font(.caption.weight(.bold))
                            }
                            Text(input.title)
                                .font(.callout.weight(selected ? .semibold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .clearGlass(in: Capsule(), tint: selected ? .accentColor : nil)
                    .accessibilityLabel(input.title)
                    .help(input.label)
                    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if prefs.hasTV, model.isOn {
                Button { prefs.showRemote.toggle() } label: {
                    Label(prefs.showRemote ? L("Nascondi il telecomando") : L("Telecomando"),
                          systemImage: prefs.showRemote ? "chevron.up" : "dpad")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button { close(); model.showSettings(nil) } label: {
                Image(systemName: "gearshape").font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut(",", modifiers: .command)
            .help(L("Impostazioni…"))
            .accessibilityLabel(L("Impostazioni…"))
        }
    }
}

/// Un tasto rotondo di vetro trasparente con un simbolo.
struct GlassIconButton: View {
    var symbol: String
    var label: String
    var tint: Color?
    var size: CGFloat = 32
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .medium))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .clearGlass(in: Circle(), tint: tint)
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
        GlassGroup(spacing: 8) {
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
        }
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
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .clearGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .help(label)
        .accessibilityLabel(label)
    }
}
