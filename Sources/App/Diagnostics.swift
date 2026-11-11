// Diagnostica: un registro breve di ciò che succede (collegamento con la TV, aggiornamenti) e un report in testo semplice da allegare
// a una segnalazione. Solo in memoria, mai dati personali: niente nomi di file, niente indirizzi, niente app aperte.

import AppKit
import Foundation

enum DiagCategory: String {
    case app, tv, update, feedback
}

@MainActor
final class DiagnosticsLog: ObservableObject {
    static let shared = DiagnosticsLog()

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let category: DiagCategory
        let message: String
    }

    @Published private(set) var entries: [Entry] = []

    func add(_ category: DiagCategory, _ message: String) {
        entries.append(Entry(date: Date(), category: category, message: message))
        if entries.count > 200 { entries.removeFirst(entries.count - 200) }
    }

    nonisolated static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }
}

/// Scorciatoia per scrivere nel registro da qualsiasi punto del codice sul main actor.
@MainActor
func diag(_ category: DiagCategory, _ message: String) {
    DiagnosticsLog.shared.add(category, message)
}

enum SystemInfo {
    /// "Mac14,2"
    static var model: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    static var macOS: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    static var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    static var version: String { info["CFBundleShortVersionString"] as? String ?? "?" }
    static var build: String { info["CFBundleVersion"] as? String ?? "?" }
    static var commit: String { info["TIVUGitCommit"] as? String ?? "?" }

    /// Una riga per le email e le segnalazioni: "Tivu 0.4.0 (12) · macOS 27.0.1 · Mac14,2 · it".
    static var oneLine: String {
        "Tivu \(version) (\(build)) · macOS \(macOS) · \(model) · \(Localization.effectiveCode)"
    }
}

enum DiagnosticsReport {
    @MainActor
    static func make(model: AppModel) -> String {
        var out: [String] = []
        func section(_ title: String) { out.append(""); out.append("## \(title)") }
        func row(_ key: String, _ value: String) { out.append("- \(key): \(value)") }
        func yesNo(_ b: Bool) -> String { b ? "yes" : "no" }

        let prefs = model.prefs
        out.append("# Tivu diagnostics")
        row("Generated", DiagnosticsLog.stamp(Date()))

        section("App")
        row("Version", "\(SystemInfo.version) (build \(SystemInfo.build), commit \(SystemInfo.commit))")
        row("Icon", SystemInfo.info["TIVUIconTier"] as? String ?? "?")
        row("Installed via", Updater.channel == .homebrew ? "Homebrew" : "source build")
        row("Language", "\(prefs.language.rawValue) → \(Localization.effectiveCode)")

        section("Mac")
        row("Model", SystemInfo.model)
        row("macOS", "\(SystemInfo.macOS) (\(ProcessInfo.processInfo.operatingSystemVersionString))")
        row("Architecture", SystemInfo.architecture)
        row("Audio output is HDMI", yesNo(model.audio.isHDMI))

        // Mai l'indirizzo della TV, il suo indirizzo fisico o la chiave: solo se ci sono.
        section("TV")
        row("Paired", yesNo(prefs.hasTV))
        row("Model", prefs.tvModel.isEmpty ? "?" : prefs.tvModel)
        row("State", "\(model.tvState)")
        row("Key saved", yesNo(prefs.clientKey != nil))
        row("Hardware address known (power on)", yesNo(prefs.tvMAC != nil))
        row("Inputs", model.inputs.map { "\($0.id)\($0.connected ? "*" : "")" }.joined(separator: ", "))
        row("Current input", model.currentInput?.id ?? "none (TV app or unknown)")

        section("Preferences")
        row("Volume keys", prefs.mediaKeys.rawValue)
        row("Accessibility permission", yesNo(MediaKeys.isTrusted))
        row("Key filter running", yesNo(model.keysRunning))
        row("Keys go to the TV now", yesNo(model.keysGoToTV))
        row("Remote shown", yesNo(prefs.showRemote))
        row("Automatic update check", yesNo(prefs.autoCheckUpdates))

        section("Updates")
        row("State", "\(model.updater.state)")
        row("Last check", model.updater.lastCheck.map(DiagnosticsLog.stamp) ?? "never")

        section("Log")
        let entries = DiagnosticsLog.shared.entries.suffix(60)
        if entries.isEmpty { out.append("(empty)") }
        for e in entries { out.append("\(DiagnosticsLog.stamp(e.date)) [\(e.category.rawValue)] \(e.message)") }
        return out.joined(separator: "\n") + "\n"
    }

    static var suggestedFileName: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return "Tivu-diagnostics-\(f.string(from: Date())).txt"
    }
}
