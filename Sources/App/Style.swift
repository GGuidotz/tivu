// Colori e vetro, in un posto solo. Le forme, i riempimenti e le molle vengono da Sguardo, il sistema di design comune
// (Vendor/Sguardo, compilato insieme all'app da build.sh): qui restano i colori di Tivu e gli aiuti che Sguardo non ha.
// Regola (HIG, Liquid Glass): il vetro solo sui controlli che galleggiano (la barra delle schede di Sguardo); il
// contenuto usa i riempimenti di Sguardo (velo traslucido + filo da 1 pt). Il pannello stesso è un popover: su macOS 26
// il vetro ce lo mette il sistema. Riduci trasparenza e Aumenta contrasto li gestisce il sistema.

import AppKit
import SwiftUI

enum Palette {
    /// Il verde di "tutto a posto": sempre insieme a un simbolo o a un testo, mai da solo. È un colore di stato, non
    /// quello d'accento.
    static let calm = Color(red: 0.20, green: 0.78, blue: 0.45)
}

extension SG.Accent {
    /// L'accento di Tivu per Sguardo: il viola della barra più alta nell'icona (volume al massimo, 0xA85CF6; lo
    /// stesso valore di BARS in tools/render-icon.py). Tivu non ha un colore del marchio: il verde di Palette.calm è
    /// di stato. Il bianco sopra questo viola fa circa 3,8:1 (meno di 4,5:1): le etichette dei pulsanti principali
    /// sono 13 pt medium, quindi vanno guardate in chiaro.
    static let tivu = SG.Accent(hex: 0xA85CF6)
}

extension View {
    /// Vetro per i controlli che galleggiano. Mai per il contenuto. Prima di macOS 26: materiale + velo + filo (Sguardo).
    func glassSurface(in shape: some InsettableShape, interactive: Bool = false) -> some View {
        sgFloatingChrome(in: shape, interactive: interactive)
    }

    /// Una scheda del contenuto, come le righe di Sguardo: velo traslucido (più bianco della finestra in chiaro), filo da
    /// 1 pt, angoli continui da 16 pt. Niente vetro (il vetro è dei controlli), niente ombre, niente animazioni.
    func contentCard(padding: CGFloat = 12, radius: CGFloat = SG.Radius.row) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(ContentCardBackground(radius: radius))
    }
}

private struct ContentCardBackground: ViewModifier {
    var radius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .sgRowSurface(in: shape)
            .overlay {
                // Aumenta contrasto: un bordo pieno sopra il filo.
                if contrast == .increased { shape.strokeBorder(Color.primary.opacity(0.35), lineWidth: 1) }
            }
    }
}

/// Campo di testo a capsula per le finestre (Sguardo ha solo quello scuro delle isole): stessa forma del selettore a
/// capsula, riempimento tenue e filo da 1 pt. Colorato con il testo normale, mai con l'accento.
struct CapsuleField: View {
    var title: String
    @Binding var text: String
    var prompt: String
    var monospaced = false
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(title, text: $text, prompt: Text(verbatim: prompt))
            .textFieldStyle(.plain)
            .font(monospaced ? .system(size: 12, design: .monospaced) : SG.Font.field)
            .foregroundStyle(SG.Ink.primary)
            .onSubmit(onSubmit)
            .padding(.horizontal, 14)
            .frame(height: SG.Size.buttonHeader)
            .background(Capsule().fill(SG.Fill.pickerPill))
            .overlay(Capsule().strokeBorder(SG.Fill.rowBorder, lineWidth: SG.Stroke.hairline))
    }
}
