// Impostazioni (⌘,): quattro schede sotto una barra di vetro che galleggia. Solo ciò che si cambia di rado, più
// aggiornamenti e feedback, come in Nod e in What's Going On.

import AppKit
import SwiftUI

struct SettingsView: View {
    static let size = CGSize(width: 560, height: 600)

    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences

    init(model: AppModel) {
        self.model = model
        prefs = model.prefs
    }

    var body: some View {
        Group {
            switch model.settingsTab {
            case .general: GeneralSettings(model: model, prefs: prefs)
            case .tv: TVSettings(model: model, prefs: prefs)
            case .updates: UpdatesSettings(updater: model.updater, prefs: prefs)
            case .feedback: FeedbackSettings(model: model)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)   // il fondo è il materiale della finestra (SettingsWindow)
        .safeAreaInset(edge: .top, spacing: 0) {
            SettingsTabBar(selection: $model.settingsTab)
                .padding(.top, 2)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .id(prefs.language)   // cambio di lingua: ridisegna tutto subito
    }
}

/// Il testo sotto una sezione.
struct Footnote: View {
    var text: String
    var font: Font = .caption
    init(_ text: String, font: Font = .caption) { self.text = text; self.font = font }
    var body: some View {
        Text(text).font(font).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Generale

private struct GeneralSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle(L("Apri all'accesso"), isOn: Binding(
                    get: { launchAtLogin },
                    set: { enabled in
                        loginError = LaunchAtLogin.set(enabled)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                ))
                if let loginError { Footnote(loginError) }
                Picker(L("Lingua"), selection: $prefs.language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
            }

            Section {
                Picker(L("I tasti volume comandano la TV"), selection: $prefs.mediaKeys) {
                    ForEach(MediaKeysMode.allCases) { Text($0.title).tag($0) }
                }
                if prefs.mediaKeys != .never { KeysPermission(model: model) }
            } header: {
                Text(L("Tasti volume della tastiera"))
            } footer: {
                Footnote(L("Su un'uscita HDMI macOS disattiva i tasti volume: Tivu li passa alla TV, che regola anche le casse collegate a lei. Con un'altra uscita (cuffie, altoparlanti del Mac) i tasti tornano normali."))
            }

            Section {
                LabeledContent(L("Consumo di Tivu")) { OwnUsageText() }
                Button(L("Rivedi la guida iniziale")) { model.showOnboarding() }
            } footer: {
                Footnote(L("Tivu non interroga la TV di continuo: è lei ad avvisare quando volume o ingresso cambiano. Con questa finestra aperta il valore è un po' più alto."))
            }
        }
    }
}

/// "0,1% di CPU · 24 MB", aggiornato ogni due secondi finché si vede.
private struct OwnUsageText: View {
    @State private var text = "–"

    var body: some View {
        Text(text)
            .monospacedDigit()
            .task {
                var last = OwnUsage.cpuSeconds, lastTime = Date()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    let now = OwnUsage.cpuSeconds, time = Date()
                    let percent = max(0, (now - last) / time.timeIntervalSince(lastTime) * 100)
                    last = now; lastTime = time
                    let megabytes = Double(OwnUsage.memoryBytes) / 1_048_576
                    text = L("%@%% di CPU · %@ MB", String(format: "%.1f", locale: Localization.locale, percent),
                             String(format: "%.0f", megabytes))
                }
            }
    }
}

/// Il permesso Accessibilità per i tasti volume: lo stato scritto, il pulsante per darlo, e un controllo ogni due
/// secondi finché questa riga si vede, così appena lo concedi i tasti funzionano senza riaprire l'app.
struct KeysPermission: View {
    @ObservedObject var model: AppModel
    @State private var trusted = MediaKeys.isTrusted

