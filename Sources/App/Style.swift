// Colori e vetro, in un posto solo.
// Regola (HIG, Liquid Glass): il vetro sui controlli che galleggiano (i pulsanti del pannello, la barra delle schede);
// il pannello stesso è un popover: su macOS 26 il vetro ce lo mette il sistema. Prima di macOS 26 il vetro diventa un
// materiale sottile. Riduci trasparenza e Aumenta contrasto li gestisce il sistema.

import AppKit
import SwiftUI

enum Palette {
    /// Il verde di "tutto a posto": sempre insieme a un simbolo o a un testo, mai da solo.
    static let calm = Color(red: 0.20, green: 0.78, blue: 0.45)
}

extension View {
    /// Vetro per i controlli che galleggiano. Mai per il contenuto.
    @ViewBuilder
    func glassSurface(in shape: some Shape, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// Vetro trasparente: lascia vedere quasi tutto quello che c'è sotto. Per i tasti del pannello.
    @ViewBuilder
    func clearGlass(in shape: some Shape, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.clear.tint(tint).interactive(), in: shape)
        } else {
            self.background((tint ?? Color.primary.opacity(0.08)).opacity(tint == nil ? 1 : 0.35), in: shape)
        }
    }

    /// Pulsante di vetro (secondario).
    @ViewBuilder
    func glassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// Il pulsante principale, uno per vista: vetro colorato.
    @ViewBuilder
    func glassProminentButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}

/// Contenitore dei controlli di vetro: su macOS 26 le forme vicine si fondono e si trasformano insieme.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
