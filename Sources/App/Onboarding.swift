// La guida dei primi passi: quattro schermate brevi al primo avvio (e da Impostazioni › Generale). Cosa fa l'app,
// abbinare la TV, i tasti volume, come si usa. Ogni scelta qui è la stessa delle impostazioni, quindi si può saltare
// tutto: chiudere la finestra va bene quanto arrivare in fondo.
// HIG (onboarding): breve, si impara usando, i permessi si chiedono nel momento in cui servono e spiegando perché.

import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let view = OnboardingView(model: model, prefs: model.prefs) { [weak self] in
                self?.window?.performClose(nil)
                model.openPanel?()
            }
            let w = TranslucentWindow.make(view, size: OnboardingView.size)
            w.delegate = self
            window = w
        }
        window?.title = L("Benvenuto in Tivu")
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Chiusa in qualunque modo, la guida è vista: non torna da sola. Via anche le viste, come per le impostazioni.
    nonisolated func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                AppModel.shared.prefs.onboardingDone = true
                self?.window?.contentViewController = nil
                self?.window = nil
            }
        }
    }
}

struct OnboardingView: View {
    static let size = CGSize(width: 520, height: 560)

    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    var finish: () -> Void

    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let steps = 4

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: pairing
                case 2: keys
                default: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 36)
            .padding(.top, 44)
            .transition(.opacity)
            .id(step)

            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .id(prefs.language)
    }

    // MARK: - Passi

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(L("Benvenuto in Tivu"))
                .font(.largeTitle.weight(.semibold))
                .fontDesign(.rounded)
                .multilineTextAlignment(.center)
            Text(L("Il telecomando della tua TV, nella barra dei menu: volume, ingressi, accensione."))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("Il cavo HDMI porta immagine e suono, ma non i comandi: quelli passano dalla rete di casa. Tutto resta tra il Mac e la TV."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private var pairing: some View {
        StepPage(symbol: "tv", title: L("Abbina la TV"),
                 text: L("Accendi la TV, poi cercala. La prima volta ti chiede di accettare con il telecomando (LG) o mostra un codice da scrivere qui (Android): una volta sola.")) {
            TVFinder(model: model, prefs: prefs)
            Footnote(L("macOS può chiederti di lasciare che Tivu trovi i dispositivi nella rete locale: serve per parlare con la TV."), font: .callout)
        }
    }

    private var keys: some View {
        StepPage(symbol: "speaker.wave.2", title: L("Tasti volume"),
                 text: L("Con l'audio in HDMI i tasti volume del Mac non fanno nulla. Tivu li passa alla TV, che regola anche le casse collegate a lei.")) {
            Picker(L("I tasti volume comandano la TV"), selection: $prefs.mediaKeys) {
                ForEach(MediaKeysMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            if prefs.mediaKeys != .never {
                KeysPermission(model: model)
                    .padding(.top, 4)
            }
            Footnote(L("Puoi saltare questo passo: il volume si regola comunque dal pannello e con la rotella sopra l'icona nella barra."), font: .callout)
        }
    }

    private var ready: some View {
        StepPage(symbol: "checkmark.circle", title: L("Tutto pronto"),
                 text: L("Ecco come si usa.")) {
            Tip(symbol: "cursorarrow.click", text: L("Clic sull'icona nella barra: volume, ingressi HDMI, accendi e spegni."))
            Tip(symbol: "scroll", text: L("Rotella o due dita sopra l'icona: volume, senza aprire nulla."))
            Tip(symbol: "dpad", text: L("Nel pannello, Telecomando apre frecce e OK: ci arrivi alle impostazioni dell'immagine della TV."))
            Tip(symbol: "cursorarrow.click.2", text: L("Clic destro (o ctrl-clic): impostazioni, novità, feedback, esci."))
            Toggle(L("Apri all'accesso"), isOn: Binding(
                get: { LaunchAtLogin.isEnabled },
                set: { LaunchAtLogin.set($0) }
            ))
            .toggleStyle(.switch)
            .padding(.top, 8)
        }
    }

    // MARK: - In fondo

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<steps, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Color.primary.opacity(0.75) : Color.primary.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("Passo %d di %d", step + 1, steps))

            Spacer()

            GlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    if step > 0 {
                        Button(L("Indietro")) { go(step - 1) }
                            .glassButton()
                            .keyboardShortcut(.cancelAction)
                    }
                    Button(step == steps - 1 ? L("Inizia") : L("Avanti")) {
                        if step == steps - 1 { finish() } else { go(step + 1) }
                    }
                    .glassProminentButton()
                    .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private func go(_ next: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step = min(max(0, next), steps - 1) }
    }
}

/// Una pagina della guida: simbolo, titolo, una frase, poi il contenuto.
private struct StepPage<Content: View>: View {
    var symbol: String
    var title: String
    var text: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.title.weight(.semibold))
                .fontDesign(.rounded)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Tip: View {
    var symbol: String
    var text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 22)
        }
        .font(.body)
    }
}