    var body: some View {
        HStack(spacing: 10) {
            if trusted && model.keysRunning {
                Label(L("Accessibilità concessa: i tasti funzionano"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Palette.calm)
            } else if trusted {
                Label(L("Permesso dato: riapri Tivu per attivare i tasti"), systemImage: "arrow.clockwise.circle.fill")
                    .foregroundStyle(.orange)
            } else {
                Button(L("Consenti l'Accessibilità…")) {
                    MediaKeys.requestTrust()
                    MediaKeys.openSettings()
                }
                .glassButton()
                Text(L("Serve per ricevere i tasti volume. Tivu vede solo quelli."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            while !Task.isCancelled {
                trusted = MediaKeys.isTrusted
                if trusted && !model.keysRunning { model.refreshMediaKeys() }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
}

// MARK: - TV

private struct TVSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @State private var confirmForget = false

    var body: some View {
        Form {
            if prefs.hasTV {
                Section {
                    LabeledContent(L("TV"), value: model.tvTitle)
                    LabeledContent(L("Stato"), value: model.summary)
                    LabeledContent(L("Accensione dal Mac")) {
                        if prefs.tvMAC != nil {
                            Label(L("Pronta"), systemImage: "checkmark.circle.fill").foregroundStyle(Palette.calm)
                        } else {
                            Text(L("Disponibile dopo il primo collegamento")).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Button(L("Ricollega")) { model.connect() }
                        Spacer()
                        Button(L("Dimentica questa TV…"), role: .destructive) { confirmForget = true }
                    }
                } footer: {
                    Footnote(L("Per accenderla dal Mac, sulla TV dev'essere attiva l'accensione dalla rete (di solito in Impostazioni › Generale o Rete). Se non parte, il primo tasto è quello del telecomando."))
                }
                .confirmationDialog(L("Dimenticare questa TV?"), isPresented: $confirmForget) {
                    Button(L("Dimentica"), role: .destructive) { model.forgetTV() }
                    Button(L("Annulla"), role: .cancel) {}
                } message: {
                    Text(L("Per usarla di nuovo dovrai accettare ancora il collegamento con il telecomando."))
                }

                Section {
                    PictureTip(symbol: "tag", text: L("Sulla TV, dai all'ingresso del Mac l'etichetta PC (Ingressi › modifica): il testo diventa nitido e i ritocchi automatici si spengono."))
                    PictureTip(symbol: "arrow.up.left.and.arrow.down.right", text: L("Formato immagine: Solo ricerca (Just Scan), così i bordi non vengono tagliati."))
                    PictureTip(symbol: "wand.and.stars.inverse", text: L("Nitidezza bassa, riduzione del rumore e TruMotion spenti: sono pensati per l'antenna, non per un computer."))
                    PictureTip(symbol: "display", text: L("Sul Mac: Impostazioni di Sistema › Schermi, risoluzione nativa della TV e il suo profilo colore."))
                    HStack {
                        Button(L("Apri il menu rapido della TV")) { model.press(.menu) }
                            .disabled(model.tvState != .connected)
                        Button(L("Apri Schermi sul Mac")) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                } header: {
                    Text(L("Immagine migliore"))
                } footer: {
                    Footnote(L("Le impostazioni dell'immagine stanno nella TV e dalla rete non si possono cambiare direttamente: con il telecomando del pannello ci arrivi senza alzarti."))
                }
            } else {
                Section {
                    TVFinder(model: model, prefs: prefs)
                } header: {
                    Text(L("Abbina una TV"))
                } footer: {
                    Footnote(L("Funziona con le TV LG con webOS, accese e sulla stessa rete del Mac. La prima volta la TV chiede di accettare il collegamento con il telecomando."))
                }
            }
        }
    }
}

private struct PictureTip: View {
    var symbol: String
    var text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint)
        }
    }
}

/// Cerca le TV nella rete di casa e avvia l'abbinamento. Nella guida iniziale e in Impostazioni › TV.
struct TVFinder: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @State private var manual = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if prefs.hasTV {
                paired
            } else {
                HStack(spacing: 10) {
                    Button(L("Cerca la TV")) { model.search() }
                        .glassProminentButton()
                        .disabled(model.searching)
                    if model.searching { ProgressView().controlSize(.small) }
                }
                ForEach(model.found) { tv in
                    HStack(spacing: 10) {
                        Image(systemName: "tv").foregroundStyle(.tint).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tv.model.isEmpty ? tv.name : "LG \(tv.model)")
                            Text(tv.host).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        Spacer()
                        Button(L("Abbina")) { model.pair(host: tv.host, name: tv.name, model: tv.model, mac: tv.mac) }
                            .glassButton()
                    }
                }
                if model.searchedOnce, model.found.isEmpty, !model.searching {
                    Footnote(L("Nessuna TV trovata. Controlla che sia accesa e sulla stessa rete del Mac, oppure scrivi qui sotto il suo indirizzo (sulla TV: Impostazioni › Rete)."), font: .callout)
                }
                HStack(spacing: 8) {
                    TextField(L("Indirizzo della TV"), text: $manual, prompt: Text(verbatim: "192.168.1.20"))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.pair(host: manual) }
                    Button(L("Abbina")) { model.pair(host: manual) }
                        .disabled(manual.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var paired: some View {
        HStack(spacing: 10) {
            switch model.tvState {
            case .connected:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.calm)
            case .pairing:
                Image(systemName: "hand.tap.fill").foregroundStyle(.orange)
            case .connecting:
                ProgressView().controlSize(.small)
            case .disconnected:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(model.tvTitle).font(.body.weight(.medium))
                Text(model.tvState == .connected ? L("Abbinata e collegata") : model.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        if model.tvState != .connected {
            HStack {
                Button(L("Riprova")) { model.connect() }
                Button(L("Scegli un'altra TV")) { model.forgetTV() }
            }
        }
    }
}

// MARK: - Aggiornamenti

private struct UpdatesSettings: View {
    @ObservedObject var updater: Updater
    @ObservedObject var prefs: Preferences
    private let current = Changelog.load().first

    var body: some View {
        Form {
            Section {
                Toggle(L("Controlla automaticamente (ogni 6 ore)"), isOn: $prefs.autoCheckUpdates)
                LabeledContent(L("Versione installata"), value: updater.currentVersion)
                LabeledContent(L("Ultimo controllo")) {
                    if let last = updater.lastCheck { Text(last, style: .relative) } else { Text(L("Mai")) }
                }
                HStack {
                    Button(L("Controlla ora")) { Task { await updater.check() } }
                        .disabled(updater.state == .checking)
                    UpdateStateText(updater: updater)
                }
            }

            if updater.isUpdateAvailable {
                Section { UpdateCard(updater: updater) }
            }

            if let current {
                Section {
                    ChangelogList(entries: [current])
                    Button(L("Mostra la schermata delle novità")) { AppModel.shared.showWhatsNew() }
                } header: {
                    Text(L("Novità di questa versione"))
                }
            }
        }
    }
}

private struct UpdateStateText: View {
    @ObservedObject var updater: Updater

    var body: some View {
        switch updater.state {
        case .idle: EmptyView()
        case .checking: ProgressView().controlSize(.small)
        case .upToDate:
            Label(L("Tivu è aggiornato."), systemImage: "checkmark.circle.fill").foregroundStyle(Palette.calm)
        case .available(let version):
            Label(L("Disponibile la versione %@", version), systemImage: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
        case .failed(let why):
            Text(why).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Le novità della nuova versione e il comando per aggiornare.
private struct UpdateCard: View {
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case .available(let version) = updater.state {
                Label(L("Disponibile Tivu %@", version), systemImage: "arrow.down.circle.fill")
                    .font(.headline)
            }
            if !updater.news.isEmpty { ChangelogList(entries: updater.news) }
            Text(L("Per aggiornare, esegui nel Terminale:")).foregroundStyle(.secondary)
            Text(updater.command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
            HStack {
                Button(L("Copia comando")) { updater.copyCommand() }
                Button(L("Aggiorna nel Terminale")) { updater.runInTerminal() }
                    .glassProminentButton()
            }
            if let error = updater.terminalError {
                Text(error).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Feedback

private struct FeedbackSettings: View {
    @ObservedObject var model: AppModel
    @State private var status: String?
    @State private var showReport = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Tivu").font(.title2.weight(.semibold)).fontDesign(.rounded)
                        Text(L("Versione %@", "\(SystemInfo.version) (\(SystemInfo.build))")).foregroundStyle(.secondary)
                        Text(L("Il telecomando della TV, nella barra dei menu.")).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                FeedbackButton(symbol: "ladybug", title: L("Segnala un problema"),
                               detail: L("Su GitHub, con versione, macOS e modello del Mac già scritti.")) {
                    Feedback.openIssue(.problem)
                }
                FeedbackButton(symbol: "lightbulb", title: L("Suggerisci un'idea"),
                               detail: L("Un comando che manca, un modello di TV che non va, un modo migliore di fare qualcosa.")) {
                    Feedback.openIssue(.idea)
                }
                FeedbackButton(symbol: "envelope", title: L("Scrivi un'email"),
                               detail: Developer.email) {
                    Feedback.composeEmail()
                }
            } header: {
                Text(L("Feedback"))
            } footer: {
                Footnote(L("GitHub è il canale preferito: le segnalazioni sono pubbliche, quindi non scrivere dati personali. Per qualcosa di privato usa l'email."))
            }

            Section {
                HStack {
                    Button(L("Copia report")) {
                        Feedback.copyReport(model: model)
                        status = L("Report copiato: incollalo nella segnalazione.")
                    }
                    Button(L("Salva…")) { status = Feedback.saveReport(model: model) }
                    Spacer()
                    Button(showReport ? L("Nascondi") : L("Mostra")) { showReport.toggle() }
                }
                if let status { Footnote(status) }
                if showReport {
                    ScrollView {
                        Text(DiagnosticsReport.make(model: model))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 200)
                }
            } header: {
                Text(L("Diagnostica"))
            } footer: {
                Footnote(L("Il report dice versione, Mac, modello e stato della TV, le tue scelte e gli ultimi eventi. Mai indirizzi di rete né la chiave della TV."))
            }

            Section {
                DeveloperLinks()
                Footnote(L("Progetto indipendente, non affiliato a LG. webOS è un marchio di LG Electronics."))
            }
        }
    }
}

private struct FeedbackButton: View {
    var symbol: String
    var title: String
    var detail: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
    }
}
