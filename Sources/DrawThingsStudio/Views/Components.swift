import SwiftUI

/// Bricht Chips automatisch in neue Zeilen um.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// Auswählbare Kapsel für einen Baustein.
struct Chip: View {
    let title: String
    let isOn: Bool
    var swatch: Color?
    var isPending = false
    /// Kleine Zusatzangabe hinter dem Titel, z. B. eine Anzahl.
    var detail: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isOn && swatch == nil {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .heavy))
                }
                if let swatch {
                    Circle()
                        .fill(swatch)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 0.5))
                }
                Text(title)
                    .font(.callout)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .monospacedDigit()
                        .opacity(0.65)
                }
                if isPending {
                    ProgressView()
                        .controlSize(.mini)
                        .help("Gemma schreibt den englischen Prompt …")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4.5)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background {
                Capsule().fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(isHovering ? 0.12 : 0.065)))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isOn)
        .animation(.easeOut(duration: 0.1), value: isHovering)
    }
}

/// Farbverlauf für alles, was Gemma macht – angelehnt an Apple Intelligence.
enum GemmaStyle {
    static let colors: [Color] = [
        Color(red: 0.98, green: 0.45, blue: 0.20),
        Color(red: 0.93, green: 0.29, blue: 0.55),
        Color(red: 0.58, green: 0.36, blue: 0.96),
        Color(red: 0.25, green: 0.56, blue: 0.98),
    ]

    static let gradient = LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    static let tint = Color(red: 0.58, green: 0.36, blue: 0.96)
}

/// Rotierender Leuchtrand, solange etwas rendert.
struct GlowBorder: View {
    var cornerRadius: CGFloat = 8
    var lineWidth: CGFloat = 3

    var body: some View {
        TimelineView(.animation) { context in
            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) / 4 * 360
            let gradient = AngularGradient(colors: GemmaStyle.colors + [GemmaStyle.colors[0]], center: .center, angle: .degrees(angle))
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(gradient, lineWidth: lineWidth * 3)
                    .blur(radius: 14)
                    .opacity(0.8)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(gradient, lineWidth: lineWidth)
            }
        }
        .allowsHitTesting(false)
    }
}

struct StatusDot: View {
    let color: Color
    var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay {
                if pulsing {
                    Circle()
                        .stroke(color, lineWidth: 2)
                        .phaseAnimator([false, true]) { view, phase in
                            view.scaleEffect(phase ? 2.2 : 1).opacity(phase ? 0 : 0.8)
                        } animation: { _ in .easeOut(duration: 1.1) }
                }
            }
    }
}

extension View {
    /// Dezente Karte für Inhalte im Inspector.
    func card(padding: CGFloat = 12, cornerRadius: CGFloat = 12) -> some View {
        self
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }
}

enum Format {
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func size(_ size: CGSize) -> String {
        "\(Int(size.width)) × \(Int(size.height))"
    }
}

/// Bild für SwiftUI aus einem CGImage.
struct CGImageView: View {
    let image: CGImage
    var contentMode: ContentMode = .fit

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: contentMode)
    }
}
