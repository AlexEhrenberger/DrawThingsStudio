import AppKit
import SwiftUI

/// Kennlinie eines Reglers: Um den Nullpunkt fein, nach außen stärker (Potenzkurve),
/// ähnlich wie Photoshop. Die Reglerstellung `u` läuft von −1 … 1 (bzw. 0 … 1).
struct SliderSpec {
    enum Display {
        case percent        // −100 … +100 wie in Photoshop
        case ev             // Belichtung in Blendenstufen
        case degrees        // Winkel
        case sideFraction(decimals: Int)   // Anteil der Bildseite in %
    }

    var neutral: Double
    var lower: Double
    var upper: Double
    var gamma: Double = 2
    var display: Display = .percent
    /// Wert für Doppelklick; sonst der Nullpunkt.
    var resetValue: Double?

    var isBipolar: Bool { lower < neutral }

    func value(at position: Double) -> Double {
        let magnitude = pow(abs(position), gamma)
        return position >= 0
            ? neutral + magnitude * (upper - neutral)
            : neutral + magnitude * (lower - neutral)
    }

    func position(of value: Double) -> Double {
        if value >= neutral {
            let span = upper - neutral
            return span == 0 ? 0 : pow(min(max((value - neutral) / span, 0), 1), 1 / gamma)
        }
        let span = neutral - lower
        return span == 0 ? 0 : -pow(min(max((neutral - value) / span, 0), 1), 1 / gamma)
    }

    func label(for value: Double) -> String {
        switch display {
        case .percent:
            let number = Int((position(of: value) * 100).rounded())
            if number == 0 { return "0" }
            return isBipolar ? (number > 0 ? "+\(number)" : "−\(-number)") : "\(number)"
        case .ev:
            return String(format: "%+.2f EV", value).replacingOccurrences(of: "-", with: "−")
        case .degrees:
            return String(format: "%+.1f°", value).replacingOccurrences(of: "-", with: "−")
        case .sideFraction(let decimals):
            return String(format: "%.\(decimals)f %%", value * 100)
        }
    }

    /// Eingetippte Zahl (in Anzeige-Einheiten) in einen Wert umrechnen.
    func value(fromTyped text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: ",", with: ".")
            .filter { "0123456789.-+".contains($0) }
        guard let number = Double(cleaned) else { return nil }
        let result: Double
        switch display {
        case .percent: result = value(at: min(max(number / 100, isBipolar ? -1 : 0), 1))
        case .ev, .degrees: result = number
        case .sideFraction: result = number / 100
        }
        return min(max(result, min(lower, neutral)), upper)
    }
}

/// Regler mit Kennlinie, ⌥ für Feineinstellung, Einrasten bei 0, Doppelklick = zurücksetzen,
/// Klick auf die Zahl = Wert eintippen.
struct AdjustSlider: View {
    let title: String
    @Binding var value: Double
    let spec: SliderSpec
    /// Farbverlauf statt der grauen Spur – zeigt, wohin der Regler färbt (Farbkorrektur).
    var track: [Color]?

    @State private var isEditing = false
    @State private var typed = ""
    @FocusState private var fieldFocused: Bool

    private var isNeutral: Bool { abs(value - (spec.resetValue ?? spec.neutral)) < 0.000_001 }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                if isEditing {
                    TextField("", text: $typed)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                        .focused($fieldFocused)
                        .onSubmit(commit)
                        .onExitCommand { isEditing = false }
                        .onChange(of: fieldFocused) { _, focused in if !focused { commit() } }
                } else {
                    Text(spec.label(for: value))
                        .monospacedDigit()
                        .foregroundStyle(isNeutral ? Color.secondary : Color.accentColor)
                        .onTapGesture {
                            typed = spec.label(for: value).replacingOccurrences(of: " EV", with: "")
                                .replacingOccurrences(of: "°", with: "").replacingOccurrences(of: " %", with: "")
                            isEditing = true
                            fieldFocused = true
                        }
                        .help("Klicken, um einen Wert einzutippen")
                }
            }
            .font(.callout)
            PrecisionSlider(value: $value, spec: spec, track: track)
                .frame(height: 18)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture(count: 2).onEnded { value = spec.resetValue ?? spec.neutral })
        .help("Ziehen · ⌥ beim Ziehen = fein · Doppelklick = zurücksetzen")
    }

    private func commit() {
        if let parsed = spec.value(fromTyped: typed) { value = parsed }
        isEditing = false
    }
}

struct PrecisionSlider: View {
    @Binding var value: Double
    let spec: SliderSpec
    var track: [Color]?

    @State private var dragStart: (position: Double, x: CGFloat)?
    @State private var isHovering = false

