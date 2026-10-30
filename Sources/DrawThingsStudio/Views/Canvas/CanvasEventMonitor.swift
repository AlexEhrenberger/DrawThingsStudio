import AppKit
import SwiftUI

/// Fängt Trackpad-Gesten (zwei Finger schieben, Pinch, Doppeltipp mit zwei Fingern) und
/// das Mausrad über der ganzen Arbeitsfläche ab – auch über dem Bild und der Leerfläche.
/// SwiftUI bietet unter macOS kein Scroll-Ereignis für beliebige Views, deshalb ein lokaler Event-Monitor.
struct CanvasEventMonitor: NSViewRepresentable {
    var isActive: Bool
    /// Verschiebung in Punkten; `zoomModifier` = ⌘ oder ⌥ gedrückt (dann zoomen statt schieben).
    /// nil = Scrollen bleibt beim System (z. B. im Raster der Galerie, nur Pinch wird abgefangen).
    var onScroll: ((_ delta: CGSize, _ location: CGPoint, _ zoomModifier: Bool) -> Void)?
    var onMagnify: (_ factor: Double, _ location: CGPoint) -> Void
    var onSmartMagnify: ((_ location: CGPoint) -> Void)?

    func makeNSView(context: Context) -> MonitorView { MonitorView() }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.isActive = isActive
        view.onScroll = onScroll
        view.onMagnify = onMagnify
        view.onSmartMagnify = onSmartMagnify
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) {
        view.removeMonitor()
    }

    final class MonitorView: NSView {
        var isActive = false
        var onScroll: ((CGSize, CGPoint, Bool) -> Void)?
        var onMagnify: ((Double, CGPoint) -> Void)?
        var onSmartMagnify: ((CGPoint) -> Void)?
        private var monitor: Any?

        // Klicks gehen durch – der Monitor arbeitet unabhängig von der View-Hierarchie.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify, .smartMagnify]) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard isActive, let window, event.window === window else { return event }
            let local = convert(event.locationInWindow, from: nil)
            guard bounds.contains(local) else { return event }
            if event.type == .scrollWheel {
                guard onScroll != nil else { return event }
                // Listen und Textfelder (z. B. Seitenleisten) behalten ihr eigenes Scrollen.
                if let hit = window.contentView?.hitTest(event.locationInWindow),
                   let scrollView = hit.enclosingScrollView, !isDescendant(of: scrollView) {
                    return event
                }
            }
            if event.type == .smartMagnify, onSmartMagnify == nil { return event }
            let point = CGPoint(x: local.x, y: isFlipped ? local.y : bounds.height - local.y)
            switch event.type {
            case .scrollWheel:
                let zoomModifier = !event.modifierFlags.intersection([.command, .option]).isEmpty
                var delta = CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY)
                if !event.hasPreciseScrollingDeltas {
                    // Mausrad: Zeilen in Punkte umrechnen; ⇧ = waagerecht.
                    delta = CGSize(width: delta.width * 14, height: delta.height * 14)
                    if event.modifierFlags.contains(.shift) && delta.width == 0 {
                        delta = CGSize(width: delta.height, height: 0)
                    }
                    if zoomModifier { delta.height *= 2 }
                }
                onScroll?(delta, point, zoomModifier)
            case .magnify:
                onMagnify?(1 + event.magnification, point)
            case .smartMagnify:
                onSmartMagnify?(point)
            default:
                return event
            }
            return nil
        }
    }
}
