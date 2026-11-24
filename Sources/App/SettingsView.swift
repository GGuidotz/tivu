// Impostazioni (⌘,): quattro schede, con la barra a capsula di Sguardo che galleggia in fondo. Solo ciò che si cambia
// di rado, più aggiornamenti e feedback, come in Nod e in What's Going On.

import AppKit
import SwiftUI

struct SettingsView: View {
    static let size = CGSize(width: 560, height: 640)

    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences

    init(model: AppModel) {
        self.model = model
        prefs = model.prefs
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch model.settingsTab {
                case .general: GeneralSettings(model: model, prefs: prefs)
                case .tv: TVSettings(model: model, prefs: prefs)
                case .updates: UpdatesSettings(updater: model.updater, prefs: prefs)
                case .feedback: FeedbackSettings(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // La barra delle schede galleggia in fondo: le righe ci scorrono sotto (SGPage lascia lo spazio).
            SettingsTabBar(selection: $model.settingsTab)
                .padding(.bottom, SG.Size.tabBarBottomInset)
        }
        // In alto, sotto i semafori della finestra, il contenuto sfuma invece di tagliarsi di netto.
        .overlay(alignment: .top) { SGProgressiveBlur() }
        .frame(width: Self.size.width, height: Self.size.height)
        // La barra del titolo è trasparente e la vista occupa tutta la finestra: senza questo la zona sicura in alto
        // spinge giù tutto e la barra delle schede finisce sul bordo inferiore.
        .ignoresSafeArea()
        .sguardoAccent(default: .tivu)
        .id(prefs.language)   // cambio di lingua: ridisegna tutto subito
    }
}

/// Il testo sotto un gruppo di controlli fuori dalle pagine di impostazioni (guida iniziale, abbinamento).
struct Footnote: View {
    var text: String
    var font: Font = SG.Font.caption
    init(_ text: String, font: Font = SG.Font.caption) { self.text = text; self.font = font }
    var body: some View {
        Text(text).font(font).foregroundStyle(SG.Ink.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Generale

private struct GeneralSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    var body: some View {
        SGPage {
            SGSection {
                SGToggleRow(L("Apri all'accesso"), isOn: Binding(
                    get: { launchAtLogin },
                    set: { enabled in
                        loginError = LaunchAtLogin.set(enabled)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                ))
                if let loginError {
                    SGRowBlock { SGFootnote(loginError) }
                }
                SGDivider()
                SGMenuRow(L("Lingua"), selection: $prefs.language,
                          options: AppLanguage.allCases.map { (value: $0, title: $0.title) })
                SGDivider()
                SGAccentRow(L("Colore d'accento"),
                            options: (app: L("Colore dell'app"), system: L("Colore di sistema"), custom: L("Personalizzato")),
                            appDefault: .tivu)
            }

            SGSection(L("Tasti volume della tastiera")) {
                SGMenuRow(L("I tasti volume comandano la TV"), selection: $prefs.mediaKeys,
                          options: MediaKeysMode.allCases.map { (value: $0, title: $0.title) })
                if prefs.mediaKeys != .never {
                    SGDivider()
                    SGRowBlock { KeysPermission(model: model) }
                }
            } footer: {
                SGFootnote(L("Su un'uscita HDMI macOS disattiva i tasti volume: Tivu li passa alla TV, che regola anche le casse collegate a lei. Con un'altra uscita (cuffie, altoparlanti del Mac) i tasti tornano normali."))
            }

            SGSection {
                SGValueRow(L("Consumo di Tivu")) { OwnUsageText() }
                SGDivider()
                SGRowBlock {
                    Button(L("Rivedi la guida iniziale")) { model.showOnboarding() }
                        .buttonStyle(.sgSecondary)
                }
            } footer: {
                SGFootnote(L("Tivu non interroga la TV di continuo: è lei ad avvisare quando volume o ingresso cambiano. Con questa finestra aperta il valore è un po' più alto."))
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
            .lineLimit(1)
            .fixedSize()
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
                .buttonStyle(.sgSecondary)
                Text(L("Serve per ricevere i tasti volume. Tivu vede solo quelli."))
                    .font(SG.Font.caption)
                    .foregroundStyle(SG.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(SG.Font.body)
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
        SGPage {
            if prefs.hasTV {
                SGSection {
                    SGValueRow(L("TV"), value: model.tvTitle)
                    SGDivider()
                    SGValueRow(L("Stato"), value: model.summary)
                    SGDivider()
                    SGLabeledRow {
                        Text(L("Accensione dal Mac"))
                    } trailing: {
                        if prefs.tvMAC != nil {
                            Label(L("Pronta"), systemImage: "checkmark.circle.fill")
                                .font(SG.Font.body)
                                .foregroundStyle(Palette.calm)
                        } else {
                            Text(L("Disponibile dopo il primo collegamento"))
                                .font(SG.Font.body)
                                .foregroundStyle(SG.Ink.secondary)
                        }
                    }
                    SGDivider()
                    SGRowBlock {
                        HStack {
                            Button(L("Ricollega")) { model.connect() }
                                .buttonStyle(.sgSecondary)
                            Spacer()
                            Button(L("Dimentica questa TV…"), role: .destructive) { confirmForget = true }
                                .buttonStyle(.sgDestructive)
                        }
                    }
                } footer: {
                    SGFootnote(L("Per accenderla dal Mac, sulla TV dev'essere attiva l'accensione dalla rete (di solito in Impostazioni › Generale o Rete). Se non parte, il primo tasto è quello del telecomando."))
                }
                .confirmationDialog(L("Dimenticare questa TV?"), isPresented: $confirmForget) {
                    Button(L("Dimentica"), role: .destructive) { model.forgetTV() }
                    Button(L("Annulla"), role: .cancel) {}
                } message: {
                    Text(L("Per usarla di nuovo dovrai accettare ancora il collegamento con il telecomando."))
                }

                SGSection(L("Immagine migliore")) {
                    SGRowBlock { PictureTip(symbol: "tag", text: L("Sulla TV, dai all'ingresso del Mac l'etichetta PC (Ingressi › modifica): il testo diventa nitido e i ritocchi automatici si spengono.")) }
                    SGDivider()
                    SGRowBlock { PictureTip(symbol: "arrow.up.left.and.arrow.down.right", text: L("Formato immagine: Solo ricerca (Just Scan), così i bordi non vengono tagliati.")) }
                    SGDivider()
                    SGRowBlock { PictureTip(symbol: "wand.and.stars.inverse", text: L("Nitidezza bassa, riduzione del rumore e TruMotion spenti: sono pensati per l'antenna, non per un computer.")) }
                    SGDivider()
                    SGRowBlock { PictureTip(symbol: "display", text: L("Sul Mac: Impostazioni di Sistema › Schermi, risoluzione nativa della TV e il suo profilo colore.")) }
                    SGDivider()
                    SGRowBlock {
                        HStack(spacing: 8) {
                            Button(L("Apri il menu rapido della TV")) { model.press(.menu) }
                                .buttonStyle(.sgSecondary)
                                .disabled(model.tvState != .connected)
                            Button(L("Apri Schermi sul Mac")) {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.sgSecondary)
                        }
                    }
                } footer: {
                    SGFootnote(L("Le impostazioni dell'immagine stanno nella TV e dalla rete non si possono cambiare direttamente: con il telecomando del pannello ci arrivi senza alzarti."))
                }
            } else {
                SGSection(L("Abbina una TV")) {
                    SGRowBlock { TVFinder(model: model, prefs: prefs) }
                } footer: {
                    SGFootnote(L("Funziona con le TV LG con webOS e con le TV Android o Google TV, accese e sulla stessa rete del Mac. La prima volta la TV chiede di accettare il collegamento con il telecomando (LG) o mostra un codice da scrivere qui (Android)."))
                }
            }
        }
    }
}

private struct PictureTip: View {
    var symbol: String
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
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
                        .buttonStyle(.sgPrimary)
                        .disabled(model.searching)
                    if model.searching { ProgressView().controlSize(.small) }
                }
                ForEach(model.found) { tv in
                    HStack(spacing: 10) {
                        Image(systemName: "tv").foregroundStyle(.tint).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tv.brand == .android ? tv.name : (tv.model.isEmpty ? tv.name : "LG \(tv.model)"))
                                .font(SG.Font.body)
                            Text(tv.host).font(SG.Font.caption).foregroundStyle(SG.Ink.secondary).monospacedDigit()
                        }
                        Spacer()
                        Button(L("Abbina")) { model.pair(host: tv.host, name: tv.name, model: tv.model, mac: tv.mac, brand: tv.brand) }
                            .buttonStyle(.sgSecondary)
                    }
                }
                if model.searchedOnce, model.found.isEmpty, !model.searching {
                    Footnote(L("Nessuna TV trovata. Controlla che sia accesa e sulla stessa rete del Mac, oppure scrivi qui sotto il suo indirizzo (sulla TV: Impostazioni › Rete)."), font: SG.Font.field)
                }
                HStack(spacing: 8) {
                    CapsuleField(title: L("Indirizzo della TV"), text: $manual, prompt: "192.168.1.20") {
                        model.pair(host: manual)
                    }
                    Button(L("Abbina")) { model.pair(host: manual) }
                        .buttonStyle(.sgSecondary)
                        .disabled(manual.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !manual.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(L("È una TV Android o Google TV")) { model.pair(host: manual, brand: .android) }
                        .buttonStyle(.link)
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
                Text(model.tvTitle).font(SG.Font.bodyEmphasis)
                Text(model.tvState == .connected ? L("Abbinata e collegata") : model.summary)
                    .font(SG.Font.field)
                    .foregroundStyle(SG.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        if model.tvState == .pairing, prefs.tvBrand == .android {
            PairingCode(model: model)
        }
        if model.tvState != .connected {
            HStack {
                Button(L("Riprova")) { model.connect() }
                    .buttonStyle(.sgSecondary)
                Button(L("Scegli un'altra TV")) { model.forgetTV() }
                    .buttonStyle(.sgSecondary)
            }
        }
    }
}

/// Il codice a 6 caratteri che una TV Android mostra durante l'abbinamento.
struct PairingCode: View {
    @ObservedObject var model: AppModel
    @State private var code = ""
    @State private var wrong = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                CapsuleField(title: L("Codice mostrato sulla TV"), text: $code, prompt: "A1B2C3", monospaced: true,
                             onSubmit: send)
                    .frame(maxWidth: 200)
                Button(L("Conferma"), action: send)
                    .buttonStyle(.sgPrimary)
                    .disabled(code.trimmingCharacters(in: .whitespaces).count != 6)
            }
            if wrong {
                Text(L("Il codice non è giusto: controlla sulla TV e riprova."))
                    .font(SG.Font.field)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func send() {
        wrong = !model.submitPairingCode(code)
    }
}

// MARK: - Aggiornamenti

private struct UpdatesSettings: View {
    @ObservedObject var updater: Updater
    @ObservedObject var prefs: Preferences
    private let current = Changelog.load().first

    var body: some View {
        SGPage {
            SGSection {
                SGToggleRow(L("Controlla automaticamente (ogni 6 ore)"), isOn: $prefs.autoCheckUpdates)
                SGDivider()
                SGValueRow(L("Versione installata"), value: updater.currentVersion)
                SGDivider()
                SGValueRow(L("Ultimo controllo")) {
                    if let last = updater.lastCheck { Text(last, style: .relative) } else { Text(L("Mai")) }
                }
                SGDivider()
                SGLabeledRow {
                    Button(L("Controlla ora")) { Task { await updater.check() } }
                        .buttonStyle(.sgSecondary)
                        .disabled(updater.state == .checking)
                } trailing: {
                    UpdateStateText(updater: updater)
                }
            }

            if updater.isUpdateAvailable {
                SGSection { SGRowBlock { UpdateCard(updater: updater) } }
            }

            if let current {
                SGSection(L("Novità di questa versione")) {
                    SGRowBlock { ChangelogList(entries: [current]) }
                    SGDivider()
                    SGRowBlock {
                        Button(L("Mostra la schermata delle novità")) { AppModel.shared.showWhatsNew() }
                            .buttonStyle(.sgSecondary)
                    }
                }
            }
        }
    }
}

private struct UpdateStateText: View {
    @ObservedObject var updater: Updater
    @Environment(\.sgAccent) private var accent

    var body: some View {
        switch updater.state {
        case .idle: EmptyView()
        case .checking: ProgressView().controlSize(.small)
        case .upToDate:
            Label(L("Tivu è aggiornato."), systemImage: "checkmark.circle.fill").foregroundStyle(Palette.calm)
        case .available(let version):
            Label(L("Disponibile la versione %@", version), systemImage: "arrow.down.circle.fill").foregroundStyle(accent.base)
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
                    .font(SG.Font.bodyEmphasis)
            }
            if !updater.news.isEmpty { ChangelogList(entries: updater.news) }
            Text(L("Per aggiornare, esegui nel Terminale:")).foregroundStyle(SG.Ink.secondary)
            Text(updater.command)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SG.Fill.tile, in: .sgTile)
                .overlay(RoundedRectangle.sgTile.strokeBorder(SG.Fill.rowBorder, lineWidth: SG.Stroke.hairline))
            HStack(spacing: 8) {
                Button(L("Copia comando")) { updater.copyCommand() }
                    .buttonStyle(.sgSecondary)
                Button(L("Aggiorna nel Terminale")) { updater.runInTerminal() }
                    .buttonStyle(.sgPrimary)
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
        SGPage {
            SGSection {
                SGRowBlock {
                    HStack(spacing: 16) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 72, height: 72)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Tivu").font(SG.Font.title)
                            Text(L("Versione %@", "\(SystemInfo.version) (\(SystemInfo.build))")).foregroundStyle(SG.Ink.secondary)
                            Text(L("Il telecomando della TV, nella barra dei menu.")).foregroundStyle(SG.Ink.secondary)
                        }
                    }
                }
            }

            SGSection(L("Feedback")) {
                FeedbackButton(symbol: "ladybug", title: L("Segnala un problema"),
                               detail: L("Su GitHub, con versione, macOS e modello del Mac già scritti.")) {
                    Feedback.openIssue(.problem)
                }
                SGDivider()
                FeedbackButton(symbol: "lightbulb", title: L("Suggerisci un'idea"),
                               detail: L("Un comando che manca, un modello di TV che non va, un modo migliore di fare qualcosa.")) {
                    Feedback.openIssue(.idea)
                }
                SGDivider()
                FeedbackButton(symbol: "envelope", title: L("Scrivi un'email"),
                               detail: Developer.email) {
                    Feedback.composeEmail()
                }
            } footer: {
                SGFootnote(L("GitHub è il canale preferito: le segnalazioni sono pubbliche, quindi non scrivere dati personali. Per qualcosa di privato usa l'email."))
            }

            SGSection(L("Diagnostica")) {
                SGRowBlock {
                    HStack(spacing: 8) {
                        Button(L("Copia report")) {
                            Feedback.copyReport(model: model)
                            status = L("Report copiato: incollalo nella segnalazione.")
                        }
                        .buttonStyle(.sgSecondary)
                        Button(L("Salva…")) { status = Feedback.saveReport(model: model) }
                            .buttonStyle(.sgSecondary)
                        Spacer()
                        Button(showReport ? L("Nascondi") : L("Mostra")) { showReport.toggle() }
                            .buttonStyle(.sgSecondary)
                    }
                }
                if let status {
                    SGDivider()
                    SGRowBlock { SGFootnote(status) }
                }
                if showReport {
                    SGDivider()
                    SGRowBlock {
                        ScrollView {
                            Text(DiagnosticsReport.make(model: model))
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 200)
                    }
                }
            } footer: {
                SGFootnote(L("Il report dice versione, Mac, modello e stato della TV, le tue scelte e gli ultimi eventi. Mai indirizzi di rete né la chiave della TV."))
            }

            SGSection {
                SGRowBlock {
                    VStack(alignment: .leading, spacing: 8) {
                        DeveloperLinks()
                        SGFootnote(L("Progetto indipendente, non affiliato a LG né a Google. webOS è un marchio di LG Electronics; Android TV e Google TV sono marchi di Google LLC."))
                    }
                }
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
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(SG.Font.body).foregroundStyle(SG.Ink.primary)
                    Text(detail).font(SG.Font.caption).foregroundStyle(SG.Ink.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(SG.Ink.tertiary)
            }
            .padding(.horizontal, SG.Space.rowInset)
            .padding(.vertical, 8)
            .frame(minHeight: SG.Size.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
    }
}