    private var minPosition: Double { spec.isBipolar ? -1 : 0 }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width - 14, 1)
            let position = spec.position(of: value)
            let originX = 7 + width * (spec.isBipolar ? 0.5 : 0)
            let thumbX = 7 + width * (spec.isBipolar ? (position + 1) / 2 : position)
            ZStack(alignment: .leading) {
                if let track {
                    Capsule()
                        .fill(LinearGradient(colors: track, startPoint: .leading, endPoint: .trailing))
                        .opacity(0.8)
                        .frame(height: 4)
                        .padding(.horizontal, 7)
                } else {
                    Capsule()
                        .fill(Color.primary.opacity(0.13))
                        .frame(height: 4)
                        .padding(.horizontal, 7)
                }
                if spec.isBipolar {
                    Rectangle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 1, height: 9)
                        .position(x: originX, y: proxy.size.height / 2)
                }
                if track == nil {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: abs(thumbX - originX), height: 4)
                        .position(x: (thumbX + originX) / 2, y: proxy.size.height / 2)
                }
                Circle()
                    .fill(Color(nsColor: .controlColor))
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                    .frame(width: dragStart != nil || isHovering ? 15 : 13, height: dragStart != nil || isHovering ? 15 : 13)
                    .position(x: thumbX, y: proxy.size.height / 2)
                    .animation(.easeOut(duration: 0.12), value: isHovering)
            }
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let fine = NSEvent.modifierFlags.contains(.option)
                        if dragStart == nil {
                            // Klick neben den Knopf springt dorthin (außer mit ⌥).
                            let current = spec.position(of: value)
                            let nearThumb = abs(drag.startLocation.x - thumbX) < 10
                            let start = nearThumb || fine ? current : positionAt(drag.startLocation.x, width: width)
                            dragStart = (start, drag.startLocation.x)
                        }
                        guard let start = dragStart else { return }
                        let span = spec.isBipolar ? 2.0 : 1.0
                        var next = start.position + Double(drag.location.x - start.x) / Double(width) * span * (fine ? 0.2 : 1)
                        next = min(max(next, minPosition), 1)
                        // Sanft am Nullpunkt einrasten.
                        if spec.isBipolar && abs(next) < 0.02 && !fine { next = 0 }
                        value = spec.value(at: next)
                    }
                    .onEnded { _ in dragStart = nil }
            )
        }
    }

    private func positionAt(_ x: CGFloat, width: CGFloat) -> Double {
        let fraction = min(max(Double(x - 7) / Double(width), 0), 1)
        return spec.isBipolar ? fraction * 2 - 1 : fraction
    }
}

/// Kennlinien aller Regler.
enum SliderSpecs {
    static let exposure = SliderSpec(neutral: 0, lower: -2, upper: 2, gamma: 1.7, display: .ev)
    static let contrast = SliderSpec(neutral: 1, lower: 0.75, upper: 1.3, gamma: 2.2)
    /// < 1 dunkelt Lichter ab (Core Image), > 1 hellt sie über eine Tonkurve auf.
    static let highlights = SliderSpec(neutral: 1, lower: 0.3, upper: 2, gamma: 1.8)
    static let shadows = SliderSpec(neutral: 0, lower: -1, upper: 1, gamma: 1.8)
    static let saturation = SliderSpec(neutral: 1, lower: 0, upper: 1.6, gamma: 1.6)
    static let vibrance = SliderSpec(neutral: 0, lower: -1, upper: 1, gamma: 1.6)
    static let temperature = SliderSpec(neutral: 0, lower: -100, upper: 100, gamma: 1.8)
    static let tint = SliderSpec(neutral: 0, lower: -60, upper: 60, gamma: 1.8)
    /// Farbkorrektur Rot, Grün, Blau.
    static let colorChannel = SliderSpec(neutral: 0, lower: -1, upper: 1, gamma: 1.8)
    static let sharpness = SliderSpec(neutral: 0, lower: 0, upper: 1.5, gamma: 1.5)
    static let clarity = SliderSpec(neutral: 0, lower: 0, upper: 1, gamma: 1.5)
    static let noise = SliderSpec(neutral: 0, lower: 0, upper: 1, gamma: 1.5)
    static let vignette = SliderSpec(neutral: 0, lower: 0, upper: 1.5, gamma: 1.5)
    static let grain = SliderSpec(neutral: 0, lower: 0, upper: 1, gamma: 1.5)
    static let straighten = SliderSpec(neutral: 0, lower: -45, upper: 45, gamma: 2, display: .degrees)
    static let brush = SliderSpec(neutral: 0.005, lower: 0.005, upper: 0.25, gamma: 1.6, display: .sideFraction(decimals: 0), resetValue: 0.06)
    static let feather = SliderSpec(neutral: 0, lower: 0, upper: 0.03, gamma: 1.6, display: .sideFraction(decimals: 1), resetValue: 0.004)
}
