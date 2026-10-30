import AppKit
import SwiftUI

/// Wie Seitenleiste und Inspector aussehen.
enum InterfaceStyle: String, CaseIterable, Identifiable {
    /// Wie bisher: die Panels liegen auf der grauen Fensterfläche.
    case solid
    /// Liquid Glass: Das Fenster ist hinter den Panels durchsichtig, der Schreibtisch färbt sie leicht ein.
    case glass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: "Matt"
        case .glass: "Glas"
        }
    }
}

extension View {
    /// Formulare im Inspector: im Glas-Modus ohne eigenen grauen Hintergrund, damit das Glas sichtbar bleibt.
    func panelFormBackground() -> some View {
        modifier(PanelFormBackground())
    }
}

private struct PanelFormBackground: ViewModifier {
    @Environment(Studio.self) private var studio

    func body(content: Content) -> some View {
        content.scrollContentBackground(studio.settings.interfaceStyle == .glass ? .hidden : .automatic)
    }
}

/// Glas-Modus: Fensterhintergrund durchsichtig – die Liquid-Glass-Panels von Seitenleiste und Inspector
/// nehmen dann die Farben des Schreibtischs auf. Matt: Fenster deckend wie gewohnt.
///
/// `dark`: Labs – das ganze Fenster dunkel (Werkzeugleiste, Seitenleiste, Menüs), wie der Fokusmodus.
struct WindowStyler: NSViewRepresentable {
    let transparent: Bool
    var dark = false

    func makeNSView(context: Context) -> StylerView { StylerView() }

    func updateNSView(_ view: StylerView, context: Context) {
        view.transparent = transparent
        view.dark = dark
        view.apply()
    }

    final class StylerView: NSView {
        var transparent = false
        var dark = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        /// SwiftUI setzt das Erscheinungsbild des Fensters gelegentlich selbst zurück – etwa nach dem Öffnen-Dialog.
        /// In Labs stünde dann schwarze Schrift auf Schwarz; deshalb gleich wieder dunkel machen.
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            guard dark, window?.appearance?.name != .darkAqua else { return }
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        func apply() {
            guard let window else { return }
            window.isOpaque = !transparent
            window.backgroundColor = transparent ? .clear : dark ? .black : .windowBackgroundColor
            if dark {
                if window.appearance?.name != .darkAqua { window.appearance = NSAppearance(named: .darkAqua) }
            } else if window.appearance != nil {
                window.appearance = nil
            }
        }
    }
}
